#!/usr/bin/env python3
"""Offline unit tests for batched scripts/check-statements.py.

Run: python3 -m unittest scripts/test_check_statements.py
"""
import contextlib
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import threading
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("check_statements", os.path.join(HERE, "check-statements.py"))
cs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cs)


def _completed(stdout="", stderr="", returncode=0):
    return subprocess.CompletedProcess(args=["mock"], returncode=returncode, stdout=stdout, stderr=stderr)


class CheckStatementsUnitTests(unittest.TestCase):
    def test_parse_verdict_fail_closed_rules(self):
        self.assertEqual(
            cs.parse_verdict('noise\n{"ok": true, "summary": "verified"}\n', "", 0),
            {"ok": True, "summary": "verified"},
        )
        # Non-zero exit with ok: true MUST fail closed.
        bad_rc = cs.parse_verdict('{"ok": true, "summary": "spoof"}\n', "", 1)
        self.assertFalse(bad_rc["ok"])
        self.assertIn("exited 1", bad_rc["summary"])

        # Missing or malformed JSON MUST fail closed.
        self.assertFalse(cs.parse_verdict("not json\n", "stderr msg", 0)["ok"])
        self.assertFalse(cs.parse_verdict('{"ok": "yes"}\n', "", 0)["ok"])
        self.assertFalse(cs.parse_verdict('{"summary": "no ok field"}\n', "", 0)["ok"])

    def test_parse_batch_output_fail_closed_on_missing_malformed_and_duplicates(self):
        stdout = "\n".join([
            "some random lean log",
            cs.BATCH_RESULT_PREFIX + json.dumps({"task_id": "t1", "verdict": {"ok": True, "summary": "ok1"}}),
            cs.BATCH_RESULT_PREFIX + "{not valid json",
            cs.BATCH_RESULT_PREFIX + json.dumps({"task_id": "t2", "verdict": {"ok": False, "summary": "mismatch"}}),
            cs.BATCH_RESULT_PREFIX + json.dumps({"task_id": "t3", "verdict": {"ok": True, "summary": "dup1"}}),
            cs.BATCH_RESULT_PREFIX + json.dumps({"task_id": "t3", "verdict": {"ok": False, "summary": "dup2"}}),
            # t4 intentionally missing (e.g., container crashed mid-batch)
        ])
        res = dict(cs.parse_batch_output(stdout, "oom killed", ["t1", "t2", "t3", "t4"], returncode=137))
        self.assertTrue(res["t1"]["ok"])
        self.assertFalse(res["t2"]["ok"])
        self.assertEqual(res["t2"]["summary"], "mismatch")
        self.assertFalse(res["t3"]["ok"])
        self.assertIn("duplicate", res["t3"]["summary"])
        self.assertFalse(res["t4"]["ok"])
        self.assertIn("missing batch verdict", res["t4"]["summary"])
        self.assertIn("exit 137", res["t4"]["summary"])

    def test_run_mission_batch_uses_single_container_for_50_tasks(self):
        task_ids = [f"task_{i:02d}" for i in range(50)]
        calls = []

        def fake_run(cmd, **kwargs):
            calls.append((cmd, kwargs))
            if cmd[:2] == ["docker", "create"]:
                return _completed(stdout="cid_abc123\n")
            if cmd[:2] == ["docker", "cp"]:
                return _completed()
            if cmd[:2] == ["docker", "start"]:
                lines = [
                    cs.BATCH_RESULT_PREFIX + json.dumps({
                        "task_id": tid,
                        "verdict": {"ok": tid != "task_17", "summary": f"res-{tid}"},
                    })
                    for tid in task_ids
                ]
                return _completed(stdout="\n".join(lines) + "\n")
            if cmd[:2] == ["docker", "rm"]:
                return _completed()
            raise AssertionError(f"unexpected command: {cmd}")

        with mock.patch.object(cs.subprocess, "run", side_effect=fake_run):
            results = cs.run_mission_batch("/tmp/fake-mission", "sunstead/verifier-lean4:v0.2", task_ids, timeout=120)

        self.assertEqual(len(results), 50)
        self.assertEqual(sum(1 for _, v in results if v["ok"]), 49)
        self.assertFalse(dict(results)["task_17"]["ok"])

        creates = [c for c, _ in calls if c[:2] == ["docker", "create"]]
        cps = [c for c, _ in calls if c[:2] == ["docker", "cp"]]
        starts = [(c, kw) for c, kw in calls if c[:2] == ["docker", "start"]]
        rms = [c for c, _ in calls if c[:2] == ["docker", "rm"]]

        # Exactly 1 container, 2 docker cp (mission dir + script), 1 start, 1 rm for all 50 tasks!
        self.assertEqual(len(creates), 1)
        self.assertEqual(len(cps), 2)
        self.assertEqual(len(starts), 1)
        self.assertEqual(len(rms), 1)
        self.assertIn("--network=none", creates[0])
        self.assertIn("--inside-batch", creates[0])
        self.assertEqual(creates[0][-50:], task_ids)
        # Outer timeout scales with batch size + 60s margin.
        self.assertEqual(starts[0][1]["timeout"], 120 * 50 + 60)

    def test_run_mission_batch_respects_batch_size_chunking(self):
        task_ids = [f"t{i}" for i in range(5)]
        creates = []

        def fake_run(cmd, **kwargs):
            if cmd[:2] == ["docker", "create"]:
                creates.append(cmd)
                return _completed(stdout=f"cid_{len(creates)}\n")
            if cmd[:2] == ["docker", "start"]:
                chunk = creates[-1][creates[-1].index("--inside-batch") + 2:]
                out = "\n".join(
                    cs.BATCH_RESULT_PREFIX + json.dumps({"task_id": tid, "verdict": {"ok": True, "summary": "ok"}})
                    for tid in chunk
                )
                return _completed(stdout=out + "\n")
            return _completed()

        with mock.patch.object(cs.subprocess, "run", side_effect=fake_run):
            results = cs.run_mission_batch("/tmp/m", "img", task_ids, timeout=60, batch_size=2)

        self.assertEqual([tid for tid, _ in results], task_ids)
        self.assertEqual(len(creates), 3)  # 2 + 2 + 1

    def test_run_mission_batch_timeout_salvages_completed_and_fails_remaining(self):
        partial = cs.BATCH_RESULT_PREFIX + json.dumps({"task_id": "t1", "verdict": {"ok": True, "summary": "fast"}}) + "\n"
        rm_called = []

        def fake_run(cmd, **kwargs):
            if cmd[:2] == ["docker", "create"]:
                return _completed(stdout="cid_timeout\n")
            if cmd[:2] == ["docker", "start"]:
                raise subprocess.TimeoutExpired(cmd=cmd, timeout=kwargs["timeout"], output=partial.encode("utf-8"), stderr=b"")
            if cmd[:2] == ["docker", "rm"]:
                rm_called.append(cmd)
            return _completed()

        with mock.patch.object(cs.subprocess, "run", side_effect=fake_run):
            res = dict(cs.run_mission_batch("/tmp/m", "img", ["t1", "t2", "t3"], timeout=30))

        self.assertTrue(res["t1"]["ok"])
        self.assertFalse(res["t2"]["ok"])
        self.assertIn("timed out", res["t2"]["summary"])
        self.assertFalse(res["t3"]["ok"])
        self.assertEqual(len(rm_called), 1)

    def test_inside_batch_isolates_child_failures_and_timeouts(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_script = os.path.join(tmp, "fake_check.py")
            with open(fake_script, "w", encoding="utf-8") as f:
                f.write(
                    "import json, sys, time\n"
                    "tid = sys.argv[2]\n"
                    "if tid == 'ok_task':\n"
                    "    print(json.dumps({'ok': True, 'summary': 'type matches'}))\n"
                    "    sys.exit(0)\n"
                    "elif tid == 'fail_task':\n"
                    "    print(json.dumps({'ok': False, 'summary': 'statement mismatch'}))\n"
                    "    sys.exit(1)\n"
                    "elif tid == 'spoof_exit':\n"
                    "    print(json.dumps({'ok': True, 'summary': 'fake ok'}))\n"
                    "    sys.exit(2)\n"
                    "elif tid == 'slow_task':\n"
                    "    time.sleep(5)\n"
                )
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                cs.inside_batch(
                    ["ok_task", "fail_task", "spoof_exit", "slow_task"],
                    task_timeout=1,
                    workdir=tmp,
                    script_path=fake_script,
                )
            parsed = dict(cs.parse_batch_output(buf.getvalue(), "", ["ok_task", "fail_task", "spoof_exit", "slow_task"]))
            self.assertTrue(parsed["ok_task"]["ok"])
            self.assertFalse(parsed["fail_task"]["ok"])
            self.assertEqual(parsed["fail_task"]["summary"], "statement mismatch")
            self.assertFalse(parsed["spoof_exit"]["ok"])
            self.assertIn("exited 2", parsed["spoof_exit"]["summary"])
            self.assertFalse(parsed["slow_task"]["ok"])
            self.assertIn("timed out", parsed["slow_task"]["summary"])

    def test_main_cli_filters_mission_exclude_and_image(self):
        with tempfile.TemporaryDirectory() as tmp:
            for mid, img, tids in [
                ("m-alpha", "img-a", ["a1", "a2"]),
                ("m-beta", "img-b", ["b1"]),
                ("m-gamma", "img-a", ["g1"]),
            ]:
                mdir = os.path.join(tmp, mid)
                os.makedirs(mdir)
                with open(os.path.join(mdir, "sunstead.json"), "w", encoding="utf-8") as f:
                    json.dump({
                        "id": mid,
                        "verifier": {"image": img},
                        "tasks": [{"id": t} for t in tids],
                    }, f)

            seen = []

            def fake_batch(mission_dir, image, task_ids, timeout, batch_size=0):
                seen.append((os.path.basename(mission_dir), image, list(task_ids), timeout, batch_size))
                return [(tid, {"ok": True, "summary": "ok"}) for tid in task_ids]

            out = io.StringIO()
            with mock.patch.object(cs, "MISSIONS", tmp), \
                 mock.patch.object(cs, "run_mission_batch", side_effect=fake_batch), \
                 contextlib.redirect_stdout(out):
                with self.assertRaises(SystemExit) as cm:
                    cs.main(["--image", "img-a", "--exclude-mission", "m-gamma", "--timeout", "42"])
            self.assertEqual(cm.exception.code, 0)
            self.assertEqual(seen, [("m-alpha", "img-a", ["a1", "a2"], 42, 0)])
            self.assertIn("[OK] m-alpha/a1: ok", out.getvalue())
            self.assertIn("[OK] m-alpha/a2: ok", out.getvalue())
            self.assertIn("2 task(s) checked, 0 failure(s)", out.getvalue())

    def test_main_exits_nonzero_on_failure_or_zero_checked(self):
        with tempfile.TemporaryDirectory() as tmp:
            mdir = os.path.join(tmp, "m-one")
            os.makedirs(mdir)
            with open(os.path.join(mdir, "sunstead.json"), "w", encoding="utf-8") as f:
                json.dump({"id": "m-one", "verifier": {"image": "img"}, "tasks": [{"id": "t1"}]}, f)

            out = io.StringIO()
            with mock.patch.object(cs, "MISSIONS", tmp), \
                 mock.patch.object(cs, "run_mission_batch", return_value=[("t1", {"ok": False, "summary": "bad"})]), \
                 contextlib.redirect_stdout(out):
                with self.assertRaises(SystemExit) as cm:
                    cs.main(["--mission", "m-one"])
            self.assertEqual(cm.exception.code, 1)
            self.assertIn("[FAIL] m-one/t1: bad", out.getvalue())

            out2 = io.StringIO()
            with mock.patch.object(cs, "MISSIONS", tmp), contextlib.redirect_stdout(out2):
                with self.assertRaises(SystemExit) as cm2:
                    cs.main(["--mission", "nonexistent"])
            self.assertEqual(cm2.exception.code, 1)
            self.assertIn("no tasks checked", out2.getvalue())

    def test_main_parallel_jobs_schedules_largest_first_and_aggregates_failures(self):
        with tempfile.TemporaryDirectory() as tmp:
            for mid, tids in [
                ("m-small", ["s1"]),
                ("m-large", ["l1", "l2", "l3", "l4"]),
                ("m-med", ["m1", "m2"]),
            ]:
                mdir = os.path.join(tmp, mid)
                os.makedirs(mdir)
                with open(os.path.join(mdir, "sunstead.json"), "w", encoding="utf-8") as f:
                    json.dump({"id": mid, "verifier": {"image": "img"}, "tasks": [{"id": t} for t in tids]}, f)

            started = []

            def fake_batch(mission_dir, image, task_ids, timeout, batch_size=0):
                name = os.path.basename(mission_dir)
                started.append(name)
                return [
                    (tid, {"ok": tid != "m2", "summary": f"res-{tid}"})
                    for tid in task_ids
                ]

            out = io.StringIO()
            with mock.patch.object(cs, "MISSIONS", tmp), \
                 mock.patch.object(cs, "run_mission_batch", side_effect=fake_batch), \
                 contextlib.redirect_stdout(out):
                with self.assertRaises(SystemExit) as cm:
                    cs.main(["--jobs", "3"])
            self.assertEqual(cm.exception.code, 1)
            self.assertEqual(set(started), {"m-small", "m-large", "m-med"})
            text = out.getvalue()
            self.assertIn("[OK] m-large/l1: res-l1", text)
            self.assertIn("[FAIL] m-med/m2: res-m2", text)
            self.assertIn("7 task(s) checked, 1 failure(s)", text)

            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                with self.assertRaises(SystemExit) as cm_bad:
                    cs.main(["--jobs", "0"])
            self.assertEqual(cm_bad.exception.code, 2)

    def test_build_work_chunks_splits_and_orders_largest_first(self):
        work = [
            ("m-small", "/tmp/m-small", "img", ["s1"]),
            ("m-empty", "/tmp/m-empty", "img", []),
            ("m-huge", "/tmp/m-huge", "img", ["h1", "h2", "h3", "h4", "h5"]),
            ("m-med", "/tmp/m-med", "img", ["m1", "m2", "m3"]),
        ]
        # batch_size=0 keeps one chunk per non-empty mission, sorted largest-first.
        whole = cs.build_work_chunks(work, batch_size=0)
        self.assertEqual(
            [(name, idx, chunk) for name, _d, _img, idx, chunk in whole],
            [
                ("m-huge", 0, ["h1", "h2", "h3", "h4", "h5"]),
                ("m-med", 0, ["m1", "m2", "m3"]),
                ("m-small", 0, ["s1"]),
            ],
        )

        # batch_size=2 splits each mission and orders globally by (-len(chunk), mission, chunk_idx).
        chunked = cs.build_work_chunks(work, batch_size=2)
        self.assertEqual(
            [(name, idx, chunk) for name, _d, _img, idx, chunk in chunked],
            [
                ("m-huge", 0, ["h1", "h2"]),
                ("m-huge", 1, ["h3", "h4"]),
                ("m-med", 0, ["m1", "m2"]),
                ("m-huge", 2, ["h5"]),
                ("m-med", 1, ["m3"]),
                ("m-small", 0, ["s1"]),
            ],
        )

    def test_main_parallel_chunk_work_stealing_via_batch_size_and_jobs(self):
        with tempfile.TemporaryDirectory() as tmp:
            # Single 7-task mission + one 2-task mission with --batch-size 3 --jobs 3:
            # m-big splits into chunks of [3, 3, 1] and m-two has [2]; workers must run
            # chunks of m-big concurrently rather than serializing m-big on one worker.
            for mid, tids in [
                ("m-big", [f"b{i}" for i in range(7)]),
                ("m-two", ["t1", "t2"]),
            ]:
                mdir = os.path.join(tmp, mid)
                os.makedirs(mdir)
                with open(os.path.join(mdir, "sunstead.json"), "w", encoding="utf-8") as f:
                    json.dump({"id": mid, "verifier": {"image": "img"}, "tasks": [{"id": t} for t in tids]}, f)

            lock = threading.Lock()
            active = 0
            peak_active = 0
            both_big_chunks_parallel = threading.Barrier(2, timeout=5)
            seen_chunks = []

            def fake_chunk(mission_dir, image, chunk, timeout):
                nonlocal active, peak_active
                name = os.path.basename(mission_dir)
                with lock:
                    seen_chunks.append((name, list(chunk), timeout))
                    active += 1
                    peak_active = max(peak_active, active)
                try:
                    # The two 3-task chunks of m-big are scheduled first; syncing them
                    # proves one large mission is truly fanned out across parallel workers.
                    if name == "m-big" and len(chunk) == 3:
                        both_big_chunks_parallel.wait()
                    return [
                        (tid, {"ok": tid != "b4", "summary": f"ok-{tid}" if tid != "b4" else "bad-b4"})
                        for tid in chunk
                    ]
                finally:
                    with lock:
                        active -= 1

            out = io.StringIO()
            with mock.patch.object(cs, "MISSIONS", tmp), \
                 mock.patch.object(cs, "_run_batch_chunk", side_effect=fake_chunk), \
                 contextlib.redirect_stdout(out):
                with self.assertRaises(SystemExit) as cm:
                    cs.main(["--batch-size", "3", "--jobs", "3", "--timeout", "77"])

            self.assertEqual(cm.exception.code, 1)
            self.assertGreaterEqual(peak_active, 2, "chunks from the same mission must execute concurrently")
            self.assertEqual(len(seen_chunks), 4)
            self.assertEqual(
                sorted((n, tuple(c), to) for n, c, to in seen_chunks),
                sorted([
                    ("m-big", ("b0", "b1", "b2"), 77),
                    ("m-big", ("b3", "b4", "b5"), 77),
                    ("m-two", ("t1", "t2"), 77),
                    ("m-big", ("b6",), 77),
                ]),
            )
            text = out.getvalue()
            self.assertIn("[OK] m-big/b0: ok-b0", text)
            self.assertIn("[FAIL] m-big/b4: bad-b4", text)
            self.assertIn("[OK] m-two/t2: ok-t2", text)
            self.assertIn("9 task(s) checked, 1 failure(s)", text)

    def test_inside_batch_cleans_up_tmp_job_dirs_after_non_ok_verdicts(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_tmp = os.path.join(tmp, "fake_tmp")
            os.makedirs(fake_tmp)
            keep_dir = os.path.join(fake_tmp, "unrelated-dir")
            os.makedirs(keep_dir)
            saw_leftover_on_next = os.path.join(tmp, "next_saw.json")

            fake_script = os.path.join(tmp, "fake_child.py")
            with open(fake_script, "w", encoding="utf-8") as f:
                f.write(
                    "import glob, json, os, sys\n"
                    f"fake_tmp = {fake_tmp!r}\n"
                    f"record_path = {saw_leftover_on_next!r}\n"
                    "tid = sys.argv[2]\n"
                    "if tid == 'fail_task':\n"
                    "    d = os.path.join(fake_tmp, 'sunstead-job-fail')\n"
                    "    os.makedirs(d, exist_ok=True)\n"
                    "    open(os.path.join(d, 'leak.olean'), 'w').write('x')\n"
                    "    print(json.dumps({'ok': False, 'summary': 'mismatch'}))\n"
                    "    sys.exit(1)\n"
                    "elif tid == 'oom_task':\n"
                    "    # Check previous failed task's temp dir was already removed.\n"
                    "    before = sorted(os.path.basename(p) for p in glob.glob(os.path.join(fake_tmp, 'sunstead-job-*')))\n"
                    "    open(record_path, 'w').write(json.dumps({'before_oom': before}))\n"
                    "    d = os.path.join(fake_tmp, 'sunstead-job-oom')\n"
                    "    os.makedirs(d, exist_ok=True)\n"
                    "    open(os.path.join(d, 'core.tmp'), 'w').write('y')\n"
                    "    sys.exit(137)\n"
                    "elif tid == 'after_oom':\n"
                    "    cur = json.loads(open(record_path).read())\n"
                    "    cur['before_after_oom'] = sorted(os.path.basename(p) for p in glob.glob(os.path.join(fake_tmp, 'sunstead-job-*')))\n"
                    "    open(record_path, 'w').write(json.dumps(cur))\n"
                    "    print(json.dumps({'ok': True, 'summary': 'clean'}))\n"
                    "    sys.exit(0)\n"
                )

            buf = io.StringIO()
            with mock.patch.object(cs, "JOB_TMP_DIR", fake_tmp), contextlib.redirect_stdout(buf):
                cs.inside_batch(
                    ["fail_task", "oom_task", "after_oom"],
                    task_timeout=5,
                    workdir=tmp,
                    script_path=fake_script,
                )

            parsed = dict(cs.parse_batch_output(buf.getvalue(), "", ["fail_task", "oom_task", "after_oom"]))
            self.assertFalse(parsed["fail_task"]["ok"])
            self.assertFalse(parsed["oom_task"]["ok"])
            self.assertTrue(parsed["after_oom"]["ok"])
            with open(saw_leftover_on_next, "r", encoding="utf-8") as fh:
                seen = json.load(fh)
            self.assertEqual(seen["before_oom"], [], "fail_task leftover /tmp/sunstead-job-* must be removed")
            self.assertEqual(seen["before_after_oom"], [], "oom_task leftover /tmp/sunstead-job-* must be removed")
            self.assertTrue(os.path.isdir(keep_dir), "unrelated /tmp entries must not be touched")


if __name__ == "__main__":
    unittest.main()
