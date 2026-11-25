import importlib.util
import io
import json
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
IMAGE_V435 = "sunstead/verifier-lean4-v4.35.0:v0.1"


def has_verifier_image(image=IMAGE):
    if not shutil.which("docker"):
        return False
    p = subprocess.run(["docker", "image", "inspect", image], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
    def test_rank_baseline_and_corrupt_certificates(self):
        source = (audit.ROOT / "missions/matrix-rank444-f2/Rank444/Certificate.lean").read_text()
        self.assertEqual(audit.check_rank_table(source), 47)
        with self.assertRaisesRegex(ValueError, "term count"):
            audit.check_rank_table(source.replace("Nat := 47", "Nat := 46"))
        with self.assertRaisesRegex(ValueError, "matrix product differs"):
            audit.check_rank_table(source.replace("(256,", "(257,", 1))

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

    def test_resolve_audit_target_multi_toolchain(self):
        pnt_dir = audit.ROOT / "missions" / "pnt-analytic-foundations"
        pnt_manifest = json.loads((pnt_dir / "sunstead.json").read_text(encoding="utf-8"))
        self.assertEqual(audit.resolve_audit_target(pnt_dir, pnt_manifest), (IMAGE, "4.36.0"))

        lnsym_dir = audit.ROOT / "missions" / "lnsym-aes-gcm-armv8"
        lnsym_manifest = json.loads((lnsym_dir / "sunstead.json").read_text(encoding="utf-8"))
        self.assertEqual(audit.resolve_audit_target(lnsym_dir, lnsym_manifest), (IMAGE_V435, "4.35.0"))
        self.assertTrue(audit.is_repo_snapshot(lnsym_manifest))

        bad_img = {**lnsym_manifest, "verifier": {**lnsym_manifest["verifier"], "image": "evil/image:latest"}}
        with self.assertRaisesRegex(ValueError, "unsupported verifier image"):
            audit.resolve_audit_target(lnsym_dir, bad_img)
        bad_tc = {**lnsym_manifest, "verifier": {**lnsym_manifest["verifier"], "toolchain": "leanprover/lean4:v4.36.0"}}
        with self.assertRaisesRegex(ValueError, "disagrees with lean-toolchain"):
            audit.resolve_audit_target(lnsym_dir, bad_tc)

    def test_module_to_relpath_and_repo_snapshot_input(self):
        self.assertEqual(
            audit.module_to_relpath("Proofs.\u00abAES-GCM\u00bb.AESGCMEncKernelSym"),
            "Proofs/AES-GCM/AESGCMEncKernelSym.lean",
        )
        for bad in ("../Escape", "A.B;rm", "A.\u00ab../x\u00bb.B", "A..B"):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "invalid Lean module"):
                audit.module_to_relpath(bad)

        manifest = {
            "snapshot": {
                "mode": "repo-snapshot",
                "snapshot_id": "lnsym-aes-gcm-armv8",
                "lean_options": ["linter.unusedSimpArgs=false"],
            },
            "tasks": [{
                "id": "t1",
                "depends_on": [],
                "target_files": ["Snap/AES-GCM/Target.lean"],
            }],
        }
        seed_tree = {"Snap/AES-GCM/Target.lean": (b"theorem p : True := by sorry\n", False)}
        live_tree = {"Snap/AES-GCM/Target.lean": (b"theorem p : True := trivial\n", False)}
        contracts = {"t1": {"module": "Snap.\u00abAES-GCM\u00bb.Target", "theorem": "p"}}
        raw, snap_id, opts, checks = audit.repo_snapshot_input(seed_tree, live_tree, manifest, ["t1"], contracts)
        self.assertEqual(snap_id, "lnsym-aes-gcm-armv8")
        self.assertEqual(opts, ["linter.unusedSimpArgs=false"])
        self.assertEqual(checks, [("Snap.\u00abAES-GCM\u00bb.Target", "Snap/AES-GCM/Target", "p")])
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as tar:
            names = set(tar.getnames())
            checker_src = tar.extractfile("SunsteadAuditCheck.lean").read().decode("utf-8")
        self.assertIn("seed/Snap/AES-GCM/Target.lean", names)
        self.assertIn("live/Snap/AES-GCM/Target.lean", names)
        self.assertIn("collectFrozenTypeDeps", checker_src)
        self.assertIn("loadExts := false", checker_src)

        ok_v435 = "Lean (version 4.35.0, test)\nSUNSTEAD_AUDIT_AXIOM p propext\nSUNSTEAD_AUDIT_OK p\n"
        self.assertEqual(audit.parse_audit_output(ok_v435, checks, expected_version="4.35.0"), {"p": ["propext"]})
        with self.assertRaisesRegex(ValueError, "wrong Lean version"):
            audit.parse_audit_output(ok_v435, checks, expected_version="4.36.0")

    @unittest.skipUnless(has_verifier_image(IMAGE_V435), f"requires local {IMAGE_V435} container image")
    def test_container_repo_snapshot_honest_and_attacks(self):
        manifest = {
            "snapshot": {"mode": "repo-snapshot", "snapshot_id": "lnsym-aes-gcm-armv8", "lean_options": []},
            "tasks": [{"id": "t1", "depends_on": [], "target_files": ["Snap/AES-GCM/Target.lean"]}],
        }
        contracts = {"t1": {"module": "Snap.\u00abAES-GCM\u00bb.Target", "theorem": "SnapAes.ok"}}
        seed_src = (
            b"namespace SnapAes\n"
            b"abbrev rounds : Nat := 14\n"
            b"theorem ok : rounds = 14 := by\n"
            b"  sorry\n"
            b"end SnapAes\n"
        )
        honest_src = (
            b"namespace SnapAes\n"
            b"abbrev rounds : Nat := 14\n"
            b"theorem ok : rounds = 14 := rfl\n"
            b"end SnapAes\n"
        )
        seed_tree = {"Snap/AES-GCM/Target.lean": (seed_src, False)}

        raw, snap_id, opts, checks = audit.repo_snapshot_input(
            seed_tree, {"Snap/AES-GCM/Target.lean": (honest_src, False)}, manifest, ["t1"], contracts
        )
        audit.check_lean_repo_snapshot(IMAGE_V435, raw, snap_id, opts, checks, expected_version="4.35.0")

        # Attack 1: weaken local abbrev referenced by the theorem's type.
        weak_abbrev = (
            b"namespace SnapAes\n"
            b"abbrev rounds : Nat := 10\n"
            b"axiom fake : 10 = 14\n"
            b"theorem ok : rounds = 14 := fake\n"
            b"end SnapAes\n"
        )
        raw, snap_id, opts, checks = audit.repo_snapshot_input(
            seed_tree, {"Snap/AES-GCM/Target.lean": (weak_abbrev, False)}, manifest, ["t1"], contracts
        )
        with self.assertRaises(subprocess.CalledProcessError) as ctx:
            audit.check_lean_repo_snapshot(IMAGE_V435, raw, snap_id, opts, checks, expected_version="4.35.0")
        self.assertIn(b"FROZEN_DEP_MODIFIED SnapAes.rounds", ctx.exception.output)

        # Attack 2: custom axiom + elab_rules spoofing.
        spoofed = (
            b"import Lean\n"
            b"open Lean Elab Command\n"
            b"elab_rules : command | `(#print axioms $_) => logInfo \"'SnapAes.ok' does not depend on any axioms\"\n"
            b"namespace SnapAes\n"
            b"abbrev rounds : Nat := 14\n"
            b"axiom cheat : rounds = 14\n"
            b"theorem ok : rounds = 14 := cheat\n"
            b"end SnapAes\n"
        )
        raw, snap_id, opts, checks = audit.repo_snapshot_input(
            seed_tree, {"Snap/AES-GCM/Target.lean": (spoofed, False)}, manifest, ["t1"], contracts
        )
        with self.assertRaisesRegex(ValueError, "non-standard axiom.*SnapAes.cheat"):
            audit.check_lean_repo_snapshot(IMAGE_V435, raw, snap_id, opts, checks, expected_version="4.35.0")

    @unittest.skipUnless(has_verifier_image(IMAGE_V435), f"requires local {IMAGE_V435} container image")
    def test_container_lnsym_real_seed_detects_sorry_axiom(self):
        lnsym_dir = audit.ROOT / "missions" / "lnsym-aes-gcm-armv8"
        manifest = json.loads((lnsym_dir / "sunstead.json").read_text(encoding="utf-8"))
        contracts, _ = audit.proof_contract(lnsym_dir)
        rel = "Proofs/AES-GCM/AESGCMEncKernelSym.lean"
        seed_bytes = (lnsym_dir / rel).read_bytes()
        tree = {rel: (seed_bytes, False)}
        image, version = audit.resolve_audit_target(lnsym_dir, manifest)
        raw, snap_id, opts, checks = audit.repo_snapshot_input(
            tree, tree, manifest, ["aes_gcm_enc_kernel_run_139"], contracts
        )
        with self.assertRaisesRegex(ValueError, "non-standard axiom.*sorryAx"):
            audit.check_lean_repo_snapshot(image, raw, snap_id, opts, checks, expected_version=version)


if __name__ == "__main__":
    unittest.main()
