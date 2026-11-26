#!/usr/bin/env python3
"""Offline tests for scripts/sunstead_verify.py, the public verifier served at
https://sunstead.org/verify.py (no network, no Lean: --no-build).

The build, axiom and spoofing paths are shared with export-upstream.py and
covered by test_export_upstream.py's BuildTests.

Run: python3 scripts/test_sunstead_verify.py
"""
import contextlib
import hashlib
import importlib.util
import inspect
import io
import json
import os
import sys
import tarfile
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod  # inspect.getsource needs it for classes
    spec.loader.exec_module(mod)
    return mod


sv = load("sunstead_verify_under_test", "sunstead_verify.py")
scout = load("scout_upstream_for_parity", "scout-upstream.py")
fx = load("export_fixtures", "test_export_upstream.py")


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
        src = fx.read(os.path.join(HERE, "sunstead_verify.py"))
        for line in src.splitlines():
            if line.startswith(("import ", "from ")):
                mod = line.split()[1].split(".")[0]
                self.assertIn(mod, {
                    "argparse", "ast", "hashlib", "io", "json", "os", "re", "shutil", "subprocess",
                    "sys", "tarfile", "tempfile", "urllib", "dataclasses",
                }, line)


class VerifyTests(fx.ExportTests.__base__):
    # Reuse ExportTests' fixture (fake upstream git repo + mission m1) without its tests.
    setUp = fx.ExportTests.setUp
    tearDown = fx.ExportTests.tearDown
    write_mission = fx.ExportTests.write_mission

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
        fx.write(pj, json.dumps(proof or self.proof_with()))
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
        self.assertIn("exact helper_one", fx.read(os.path.join(keep, "Up", "Ch1.lean")))
        code, err, _ = self.run_verify(extra=("--no-build", "--keep", keep))
        self.assertEqual(code, 2, "refuses to overwrite an existing --keep dir")

    def test_rejects_patch_that_does_not_hash_to_the_id(self):
        code, err, _ = self.run_verify(self.proof_with(proof_id="cd" * 32))
        self.assertEqual(code, 1)
        self.assertIn("not the requested id", err)

    def test_restated_theorem_uses_the_upstream_statement(self):
        # Only the proof is taken: the spliced declaration keeps the upstream
        # statement verbatim, and a real build's reference check decides.
        restated = fx.PROVED_FILE.replace("liouville = 1 := by\n  --", "M1.liouville = 1 := by\n  --")
        keep = os.path.join(self.tmp.name, "kept")
        code, err, out = self.run_verify(
            self.proof_with(fx.make_patch("M1/Mult.lean", fx.SEED_FILE, restated)), extra=("--no-build", "--keep", keep)
        )
        self.assertEqual(code, 0, err)
        self.assertIn("restates the theorem", out)
        self.assertIn("lemma isCM_liouville :\n    liouville = 1 := by\n  -- the actual proof", fx.read(os.path.join(keep, "Up", "Ch1.lean")))

    def test_rejects_upstream_mismatch(self):
        # A seed whose statement differs from upstream (a dishonest or stale hub) is caught upstream-side.
        seed2 = fx.SEED_FILE.replace("liouville = 1", "liouville = 2")
        self.write_mission(seed=seed2)
        proved2 = fx.PROVED_FILE.replace("liouville = 1", "liouville = 2")
        code, err, _ = self.run_verify(self.proof_with(fx.make_patch("M1/Mult.lean", seed2, proved2)))
        self.assertEqual(code, 1)
        self.assertIn("upstream statement differs", err)

    def test_rejects_remaining_sorry(self):
        bad = fx.PROVED_FILE.replace("exact helper_one", "sorry")
        code, err, _ = self.run_verify(self.proof_with(fx.make_patch("M1/Mult.lean", fx.SEED_FILE, bad)))
        self.assertEqual(code, 1)
        self.assertIn("still contains `sorry`", err)

    def test_ledger_and_bundle_upstream_must_agree(self):
        code, err, _ = self.run_verify(self.proof_with(upstream={"repo": "evil/up", "commit": self.sha}))
        self.assertEqual(code, 1)
        self.assertIn("disagree", err)

    def test_refuses_metaprogramming_unless_allowed(self):
        for snippet in (
            'elab "cheat" : tactic => pure ()',
            "macro \"cheat\" : tactic => `(tactic| rfl)",
            "@[implemented_by foo] def bar : Nat := 1",
            "initialize counter : IO.Ref Nat ← IO.mkRef 0",
            None,  # in-proof: run_tac
        ):
            # Directly after the helper, so it rides along with what gets spliced upstream.
            if snippet is None:
                proved = fx.PROVED_FILE.replace("  exact helper_one", "  run_tac (pure ())\n  exact helper_one")
            else:
                proved = fx.PROVED_FILE.replace(":= rfl\n", ":= rfl\n\n" + snippet + "\n")
            proof = self.proof_with(fx.make_patch("M1/Mult.lean", fx.SEED_FILE, proved))
            code, err, _ = self.run_verify(proof)
            self.assertEqual(code, 1, snippet)
            self.assertIn("runs code at build time", err)
        code, err, _ = self.run_verify(proof, extra=("--no-build", "--allow-metaprogramming"))
        self.assertEqual(code, 0, err)

    def test_metaprogramming_words_in_comments_and_names_are_fine(self):
        proved = fx.PROVED_FILE.replace("-- the actual proof", "-- no macro or #eval here; elab-free")
        proved = proved.replace("theorem helper_one", "theorem macro_free_helper_one").replace("exact helper_one", "exact macro_free_helper_one")
        code, err, _ = self.run_verify(self.proof_with(fx.make_patch("M1/Mult.lean", fx.SEED_FILE, proved)))
        self.assertEqual(code, 0, err)

    def test_upstream_sorry_inside_a_larger_declaration_is_not_checkable(self):
        up = fx.UPSTREAM_FILE.replace(
            "@[simp] lemma isCM_liouville :\n    liouville = 1 := by\n  sorry",
            "@[simp] lemma big_theorem :\n    liouville = 1 := by\n  have h : liouville = 1 := by\n    sorry\n  exact h",
        )
        fx.write(os.path.join(self.up, "Up", "Ch1.lean"), up)
        fx.git(self.up, "commit", "-qam", "nested")
        self.sha = fx.git(self.up, "rev-parse", "HEAD").strip()
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
        src = fx.UPSTREAM_FILE
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
        proved = fx.PROVED_FILE.replace("import Mathlib.Tactic.Ring\n", "import Mathlib.Tactic.Ring\nimport Up.Ch2\n")
        code, err, _ = self.run_verify(self.proof_with(fx.make_patch("M1/Mult.lean", fx.SEED_FILE, proved)))
        self.assertEqual(code, 3, err)
        self.assertIn("`Up.Ch2`, which is not a module of the upstream repository", err)

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


@unittest.skipUnless(sv.shutil.which("lake"), "needs a Lean toolchain (lake on PATH)")
class PublicBuildTests(unittest.TestCase):
    """verify.py end to end with `lake build`, on export's core-Lean-only fixture."""

    setUp = fx.BuildTests.setUp
    make_fixture = fx.BuildTests.make_fixture
    tearDown = fx.BuildTests.tearDown

    def run_public(self, proved):
        patch = fx.make_patch("M1/Mult.lean", self.seed, proved)
        t = self.tmp.name
        pj, bj = os.path.join(t, "proof.json"), os.path.join(t, "seed.tar.gz")
        fx.write(pj, json.dumps({
            "proof_id": hashlib.sha256(patch.encode()).hexdigest(), "mission_id": "m1", "task_id": "is_cm",
            "patch": patch, "upstream": {"repo": "o/up", "commit": self.sha},
        }))
        with open(bj, "wb") as f:
            f.write(tar_of(os.path.join(self.missions, "m1")))
        err, out = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
            code = sv.main(["--proof-json", pj, "--seed-bundle", bj, "--upstream-url", "file://" + self.up, "--json"])
        return code, err.getvalue(), out.getvalue()

    def test_verifies_against_upstream(self):
        proved = fx.CORE_SEED.replace("liouville = 1 := by\n  sorry", "liouville = 1 := by\n  rfl")
        code, err, out = self.run_public(proved)
        self.assertEqual(code, 0, err)
        r = json.loads(out)
        self.assertTrue(r["verified"])
        self.assertEqual(r["axioms"], [])

    def test_rejects_meaning_changing_instance(self):
        self.tmp.cleanup()
        self.make_fixture(
            fx.CORE_UPSTREAM.replace("liouville = 1 := by", "liouville ≤ 0 := by"),
            seed=fx.CORE_SEED.replace("liouville = 1 := by", "liouville ≤ 0 := by"),
        )
        proved = self.seed.replace(
            "/-- Open", "theorem helper_ok : True := trivial\n\n"
            "instance (priority := high) cheatLE : LE Nat := ⟨fun _ _ => True⟩\n\n/-- Open"
        ).replace("liouville ≤ 0 := by\n  sorry", "liouville ≤ 0 := by\n  trivial")
        code, err, _ = self.run_public(proved)
        self.assertEqual(code, 1, err)
        self.assertIn("no longer states what the upstream statement states", err)


if __name__ == "__main__":
    unittest.main()
