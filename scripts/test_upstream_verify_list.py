#!/usr/bin/env python3
"""Offline tests for scripts/upstream-verify-list.py."""
import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("uvl", os.path.join(HERE, "upstream-verify-list.py"))
uvl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uvl)

A, B, C = "a" * 64, "b" * 64, "c" * 64


class Tests(unittest.TestCase):
    def test_uses_structured_verification_when_present(self):
        ledger = {"proofs": [
            {"proof_id": A, "verification": {"upstream_replay": {"kind": "in_place_sorry", "command": "curl ..."}}},
            {"proof_id": B, "verification": {"upstream_replay": None}, "verify_command": "stale"},
        ]}
        self.assertEqual(uvl.list_ids(ledger), [A])

    def test_uses_verify_command_when_present(self):
        ledger = {"proofs": [
            {"proof_id": A, "verify_command": "curl ... verify.py " + A},
            {"proof_id": B, "verify_command": None, "upstream": {"task_url": "u"}},
        ]}
        self.assertEqual(uvl.list_ids(ledger), [A])

    def test_falls_back_for_an_older_ledger(self):
        ledger = {"proofs": [
            {"proof_id": A, "entry_kind": "proof", "upstream": {"task_url": "u"}},
            {"proof_id": B, "mission_demo": True, "upstream": {"task_url": "u"}},
            {"proof_id": C, "entry_kind": "subgoal", "upstream": {"task_url": "u"}},
            {"proof_id": "x", "upstream": {"task_url": "u"}},
        ]}
        self.assertEqual(uvl.list_ids(ledger), [A])

    def test_only_narrows_and_validates(self):
        self.assertEqual(uvl.list_ids({"proofs": []}, B), [B])
        self.assertEqual(uvl.list_ids({"proofs": []}, "nope; rm -rf /"), [])

    def test_report(self):
        with tempfile.TemporaryDirectory() as d:
            for pid, code in ((A, 0), (B, 3), (C, 1)):
                os.makedirs(os.path.join(d, pid))
                r = {"proof_id": pid, "exit_code": code, "stderr_tail": ["FAILED: boom"]}
                if code == 0:
                    r.update(upstream_repo="o/up", upstream_commit="f" * 40, upstream_declaration="Up.x", axioms=["propext"])
                with open(os.path.join(d, pid, "result.json"), "w") as f:
                    json.dump(r, f)
            out = uvl.report(d)
        self.assertIn("1/3 verified", out)
        self.assertIn("✅ verified | o/up@ffffffffffff | `Up.x` | propext", out)
        self.assertIn("❌ failed", out)
        self.assertIn("FAILED: boom", out)

    def test_report_counts_missing_results_against_selected(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, A))
            with open(os.path.join(d, A, "result.json"), "w") as f:
                json.dump({"proof_id": A, "exit_code": 0}, f)
            out = uvl.report(d, [A, B])
        self.assertIn("1/2 verified", out)
        self.assertIn("produced no result:** `" + B + "`", out)
        self.assertIn("⛔ no result", out)

    def test_report_with_no_artifacts_at_all(self):
        with tempfile.TemporaryDirectory() as d:
            out = uvl.report(os.path.join(d, "absent"), [A, B])
        self.assertIn("0/2 verified", out)
        self.assertIn("2 selected proof(s) produced no result", out)

    def test_exit_3_is_not_counted_as_missing(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, A))
            with open(os.path.join(d, A, "result.json"), "w") as f:
                json.dump({"proof_id": A, "exit_code": 3}, f)
            out = uvl.report(d, [A])
        self.assertIn("0/1 verified", out)
        self.assertIn("not upstream-checkable", out)
        self.assertNotIn("no result", out)


if __name__ == "__main__":
    unittest.main()
