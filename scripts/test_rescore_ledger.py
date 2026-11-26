#!/usr/bin/env python3
"""Offline parity and completeness checks for the public scoring replay."""

import runpy
import unittest
from pathlib import Path

tool = runpy.run_path(str(Path(__file__).with_name("rescore-ledger.py")))
points, replay, accepted = (tool[name] for name in ("points", "replay", "accepted"))


class ReplayTests(unittest.TestCase):
    def test_award_branches(self):
        self.assertEqual(points("minimize", 31, 29, 29), 25)
        self.assertEqual(points("minimize", 31, 30, 29), 10)
        self.assertEqual(points("maximize", 1, 90, 100), 0)
        self.assertEqual(points("minimize", 47, 46, 47), 107)
        self.assertEqual(points("maximize", 110, 121, 100), 476)
        self.assertEqual(points("minimize", 10, 0, 10), 5000)

    def test_replay_uses_completion_order_and_previous_record(self):
        def row(id_, score, created_at, completed_at):
            return {
                "id": id_, "mission_id": "m", "task_id": "x", "accepted": True,
                "score": score, "created_at": created_at, "completed_at": completed_at,
            }

        task = {"id": "x", "baseline_score": 31, "best_known": {"value": 29}}
        snapshot = {
            "submissions": [row("breaks", 28, 1, 10), row("tie", 29, 2, 9), row("record", 27, 3, 10)],
            "mission_modes": {"m": "hillclimb"},
            "hillclimb_missions": {"m": {
                "mission": {"manifest": {"score_direction": "minimize"}},
                "tasks": [{"def": task}],
            }},
        }
        rows = replay(snapshot)
        self.assertEqual([r["id"] for r in rows], ["tie", "breaks", "record"])
        self.assertEqual([r["previous"] for r in rows], [31, 29, 28])
        self.assertEqual([r["replayed"] for r in rows], [25, 175, 181])
        del task["best_known"]
        with self.assertRaisesRegex(ValueError, "no finite public best_known"):
            replay(snapshot)

    def test_capped_feed_cannot_claim_completeness(self):
        with self.assertRaisesRegex(ValueError, "public submission feed is capped"):
            accepted([{}] * 200)


if __name__ == "__main__":
    unittest.main()
