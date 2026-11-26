import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = importlib.util.spec_from_file_location("ci_path_gate", Path(__file__).with_name("ci-path-gate.py"))
gate = importlib.util.module_from_spec(MODULE)
MODULE.loader.exec_module(gate)


class CiPathGateTests(unittest.TestCase):
    def test_hub_web_docs_skip_verifiers(self):
        res = gate.classify_paths([
            "cloudflare/src/hub_do.ts",
            "cloudflare/src/core.ts",
            "web/app.js",
            "docs/DESIGN.md",
        ])
        self.assertFalse(res["run_v436"])
        self.assertFalse(res["run_v435"])
        self.assertFalse(res["run_v431"])
        self.assertFalse(res["run_export"])
        self.assertFalse(res["pub_v436"])
        self.assertFalse(res["pub_v435"])
        self.assertFalse(res["pub_v431"])

    def test_single_toolchain_mission_isolates_to_its_toolchain(self):
        r436 = gate.classify_paths(["missions/arklib-near-capacity-primes/ArkLibNearCapacity/Spec.lean"])
        self.assertTrue(r436["run_v436"])
        self.assertTrue(r436["pub_v436"])
        self.assertFalse(r436["run_v435"])
        self.assertFalse(r436["run_v431"])
        self.assertFalse(r436["pub_v435"])
        self.assertFalse(r436["pub_v431"])

        r435 = gate.classify_paths(["missions/lnsym-aes-gcm-armv8/Proofs/AES-GCM/AESGCMEncKernelSym.lean"])
        self.assertTrue(r435["run_v435"])
        self.assertTrue(r435["pub_v435"])
        self.assertFalse(r435["run_v436"])
        self.assertFalse(r435["run_v431"])

        r431 = gate.classify_paths(["missions/curve25519-dalek/Curve25519Dalek/Math/Edwards/Representation.lean"])
        self.assertTrue(r431["run_v431"])
        self.assertTrue(r431["pub_v431"])
        self.assertFalse(r431["run_v436"])
        self.assertFalse(r431["run_v435"])

    def test_mission_verify_or_manifest_also_runs_export(self):
        res = gate.classify_paths(["missions/ieantn-buthe-prime-bounds/sunstead.json"])
        self.assertTrue(res["run_v436"])
        self.assertTrue(res["run_export"])
        self.assertFalse(res["run_v435"])
        self.assertFalse(res["run_v431"])

    def test_verifier_common_enables_all_toolchains_and_publishes(self):
        res = gate.classify_paths(["missions/verifier-common/SunsteadCheck.lean"])
        for key in ("run_v436", "run_v435", "run_v431", "pub_v436", "pub_v435", "pub_v431"):
            self.assertTrue(res[key], key)

    def test_verifier_server_and_redteam_enable_all_verifiers_only(self):
        for p in ("cloudflare/containers/verifier_server.py", "scripts/redteam.py", "scripts/check-statements.py"):
            with self.subTest(path=p):
                res = gate.classify_paths([p])
                self.assertTrue(res["run_v436"])
                self.assertTrue(res["run_v435"])
                self.assertTrue(res["run_v431"])
                self.assertFalse(res["pub_v436"])

    def test_cloudflare_dockerfile_only_runs_its_toolchain(self):
        res = gate.classify_paths(["cloudflare/containers/lean4-v4.31.0/Dockerfile"])
        self.assertTrue(res["run_v431"])
        self.assertFalse(res["run_v436"])
        self.assertFalse(res["run_v435"])
        self.assertFalse(res["pub_v431"])

    def test_export_scripts_only_run_export(self):
        res = gate.classify_paths(["scripts/export-upstream.py"])
        self.assertTrue(res["run_export"])
        for path in ("scripts/sunstead_verify.py", "scripts/test_sunstead_verify.py", "scripts/scout-upstream.py"):
            self.assertTrue(gate.classify_paths([path])["run_export"], path)
        self.assertFalse(res["run_v436"])
        self.assertFalse(res["run_v435"])
        self.assertFalse(res["run_v431"])

    def test_deleted_or_unmapped_mission_fails_closed(self):
        res = gate.classify_paths(["missions/deleted-old-mission/verify"])
        for key in ("run_v436", "run_v435", "run_v431", "pub_v436", "pub_v435", "pub_v431"):
            self.assertTrue(res[key], key)

    def test_diff_error_and_schedule_fail_closed(self):
        for res in (
            gate.classify_paths(None, event_name="pull_request"),
            gate.classify_paths([], event_name="schedule"),
            gate.classify_paths([], event_name="workflow_dispatch"),
        ):
            for key in ("run_v436", "run_v435", "run_v431", "run_export"):
                self.assertTrue(res[key], key)

    def test_dynamic_new_mission_discovery(self):
        with tempfile.TemporaryDirectory() as tmp:
            m = Path(tmp) / "new-crypto-v435"
            m.mkdir()
            (m / "sunstead.json").write_text(json.dumps({
                "verifier": {"image": "sunstead/verifier-lean4-v4.35.0:v0.1"}
            }), encoding="utf-8")
            res = gate.classify_paths(["missions/new-crypto-v435/Target.lean"], missions_dir=tmp)
            self.assertTrue(res["run_v435"])
            self.assertTrue(res["pub_v435"])
            self.assertFalse(res["run_v436"])
            self.assertFalse(res["run_v431"])


if __name__ == "__main__":
    unittest.main()
