#!/usr/bin/env python3
"""Offline unit tests for scripts/scout-upstream.py.  Run: python3 scripts/test_scout_upstream.py"""
import importlib.util
import os
import unittest

_spec = importlib.util.spec_from_file_location(
    "scout_upstream", os.path.join(os.path.dirname(os.path.abspath(__file__)), "scout-upstream.py")
)
scout = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scout)

LEAN = '''import Mathlib

/-! Module docs mention sorry but are a comment. -/

namespace Foo

def bad (n : Nat) : Nat := sorry

theorem open_one (n : Nat) : n + 0 = n := by
  sorry

@[simp] lemma open_two : True := by
  have := open_one 3
  sorry

theorem stmt_sorry (h : (sorry : Prop)) : True := trivial

theorem done : 1 = 1 := rfl

theorem in_string : "sorry".length = 5 := by decide

-- UPSTREAMED to Mathlib, do not work on this one
theorem upstreamed_one : 2 = 2 := by
  sorry

theorem uses_bad : bad 1 = bad 1 := by
  sorry

instance : Inhabited Nat := sorry

end Foo
'''


def by_name(rows):
    return {(d.name, sl): (status, reasons) for d, sl, status, reasons in rows}


class ScoutTests(unittest.TestCase):
    def setUp(self):
        self.rows = scout.analyze_file("Foo/Bar.lean", LEAN)
        self.names = {d.name: (status, reasons) for d, sl, status, reasons in self.rows}

    def test_masking_ignores_comments_and_strings(self):
        masked = scout.mask_comments_and_strings('a -- sorry\n/- sorry /- nested -/ -/ "sorry" b')
        self.assertNotIn("sorry", masked)
        self.assertEqual(masked.count("\n"), 1)
        self.assertIn("a", masked)
        self.assertIn("b", masked)
        self.assertNotIn("in_string", self.names)  # "sorry" in a string literal is not a sorry
        self.assertNotIn("Foo.done", self.names)

    def test_proof_sorries_are_candidates_with_namespaced_names(self):
        self.assertEqual(self.names["Foo.open_one"][0], "candidate")
        self.assertEqual(self.names["Foo.open_two"][0], "candidate")

    def test_definition_and_instance_sorries_are_excluded(self):
        self.assertEqual(self.names["Foo.bad"][0], "excluded")
        self.assertIn("def sorry", self.names["Foo.bad"][1][0])
        inst = [r for d, sl, st, r in self.rows if d.kind == "instance"]
        self.assertTrue(inst and "instance sorry" in inst[0][0])

    def test_statement_sorry_is_excluded(self):
        status, reasons = self.names["Foo.stmt_sorry"]
        self.assertEqual(status, "excluded")
        self.assertIn("statement", reasons[0])

    def test_marked_declarations_are_excluded(self):
        status, reasons = self.names["Foo.upstreamed_one"]
        self.assertEqual(status, "excluded")
        self.assertTrue(any("upstreamed" in r.lower() for r in reasons), reasons)

    def test_test_paths_are_excluded(self):
        rows = scout.analyze_file("test/Foo.lean", "theorem t : True := by\n  sorry\n")
        self.assertEqual(rows[0][2], "excluded")

    def test_dependency_edges(self):
        c = lambda name: scout.Candidate("r", "c" * 40, "F.lean", 1, "theorem", name, "", "candidate", [], False, [], False)
        a, b = c("Foo.open_one"), c("Foo.open_two")
        proof_text = {("F.lean", "Foo.open_two"): ":= by\n  have := open_one 3\n  sorry", ("F.lean", "Foo.open_one"): ":= by sorry"}
        scout.link_dependencies([a, b], proof_text)
        self.assertEqual(b.depends_on, ["Foo.open_one"])
        self.assertEqual(a.depends_on, [])

    def test_statement_end(self):
        code = "theorem t (h : ∀ x, x := 1) : True := by\n  sorry"
        self.assertEqual(code[scout.statement_end(code):].split()[0], ":=")
        self.assertTrue(code[: scout.statement_end(code)].endswith("True "))

    def test_spdx(self):
        self.assertEqual(scout.detect_spdx("                                 Apache License\n                           Version 2.0, January 2004"), "Apache-2.0")
        self.assertEqual(scout.detect_spdx("MIT License\n\nPermission is hereby granted, free of charge, to any person"), "MIT")
        self.assertEqual(scout.detect_spdx("All rights reserved."), "UNKNOWN")

    def test_license_status(self):
        self.assertEqual(scout.license_status("Apache-2.0"), "permissive")
        self.assertTrue(scout.license_status("AGPL-3.0").startswith("copyleft"))
        self.assertTrue(scout.license_status("UNKNOWN").startswith("unknown"))

    def test_hints(self):
        self.assertTrue(scout.feasibility_hints("", "theorem x : RH_up_to 3e12", ""))
        self.assertEqual(scout.feasibility_hints("", "theorem x (n : ℕ) : n + 0 = n", ""), [])


if __name__ == "__main__":
    unittest.main()
