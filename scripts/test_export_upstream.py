#!/usr/bin/env python3
"""Offline tests for scripts/export-upstream.py (no network, no Lean: --no-build).

Run: python3 scripts/test_export_upstream.py
"""
import contextlib
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
_spec = importlib.util.spec_from_file_location("export_upstream", os.path.join(HERE, "export-upstream.py"))
ex = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ex)

GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@localhost", "-c", "commit.gpgsign=false"]

UPSTREAM_FILE = """import Mathlib

namespace Up

def liouville : Nat := 1

/-- The Liouville function is completely multiplicative. -/
@[simp] lemma isCM_liouville :
    liouville = 1 := by
  sorry

lemma other_open : True := by
  sorry

end Up
"""

SEED_FILE = """import M1.Spec

namespace M1

/-- Open `sorry` from `Up/Ch1.lean:8`. -/
lemma isCM_liouville :
    liouville = 1 := by
  sorry

end M1
"""

PROVED_FILE = """import M1.Spec
import Mathlib.Tactic.Ring

namespace M1

/-- A helper the contributor added. -/
theorem helper_one : (1 : Nat) = 1 := rfl

/-- Open `sorry` from `Up/Ch1.lean:8`. -/
lemma isCM_liouville :
    liouville = 1 := by
  -- the actual proof
  exact helper_one

end M1
"""

VERIFY = '''#!/usr/bin/env python3
TASKS = {
    "is_cm": {
        "module": "M1.Mult",
        "theorem": "M1.isCM_liouville",
        "statement": "def is_cm : Prop := True",
    },
}
'''


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def git(cwd, *args):
    return subprocess.run([*GIT, *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def make_patch(path, before, after):
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, os.path.dirname(path)))
        full = os.path.join(d, path)
        write(full, before)
        git(d, "init", "-q")
        git(d, "add", "-A")
        git(d, "commit", "-q", "-m", "s")
        write(full, after)
        return git(d, "diff")


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.up = os.path.join(t, "upstream")
        os.makedirs(os.path.join(self.up, "Up"))
        write(os.path.join(self.up, "Up", "Ch1.lean"), UPSTREAM_FILE)
        git(self.up, "init", "-q")
        git(self.up, "add", "-A")
        git(self.up, "commit", "-q", "-m", "upstream")
        git(self.up, "config", "uploadpack.allowReachableSHA1InWant", "true")
        self.sha = git(self.up, "rev-parse", "HEAD").strip()
        self.missions = os.path.join(t, "missions")
        self.write_mission()
        self.proof = {
            "proof_id": "ab" * 32,
            "permalink": "https://sunstead.org/proofs/" + "ab" * 32,
            "mission_id": "m1",
            "task_id": "is_cm",
            "contributor": "codex-dirichlet",
            "display_name": "Codex Dirichlet",
            "github": "codex-dirichlet",
            "spec_is_current": True,
            "patch": make_patch("M1/Mult.lean", SEED_FILE, PROVED_FILE),
        }

    def tearDown(self):
        self.tmp.cleanup()

    def write_mission(self, demo=False, seed=SEED_FILE):
        m = os.path.join(self.missions, "m1")
        os.makedirs(os.path.join(m, "M1"), exist_ok=True)
        manifest = {
            "id": "m1", "title": "M1", "tier": 1, "mode": "dag", "demo": demo,
            "upstream": {"repo": "o/up", "commit": self.sha, "license": "Apache-2.0"},
            "frozen_paths": ["M1/Spec.lean"],
            "tasks": [{
                "id": "is_cm", "title": "cm", "target_files": ["M1/Mult.lean"],
                "upstream_url": f"https://github.com/o/up/blob/{self.sha}/Up/Ch1.lean#L8-L9",
            }],
        }
        write(os.path.join(m, "sunstead.json"), json.dumps(manifest))
        write(os.path.join(m, "UPSTREAM.json"), json.dumps({"repo": "o/up", "commit": self.sha, "license": "Apache-2.0", "checks": []}))
        write(os.path.join(m, "verify"), VERIFY)
        write(os.path.join(m, "M1", "Spec.lean"), "def liouville : Nat := 1\n")
        write(os.path.join(m, "M1", "Mult.lean"), seed)

    def run_export(self, proof=None, extra=(), out=None):
        pj = os.path.join(self.tmp.name, "proof.json")
        write(pj, json.dumps(proof or self.proof))
        self.out = out or os.path.join(self.tmp.name, "bundle")
        argv = ["--proof-json", pj, "--out", self.out, "--missions-root", self.missions,
                "--upstream-url", "file://" + self.up, "--no-build", *extra]
        err, stdout = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(stdout):
            code = ex.main(argv)
        return code, err.getvalue(), stdout.getvalue()

    def test_happy_path_writes_bundle_and_touches_nothing_else(self):
        before = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout
        code, err, out = self.run_export()
        self.assertEqual(code, 0, err)
        self.assertIn("NOT BUILT", out)
        patch = read(os.path.join(self.out, "upstream.patch"))
        self.assertIn("+theorem helper_one : (1 : Nat) = 1 := rfl", patch)
        self.assertIn("+  exact helper_one", patch)
        self.assertIn("+import Mathlib.Tactic.Ring", patch)
        self.assertIn("-  sorry", patch)
        self.assertEqual(patch.count("-  sorry"), 1, "only the target's sorry is replaced")
        meta = json.loads(read(os.path.join(self.out, "metadata.json")))
        self.assertEqual(meta["upstream_declaration"], "Up.isCM_liouville")
        self.assertEqual(meta["helpers"], ["M1.helper_one"])
        self.assertFalse(meta["built"])
        body = read(os.path.join(self.out, "PR_BODY.md"))
        self.assertIn("Codex Dirichlet (@codex-dirichlet)", body)
        self.assertIn("Not built", body)
        # The reported span covers the helper and the declaration in the new file.
        up = read(os.path.join(self.up, "Up", "Ch1.lean"))
        self.assertIn("sorry", up.split("lemma other_open")[0], "fixture repo itself is untouched")
        applied = subprocess.run(["git", "apply", "--check", os.path.join(self.out, "upstream.patch")], cwd=self.up)
        self.assertEqual(applied.returncode, 0, "bundle patch applies to the pinned commit")
        subprocess.run(["git", "apply", os.path.join(self.out, "upstream.patch")], cwd=self.up, check=True)
        new_lines = read(os.path.join(self.up, "Up", "Ch1.lean")).split("\n")
        a, b = meta["upstream_lines"]
        region = "\n".join(new_lines[a - 1:b])
        self.assertTrue(region.startswith("/-- A helper"), region)
        self.assertIn("exact helper_one", region)
        self.assertNotIn("other_open", region)
        after = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout
        self.assertEqual(before, after, "export must not write into the Sunstead repo")

    def test_refuses_out_dir_inside_repo(self):
        code, err, _ = self.run_export(out=os.path.join(ROOT, "export-bundle-test"))
        self.assertEqual(code, 1)
        self.assertIn("inside the Sunstead repo", err)
        self.assertFalse(os.path.exists(os.path.join(ROOT, "export-bundle-test")))

    def test_refuses_changed_statement(self):
        bad = PROVED_FILE.replace("liouville = 1 := by\n  --", "liouville = liouville := by\n  --")
        code, err, _ = self.run_export({**self.proof, "patch": make_patch("M1/Mult.lean", SEED_FILE, bad)})
        self.assertEqual(code, 1)
        self.assertIn("changed the frozen statement", err)

    def test_refuses_remaining_sorry(self):
        bad = PROVED_FILE.replace("exact helper_one", "sorry")
        code, err, _ = self.run_export({**self.proof, "patch": make_patch("M1/Mult.lean", SEED_FILE, bad)})
        self.assertEqual(code, 1)
        self.assertIn("still contains `sorry`", err)

    def test_refuses_sorry_in_a_helper(self):
        bad = PROVED_FILE.replace("(1 : Nat) = 1 := rfl", "(1 : Nat) = 1 := by sorry")
        code, err, _ = self.run_export({**self.proof, "patch": make_patch("M1/Mult.lean", SEED_FILE, bad)})
        self.assertEqual(code, 1)
        self.assertIn("helper M1.helper_one contains `sorry`", err)

    def test_refuses_demo_and_stale_spec(self):
        code, err, _ = self.run_export({**self.proof, "spec_is_current": False})
        self.assertEqual(code, 1)
        self.assertIn("earlier frozen spec", err)
        self.write_mission(demo=True)
        code, err, _ = self.run_export()
        self.assertEqual(code, 1)
        self.assertIn("demo mission", err)

    def test_refuses_upstream_statement_mismatch(self):
        changed_seed = SEED_FILE.replace("liouville = 1", "liouville = 2")
        self.write_mission(seed=changed_seed)
        proved = PROVED_FILE.replace("liouville = 1", "liouville = 2")
        code, err, _ = self.run_export({**self.proof, "patch": make_patch("M1/Mult.lean", changed_seed, proved)})
        self.assertEqual(code, 1)
        self.assertIn("upstream statement differs", err)

    def test_warns_on_mission_namespace_references(self):
        proved = PROVED_FILE.replace("exact helper_one", "exact M1.helper_one")
        code, err, out = self.run_export({**self.proof, "patch": make_patch("M1/Mult.lean", SEED_FILE, proved)})
        self.assertEqual(code, 0, err)
        self.assertIn("mission namespace `M1.`", out)

    def test_upstream_url_parsing_and_verify_table(self):
        sha = "e9906138410f8f76ca66b9bc252d0993f3ee348c"
        self.assertEqual(
            ex.parse_upstream_url(f"https://github.com/A/B/blob/{sha}/P/Q.lean#L1787-L1788"),
            ("A/B", sha, "P/Q.lean", 1787, 1788),
        )
        with self.assertRaises(ex.ExportError):
            ex.parse_upstream_url("https://github.com/A/B/blob/main/P/Q.lean#L1")
        real = read(os.path.join(ROOT, "missions", "pnt-analytic-foundations", "verify"))
        self.assertEqual(
            ex.verify_theorems(real)["is_completely_multiplicative_liouville"],
            "PntFoundations.isCompletelyMultiplicative_liouville",
        )

    def test_real_missions_resolve(self):
        """Every live task's upstream_url, pin and verify theorem line up."""
        for mid in ("pnt-analytic-foundations", "arklib-near-capacity-primes"):
            manifest = json.loads(read(os.path.join(ROOT, "missions", mid, "sunstead.json")))
            for t in manifest["tasks"]:
                m = ex.load_mission(os.path.join(ROOT, "missions"), {"mission_id": mid, "task_id": t["id"]})
                self.assertTrue(m["upstream_path"].endswith(".lean"), (mid, t["id"]))
                self.assertTrue(m["theorem"], (mid, t["id"]))




CORE_UPSTREAM = """namespace Up

def liouville : Nat := 1

/-- Upstream open lemma. -/
theorem isCM_liouville :
    liouville = 1 := by
  sorry

end Up
"""

CORE_SEED = """namespace M1

def liouville : Nat := 1

/-- Open `sorry` from `Up/Ch1.lean:6`. -/
theorem isCM_liouville :
    liouville = 1 := by
  sorry

end M1
"""


@unittest.skipUnless(ex.shutil.which("lake"), "needs a Lean toolchain (lake on PATH)")
class BuildTests(unittest.TestCase):
    """Full path including `lake build` and `#print axioms`, on a core-Lean-only upstream."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.up = os.path.join(t, "upstream")
        os.makedirs(os.path.join(self.up, "Up"))
        write(os.path.join(self.up, "Up", "Ch1.lean"), CORE_UPSTREAM)
        write(os.path.join(self.up, "Up.lean"), "import Up.Ch1\n")
        write(os.path.join(self.up, "lakefile.toml"), 'name = "up"\ndefaultTargets = ["Up"]\n\n[[lean_lib]]\nname = "Up"\n')
        toolchain = os.environ.get("SUNSTEAD_TEST_TOOLCHAIN") or read(
            os.path.join(ROOT, "missions", "pnt-analytic-foundations", "lean-toolchain")
        ).strip()
        write(os.path.join(self.up, "lean-toolchain"), toolchain + "\n")
        git(self.up, "init", "-q")
        git(self.up, "add", "-A")
        git(self.up, "commit", "-q", "-m", "upstream")
        git(self.up, "config", "uploadpack.allowReachableSHA1InWant", "true")
        self.sha = git(self.up, "rev-parse", "HEAD").strip()
        self.missions = os.path.join(t, "missions")
        m = os.path.join(self.missions, "m1")
        os.makedirs(os.path.join(m, "M1"))
        write(os.path.join(m, "sunstead.json"), json.dumps({
            "id": "m1", "title": "M1", "tier": 1, "mode": "dag",
            "upstream": {"repo": "o/up", "commit": self.sha, "license": "Apache-2.0"},
            "frozen_paths": [], "tasks": [{
                "id": "is_cm", "title": "cm", "target_files": ["M1/Mult.lean"],
                "upstream_url": f"https://github.com/o/up/blob/{self.sha}/Up/Ch1.lean#L6-L8",
            }],
        }))
        write(os.path.join(m, "UPSTREAM.json"), json.dumps({"repo": "o/up", "commit": self.sha, "license": "Apache-2.0"}))
        write(os.path.join(m, "verify"), VERIFY)
        write(os.path.join(m, "M1", "Mult.lean"), CORE_SEED)

    def tearDown(self):
        self.tmp.cleanup()

    def export_with(self, proved, extra=()):
        pj = os.path.join(self.tmp.name, "proof.json")
        write(pj, json.dumps({"mission_id": "m1", "task_id": "is_cm", "spec_is_current": True,
                              "patch": make_patch("M1/Mult.lean", CORE_SEED, proved)}))
        self.out = os.path.join(self.tmp.name, "bundle")
        err, out = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
            code = ex.main(["--proof-json", pj, "--out", self.out, "--missions-root", self.missions,
                            "--upstream-url", "file://" + self.up, *extra])
        return code, err.getvalue(), out.getvalue()

    def test_builds_and_checks_axioms(self):
        proved = CORE_SEED.replace(
            "/-- Open", "theorem helper_one : liouville = 1 := rfl\n\n/-- Open"
        ).replace("liouville = 1 := by\n  sorry", "liouville = 1 := by\n  exact helper_one")
        code, err, out = self.export_with(proved, ["--lint-cmd", "test -f lakefile.toml"])
        self.assertEqual(code, 0, err + out)
        meta = json.loads(read(os.path.join(self.out, "metadata.json")))
        self.assertTrue(meta["built"])
        self.assertTrue(meta["checks"]["lake_build"])
        self.assertEqual(meta["checks"]["axioms"], [])
        self.assertEqual(meta["checks"]["lint"], [{"cmd": "test -f lakefile.toml", "ok": True}])
        self.assertIn("lake build Up.Ch1`: ok", read(os.path.join(self.out, "PR_BODY.md")))

    def test_rejects_a_proof_that_does_not_compile(self):
        proved = CORE_SEED.replace("liouville = 1 := by\n  sorry", "liouville = 1 := by\n  exact nonexistent_lemma")
        code, err, _ = self.export_with(proved)
        self.assertEqual(code, 1)
        self.assertIn("lake build Up.Ch1 failed", err)

    def test_rejects_non_standard_axioms(self):
        proved = CORE_SEED.replace(
            "/-- Open", "axiom cheat : liouville = 1\n\n/-- Open"
        ).replace("liouville = 1 := by\n  sorry", "liouville = 1 := by\n  exact cheat")
        code, err, _ = self.export_with(proved)
        self.assertEqual(code, 1)
        self.assertIn("non-standard axioms", err)


if __name__ == "__main__":
    unittest.main()
