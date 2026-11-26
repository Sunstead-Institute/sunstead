#!/usr/bin/env python3
"""Unit tests for the best-known registry checker (offline)."""
import runpy
import unittest
from pathlib import Path

check = runpy.run_path(str(Path(__file__).with_name("check-best-known.py")))["check"]


class BestKnownTests(unittest.TestCase):
    def setUp(self):
        self.entry = {
            "value": 7,
            "kind": "collection",
            "source": "A construction attaining depth seven",
            "url": "https://example.org/construction",
            "checked": "2026-11-26",
        }
        self.registry = {"missions": {"sorting": {"depth": self.entry}}}
        self.manifests = {
            "sorting": {
                "mode": "hillclimb", "score_direction": "minimize",
                "tasks": [{"id": "depth", "baseline_score": 9}],
            }
        }

    def test_open_entry_can_omit_marker(self):
        self.assertEqual(check(self.registry, self.manifests), [])

    def test_closed_entry_has_separate_citation(self):
        self.entry["proven_optimal"] = {
            "source": "Theorem 1: No depth-six network exists",
            "url": "https://example.org/theorem",
        }
        self.assertEqual(check(self.registry, self.manifests), [])

    def test_legacy_boolean_and_malformed_citation_rejected(self):
        for marker, expected in [
            (True, "proven_optimal must be an object"),
            (None, "proven_optimal must be an object"),
            ({}, "proven_optimal.source"),
            ({"source": "   ", "url": "https://example.org"}, "proven_optimal.source"),
            ({"source": "Theorem 1: No depth-six network exists", "url": "https://"}, "proven_optimal.url"),
            ({"source": "Theorem 1: No depth-six network exists", "url": "http://example.org"}, "proven_optimal.url"),
        ]:
            with self.subTest(marker=marker):
                self.entry["proven_optimal"] = marker
                self.assertTrue(any(expected in error for error in check(self.registry, self.manifests)))


if __name__ == "__main__":
    unittest.main()
