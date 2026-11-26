#!/usr/bin/env python3
"""Tests for scripts/sunstead_verify.py, the public verifier served at
https://sunstead.org/verify.py.

Offline tests (`ParityTests`, `VerifyTests`) need no network and no Lean
(`--no-build`). `PublicBuildTests` runs end-to-end with `lake build` and the
standalone `AXIOM_CHECKER` whenever `lake` is on PATH.

Run: python3 scripts/test_sunstead_verify.py -v
"""
import contextlib
import hashlib
import importlib.util
import inspect
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
import urllib.error
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod  # inspect.getsource needs it for classes
    spec.loader.exec_module(mod)
    return mod


sv = load("sunstead_verify_under_test", "sunstead_verify.py")
scout = load("scout_upstream_for_parity", "scout-upstream.py")

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


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def git(cwd, *args):
    return subprocess.run([*GIT, *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def make_patch(path, before, after, mode=None):
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, os.path.dirname(path)))
        full = os.path.join(d, path)
        write(full, before)
        git(d, "init", "-q")
        git(d, "add", "-A")
        git(d, "commit", "-q", "-m", "s")
        write(full, after)
        if mode:
            os.chmod(full, int(mode, 8))
        return git(d, "diff")


def tar_of(directory, extra=()):
    """gzip tarball of `directory` (as the hub's seed bundle is), plus raw extra members."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for root, _, files in os.walk(directory):
            for fn in files:
                full = os.path.join(root, fn)
                tf.add(full, arcname=os.path.relpath(full, directory))
        for info, data in extra:
            tf.addfile(info, io.BytesIO(data) if data is not None else None)
    return buf.getvalue()


def member(name, data=b"x", kind=tarfile.REGTYPE, linkname=""):
    info = tarfile.TarInfo(name)
    info.type = kind
    info.linkname = linkname
    info.size = len(data) if kind == tarfile.REGTYPE else 0
    return info, (data if kind == tarfile.REGTYPE else None)


class ParityTests(unittest.TestCase):
    def test_lean_parsing_matches_scout_upstream(self):
        for name in ("mask_comments_and_strings", "split_declarations", "statement_end", "Decl"):
            self.assertEqual(
                inspect.getsource(getattr(sv, name)), inspect.getsource(getattr(scout, name)),
                f"{name} drifted from scripts/scout-upstream.py; copy it across",
            )
        for name in ("DECL_KINDS", "MODIFIERS", "PROOF_KINDS"):
            self.assertEqual(getattr(sv, name), getattr(scout, name))
        for name in ("DECL_RE", "SORRY_RE"):
            self.assertEqual(getattr(sv, name).pattern, getattr(scout, name).pattern)

    def test_stdlib_only(self):
        src = read(os.path.join(HERE, "sunstead_verify.py"))
        for line in src.splitlines():
            if line.startswith(("import ", "from ")):
                mod = line.split()[1].split(".")[0]
                self.assertIn(mod, {
                    "argparse", "ast", "hashlib", "io", "json", "os", "re", "shutil", "subprocess",
                    "sys", "tarfile", "tempfile", "time", "urllib", "dataclasses",
                }, line)


class VerifyTests(unittest.TestCase):
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

    def proof_with(self, patch=None, **kw):
        p = dict(self.proof)
        p["patch"] = patch or p["patch"]
        p["proof_id"] = hashlib.sha256(p["patch"].encode("utf-8")).hexdigest()
        p["upstream"] = {"repo": "o/up", "commit": self.sha}
        p.update(kw)
        return p

    def run_verify(self, proof=None, bundle=None, extra=("--no-build",)):
        t = self.tmp.name
        pj = os.path.join(t, "proof.json")
        write(pj, json.dumps(proof or self.proof_with()))
        bj = os.path.join(t, "seed.tar.gz")
        with open(bj, "wb") as f:
            f.write(bundle if bundle is not None else tar_of(os.path.join(self.missions, "m1")))
        argv = ["--proof-json", pj, "--seed-bundle", bj, "--upstream-url", "file://" + self.up, *extra]
        err, out = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
            code = sv.main(argv)
        return code, err.getvalue(), out.getvalue()

    def test_happy_path_matches_statement_and_splices(self):
        code, err, out = self.run_verify()
        self.assertEqual(code, 0, err)
        self.assertIn("STATEMENT MATCHES upstream", out)
        self.assertIn("Up.isCM_liouville", out)
        self.assertIn("o/up@", out)
        self.assertIn("helper lemmas added: M1.helper_one", out)

    def test_json_output(self):
        code, err, out = self.run_verify(extra=("--no-build", "--json"))
        self.assertEqual(code, 0, err)
        r = json.loads(out)
        self.assertFalse(r["verified"], "an unbuilt check must never say verified")
        self.assertEqual(r["upstream_declaration"], "Up.isCM_liouville")
        self.assertEqual(r["upstream_commit"], self.sha)

    def test_keep_writes_patched_upstream(self):
        keep = os.path.join(self.tmp.name, "kept")
        code, err, _ = self.run_verify(extra=("--no-build", "--keep", keep))
        self.assertEqual(code, 0, err)
        patched = read(os.path.join(keep, "Up", "Ch1.lean"))
        self.assertIn("exact helper_one", patched)
        self.assertIn("import Mathlib.Tactic.Ring", patched)
        self.assertEqual(patched.count("sorry"), 1, "only other_open retains sorry")
        code, err, _ = self.run_verify(extra=("--no-build", "--keep", keep))
        self.assertEqual(code, 2, "refuses to overwrite an existing --keep dir")

    def test_rejects_patch_that_does_not_hash_to_the_id(self):
        code, err, _ = self.run_verify(self.proof_with(proof_id="cd" * 32))
        self.assertEqual(code, 1)
        self.assertIn("not the requested id", err)

    def test_restated_theorem_uses_the_upstream_statement(self):
        # Only the proof is taken: the spliced declaration keeps the upstream
        # statement verbatim, and a real build's reference check decides.
        restated = PROVED_FILE.replace("liouville = 1 := by\n  --", "M1.liouville = 1 := by\n  --")
        keep = os.path.join(self.tmp.name, "kept")
        code, err, out = self.run_verify(
            self.proof_with(make_patch("M1/Mult.lean", SEED_FILE, restated)), extra=("--no-build", "--keep", keep)
        )
        self.assertEqual(code, 0, err)
        self.assertIn("restates the theorem", out)
        self.assertIn(
            "lemma isCM_liouville :\n    liouville = 1 := by\n  -- the actual proof",
            read(os.path.join(keep, "Up", "Ch1.lean")),
        )
        # Strict mode rejects any statement text change.
        with self.assertRaises(sv.VerifyError) as cm:
            sv.extract_contribution(SEED_FILE, restated, "M1.isCM_liouville", allow_restated=False)
        self.assertIn("changed the frozen statement", str(cm.exception))

    def test_rejects_upstream_mismatch(self):
        # A seed whose statement differs from upstream (a dishonest or stale hub) is caught upstream-side.
        seed2 = SEED_FILE.replace("liouville = 1", "liouville = 2")
        self.write_mission(seed=seed2)
        proved2 = PROVED_FILE.replace("liouville = 1", "liouville = 2")
        code, err, _ = self.run_verify(self.proof_with(make_patch("M1/Mult.lean", seed2, proved2)))
        self.assertEqual(code, 1)
        self.assertIn("upstream statement differs", err)

    def test_rejects_remaining_sorry(self):
        bad = PROVED_FILE.replace("exact helper_one", "sorry")
        code, err, _ = self.run_verify(self.proof_with(make_patch("M1/Mult.lean", SEED_FILE, bad)))
        self.assertEqual(code, 1)
        self.assertIn("still contains `sorry`", err)

    def test_refuses_sorry_in_a_helper(self):
        bad = PROVED_FILE.replace("(1 : Nat) = 1 := rfl", "(1 : Nat) = 1 := by sorry")
        code, err, _ = self.run_verify(self.proof_with(make_patch("M1/Mult.lean", SEED_FILE, bad)))
        self.assertEqual(code, 1)
        self.assertIn("helper M1.helper_one contains `sorry`", err)

    def test_does_not_duplicate_imports_upstream_already_has(self):
        proved = PROVED_FILE.replace("import Mathlib.Tactic.Ring\n", "import Mathlib.Tactic.Ring\nimport Mathlib\n")
        keep = os.path.join(self.tmp.name, "kept-imports")
        code, err, _ = self.run_verify(
            self.proof_with(make_patch("M1/Mult.lean", SEED_FILE, proved)),
            extra=("--no-build", "--keep", keep),
        )
        self.assertEqual(code, 0, err)
        patched = read(os.path.join(keep, "Up", "Ch1.lean"))
        self.assertEqual(patched.count("import Mathlib\n"), 1)
        self.assertEqual(patched.count("import Mathlib.Tactic.Ring\n"), 1)

    def test_refuses_mode_changes(self):
        patch = make_patch("M1/Mult.lean", SEED_FILE, PROVED_FILE, mode="755")
        self.assertIn("new mode 100755", patch)
        code, err, _ = self.run_verify(self.proof_with(patch))
        self.assertEqual(code, 1)
        self.assertIn("changes file mode", err)

    def test_ledger_and_bundle_upstream_must_agree(self):
        code, err, _ = self.run_verify(self.proof_with(upstream={"repo": "evil/up", "commit": self.sha}))
        self.assertEqual(code, 1)
        self.assertIn("disagree", err)

    def test_refuses_metaprogramming_unless_allowed(self):
        for snippet in (
            'elab "cheat" : tactic => pure ()',
            'macro "cheat" : tactic => `(tactic| rfl)',
            "@[implemented_by foo] def bar : Nat := 1",
            "initialize counter : IO.Ref Nat ← IO.mkRef 0",
            None,  # in-proof: run_tac
        ):
            # Directly after the helper, so it rides along with what gets spliced upstream.
            if snippet is None:
                proved = PROVED_FILE.replace("  exact helper_one", "  run_tac (pure ())\n  exact helper_one")
            else:
                proved = PROVED_FILE.replace(":= rfl\n", ":= rfl\n\n" + snippet + "\n")
            proof = self.proof_with(make_patch("M1/Mult.lean", SEED_FILE, proved))
            code, err, _ = self.run_verify(proof)
            self.assertEqual(code, 1, snippet)
            self.assertIn("runs code at build time", err)
        code, err, _ = self.run_verify(proof, extra=("--no-build", "--allow-metaprogramming"))
        self.assertEqual(code, 0, err)

    def test_metaprogramming_words_in_comments_and_names_are_fine(self):
        proved = PROVED_FILE.replace("-- the actual proof", "-- no macro or #eval here; elab-free")
        proved = proved.replace("theorem helper_one", "theorem macro_free_helper_one").replace("exact helper_one", "exact macro_free_helper_one")
        code, err, _ = self.run_verify(self.proof_with(make_patch("M1/Mult.lean", SEED_FILE, proved)))
        self.assertEqual(code, 0, err)

    def test_upstream_sorry_inside_a_larger_declaration_is_not_checkable(self):
        up = UPSTREAM_FILE.replace(
            "@[simp] lemma isCM_liouville :\n    liouville = 1 := by\n  sorry",
            "@[simp] lemma big_theorem :\n    liouville = 1 := by\n  have h : liouville = 1 := by\n    sorry\n  exact h",
        )
        write(os.path.join(self.up, "Up", "Ch1.lean"), up)
        git(self.up, "commit", "-qam", "nested")
        self.sha = git(self.up, "rev-parse", "HEAD").strip()
        self.write_mission()
        code, err, _ = self.run_verify()
        self.assertEqual(code, 3, err)
        self.assertIn("NOT CHECKABLE AGAINST UPSTREAM", err)

    def test_unsafe_bundles_are_rejected(self):
        base = os.path.join(self.missions, "m1")
        for bad in (
            member("../escape.txt"),
            member("/abs.txt"),
            member("M1/link.lean", kind=tarfile.SYMTYPE, linkname="/etc/passwd"),
            member("M1/hard.lean", kind=tarfile.LNKTYPE, linkname="sunstead.json"),
            member("dev", kind=tarfile.FIFOTYPE),
        ):
            code, err, _ = self.run_verify(bundle=tar_of(base, [bad]))
            self.assertEqual(code, 1, bad[0].name)
            self.assertIn(bad[0].name.lstrip("./"), err)

    def test_bundled_git_dir_is_dropped(self):
        # A .git/config with core.fsmonitor would run a command on `git add`.
        marker = os.path.join(self.tmp.name, "pwned")
        cfg = f"[core]\n\tfsmonitor = touch {marker}\n".encode()
        code, err, _ = self.run_verify(bundle=tar_of(os.path.join(self.missions, "m1"), [member(".git/config", cfg)]))
        self.assertEqual(code, 0, err)
        self.assertFalse(os.path.exists(marker))

    def test_missing_lake_is_a_clear_error(self):
        real = sv.shutil.which
        sv.shutil.which = lambda tool: None if tool == "lake" else real(tool)
        try:
            code, err, _ = self.run_verify(extra=())
        finally:
            sv.shutil.which = real
        self.assertEqual(code, 1)
        self.assertIn("`lake` not found", err)
        self.assertIn("elan", err)

    def test_reference_statement_is_the_pristine_upstream_statement(self):
        src = UPSTREAM_FILE
        mission = sv.load_mission(self.missions, self.proof)
        seed, proved = sv.proved_file(mission, self.proof["patch"], self.tmp.name)
        contrib = sv.extract_contribution(seed, proved, mission["theorem"])
        text, decl, span, ref = sv.transplant(src, mission, contrib)
        self.assertEqual(ref["name"], "Up.sunsteadRefStatement")
        self.assertEqual(ref["lines"], ["theorem sunsteadRefStatement :", "    liouville = 1 := sorry", ""])
        full = sv.with_reference(text, ref).split("\n")
        at = full.index("theorem sunsteadRefStatement :")
        helper = full.index("theorem helper_one : (1 : Nat) = 1 := rfl")
        self.assertLess(at, helper, "reference is elaborated before any contributed helper")
        self.assertEqual(full[span[0] - 1 + len(ref["lines"])], "/-- A helper the contributor added. -/")
        self.assertNotIn("sunsteadRefStatement", text, "the proposed file never contains the reference")

    def test_reference_keeps_scoped_prefixes_modifiers_and_dotted_names(self):
        class D:  # minimal stand-in for a parsed declaration
            name = "Patel2020.v1.challenge_x"
            start_line = 3
        lines = ["", "set_option maxHeartbeats 400000 in", "private theorem Patel2020.v1.challenge_x : P := by", "  sorry"]
        ref = sv.reference_statement(D, "@[simp] private theorem Patel2020.v1.challenge_x : P ", lines, lines, 1)
        self.assertEqual(ref["name"], "Patel2020.v1.sunsteadRefStatement")
        self.assertEqual(ref["lines"], [
            "set_option maxHeartbeats 400000 in",
            "private theorem Patel2020.v1.sunsteadRefStatement : P := sorry", "",
        ])
        D.name = "foo"
        with self.assertRaises(sv.VerifyError):
            sv.reference_statement(D, "def foo : Nat ", lines, lines, 1)

    def test_checker_compares_against_the_reference(self):
        self.assertIn("STATEMENT_MISMATCH", sv.AXIOM_CHECKER)
        self.assertIn("d.type != r.type", sv.AXIOM_CHECKER)
        with self.assertRaises(sv.VerifyError) as cm:
            sv.read_axioms("STATEMENT_MISMATCH Up.sunsteadRefStatement\n", "Up.isCM_liouville")
        self.assertIn("no longer states", str(cm.exception))
        with self.assertRaises(sv.VerifyError):
            sv.read_axioms("MISSING Up.sunsteadRefStatement\nSUNSTEAD_AXIOMS_DONE\n", "Up.isCM_liouville")

    def test_import_of_another_task_file_is_not_upstream_checkable(self):
        # Upstream has `Up/`, so `Up.Ch2` would have to exist there; it does not.
        proved = PROVED_FILE.replace("import Mathlib.Tactic.Ring\n", "import Mathlib.Tactic.Ring\nimport Up.Ch2\n")
        code, err, _ = self.run_verify(self.proof_with(make_patch("M1/Mult.lean", SEED_FILE, proved)))
        self.assertEqual(code, 3, err)
        self.assertIn("`Up.Ch2`, which is not a module of the upstream repository", err)

    def test_upstream_url_parsing_and_verify_table(self):
        sha = "e9906138410f8f76ca66b9bc252d0993f3ee348c"
        self.assertEqual(
            sv.parse_upstream_url(f"https://github.com/A/B/blob/{sha}/P/Q.lean#L1787-L1788"),
            ("A/B", sha, "P/Q.lean", 1787, 1788),
        )
        with self.assertRaises(sv.VerifyError):
            sv.parse_upstream_url("https://github.com/A/B/blob/main/P/Q.lean#L1")
        real = read(os.path.join(ROOT, "missions", "pnt-analytic-foundations", "verify"))
        self.assertEqual(
            sv.verify_theorems(real)["is_completely_multiplicative_liouville"],
            "PntFoundations.isCompletelyMultiplicative_liouville",
        )

    def test_real_missions_resolve(self):
        """Every live non-demo DAG task's upstream_url, pin and verify theorem line up."""
        missions_dir = os.path.join(ROOT, "missions")
        checked = []
        for mid in sorted(os.listdir(missions_dir)):
            mpath = os.path.join(missions_dir, mid, "sunstead.json")
            if not os.path.isfile(mpath):
                continue
            manifest = json.loads(read(mpath))
            if manifest.get("demo") or manifest.get("mode") != "dag":
                continue
            checked.append(mid)
            for t in manifest["tasks"]:
                m = sv.load_mission(missions_dir, {"mission_id": mid, "task_id": t["id"]})
                self.assertTrue(m["upstream_path"].endswith(".lean"), (mid, t["id"]))
                self.assertTrue(m["theorem"], (mid, t["id"]))
        self.assertIn("pnt-analytic-foundations", checked)
        self.assertIn("arklib-near-capacity-primes", checked)

    def test_lean_module_quotes_hyphenated_segments(self):
        self.assertEqual(sv.lean_module("Up/Ch1.lean"), "Up.Ch1")
        self.assertEqual(
            sv.lean_module("Proofs/AES-GCM/AESGCMEncKernelSym.lean"),
            "Proofs.«AES-GCM».AESGCMEncKernelSym",
        )
        self.assertIn("loadExts := false", sv.AXIOM_CHECKER)
        self.assertIn("parseLeanName", sv.AXIOM_CHECKER)

    def test_repo_snapshot_preserves_scoped_set_option_above_helpers(self):
        """Repo-snapshot splicing keeps `set_option ... in` attached to the theorem
        when inserting helpers above it."""
        snap_upstream = (
            "import Up.«AES-GCM».Pre\n\n"
            "namespace AESProgram\n\n"
            "abbrev rounds : Nat := 14\n\n"
            "set_option maxRecDepth 1000000 in\n"
            "theorem run_kernel :\n"
            "    rounds = 14 := by\n"
            "  sorry\n\n"
            "end AESProgram\n"
        )
        snap_proved = (
            "import Up.«AES-GCM».Pre\n"
            "import AESProgram.Extra\n\n"
            "namespace AESProgram\n\n"
            "abbrev rounds : Nat := 14\n\n"
            "theorem helper_rounds : AESProgram.rounds = 14 := rfl\n\n"
            "set_option maxRecDepth 1000000 in\n"
            "theorem run_kernel :\n"
            "    rounds = 14 := by\n"
            "  exact AESProgram.helper_rounds\n\n"
            "end AESProgram\n"
        )
        with tempfile.TemporaryDirectory() as t:
            up = os.path.join(t, "upstream")
            os.makedirs(os.path.join(up, "Up", "AES-GCM"))
            write(os.path.join(up, "Up", "AES-GCM", "Kernel.lean"), snap_upstream)
            git(up, "init", "-q")
            git(up, "add", "-A")
            git(up, "commit", "-q", "-m", "upstream")
            git(up, "config", "uploadpack.allowReachableSHA1InWant", "true")
            sha = git(up, "rev-parse", "HEAD").strip()

            m = os.path.join(t, "mission")
            os.makedirs(os.path.join(m, "Up", "AES-GCM"))
            write(os.path.join(m, "sunstead.json"), json.dumps({
                "id": "snap-aes", "title": "Snap AES", "tier": 1, "mode": "dag",
                "upstream": {"repo": "o/lnsym", "commit": sha, "license": "Apache-2.0"},
                "snapshot": {"mode": "repo-snapshot", "snapshot_id": "snap-aes"},
                "frozen_paths": ["UPSTREAM.json"],
                "tasks": [{
                    "id": "run_kernel", "title": "run",
                    "target_files": ["Up/AES-GCM/Kernel.lean"],
                    "upstream_url": f"https://github.com/o/lnsym/blob/{sha}/Up/AES-GCM/Kernel.lean#L8-L10",
                }],
            }))
            write(os.path.join(m, "UPSTREAM.json"), json.dumps({
                "repo": "o/lnsym", "commit": sha, "license": "Apache-2.0", "checks": [],
            }))
            write(os.path.join(m, "verify"), (
                'TASKS = {\n'
                '    "run_kernel": {\n'
                '        "theorem": "AESProgram.run_kernel",\n'
                '        "module": "Up.«AES-GCM».Kernel",\n'
                '        "target_files": ["Up/AES-GCM/Kernel.lean"],\n'
                '    },\n'
                '}\n'
            ))
            write(os.path.join(m, "Up", "AES-GCM", "Kernel.lean"), snap_upstream)

            patch = make_patch("Up/AES-GCM/Kernel.lean", snap_upstream, snap_proved)
            pj = os.path.join(t, "proof.json")
            bj = os.path.join(t, "seed.tar.gz")
            keep = os.path.join(t, "kept")
            write(pj, json.dumps({
                "proof_id": hashlib.sha256(patch.encode("utf-8")).hexdigest(),
                "mission_id": "snap-aes",
                "task_id": "run_kernel",
                "upstream": {"repo": "o/lnsym", "commit": sha},
                "patch": patch,
            }))
            with open(bj, "wb") as f:
                f.write(tar_of(m))
            err, stdout = io.StringIO(), io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(stdout):
                code = sv.main([
                    "--proof-json", pj, "--seed-bundle", bj,
                    "--upstream-url", "file://" + up, "--no-build", "--keep", keep,
                ])
            self.assertEqual(code, 0, err.getvalue())
            patched = read(os.path.join(keep, "Up", "AES-GCM", "Kernel.lean"))
            self.assertIn(
                "theorem helper_rounds : AESProgram.rounds = 14 := rfl\n\nset_option maxRecDepth 1000000 in\ntheorem run_kernel :",
                patched,
                "helper must be inserted above `set_option ... in`, keeping it attached to `theorem run_kernel`",
            )

    def test_bad_proof_id_argument(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code = sv.main(["not-a-hash", "--hub", "https://example.invalid"])
        self.assertEqual(code, 1)
        self.assertIn("64 hex", err.getvalue())

    def test_refuses_plain_http_hub(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code = sv.main(["ab" * 32, "--hub", "http://example.com"])
        self.assertEqual(code, 1)
        self.assertIn("non-https", err.getvalue())

    def test_refutation_and_subgoal_entries_are_not_upstream_checkable(self):
        code_ref, err_ref, _ = self.run_verify(self.proof_with(entry_kind="refutation"))
        self.assertEqual(code_ref, 3, err_ref)
        self.assertIn("NOT CHECKABLE AGAINST UPSTREAM", err_ref)
        self.assertIn("refutation (¬ T)", err_ref)

        code_sub, err_sub, _ = self.run_verify(self.proof_with(entry_kind="subgoal"))
        self.assertEqual(code_sub, 3, err_sub)
        self.assertIn("NOT CHECKABLE AGAINST UPSTREAM", err_sub)
        self.assertIn("decomposition subgoal", err_sub)

    def test_open_conjecture_positive_proof_verifies_cleanly(self):
        mpath = os.path.join(self.missions, "m1", "sunstead.json")
        manifest = json.loads(read(mpath))
        manifest["open_conjecture"] = True
        write(mpath, json.dumps(manifest))
        code, err, out = self.run_verify(self.proof_with(entry_kind="proof"))
        self.assertEqual(code, 0, err)
        self.assertIn("STATEMENT MATCHES upstream", out)

    def test_lean436_module_system_parse_and_transplant(self):
        mod_upstream = (
            "module\n\n"
            "public import Up.Core\n\n"
            "@[expose] public section\n\n"
            "namespace Up\n\n"
            "public def baseVal : Nat := 1\n\n"
            "public theorem target_thm : baseVal = 1 := by\n"
            "  sorry\n\n"
            "public section Extra\n\n"
            "public lemma other_lemma : True := by\n"
            "  sorry\n\n"
            "end Extra\n\n"
            "end Up\n"
        )
        mod_proved = (
            "module\n\n"
            "public import Up.Core\n"
            "public import Mathlib.Tactic.Ring\n"
            "private import Init.Data.Nat.Basic\n\n"
            "@[expose] public section\n\n"
            "namespace Up\n\n"
            "public def baseVal : Nat := 1\n\n"
            "private lemma helper_base : baseVal = 1 := rfl\n\n"
            "public theorem target_thm : baseVal = 1 := by\n"
            "  exact helper_base\n\n"
            "public section Extra\n\n"
            "public lemma other_lemma : True := by\n"
            "  sorry\n\n"
            "end Extra\n\n"
            "end Up\n"
        )
        decls = sv.split_declarations(mod_upstream)
        by_name = {d.name: d for d in decls}
        self.assertIn("Up.baseVal", by_name)
        self.assertEqual(by_name["Up.baseVal"].kind, "def")
        self.assertIn("Up.target_thm", by_name)
        self.assertEqual(by_name["Up.target_thm"].kind, "theorem")
        # Declaration stops cleanly before `public section Extra`.
        self.assertNotIn("public section Extra", by_name["Up.target_thm"].raw)
        self.assertIn("Up.other_lemma", by_name)
        self.assertEqual(by_name["Up.other_lemma"].kind, "lemma")
        self.assertTrue(sv.has_module_header(mod_upstream))
        self.assertFalse(sv.has_module_header(UPSTREAM_FILE))

        self.assertEqual(
            sv.parse_imports(mod_proved),
            [
                ("Up.Core", "public import"),
                ("Mathlib.Tactic.Ring", "public import"),
                ("Init.Data.Nat.Basic", "private import"),
            ],
        )

        # End-to-end splice on a module-system repo-snapshot fixture.
        with tempfile.TemporaryDirectory() as t:
            up = os.path.join(t, "upstream")
            os.makedirs(os.path.join(up, "Up"))
            write(os.path.join(up, "Up", "Mod.lean"), mod_upstream)
            git(up, "init", "-q")
            git(up, "add", "-A")
            git(up, "commit", "-q", "-m", "upstream")
            git(up, "config", "uploadpack.allowReachableSHA1InWant", "true")
            sha = git(up, "rev-parse", "HEAD").strip()

            m = os.path.join(t, "mission")
            os.makedirs(os.path.join(m, "Up"))
            write(os.path.join(m, "sunstead.json"), json.dumps({
                "id": "mod-snap", "title": "Mod Snap", "tier": 1, "mode": "dag",
                "upstream": {"repo": "o/modup", "commit": sha, "license": "Apache-2.0"},
                "snapshot": {"mode": "repo-snapshot", "snapshot_id": "mod-snap", "allow_module_system": True},
                "frozen_paths": ["UPSTREAM.json"],
                "tasks": [{
                    "id": "target_thm", "title": "t",
                    "target_files": ["Up/Mod.lean"],
                    "upstream_url": f"https://github.com/o/modup/blob/{sha}/Up/Mod.lean#L11-L12",
                }],
            }))
            write(os.path.join(m, "UPSTREAM.json"), json.dumps({
                "repo": "o/modup", "commit": sha, "license": "Apache-2.0", "checks": [],
            }))
            write(os.path.join(m, "verify"), (
                'TASKS = {\n'
                '    "target_thm": {\n'
                '        "module": "Up.Mod",\n'
                '        "theorem": "Up.target_thm",\n'
                '    },\n'
                '}\n'
            ))
            write(os.path.join(m, "Up", "Mod.lean"), mod_upstream)

            patch = make_patch("Up/Mod.lean", mod_upstream, mod_proved)
            pj, bj = os.path.join(t, "proof.json"), os.path.join(t, "seed.tar.gz")
            keep = os.path.join(t, "kept-mod")
            write(pj, json.dumps({
                "proof_id": hashlib.sha256(patch.encode()).hexdigest(),
                "mission_id": "mod-snap", "task_id": "target_thm",
                "upstream": {"repo": "o/modup", "commit": sha},
                "patch": patch,
            }))
            with open(bj, "wb") as f:
                f.write(tar_of(m))

            err, stdout = io.StringIO(), io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(stdout):
                code = sv.main([
                    "--proof-json", pj, "--seed-bundle", bj,
                    "--upstream-url", "file://" + up, "--no-build", "--keep", keep,
                ])
            self.assertEqual(code, 0, err.getvalue())
            patched = read(os.path.join(keep, "Up", "Mod.lean"))
            lines = patched.splitlines()
            self.assertEqual(lines[0], "module", "`module` directive must remain at top of file")
            self.assertEqual(lines[2], "public import Up.Core")
            self.assertEqual(lines[3], "public import Mathlib.Tactic.Ring")
            self.assertEqual(lines[4], "private import Init.Data.Nat.Basic")
            self.assertEqual(patched.count("Up.Core"), 1, "must not duplicate existing public import")
            self.assertIn("private lemma helper_base : baseVal = 1 := rfl", patched)
            self.assertIn("exact helper_base", patched)

            # Missing upstream module added via `public import` must still be caught as exit 3.
            bad_proved = mod_proved.replace(
                "public import Mathlib.Tactic.Ring\n",
                "public import Up.MissingTaskFile\n",
            )
            bad_patch = make_patch("Up/Mod.lean", mod_upstream, bad_proved)
            write(pj, json.dumps({
                "proof_id": hashlib.sha256(bad_patch.encode()).hexdigest(),
                "mission_id": "mod-snap", "task_id": "target_thm",
                "upstream": {"repo": "o/modup", "commit": sha},
                "patch": bad_patch,
            }))
            err2, out2 = io.StringIO(), io.StringIO()
            with contextlib.redirect_stderr(err2), contextlib.redirect_stdout(out2):
                code2 = sv.main([
                    "--proof-json", pj, "--seed-bundle", bj,
                    "--upstream-url", "file://" + up, "--no-build",
                ])
            self.assertEqual(code2, 3, err2.getvalue())
            self.assertIn("Up.MissingTaskFile", err2.getvalue())

        # `axiom_checker_source` adds `importAll := true` only when module system is active.
        self.assertNotIn("importAll", sv.axiom_checker_source(import_all=False))
        mod_checker = sv.axiom_checker_source(import_all=True)
        self.assertIn("importAll := true", mod_checker)
        self.assertIn("loadExts := false", mod_checker)

        # Real Sphere-Packing-Lean mission resolves with allow_module_system=True.
        sp_dir = os.path.join(ROOT, "missions")
        sp_m = sv.load_mission(sp_dir, {
            "mission_id": "sphere-packing-e8-foundations",
            "task_id": "e8_sphere_packing_main_theorem",
        })
        self.assertTrue(sp_m["allow_module_system"])
        sp_main = read(os.path.join(sp_dir, "sphere-packing-e8-foundations", "SpherePacking", "MainTheorem.lean"))
        self.assertTrue(sv.has_module_header(sp_main))
        self.assertEqual(sv.parse_imports(sp_main), [("SpherePacking.Basic.E8", "public import")])
        sp_decls = sv.split_declarations(sp_main)
        self.assertEqual([d.name for d in sp_decls], ["SpherePacking.MainTheorem"])

    def test_module_file_without_imports_inserts_after_module_header(self):
        src = "/- header -/\nmodule\n\npublic theorem t : True := by\n  sorry\n"
        self.assertEqual(sv.header_import_insert_line(src), 2)
        mission = {
            "theorem": "t", "upstream_path": "Up/M.lean", "upstream_lines": (4, 5),
        }
        contrib = {
            "statement": "public theorem t : True ",
            "proof": ":= by\n  trivial",
            "helpers": [],
            "new_imports": ["Mathlib.Tactic.Ring"],
            "new_import_prefixes": {"Mathlib.Tactic.Ring": "public import"},
        }
        text, decl, span, ref = sv.transplant(src, mission, contrib)
        lines = text.splitlines()
        self.assertEqual(lines[1], "module")
        self.assertEqual(lines[2], "public import Mathlib.Tactic.Ring")
        self.assertEqual(ref["lines"][0], "public theorem sunsteadRefStatement : True := sorry")

    def test_self_contained_and_hillclimb_arenas_return_exit_3(self):
        # 1. Mission without UPSTREAM.json -> NotUpstreamCheckable (exit 3), not FileNotFoundError (exit 2).
        os.unlink(os.path.join(self.missions, "m1", "UPSTREAM.json"))
        code, err, _ = self.run_verify()
        self.assertEqual(code, 3, err)
        self.assertIn("NOT CHECKABLE AGAINST UPSTREAM", err)
        self.assertIn("UPSTREAM.json", err)

        # 2. Task without upstream_url -> NotUpstreamCheckable (exit 3).
        self.write_mission()
        mpath = os.path.join(self.missions, "m1", "sunstead.json")
        manifest = json.loads(read(mpath))
        manifest["tasks"][0].pop("upstream_url", None)
        write(mpath, json.dumps(manifest))
        code2, err2, _ = self.run_verify()
        self.assertEqual(code2, 3, err2)
        self.assertIn("NOT CHECKABLE AGAINST UPSTREAM", err2)
        self.assertIn("no upstream_url", err2)

        # 3. Hill-climb mission (both synthetic and real repo missions) -> NotUpstreamCheckable (exit 3).
        self.write_mission()
        manifest = json.loads(read(mpath))
        manifest["mode"] = "hillclimb"
        write(mpath, json.dumps(manifest))
        code3, err3, _ = self.run_verify()
        self.assertEqual(code3, 3, err3)
        self.assertIn("NOT CHECKABLE AGAINST UPSTREAM", err3)
        self.assertIn("hill-climb", err3)

        missions_dir = os.path.join(ROOT, "missions")
        for mid, tid in (
            ("coding-theory-bounds", "code_17_8"),
            ("matrix-rank444-f2", "reduce_rank"),
            ("sorting-networks-opt", "sort_n9"),
        ):
            with self.assertRaises(sv.NotUpstreamCheckable):
                sv.load_mission(missions_dir, {"mission_id": mid, "task_id": tid})

    def test_fetch_retries_transient_errors_and_never_retries_permanent_ones(self):
        class FakeResp:
            def __init__(self, payload: bytes):
                self._payload = payload

            def read(self, n=-1):
                return self._payload[:n] if n >= 0 else self._payload

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        # 1. Transient 503 then 429 then 200 -> succeeds with exponential backoff sleeps.
        sleeps = []
        outcomes = [
            urllib.error.HTTPError("https://example.invalid/a", 503, "Unavailable", {}, None),
            urllib.error.HTTPError("https://example.invalid/a", 429, "Too Many", {}, None),
            FakeResp(b"ok-bytes"),
        ]
        calls = []

        def fake_urlopen(req, timeout=None):
            calls.append(timeout)
            item = outcomes.pop(0)
            if isinstance(item, Exception):
                raise item
            return item

        with mock.patch.object(sv.urllib.request, "urlopen", side_effect=fake_urlopen):
            data = sv.fetch("https://example.invalid/a", sleep=sleeps.append)
        self.assertEqual(data, b"ok-bytes")
        self.assertEqual(calls, [120, 120, 120])
        self.assertEqual(sleeps, [0.5, 1.5])

        # 2. Transient URLError then 200 -> retries and succeeds.
        sleeps.clear()
        url_outcomes = [urllib.error.URLError("connection reset"), FakeResp(b"recovered")]
        with mock.patch.object(
            sv.urllib.request, "urlopen",
            side_effect=lambda req, timeout=None: (_ for _ in ()).throw(url_outcomes.pop(0))
            if isinstance(url_outcomes[0], Exception) else url_outcomes.pop(0),
        ):
            self.assertEqual(sv.fetch("https://example.invalid/b", sleep=sleeps.append), b"recovered")
        self.assertEqual(sleeps, [0.5])

        # 3. Exhausting transient 502 retries stops at 3 attempts and re-raises HTTPError.
        sleeps.clear()
        attempts_seen = []

        def always_502(req, timeout=None):
            attempts_seen.append(1)
            raise urllib.error.HTTPError(req.full_url, 502, "Bad Gateway", {}, None)

        with mock.patch.object(sv.urllib.request, "urlopen", side_effect=always_502):
            with self.assertRaises(urllib.error.HTTPError) as cm502:
                sv.fetch("https://example.invalid/c", sleep=sleeps.append)
        self.assertEqual(cm502.exception.code, 502)
        self.assertEqual(len(attempts_seen), 3)
        self.assertEqual(sleeps, [0.5, 1.5])

        # 4. Permanent HTTP 404 is NOT retried.
        sleeps.clear()
        seen_404 = []

        def always_404(req, timeout=None):
            seen_404.append(1)
            raise urllib.error.HTTPError(req.full_url, 404, "Not Found", {}, None)

        with mock.patch.object(sv.urllib.request, "urlopen", side_effect=always_404):
            with self.assertRaises(urllib.error.HTTPError) as cm404:
                sv.fetch("https://example.invalid/missing", sleep=sleeps.append)
        self.assertEqual(cm404.exception.code, 404)
        self.assertEqual(len(seen_404), 1)
        self.assertEqual(sleeps, [])

        # 5. Oversized download (> limit) is NOT retried and enforces limit strictly.
        sleeps.clear()
        seen_big = []

        def big_resp(req, timeout=None):
            seen_big.append(1)
            return FakeResp(b"x" * 100)

        with mock.patch.object(sv.urllib.request, "urlopen", side_effect=big_resp):
            with self.assertRaises(sv.VerifyError) as cm_big:
                sv.fetch("https://example.invalid/big", limit=16, sleep=sleeps.append)
        self.assertIn("larger than 16 bytes", str(cm_big.exception))
        self.assertEqual(len(seen_big), 1)
        self.assertEqual(sleeps, [])

        # 6. Non-https URL is rejected immediately with 0 urlopen calls.
        with mock.patch.object(sv.urllib.request, "urlopen", side_effect=AssertionError("must not call")):
            with self.assertRaises(sv.VerifyError):
                sv.fetch("http://example.invalid/plain", sleep=sleeps.append)


@unittest.skipUnless(sv.shutil.which("lake"), "needs a Lean toolchain (lake on PATH)")
class PublicBuildTests(unittest.TestCase):
    """End-to-end `verify.py` tests including `lake build`, statement-meaning
    reference check, and standalone `AXIOM_CHECKER` on core-Lean-only fixtures."""

    def setUp(self):
        self.make_fixture(CORE_UPSTREAM)

    def make_fixture(self, upstream_text, seed=None):
        self.seed = seed or CORE_SEED
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.up = os.path.join(t, "upstream")
        os.makedirs(os.path.join(self.up, "Up"))
        write(os.path.join(self.up, "Up", "Ch1.lean"), upstream_text)
        line = upstream_text.split("\n").index("theorem isCM_liouville :") + 1
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
                "upstream_url": f"https://github.com/o/up/blob/{self.sha}/Up/Ch1.lean#L{line}-L{line + 2}",
            }],
        }))
        write(os.path.join(m, "UPSTREAM.json"), json.dumps({"repo": "o/up", "commit": self.sha, "license": "Apache-2.0"}))
        write(os.path.join(m, "verify"), VERIFY)
        write(os.path.join(m, "M1", "Mult.lean"), self.seed)

    def tearDown(self):
        self.tmp.cleanup()

    def run_public(self, proved, extra=()):
        patch = make_patch("M1/Mult.lean", self.seed, proved)
        t = self.tmp.name
        pj, bj = os.path.join(t, "proof.json"), os.path.join(t, "seed.tar.gz")
        write(pj, json.dumps({
            "proof_id": hashlib.sha256(patch.encode()).hexdigest(), "mission_id": "m1", "task_id": "is_cm",
            "patch": patch, "upstream": {"repo": "o/up", "commit": self.sha},
        }))
        with open(bj, "wb") as f:
            f.write(tar_of(os.path.join(self.missions, "m1")))
        err, out = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
            code = sv.main(["--proof-json", pj, "--seed-bundle", bj, "--upstream-url", "file://" + self.up, "--json", *extra])
        return code, err.getvalue(), out.getvalue()

    def test_verifies_against_upstream_with_helper_and_clean_keep(self):
        proved = CORE_SEED.replace(
            "/-- Open", "theorem helper_one : liouville = 1 := rfl\n\n/-- Open"
        ).replace("liouville = 1 := by\n  sorry", "liouville = 1 := by\n  exact helper_one")
        keep = os.path.join(self.tmp.name, "kept-built")
        code, err, out = self.run_public(proved, extra=("--keep", keep))
        self.assertEqual(code, 0, err)
        r = json.loads(out)
        self.assertTrue(r["verified"])
        self.assertEqual(r["axioms"], [])
        self.assertEqual(r["helpers"], ["M1.helper_one"])
        self.assertNotIn("sunsteadRefStatement", read(os.path.join(keep, "Up", "Ch1.lean")))

    def test_rejects_meaning_changing_instance(self):
        # A high-priority `LE Nat` instance among the helpers would make the upstream
        # statement `liouville ≤ 0` (false) elaborate to `True`. The pristine
        # reference copy, built above the helpers, catches it.
        self.tmp.cleanup()
        self.make_fixture(
            CORE_UPSTREAM.replace("liouville = 1 := by", "liouville ≤ 0 := by"),
            seed=CORE_SEED.replace("liouville = 1 := by", "liouville ≤ 0 := by"),
        )
        proved = self.seed.replace(
            "/-- Open", "theorem helper_ok : True := trivial\n\n"
            "instance (priority := high) cheatLE : LE Nat := ⟨fun _ _ => True⟩\n\n/-- Open"
        ).replace("liouville ≤ 0 := by\n  sorry", "liouville ≤ 0 := by\n  trivial")
        code, err, _ = self.run_public(proved)
        self.assertEqual(code, 1, err)
        self.assertIn("no longer states what the upstream statement states", err)

    def test_rejects_a_proof_that_does_not_compile_with_compiler_output(self):
        proved = CORE_SEED.replace("liouville = 1 := by\n  sorry", "liouville = 1 := by\n  exact nonexistent_lemma")
        code, err, _ = self.run_public(proved)
        self.assertEqual(code, 1)
        self.assertIn("lake build Up.Ch1 failed", err)
        self.assertIn("nonexistent_lemma", err)

    def test_rejects_non_standard_axioms(self):
        proved = CORE_SEED.replace(
            "/-- Open", "axiom cheat : liouville = 1\n\n/-- Open"
        ).replace("liouville = 1 := by\n  sorry", "liouville = 1 := by\n  exact cheat")
        code, err, _ = self.run_public(proved)
        self.assertEqual(code, 1)
        self.assertIn("non-standard axioms", err)

    def test_axiom_report_cannot_be_spoofed_by_elaborators(self):
        # A source file that rewrites `#print axioms` output (redteam.py's
        # lean-spoof-axiom-report). The checker loads .oleans with loadExts := false
        # and never elaborates source, so the helper axiom is still caught.
        self.tmp.cleanup()
        self.make_fixture(
            "import Lean\nopen Lean Elab Command\n\n"
            "elab_rules : command\n"
            "  | `(#print axioms $_) => logInfo \"'Up.isCM_liouville' does not depend on any axioms\"\n\n"
            + CORE_UPSTREAM
        )
        proved = CORE_SEED.replace(
            "/-- Open", "axiom cheat : liouville = 1\n\n/-- Open"
        ).replace("liouville = 1 := by\n  sorry", "liouville = 1 := by\n  exact cheat")
        code, err, _ = self.run_public(proved)
        self.assertEqual(code, 1, err)
        self.assertIn("non-standard axioms: ['Up.cheat']", err)

    def test_builds_and_checks_guillemet_module_path(self):
        """Full `lake build` + `AXIOM_CHECKER` on a repo-snapshot mission with a
        hyphenated directory (`Up/AES-GCM/Kernel.lean` -> `Up.«AES-GCM».Kernel`)
        and `set_option ... in`."""
        snap_src = (
            "namespace AESProgram\n\n"
            "abbrev rounds : Nat := 14\n\n"
            "set_option maxRecDepth 1000000 in\n"
            "theorem run_kernel :\n"
            "    rounds = 14 := by\n"
            "  sorry\n\n"
            "end AESProgram\n"
        )
        snap_proved = (
            "namespace AESProgram\n\n"
            "abbrev rounds : Nat := 14\n\n"
            "theorem helper_rounds : AESProgram.rounds = 14 := rfl\n\n"
            "set_option maxRecDepth 1000000 in\n"
            "theorem run_kernel :\n"
            "    rounds = 14 := by\n"
            "  exact AESProgram.helper_rounds\n\n"
            "end AESProgram\n"
        )
        with tempfile.TemporaryDirectory() as t:
            up = os.path.join(t, "upstream")
            os.makedirs(os.path.join(up, "Up", "AES-GCM"))
            write(os.path.join(up, "Up", "AES-GCM", "Kernel.lean"), snap_src)
            write(os.path.join(up, "Up.lean"), "import Up.«AES-GCM».Kernel\n")
            write(os.path.join(up, "lakefile.toml"), 'name = "up"\ndefaultTargets = ["Up"]\n\n[[lean_lib]]\nname = "Up"\n')
            toolchain = os.environ.get("SUNSTEAD_TEST_TOOLCHAIN") or read(
                os.path.join(ROOT, "missions", "pnt-analytic-foundations", "lean-toolchain")
            ).strip()
            write(os.path.join(up, "lean-toolchain"), toolchain + "\n")
            git(up, "init", "-q")
            git(up, "add", "-A")
            git(up, "commit", "-q", "-m", "upstream")
            git(up, "config", "uploadpack.allowReachableSHA1InWant", "true")
            sha = git(up, "rev-parse", "HEAD").strip()

            m = os.path.join(t, "mission")
            os.makedirs(os.path.join(m, "Up", "AES-GCM"))
            write(os.path.join(m, "sunstead.json"), json.dumps({
                "id": "snap-aes", "title": "Snap AES", "tier": 1, "mode": "dag",
                "upstream": {"repo": "o/lnsym", "commit": sha, "license": "Apache-2.0"},
                "snapshot": {"mode": "repo-snapshot", "snapshot_id": "snap-aes"},
                "frozen_paths": [],
                "tasks": [{
                    "id": "run_kernel", "title": "run",
                    "target_files": ["Up/AES-GCM/Kernel.lean"],
                    "upstream_url": f"https://github.com/o/lnsym/blob/{sha}/Up/AES-GCM/Kernel.lean#L6-L8",
                }],
            }))
            write(os.path.join(m, "UPSTREAM.json"), json.dumps({
                "repo": "o/lnsym", "commit": sha, "license": "Apache-2.0",
            }))
            write(os.path.join(m, "verify"), (
                'TASKS = {\n'
                '    "run_kernel": {\n'
                '        "module": "Up.«AES-GCM».Kernel",\n'
                '        "theorem": "AESProgram.run_kernel",\n'
                '    },\n'
                '}\n'
            ))
            write(os.path.join(m, "Up", "AES-GCM", "Kernel.lean"), snap_src)

            patch = make_patch("Up/AES-GCM/Kernel.lean", snap_src, snap_proved)
            pj, bj = os.path.join(t, "proof.json"), os.path.join(t, "seed.tar.gz")
            write(pj, json.dumps({
                "proof_id": hashlib.sha256(patch.encode()).hexdigest(),
                "mission_id": "snap-aes", "task_id": "run_kernel",
                "upstream": {"repo": "o/lnsym", "commit": sha},
                "patch": patch,
            }))
            with open(bj, "wb") as f:
                f.write(tar_of(m))
            err, stdout = io.StringIO(), io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(stdout):
                code = sv.main([
                    "--proof-json", pj, "--seed-bundle", bj,
                    "--upstream-url", "file://" + up, "--json",
                ])
            self.assertEqual(code, 0, err.getvalue() + stdout.getvalue())
            r = json.loads(stdout.getvalue())
            self.assertTrue(r["verified"])
            self.assertEqual(r["axioms"], [])
            self.assertEqual(r["upstream_file"], "Up/AES-GCM/Kernel.lean")
            self.assertEqual(r["upstream_declaration"], "AESProgram.run_kernel")
            self.assertIn("Building Up.«AES-GCM».Kernel", err.getvalue())

    def test_builds_and_checks_lean436_module_system_and_catches_private_axiom(self):
        """Full `lake build` + `AXIOM_CHECKER` (`importAll := true`) on a Lean 4.36
        `module`-system fixture with `public import`, `public theorem`, and private helper."""
        core_src = (
            "module\n\n"
            "namespace ModUp\n"
            "@[expose] public def baseFactor : Nat := 11\n"
            "end ModUp\n"
        )
        mod_seed = (
            "module\n\n"
            "public import Up.Core\n\n"
            "namespace ModUp\n\n"
            "public theorem factor_eq : baseFactor = 11 := by\n"
            "  sorry\n\n"
            "end ModUp\n"
        )
        mod_honest = (
            "module\n\n"
            "public import Up.Core\n\n"
            "namespace ModUp\n\n"
            "private theorem helper_factor : baseFactor = 11 := rfl\n\n"
            "public theorem factor_eq : baseFactor = 11 := by\n"
            "  exact helper_factor\n\n"
            "end ModUp\n"
        )
        mod_cheat = (
            "module\n\n"
            "public import Up.Core\n\n"
            "namespace ModUp\n\n"
            "private axiom cheat_ax : baseFactor = 11\n\n"
            "public theorem factor_eq : baseFactor = 11 := by\n"
            "  exact cheat_ax\n\n"
            "end ModUp\n"
        )
        with tempfile.TemporaryDirectory() as t:
            up = os.path.join(t, "upstream")
            os.makedirs(os.path.join(up, "Up"))
            write(os.path.join(up, "Up", "Core.lean"), core_src)
            write(os.path.join(up, "Up", "Target.lean"), mod_seed)
            write(os.path.join(up, "Up.lean"), "import Up.Target\n")
            write(os.path.join(up, "lakefile.toml"), 'name = "up"\ndefaultTargets = ["Up"]\n\n[[lean_lib]]\nname = "Up"\n')
            toolchain = os.environ.get("SUNSTEAD_TEST_TOOLCHAIN") or read(
                os.path.join(ROOT, "missions", "pnt-analytic-foundations", "lean-toolchain")
            ).strip()
            write(os.path.join(up, "lean-toolchain"), toolchain + "\n")
            git(up, "init", "-q")
            git(up, "add", "-A")
            git(up, "commit", "-q", "-m", "upstream")
            git(up, "config", "uploadpack.allowReachableSHA1InWant", "true")
            sha = git(up, "rev-parse", "HEAD").strip()

            m = os.path.join(t, "mission")
            os.makedirs(os.path.join(m, "Up"))
            write(os.path.join(m, "sunstead.json"), json.dumps({
                "id": "mod-snap", "title": "Mod Snap", "tier": 1, "mode": "dag",
                "upstream": {"repo": "o/modup", "commit": sha, "license": "Apache-2.0"},
                "snapshot": {"mode": "repo-snapshot", "snapshot_id": "mod-snap", "allow_module_system": True},
                "frozen_paths": [],
                "tasks": [{
                    "id": "factor_eq", "title": "factor",
                    "target_files": ["Up/Target.lean"],
                    "upstream_url": f"https://github.com/o/modup/blob/{sha}/Up/Target.lean#L7-L8",
                }],
            }))
            write(os.path.join(m, "UPSTREAM.json"), json.dumps({
                "repo": "o/modup", "commit": sha, "license": "Apache-2.0",
            }))
            write(os.path.join(m, "verify"), (
                'TASKS = {\n'
                '    "factor_eq": {\n'
                '        "module": "Up.Target",\n'
                '        "theorem": "ModUp.factor_eq",\n'
                '    },\n'
                '}\n'
            ))
            write(os.path.join(m, "Up", "Target.lean"), mod_seed)

            bj = os.path.join(t, "seed.tar.gz")
            with open(bj, "wb") as f:
                f.write(tar_of(m))

            # 1. Honest proof verifies cleanly with 0 non-standard axioms.
            patch = make_patch("Up/Target.lean", mod_seed, mod_honest)
            pj = os.path.join(t, "proof.json")
            write(pj, json.dumps({
                "proof_id": hashlib.sha256(patch.encode()).hexdigest(),
                "mission_id": "mod-snap", "task_id": "factor_eq",
                "upstream": {"repo": "o/modup", "commit": sha},
                "patch": patch,
            }))
            err, stdout = io.StringIO(), io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(stdout):
                code = sv.main([
                    "--proof-json", pj, "--seed-bundle", bj,
                    "--upstream-url", "file://" + up, "--json",
                ])
            self.assertEqual(code, 0, err.getvalue() + stdout.getvalue())
            r = json.loads(stdout.getvalue())
            self.assertTrue(r["verified"])
            self.assertEqual(r["axioms"], [])

            # 2. Private axiom inside a `module` file is caught via `importAll := true`.
            cheat_patch = make_patch("Up/Target.lean", mod_seed, mod_cheat)
            write(pj, json.dumps({
                "proof_id": hashlib.sha256(cheat_patch.encode()).hexdigest(),
                "mission_id": "mod-snap", "task_id": "factor_eq",
                "upstream": {"repo": "o/modup", "commit": sha},
                "patch": cheat_patch,
            }))
            err2, stdout2 = io.StringIO(), io.StringIO()
            with contextlib.redirect_stderr(err2), contextlib.redirect_stdout(stdout2):
                code2 = sv.main([
                    "--proof-json", pj, "--seed-bundle", bj,
                    "--upstream-url", "file://" + up, "--json",
                ])
            self.assertEqual(code2, 1, err2.getvalue() + stdout2.getvalue())
            self.assertIn("non-standard axioms", err2.getvalue())


if __name__ == "__main__":
    unittest.main()
