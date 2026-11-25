#!/usr/bin/env python3
"""Offline unit and end-to-end tests for scripts/bootstrap-snapshot.sh."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "bootstrap-snapshot.sh"


def git(cwd: Path, *args: str) -> str:
    p = subprocess.run(
        [
            "git",
            "-C",
            str(cwd),
            "-c",
            "core.hooksPath=/dev/null",
            "-c",
            "user.name=Sunstead Test",
            "-c",
            "user.email=test@localhost",
            *args,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return p.stdout.strip()


class BootstrapSnapshotTests(unittest.TestCase):
    def test_bash_syntax_valid(self):
        p = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_end_to_end_bootstrap_overlay_and_sync_back(self):
        with tempfile.TemporaryDirectory(prefix="sunstead-boot-test-") as tmp:
            base = Path(tmp)
            upstream_remote = base / "remote-upstream"
            upstream_remote.mkdir()
            git(upstream_remote, "init", "-q", "-b", "main")
            (upstream_remote / "lean-toolchain").write_text("leanprover/lean4:v4.35.0\n", encoding="utf-8")
            (upstream_remote / "lakefile.toml").write_text('name = "Demo"\n', encoding="utf-8")
            (upstream_remote / "Proofs").mkdir()
            (upstream_remote / "Proofs" / "Dep.lean").write_text("def depVal : Nat := 7\n", encoding="utf-8")
            (upstream_remote / "Proofs" / "Target.lean").write_text(
                "import Proofs.Dep\ntheorem target : depVal = 7 := by sorry\n", encoding="utf-8"
            )
            git(upstream_remote, "add", ".")
            git(upstream_remote, "commit", "-q", "-m", "pinned upstream")
            pinned_sha = git(upstream_remote, "rev-parse", "HEAD")

            # Add a newer commit upstream to verify bootstrap pins the exact 40-char SHA, not HEAD.
            (upstream_remote / "Proofs" / "Dep.lean").write_text("def depVal : Nat := 999\n", encoding="utf-8")
            git(upstream_remote, "add", ".")
            git(upstream_remote, "commit", "-q", "-m", "newer commit")

            # Create a downloaded mission bundle with a live overlay (e.g., task 1 already verified).
            bundle = base / "work-demo-snap"
            (bundle / "Proofs").mkdir(parents=True)
            (bundle / "lean-toolchain").write_text("leanprover/lean4:v4.35.0\n", encoding="utf-8")
            (bundle / "UPSTREAM.json").write_text(
                json.dumps({
                    "mode": "repo-snapshot",
                    "repo": "example-org/demo-repo",
                    "commit": pinned_sha,
                    "license": "Apache-2.0",
                }),
                encoding="utf-8",
            )
            (bundle / "sunstead.json").write_text(
                json.dumps({
                    "id": "demo-snap",
                    "mode": "dag",
                    "snapshot": {
                        "mode": "repo-snapshot",
                        "snapshot_id": "demo-snap",
                        "allowed_import_prefixes": ["Proofs", "Init"],
                    },
                    "verifier": {
                        "image": "sunstead/verifier-lean4-v4.35.0:v0.1",
                        "toolchain": "leanprover/lean4:v4.35.0",
                        "command": ["./verify"],
                    },
                    "tasks": [
                        {"id": "t1", "target_files": ["Proofs/Target.lean"]},
                    ],
                }),
                encoding="utf-8",
            )
            live_target = "import Proofs.Dep\n-- live bundle state\ntheorem target : depVal = 7 := by sorry\n"
            (bundle / "Proofs" / "Target.lean").write_text(live_target, encoding="utf-8")
            git(bundle, "init", "-q", "-b", "main")
            git(bundle, "add", ".")
            git(bundle, "commit", "-q", "-m", "live bundle")

            # 1. Refuse upstream dir placed inside bundle dir.
            bad = subprocess.run(
                [
                    str(SCRIPT),
                    "--bundle-dir", str(bundle),
                    "--upstream-dir", str(bundle / "inside"),
                    "--upstream-url", str(upstream_remote),
                    "--no-cache",
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("inside --bundle-dir", bad.stderr)

            # 2. Bootstrap into default adjacent directory `../demo-snap-upstream`.
            ok = subprocess.run(
                [
                    str(SCRIPT),
                    "--bundle-dir", str(bundle),
                    "--upstream-url", str(upstream_remote),
                    "--no-cache",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
            self.assertIn("ghcr.io/sunstead-institute/verifier-lean4-v4.35.0:v0.1", ok.stdout)

            up_dir = base / "demo-snap-upstream"
            self.assertTrue((up_dir / ".git").is_dir())
            self.assertEqual(git(up_dir, "rev-parse", "HEAD"), pinned_sha)
            # Pinned dep (not newer HEAD) + live target overlaid from bundle.
            self.assertEqual((up_dir / "Proofs" / "Dep.lean").read_text(encoding="utf-8"), "def depVal : Nat := 7\n")
            self.assertEqual((up_dir / "Proofs" / "Target.lean").read_text(encoding="utf-8"), live_target)
            # Bundle working tree remains completely clean (no extra files).
            self.assertEqual(git(bundle, "status", "--porcelain"), "")

            # 3. Edit target in upstream workspace and sync back to bundle.
            proved = "import Proofs.Dep\n-- live bundle state\ntheorem target : depVal = 7 := rfl\n"
            (up_dir / "Proofs" / "Target.lean").write_text(proved, encoding="utf-8")
            sync = subprocess.run(
                [str(SCRIPT), "--bundle-dir", str(bundle), "--sync-back"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(sync.returncode, 0, sync.stdout + sync.stderr)
            self.assertEqual((bundle / "Proofs" / "Target.lean").read_text(encoding="utf-8"), proved)
            diff = git(bundle, "diff", "--", "Proofs/Target.lean")
            self.assertIn("-theorem target : depVal = 7 := by sorry", diff)
            self.assertIn("+theorem target : depVal = 7 := rfl", diff)

    def test_refuses_non_snapshot_mission(self):
        p = subprocess.run(
            [str(SCRIPT), "--bundle-dir", str(ROOT / "missions" / "matrix-rank444-f2"), "--no-cache"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("not a repo-snapshot mission", p.stderr)


if __name__ == "__main__":
    unittest.main()
