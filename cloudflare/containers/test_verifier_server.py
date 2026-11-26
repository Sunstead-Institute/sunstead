#!/usr/bin/env python3
"""Offline unit tests for cloudflare/containers/verifier_server.py.

Run: python3 cloudflare/containers/test_verifier_server.py -v
"""
import importlib.util
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

_MOD_SPEC = importlib.util.spec_from_file_location(
    "verifier_server",
    Path(__file__).with_name("verifier_server.py"),
)
vs = importlib.util.module_from_spec(_MOD_SPEC)
_MOD_SPEC.loader.exec_module(vs)


class ParsePorcelainZTests(unittest.TestCase):
    def test_renames_copies_spaces_and_untracked_dirs(self):
        raw = (
            " M Lib/Target.lean\0"
            "R  Lib/New Name.lean\0Lib/Old Name.lean\0"
            "C  Lib/Copy Target.lean\0Lib/Source.lean\0"
            "?? new dir/sub dir/file with spaces.lean\0"
            " M Lib/Target.lean\0"
            "\0"
        )
        self.assertEqual(
            vs.parse_porcelain_z(raw),
            [
                "Lib/Target.lean",
                "Lib/New Name.lean",
                "Lib/Old Name.lean",
                "Lib/Copy Target.lean",
                "Lib/Source.lean",
                "new dir/sub dir/file with spaces.lean",
            ],
        )

    def test_empty_and_short_entries(self):
        self.assertEqual(vs.parse_porcelain_z(""), [])
        self.assertEqual(vs.parse_porcelain_z("M\0?? \0"), [])


class GlobMatchesTests(unittest.TestCase):
    def test_wildcards_and_double_star(self):
        self.assertTrue(vs.glob_matches("Lib/Spec.lean", "Lib/Spec.lean"))
        self.assertFalse(vs.glob_matches("Lib/Spec.lean", "Lib/Target.lean"))
        self.assertTrue(vs.glob_matches("Lib/*.lean", "Lib/Spec.lean"))
        self.assertFalse(vs.glob_matches("Lib/*.lean", "Lib/Sub/Spec.lean"))
        self.assertTrue(vs.glob_matches("Lib/?.lean", "Lib/A.lean"))
        self.assertFalse(vs.glob_matches("Lib/?.lean", "Lib/AB.lean"))
        self.assertTrue(vs.glob_matches("Lib/**/*.lean", "Lib/Spec.lean"))
        self.assertTrue(vs.glob_matches("Lib/**/*.lean", "Lib/A/B/Spec.lean"))
        self.assertTrue(vs.glob_matches("**/*.lean", "Spec.lean"))
        self.assertTrue(vs.glob_matches("frozen/**", "frozen/a/b/c.txt"))
        self.assertFalse(vs.glob_matches("frozen/**", "other/a.txt"))


class ResolveCurrentFilesTests(unittest.TestCase):
    def setUp(self):
        vs._STATE_CACHE.clear()

    def tearDown(self):
        vs._STATE_CACHE.clear()

    def test_full_payload_caches_and_serves_hit(self):
        files = {"Lib/Target.lean": "theorem t : True := trivial\n"}
        sha = vs.files_sha256(files)
        got = vs.resolve_current_files({
            "mission_id": "m1",
            "current_files": files,
            "current_files_sha256": sha,
        })
        self.assertEqual(got, files)

        # Subsequent request sends hash only -> cache hit returns a defensive copy.
        hit = vs.resolve_current_files({
            "mission_id": "m1",
            "current_files_sha256": sha,
        })
        self.assertEqual(hit, files)
        hit["Lib/Target.lean"] = "mutated"
        self.assertEqual(
            vs.resolve_current_files({"mission_id": "m1", "current_files_sha256": sha}),
            files,
        )

    def test_sha_mismatch_and_invalid_shape_raise_value_error(self):
        with self.assertRaises(ValueError):
            vs.resolve_current_files({
                "mission_id": "m1",
                "current_files": {"a.lean": "x"},
                "current_files_sha256": "sha256:0000",
            })
        with self.assertRaises(ValueError):
            vs.resolve_current_files({
                "mission_id": "m1",
                "current_files": {"a.lean": 123},
            })

    def test_need_files_on_cache_miss_or_hash_mismatch(self):
        with self.assertRaises(vs.NeedFiles):
            vs.resolve_current_files({"mission_id": "missing", "current_files_sha256": "sha256:abc"})

        files = {"a.lean": "v1"}
        vs.resolve_current_files({"mission_id": "m1", "current_files": files})
        with self.assertRaises(vs.NeedFiles):
            vs.resolve_current_files({"mission_id": "m1", "current_files_sha256": "sha256:stale"})
        with self.assertRaises(vs.NeedFiles):
            vs.resolve_current_files({"mission_id": "m1"})

    def test_cache_state_false_does_not_populate_cache(self):
        files = {"a.lean": "ephemeral"}
        sha = vs.files_sha256(files)
        got = vs.resolve_current_files({
            "mission_id": "m-nocache",
            "current_files": files,
            "current_files_sha256": sha,
            "cache_state": False,
        })
        self.assertEqual(got, files)
        self.assertNotIn("m-nocache", vs._STATE_CACHE)
        with self.assertRaises(vs.NeedFiles):
            vs.resolve_current_files({
                "mission_id": "m-nocache",
                "current_files_sha256": sha,
            })


class ReservedStatementsRegexTests(unittest.TestCase):
    def test_blocks_reserved_and_allows_normal_lean_files(self):
        self.assertIsNotNone(vs._RESERVED_STATEMENTS_RE.match("Lib/SunsteadStatements.lean"))
        self.assertIsNotNone(vs._RESERVED_STATEMENTS_RE.match("Lib/DecompStatements_abc.lean"))
        self.assertIsNotNone(vs._RESERVED_STATEMENTS_RE.match("DecompLib/DecompStatements_task_1_d2.lean"))

        for allowed in (
            "Lib/Target.lean",
            "Lib/Spec.lean",
            "Lib/Decomp_task_d1.lean",
            "Lib/SunsteadStatementsHelper.lean",
            "Lib/DecompStatements_.txt",
            "Lib/Sub/SunsteadStatements.lean",
            "SunsteadStatements.lean",
        ):
            with self.subTest(path=allowed):
                self.assertIsNone(vs._RESERVED_STATEMENTS_RE.match(allowed))


class CleanupSandboxTmpTests(unittest.TestCase):
    def test_removes_leaked_jobs_patch_and_v2_specs_respecting_keep_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            job_dir = os.path.join(tmp, "sunstead-job-abc123")
            nested_dir = os.path.join(job_dir, "runner-deadbeef")
            os.makedirs(nested_dir)
            ro_file = os.path.join(nested_dir, "readonly.olean")
            with open(ro_file, "w", encoding="utf-8") as f:
                f.write("data")
            os.chmod(ro_file, 0o444)
            os.chmod(nested_dir, 0o555)

            patch_file = os.path.join(tmp, "incoming.patch")
            stale_spec = os.path.join(tmp, "sunstead-v2-stale.json")
            keep_spec = os.path.join(tmp, "sunstead-v2-active.json")
            unrelated_file = os.path.join(tmp, "keep-me.txt")
            unrelated_dir = os.path.join(tmp, "other-dir")
            os.makedirs(unrelated_dir)
            for path in (patch_file, stale_spec, keep_spec, unrelated_file):
                with open(path, "w", encoding="utf-8") as f:
                    f.write("x")

            with mock.patch.object(vs, "TMP_DIR", tmp):
                vs.cleanup_sandbox_tmp(keep_path=keep_spec)

            self.assertFalse(os.path.exists(job_dir))
            self.assertFalse(os.path.exists(patch_file))
            self.assertFalse(os.path.exists(stale_spec))
            self.assertTrue(os.path.isfile(keep_spec))
            self.assertTrue(os.path.isfile(unrelated_file))
            self.assertTrue(os.path.isdir(unrelated_dir))

            # Second pass without keep_path removes the active spec as well.
            with mock.patch.object(vs, "TMP_DIR", tmp):
                vs.cleanup_sandbox_tmp()
            self.assertFalse(os.path.exists(keep_spec))
            self.assertTrue(os.path.isfile(unrelated_file))
            self.assertTrue(os.path.isdir(unrelated_dir))


class RunSubprocessIsolatedTests(unittest.TestCase):
    def test_returns_completed_process_on_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = vs.run_subprocess_isolated(
                [sys.executable, "-c", "import sys; print('ok'); print('err', file=sys.stderr)"],
                cwd=tmp,
                timeout=10,
            )
            self.assertEqual(res.returncode, 0)
            self.assertEqual(res.stdout.strip(), "ok")
            self.assertEqual(res.stderr.strip(), "err")

    def test_kills_entire_process_group_and_cleans_tmp_on_timeout(self):
        with tempfile.TemporaryDirectory() as tmp:
            pid_file = os.path.join(tmp, "grandchild.pid")
            leaked_job = os.path.join(tmp, "sunstead-job-timeout-leak")
            os.makedirs(leaked_job)

            script = (
                "import subprocess, sys, time\n"
                "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
                "with open(sys.argv[1], 'w', encoding='utf-8') as f:\n"
                "    f.write(str(child.pid))\n"
                "    f.flush()\n"
                "time.sleep(60)\n"
            )
            killed_calls = []

            def fake_kill_sandbox():
                killed_calls.append(True)

            with mock.patch.object(vs, "TMP_DIR", tmp), \
                 mock.patch.object(vs, "kill_sandbox_processes", side_effect=fake_kill_sandbox):
                with self.assertRaises(subprocess.TimeoutExpired):
                    vs.run_subprocess_isolated(
                        [sys.executable, "-c", script, pid_file],
                        cwd=tmp,
                        timeout=0.5,
                    )

            self.assertEqual(len(killed_calls), 1)
            self.assertFalse(os.path.exists(leaked_job))

            # Confirm the spawned grandchild in the same process group was SIGKILLed.
            self.assertTrue(os.path.isfile(pid_file))
            child_pid = int(Path(pid_file).read_text(encoding="utf-8").strip())
            alive = True
            for _ in range(40):
                try:
                    os.kill(child_pid, 0)
                except ProcessLookupError:
                    alive = False
                    break
                time.sleep(0.05)
            self.assertFalse(alive, f"child process {child_pid} survived process-group SIGKILL")


class ResetWorkFromSeedTests(unittest.TestCase):
    def test_preserves_frozen_paths_and_uses_three_git_commands(self):
        with tempfile.TemporaryDirectory() as root:
            missions_root = os.path.join(root, "missions")
            work_dir = os.path.join(root, "work")
            tmp_dir = os.path.join(root, "tmp")
            seed_dir = os.path.join(missions_root, "demo-mission")
            os.makedirs(os.path.join(seed_dir, "Lib"))
            os.makedirs(work_dir)
            os.makedirs(tmp_dir)

            # Populate stale files in WORK_DIR and TMP_DIR to confirm cleanup.
            with open(os.path.join(work_dir, "stale.txt"), "w", encoding="utf-8") as f:
                f.write("stale")
            leaked_job = os.path.join(tmp_dir, "sunstead-job-old")
            os.makedirs(leaked_job)

            with open(os.path.join(seed_dir, "Lib", "Spec.lean"), "w", encoding="utf-8") as f:
                f.write("def frozenSeed : Nat := 42\n")
            with open(os.path.join(seed_dir, "Lib", "Target.lean"), "w", encoding="utf-8") as f:
                f.write("def target : Nat := 0\n")
            verify_src = os.path.join(seed_dir, "verify")
            with open(verify_src, "w", encoding="utf-8") as f:
                f.write("#!/bin/sh\necho '{}'\n")
            os.chmod(verify_src, 0o755)

            git_calls = []
            real_run = subprocess.run

            def spy_run(args, *pargs, **kwargs):
                if isinstance(args, list) and args and args[0] == "git":
                    git_calls.append(list(args))
                return real_run(args, *pargs, **kwargs)

            with mock.patch.object(vs, "MISSIONS_ROOT", missions_root), \
                 mock.patch.object(vs, "WORK_DIR", work_dir), \
                 mock.patch.object(vs, "TMP_DIR", tmp_dir), \
                 mock.patch.object(vs, "kill_sandbox_processes") as mock_kill, \
                 mock.patch.object(vs.subprocess, "run", side_effect=spy_run):
                vs.reset_work_from_seed(
                    "demo-mission",
                    current_files={
                        "Lib/Spec.lean": "def frozenSeed : Nat := 999 -- tampered!\n",
                        "Lib/Target.lean": "def target : Nat := 7\n",
                        "../escape.lean": "bad\n",
                    },
                    frozen_paths=["Lib/Spec.lean", "verify"],
                )

            mock_kill.assert_called_once()
            self.assertFalse(os.path.exists(os.path.join(work_dir, "stale.txt")))
            self.assertFalse(os.path.exists(leaked_job))
            self.assertFalse(os.path.exists(os.path.join(root, "escape.lean")))

            # Frozen seed file preserved; non-frozen file overlaid; verify keeps +x.
            self.assertEqual(
                Path(work_dir, "Lib", "Spec.lean").read_text(encoding="utf-8"),
                "def frozenSeed : Nat := 42\n",
            )
            self.assertEqual(
                Path(work_dir, "Lib", "Target.lean").read_text(encoding="utf-8"),
                "def target : Nat := 7\n",
            )
            verify_mode = os.stat(os.path.join(work_dir, "verify")).st_mode
            self.assertTrue(bool(verify_mode & stat.S_IXUSR))

            # Exactly 3 git subprocesses: init, add, commit with inline -c identity (no git config).
            self.assertEqual(len(git_calls), 3)
            self.assertEqual(git_calls[0][:2], ["git", "init"])
            self.assertEqual(git_calls[1], ["git", "add", "."])
            self.assertIn("commit", git_calls[2])
            self.assertIn("user.name=Sunstead Hub", git_calls[2])
            self.assertIn("user.email=hub@sunstead.org", git_calls[2])
            for call in git_calls:
                self.assertNotIn("config", call)

            author = real_run(
                ["git", "log", "-1", "--format=%an:%ae"],
                cwd=work_dir,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            self.assertEqual(author, "Sunstead Hub:hub@sunstead.org")


class HandlerSocketTimeoutTests(unittest.TestCase):
    def test_handler_default_and_extended_socket_timeout(self):
        self.assertEqual(vs.VerifierHandler.timeout, 30)
        fake_conn = mock.Mock()
        handler = vs.VerifierHandler.__new__(vs.VerifierHandler)
        handler.connection = fake_conn

        handler._extend_socket_timeout(90)
        fake_conn.settimeout.assert_called_with(300)

        handler._extend_socket_timeout(240)
        fake_conn.settimeout.assert_called_with(300)

        handler._extend_socket_timeout(260)
        fake_conn.settimeout.assert_called_with(320)


if __name__ == "__main__":
    unittest.main()
