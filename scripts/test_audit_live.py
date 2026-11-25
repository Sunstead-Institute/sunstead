import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

MODULE = importlib.util.spec_from_file_location("audit_live", Path(__file__).with_name("audit-live.py"))
audit = importlib.util.module_from_spec(MODULE)
MODULE.loader.exec_module(audit)

IMAGE = "sunstead/verifier-lean4:v0.2"


def has_verifier_image():
    if not shutil.which("docker"):
        return False
    p = subprocess.run(["docker", "image", "inspect", IMAGE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return p.returncode == 0


def bundle(entries):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w:gz") as tar:
        for name, content in entries:
            item = tarfile.TarInfo(name)
            item.size = len(content)
            tar.addfile(item, io.BytesIO(content))
    return out.getvalue()


class AuditTests(unittest.TestCase):
    def test_archive_ignores_git_and_rejects_paths(self):
        self.assertEqual(audit.archive_files(bundle([(".git/config", b"untrusted"), ("Spec.lean", b"x")])),
                         {"Spec.lean": (b"x", False)})
        for path in ("../outside", "/absolute"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "unsafe archive"):
                audit.archive_files(bundle([(path, b"x")]))

    def test_patch_replay_requires_frozen_and_scoped_changes(self):
        manifest = {"frozen_paths": ["Spec.lean"], "tasks": [
            {"id": "root", "target_files": ["Proof.lean"]},  # omitted depends_on defaults to []
        ]}
        seed = {"Spec.lean": (b"def spec := True\n", False), "Proof.lean": (b"old\n", False)}
        live = {**seed, "Proof.lean": (b"new\n", False)}
        digest = audit.spec_hash(manifest, seed)
        history = [{"seq": 1, "task_id": "root", "spec_sha256": digest}]
        patch = b"""From: Example <example@example.test>
Date: Sat, 1 Jan 2022 00:00:00 +0000
Subject: [PATCH] replace proof

---
diff --git a/Proof.lean b/Proof.lean
--- a/Proof.lean
+++ b/Proof.lean
@@ -1 +1 @@
-old
+new
"""
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            mission = tmp / "mission"
            mission.mkdir()
            for p, (data, _) in seed.items():
                (mission / p).write_bytes(data)
            self.assertEqual(audit.replay(tmp / "pass", mission, manifest, history, patch, seed, live, digest),
                             (["root"], live))
            other = {**live, "Spec.lean": (b"def spec := False\n", False)}
            with self.assertRaisesRegex(ValueError, "frozen hash mismatch"):
                audit.replay(tmp / "frozen", mission, manifest, history, patch, seed, other, digest)
            wrong_scope = {**manifest, "tasks": [{**manifest["tasks"][0], "target_files": ["Other.lean"]}]}
            with self.assertRaisesRegex(ValueError, "unexpected task files"):
                audit.replay(tmp / "scope", mission, wrong_scope, history, patch, seed, live, digest)
            with self.assertRaisesRegex(ValueError, "differs from live bundle"):
                audit.replay(tmp / "different", mission, manifest, history, patch, seed, seed, digest)

    def test_lean_input_isolates_frozen_spec_and_parses_audit_output(self):
        manifest = {"frozen_paths": ["M/Spec.lean"], "tasks": [
            {"id": "t1", "depends_on": [], "target_files": ["M/Proof.lean"]},
        ]}
        tree = {
            "M/Spec.lean": (b"def Target : Prop := True\n", False),
            "M/Proof.lean": (b"import M.Spec\ntheorem p : Target := trivial\n", False),
        }
        contracts = {"t1": {"module": "M.Proof", "theorem": "p", "statement": "def t1 : Prop := Target"}}
        raw, frozen, modules, checks = audit.lean_input(tree, manifest, ["t1"], contracts, "")
        self.assertEqual(frozen, ["M.Spec"])
        self.assertEqual(modules, ["M.Proof"])
        self.assertEqual(checks, [("M.Proof", "AuditSpec_1.t1", "p")])
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as tar:
            spec_src = tar.extractfile("SunsteadAuditSpec.lean").read().decode("utf-8")
            checker_src = tar.extractfile("SunsteadAuditCheck.lean").read().decode("utf-8")
        self.assertIn("import M.Spec", spec_src)
        self.assertNotIn("import M.Proof", spec_src, "spec must never import untrusted contributor code")
        self.assertIn("loadExts := false", checker_src)
        self.assertIn("collectAxioms", checker_src)

        ok_out = "Lean (version 4.36.0, test)\nSUNSTEAD_AUDIT_AXIOM p propext\nSUNSTEAD_AUDIT_OK p\n"
        self.assertEqual(audit.parse_audit_output(ok_out, checks), {"p": ["propext"]})
        with self.assertRaisesRegex(ValueError, "non-standard axiom"):
            audit.parse_audit_output(ok_out + "SUNSTEAD_AUDIT_AXIOM p sorryAx\n", checks)
        with self.assertRaisesRegex(ValueError, "missing or ambiguous"):
            audit.parse_audit_output("Lean (version 4.36.0, test)\n", checks)

    @unittest.skipUnless(has_verifier_image(), f"requires local {IMAGE} container image")
    def test_container_rejects_elab_rules_spoofed_axiom_report(self):
        manifest = {"frozen_paths": ["M/Spec.lean"], "tasks": [
            {"id": "t1", "depends_on": [], "target_files": ["M/Proof.lean"]},
        ]}
        spec = b"namespace M\ndef Target : Prop := 1 = 2\nend M\n"
        # Hostile contributor proof that uses a custom axiom AND registers elab_rules
        # attempting to spoof `#print axioms` and `example`.
        spoofed = (
            b"import Lean\n"
            b"import M.Spec\n"
            b"open Lean Elab Command\n"
            b"elab_rules : command | `(#print axioms $_) => logInfo \"'M.p' does not depend on any axioms\"\n"
            b"elab_rules : command | `(example : $_ := $_) => pure ()\n"
            b"namespace M\n"
            b"axiom cheat : Target\n"
            b"theorem p : Target := cheat\n"
            b"end M\n"
        )
        contracts = {"t1": {"module": "M.Proof", "theorem": "M.p", "statement": "def t1 : Prop := M.Target"}}
        raw, frozen, modules, checks = audit.lean_input(
            {"M/Spec.lean": (spec, False), "M/Proof.lean": (spoofed, False)},
            manifest, ["t1"], contracts, "",
        )
        with self.assertRaisesRegex(ValueError, "non-standard axiom.*M.cheat"):
            audit.check_lean(IMAGE, raw, frozen, modules, checks)


if __name__ == "__main__":
    unittest.main()
