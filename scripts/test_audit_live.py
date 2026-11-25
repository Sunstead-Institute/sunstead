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
IMAGE_V431 = "sunstead/verifier-lean4-v4.31.0:v0.1"


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

    def test_aes_sbox_baseline_and_corrupt_circuits(self):
        total_src = (audit.ROOT / "missions/aes-sbox-circuit/AesSbox/TotalCircuit.lean").read_text(encoding="utf-8")
        and_src = (audit.ROOT / "missions/aes-sbox-circuit/AesSbox/AndCircuit.lean").read_text(encoding="utf-8")
        self.assertEqual(audit.check_aes_sbox_circuit(total_src, "minimize_total_gates"), 130)
        self.assertEqual(audit.check_aes_sbox_circuit(and_src, "minimize_and_gates"), 36)
        with self.assertRaisesRegex(ValueError, "circuit score"):
            audit.check_aes_sbox_circuit(total_src.replace("Nat := 130", "Nat := 129", 1), "minimize_total_gates")
        with self.assertRaisesRegex(ValueError, "circuit score"):
            audit.check_aes_sbox_circuit(and_src.replace("Nat := 36", "Nat := 35", 1), "minimize_and_gates")
        with self.assertRaisesRegex(ValueError, "non-causal wire index"):
            bad_wire = total_src.replace("[\n  (", "[\n  (0, 8, 0),\n  (", 1).replace("Nat := 130", "Nat := 131", 1)
            audit.check_aes_sbox_circuit(bad_wire, "minimize_total_gates")
        with self.assertRaisesRegex(ValueError, "AES S-box differs"):
            audit.check_aes_sbox_circuit(total_src.replace("[132,", "[131,", 1), "minimize_total_gates")
        with self.assertRaisesRegex(ValueError, "circuit format"):
            audit.check_aes_sbox_circuit(total_src + "\n#eval 1\n", "minimize_total_gates")

        # Verify audit_aes_sbox_history rejects non-improving progression and validates seed baselines.
        manifest = json.loads((audit.ROOT / "missions/aes-sbox-circuit/sunstead.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            (repo / "AesSbox").mkdir(parents=True)
            (repo / "AesSbox/TotalCircuit.lean").write_text(total_src, encoding="utf-8")
            (repo / "AesSbox/AndCircuit.lean").write_text(and_src, encoding="utf-8")
            audit.repo_git(repo, "init", "--quiet", "--template=")
            audit.repo_git(repo, "add", ".")
            audit.repo_git(repo, "commit", "--quiet", "-m", "seed")
            # Commit a non-improving duplicate total circuit: must be rejected.
            (repo / "AesSbox/TotalCircuit.lean").write_text(total_src + "\n", encoding="utf-8")
            audit.repo_git(repo, "add", ".")
            audit.repo_git(repo, "commit", "--quiet", "-m", "no improvement")
            snap_tasks = [
                {"def": {"id": "minimize_total_gates"}, "status": "verified", "best_score": 130},
                {"def": {"id": "minimize_and_gates"}, "status": "open", "best_score": 36},
            ]
            with self.assertRaisesRegex(ValueError, "progression"):
                audit.audit_aes_sbox_history(repo, ["minimize_total_gates"], snap_tasks, manifest)

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

        c25519_dir = audit.ROOT / "missions" / "curve25519-dalek"
        c25519_manifest = json.loads((c25519_dir / "sunstead.json").read_text(encoding="utf-8"))
        self.assertEqual(audit.resolve_audit_target(c25519_dir, c25519_manifest), (IMAGE_V431, "4.31.0"))
        self.assertTrue(audit.is_repo_snapshot(c25519_manifest))

        tc_map = audit.parse_toolchain_images([
            "v4.35.0=custom/v435:test",
            "v4.31.0=custom/v431:test",
            "leanprover/lean4:v4.36.0=custom/v436:test",
        ])
        self.assertEqual(audit.resolve_audit_target(lnsym_dir, lnsym_manifest, toolchain_images=tc_map), ("custom/v435:test", "4.35.0"))
        self.assertEqual(audit.resolve_audit_target(c25519_dir, c25519_manifest, toolchain_images=tc_map), ("custom/v431:test", "4.31.0"))
        self.assertEqual(audit.resolve_audit_target(pnt_dir, pnt_manifest, toolchain_images=tc_map), ("custom/v436:test", "4.36.0"))
        self.assertEqual(
            audit.resolve_audit_target(
                lnsym_dir, lnsym_manifest, toolchain_images=audit.parse_toolchain_images([], image_v435="alt/v435:1")
            ),
            ("alt/v435:1", "4.35.0"),
        )
        self.assertEqual(
            audit.resolve_audit_target(
                c25519_dir, c25519_manifest, toolchain_images=audit.parse_toolchain_images([], image_v431="alt/v431:1")
            ),
            ("alt/v431:1", "4.31.0"),
        )
        with self.assertRaisesRegex(ValueError, "invalid --toolchain-image"):
            audit.parse_toolchain_images(["badspec"])

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

    @unittest.skipUnless(has_verifier_image(IMAGE_V435), f"requires local {IMAGE_V435} container image")
    def test_container_lnsym_gcm_real_seed_detects_sorry_axiom(self):
        gcm_dir = audit.ROOT / "missions" / "lnsym-gcm-gmult-armv8"
        manifest = json.loads((gcm_dir / "sunstead.json").read_text(encoding="utf-8"))
        contracts, _ = audit.proof_contract(gcm_dir)
        rel = "Proofs/AES-GCM/GCMGmultV8Sym.lean"
        seed_bytes = (gcm_dir / rel).read_bytes()
        tree = {rel: (seed_bytes, False)}
        image, version = audit.resolve_audit_target(gcm_dir, manifest)
        for tid in ("gcm_polyval_mul_eq_polynomial_mult", "polynomial_mult_append"):
            with self.subTest(task=tid):
                raw, snap_id, opts, checks = audit.repo_snapshot_input(tree, tree, manifest, [tid], contracts)
                with self.assertRaisesRegex(ValueError, "non-standard axiom.*sorryAx"):
                    audit.check_lean_repo_snapshot(image, raw, snap_id, opts, checks, expected_version=version)

    @unittest.skipUnless(has_verifier_image(IMAGE_V431), f"requires local {IMAGE_V431} container image")
    def test_container_v431_repo_snapshot_honest_and_attacks(self):
        manifest = {
            "snapshot": {"mode": "repo-snapshot", "snapshot_id": "curve25519-dalek", "lean_options": []},
            "tasks": [{"id": "t1", "depends_on": [], "target_files": ["Snap431/Target.lean"]}],
        }
        contracts = {"t1": {"module": "Snap431.Target", "theorem": "Snap431.ok"}}
        seed_src = (
            b"namespace Snap431\n"
            b"abbrev modulus : Nat := 25519\n"
            b"theorem ok : modulus = 25519 := by\n"
            b"  sorry\n"
            b"end Snap431\n"
        )
        honest_src = (
            b"namespace Snap431\n"
            b"abbrev modulus : Nat := 25519\n"
            b"theorem ok : modulus = 25519 := rfl\n"
            b"end Snap431\n"
        )
        seed_tree = {"Snap431/Target.lean": (seed_src, False)}

        raw, snap_id, opts, checks = audit.repo_snapshot_input(
            seed_tree, {"Snap431/Target.lean": (honest_src, False)}, manifest, ["t1"], contracts
        )
        audit.check_lean_repo_snapshot(IMAGE_V431, raw, snap_id, opts, checks, expected_version="4.31.0")

        weak_abbrev = (
            b"namespace Snap431\n"
            b"abbrev modulus : Nat := 17\n"
            b"axiom fake : 17 = 25519\n"
            b"theorem ok : modulus = 25519 := fake\n"
            b"end Snap431\n"
        )
        raw, snap_id, opts, checks = audit.repo_snapshot_input(
            seed_tree, {"Snap431/Target.lean": (weak_abbrev, False)}, manifest, ["t1"], contracts
        )
        with self.assertRaises(subprocess.CalledProcessError) as ctx:
            audit.check_lean_repo_snapshot(IMAGE_V431, raw, snap_id, opts, checks, expected_version="4.31.0")
        self.assertIn(b"FROZEN_DEP_MODIFIED Snap431.modulus", ctx.exception.output)

        spoofed = (
            b"import Lean\n"
            b"open Lean Elab Command\n"
            b"elab_rules : command | `(#print axioms $_) => logInfo \"'Snap431.ok' does not depend on any axioms\"\n"
            b"namespace Snap431\n"
            b"abbrev modulus : Nat := 25519\n"
            b"axiom cheat : modulus = 25519\n"
            b"theorem ok : modulus = 25519 := cheat\n"
            b"end Snap431\n"
        )
        raw, snap_id, opts, checks = audit.repo_snapshot_input(
            seed_tree, {"Snap431/Target.lean": (spoofed, False)}, manifest, ["t1"], contracts
        )
        with self.assertRaisesRegex(ValueError, "non-standard axiom.*Snap431.cheat"):
            audit.check_lean_repo_snapshot(IMAGE_V431, raw, snap_id, opts, checks, expected_version="4.31.0")

    @unittest.skipUnless(has_verifier_image(IMAGE_V431), f"requires local {IMAGE_V431} container image")
    def test_container_curve25519_real_seed_detects_sorry_axiom(self):
        c_dir = audit.ROOT / "missions" / "curve25519-dalek"
        manifest = json.loads((c_dir / "sunstead.json").read_text(encoding="utf-8"))
        contracts, _ = audit.proof_contract(c_dir)
        rel_curve = "Curve25519Dalek/Math/Edwards/Curve.lean"
        rel_rist = "Curve25519Dalek/Math/Ristretto/Representation.lean"
        tree = {
            rel_curve: ((c_dir / rel_curve).read_bytes(), False),
            rel_rist: ((c_dir / rel_rist).read_bytes(), False),
        }
        image, version = audit.resolve_audit_target(c_dir, manifest)
        # Task 1 alone + full 2-task DAG with frozen bridge module (Edwards/Representation.lean).
        for accepted in (["add_assoc_ed25519"], ["add_assoc_ed25519", "is_even_iff_in_doubling_image_right"]):
            with self.subTest(accepted=accepted):
                raw, snap_id, opts, checks = audit.repo_snapshot_input(tree, tree, manifest, accepted, contracts)
                with self.assertRaisesRegex(ValueError, "non-standard axiom.*sorryAx"):
                    audit.check_lean_repo_snapshot(image, raw, snap_id, opts, checks, expected_version=version)


    def test_alphatensor_rank_tables_verified_and_tampering_rejected(self):
        at_dir = audit.ROOT / "missions" / "matrix-rank-alphatensor-f2"
        for (mid, tid), (n, m, p, max_r, cert_path, score_name, cert_name, max_bytes) in audit.RANK_TASK_SPECS.items():
            if mid != "matrix-rank-alphatensor-f2":
                continue
            with self.subTest(task=tid):
                src = (at_dir / cert_path).read_text(encoding="utf-8")
                self.assertEqual(
                    audit.check_rank_table(src, n, m, p, max_r, score_name, cert_name, max_bytes),
                    max_r,
                )
        bad = "def B334.score333 : Nat := 1\ndef B334.cert333 : List (Nat × Nat × Nat) := [(1, 1, 1)]\n"
        with self.assertRaisesRegex(ValueError, "matrix product differs"):
            audit.check_rank_table(bad, 3, 3, 3, 23, "B334.score333", "B334.cert333", 16384)

    def test_audit_attestation_builder_and_publisher(self):
        run_url = audit.github_actions_run_url({
            "GITHUB_SERVER_URL": "https://github.com",
            "GITHUB_REPOSITORY": "Sunstead-Institute/sunstead",
            "GITHUB_RUN_ID": "987654321",
        })
        self.assertEqual(run_url, "https://github.com/Sunstead-Institute/sunstead/actions/runs/987654321")
        self.assertIsNone(audit.github_actions_run_url({}))

        payload = audit.build_audit_attestation(
            toolchain="lean4:v4.36.0",
            axioms=["propext", "Classical.choice"],
            summary="Stock Lean 4.36.0 + leanchecker passed",
            run_url=run_url,
            commit_sha="0123456789abcdef",
            audited_at=1700000000,
        )
        seen = {}

        class FakeResp:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def read(self):
                return json.dumps({"ok": True, "audit": payload}).encode("utf-8")

        def fake_open(req, timeout=30):
            seen["url"] = req.full_url
            seen["method"] = req.get_method()
            seen["auth"] = req.get_header("Authorization")
            seen["body"] = json.loads(req.data.decode("utf-8"))
            return FakeResp()

        pid = "ab" * 32
        res = audit.publish_audit_attestation(f"sha256:{pid}", payload, "tok-secret", hub_base="https://sunstead.test", opener=fake_open)
        self.assertTrue(res["ok"])
        self.assertEqual(seen["url"], f"https://sunstead.test/api/proofs/{pid}/audit")
        self.assertEqual(seen["method"], "POST")
        self.assertEqual(seen["auth"], "Bearer tok-secret")
        self.assertEqual(seen["body"]["status"], "passed")
        self.assertEqual(seen["body"]["toolchain"], "lean4:v4.36.0")

        with self.assertRaisesRegex(ValueError, "invalid proof_id"):
            audit.publish_audit_attestation("not-a-hash", payload, "tok-secret", opener=fake_open)

    def test_matrix_rank444_verify_guards_missing_arg_and_non_utf8(self):
        verify_path = audit.ROOT / "missions/matrix-rank444-f2/verify"
        with tempfile.TemporaryDirectory() as tmp:
            # Copy verify + Rank444/Certificate.lean and verify stubs into temp dir
            dst = Path(tmp) / "m"
            (dst / "Rank444").mkdir(parents=True)
            shutil.copy2(verify_path, dst / "verify")
            (dst / "Rank444/Certificate.lean").write_bytes(b"\xff\xfe\xfd invalid utf8")
            # Inject a tiny local sunstead_sandbox stub on PYTHONPATH so we test verify's own guards cleanly.
            stub_dir = Path(tmp) / "stub"
            stub_dir.mkdir()
            (stub_dir / "sunstead_sandbox.py").write_text(
                "import json, sys\n"
                "def emit(ok, summary, stage=None, **kw):\n"
                "    print(json.dumps({'ok': ok, 'summary': summary, 'stage': stage}))\n"
                "    sys.exit(0 if ok else 1)\n"
                "def lean_verify(*a, **kw):\n"
                "    emit(True, 'stub')\n",
                encoding="utf-8",
            )
            env = {**audit.os.environ, "PYTHONPATH": str(stub_dir)}
            # Missing argv[1] emits JSON lint error cleanly instead of IndexError.
            p_noarg = subprocess.run([audit.sys.executable, str(dst / "verify")], capture_output=True, text=True, env=env)
            self.assertNotEqual(p_noarg.returncode, 0)
            self.assertEqual(json.loads(p_noarg.stdout.strip())["stage"], "lint")
            # Non-UTF-8 certificate emits JSON lint error cleanly instead of UnicodeDecodeError.
            p_utf8 = subprocess.run([audit.sys.executable, str(dst / "verify"), "reduce_rank"], capture_output=True, text=True, env=env)
            self.assertNotEqual(p_utf8.returncode, 0)
            verdict = json.loads(p_utf8.stdout.strip())
            self.assertEqual(verdict["stage"], "lint")
            self.assertIn("UTF-8", verdict["summary"])


if __name__ == "__main__":
    unittest.main()
