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


def cand(name, file="Foo/Bar.lean", line=10, status="candidate", **kw):
    return scout.Candidate("o/r", "c" * 40, file, line, "theorem", name, "", status, [], False, [], False, **kw)


class FakeGh:
    """Stands in for `gh`: answers GET paths from a dict and records calls."""

    def __init__(self, routes):
        self.routes, self.calls = routes, []

    def __call__(self, args):
        self.calls.append(args)
        path = args[-1]
        base, _, query = path.partition("?")
        page = int(dict(kv.split("=") for kv in query.split("&") if "=" in kv).get("page", "1"))
        return self.routes.get(base, []) if page == 1 else []


class MultiToolchainTests(unittest.TestCase):
    def test_watchlist_domains(self):
        for repo in ("Verified-zkEVM/VCVio", "leanprover/LNSym", "reilabs/proven-zk", "BobDyLean/dylean"):
            self.assertEqual(scout.DOMAIN_OF[repo], "cryptography")
        for repo in ("k3nfalt/longtails", "optsuite/optlib", "verified-optimization/CvxLean", "lean-dojo/FloatLib"):
            self.assertEqual(scout.DOMAIN_OF[repo], "optimization")
        self.assertEqual(len(scout.WATCHLIST), len(set(scout.WATCHLIST)))
        self.assertEqual(set(scout.DOMAINS), {"math", "cryptography", "optimization"})

    def test_file_imports(self):
        src = "/- header -/\nmodule\n-- c\nimport Mathlib.Data.Nat.Basic\npublic import ArkLib.Foo Batteries.Data\n\ntheorem t : True := trivial\nimport NotHeader\n"
        self.assertEqual(scout.file_imports(src), ["Mathlib.Data.Nat.Basic", "ArkLib.Foo", "Batteries.Data"])

    def test_classify_packaging(self):
        self.assertEqual(scout.classify_packaging(["Mathlib", "Aesop", "Lean.Elab"]), ("standalone-mathlib", []))
        self.assertEqual(scout.classify_packaging([]), ("standalone-mathlib", []))
        self.assertEqual(
            scout.classify_packaging(["Mathlib", "VCVio.OracleComp", "ArkLib.Data"]),
            ("repo-snapshot", ["ArkLib.Data", "VCVio.OracleComp"]),
        )

    def test_group_by_toolchain(self):
        info = lambda repo, tc, lic: {"repo": repo, "commit": "c" * 40, "mathlib": None, "toolchain": tc, "license": lic, "error": None}
        a = cand("A.a", packaging="standalone-mathlib", packageable_now=True)
        b = cand("A.b", packaging="repo-snapshot")
        c = cand("B.c", packaging="repo-snapshot")
        x = cand("B.x", status="excluded", packaging="standalone-mathlib")
        results = [
            (info("o/a", "leanprover/lean4:v4.36.0", "Apache-2.0"), [a, b]),
            (info("o/b", "leanprover/lean4:v4.35.0", "AGPL-3.0"), [c, x]),
            ({"repo": "o/broken", "error": "clone failed"}, []),
        ]
        g = scout.group_by_toolchain(results)
        self.assertEqual(list(g), [("leanprover/lean4:v4.35.0", "copyleft"), ("leanprover/lean4:v4.36.0", "permissive")])
        self.assertEqual(g[("leanprover/lean4:v4.36.0", "permissive")]["standalone-mathlib"], 1)
        self.assertEqual(g[("leanprover/lean4:v4.36.0", "permissive")]["repo-snapshot"], 1)
        self.assertEqual(g[("leanprover/lean4:v4.36.0", "permissive")]["packageable_now"], 1)
        self.assertEqual(g[("leanprover/lean4:v4.35.0", "copyleft")]["standalone-mathlib"], 0)  # excluded not counted
        md = scout.render_markdown(results, None)
        self.assertIn("## Candidates by toolchain and license", md)
        self.assertIn("| leanprover/lean4:v4.35.0 | copyleft | o/b | 0 | 1 | 0 |", md)
        self.assertIn("not checked", md)


PATCH_SOLVES = """@@ -8,4 +8,6 @@ namespace Foo

 theorem open_one (n : Nat) : n + 0 = n := by
-  sorry
+  simp
"""
PATCH_EDITS = """@@ -40,3 +40,3 @@ section
-theorem open_two : True := by
+theorem open_two : True ∧ True := by
   sorry
"""


class CheckPrsTests(unittest.TestCase):
    def setUp(self):
        self.gh = FakeGh({
            "repos/o/r/pulls": [{"number": 7, "html_url": "u7", "title": "fill open_one", "body": ""},
                                {"number": 8, "html_url": "u8", "title": "refactor", "body": None},
                                {"number": 9, "html_url": "u9", "title": "docs", "body": "unrelated"}],
            "repos/o/r/pulls/7/files": [{"filename": "Foo/Bar.lean", "patch": PATCH_SOLVES}],
            "repos/o/r/pulls/8/files": [{"filename": "Foo/Bar.lean", "patch": PATCH_EDITS}],
            "repos/o/r/pulls/9/files": [{"filename": "README.md", "patch": "@@ -1 +1 @@\n-a\n+b"}],
            "repos/o/r/issues": [{"number": 7, "pull_request": {}, "title": "fill open_three", "body": ""},
                                 {"number": 3, "html_url": "i3", "title": "Who is doing open_three?", "body": ""}],
        })

    def test_fetch_is_read_only_and_skips_prs_in_issues(self):
        work = scout.fetch_open_work("o/r", self.gh)
        self.assertEqual([p["number"] for p in work["prs"]], [7, 8, 9])
        self.assertEqual([i["number"] for i in work["issues"]], [3])
        for args in self.gh.calls:
            self.assertEqual(args[:3], ["api", "-X", "GET"])

    def test_matches_and_exclusion(self):
        work = scout.fetch_open_work("o/r", self.gh)
        one, two, three, four = cand("Foo.open_one", line=10), cand("Foo.open_two", line=41), cand("Foo.open_three", file="Foo/Baz.lean"), cand("Foo.open_four", file="Foo/Baz.lean")
        scout.apply_open_work([one, two, three, four], work)
        self.assertEqual(one.status, "excluded")
        self.assertIn("likely solved in open PR #7", one.reasons)
        self.assertFalse(one.packageable_now)
        self.assertEqual(two.status, "candidate")
        self.assertIn({"kind": "pr", "number": 8, "url": "u8", "match": "edits"}, two.open_work)
        self.assertIn({"kind": "pr", "number": 7, "url": "u7", "match": "file"}, two.open_work)
        self.assertEqual(three.open_work, [{"kind": "issue", "number": 3, "url": "i3", "match": "mentions"}])
        self.assertEqual(four.open_work, [])

    def test_solves_by_line_without_name(self):
        work = {"prs": [{"number": 1, "url": "u", "text": "", "files": [{"filename": "F.lean", "patch": "@@ -20,2 +20,2 @@\n-  sorry\n+  rfl\n"}]}], "issues": []}
        c = cand("X.lemma_by_line", file="F.lean", line=20)
        self.assertEqual(scout.match_open_work(c, work)[0]["match"], "solves")
        c.line = 50
        self.assertEqual(scout.match_open_work(c, work)[0]["match"], "file")

    def test_pagination(self):
        calls = []

        def gh(args):
            calls.append(args[-1])
            return [{"n": i} for i in range(100)] if args[-1].endswith("&page=1") else [{"n": 100}]
        self.assertEqual(len(scout.gh_paginate("repos/o/r/pulls?state=open", gh)), 101)
        self.assertEqual(calls, ["repos/o/r/pulls?state=open&per_page=100&page=1", "repos/o/r/pulls?state=open&per_page=100&page=2"])

    def test_check_failure_is_reported_not_fatal(self):
        def boom(args):
            raise RuntimeError("gh: not logged in")
        with self.assertRaises(RuntimeError):
            scout.fetch_open_work("o/r", boom)


class NoNetworkTests(unittest.TestCase):
    def test_suite_makes_no_subprocess_calls(self):
        """The offline tests above must never reach gh/git: guard subprocess.run."""
        orig = scout.subprocess.run
        scout.subprocess.run = lambda *a, **k: (_ for _ in ()).throw(AssertionError("network/subprocess call in tests"))
        try:
            suite = unittest.defaultTestLoader.loadTestsFromTestCase(CheckPrsTests)
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(MultiToolchainTests))
            result = unittest.TestResult()
            suite.run(result)
            self.assertTrue(result.wasSuccessful(), result.failures + result.errors)
        finally:
            scout.subprocess.run = orig


if __name__ == "__main__":
    unittest.main()
