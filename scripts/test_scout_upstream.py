#!/usr/bin/env python3
"""Offline unit tests for scripts/scout-upstream.py.  Run: python3 scripts/test_scout_upstream.py"""
import ast
import contextlib
import importlib.util
import io
import json
import os
import stat
import subprocess
import sys
import tempfile
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

    def test_externally_verified_attribute_is_excluded(self):
        src = "@[step, externally_verified]\ntheorem spec (n : Nat) : n = n := by\n  sorry\n"
        rows = scout.analyze_file("Specs/Mul.lean", src)
        self.assertEqual(rows[0][2], "excluded")
        self.assertTrue(any("externally_verified" in r for r in rows[0][3]), rows[0][3])

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

    def test_lean436_module_public_declarations_and_public_section(self):
        src = (
            "module\n\n"
            "public import Mathlib\n\n"
            "namespace ModPkg\n\n"
            "public def bad_def : Nat := sorry\n\n"
            "public theorem pub_open (n : Nat) : n = n := by\n"
            "  sorry\n\n"
            "public section Sec\n\n"
            "public lemma pub_lemma : True := by\n"
            "  sorry\n\n"
            "end Sec\n\n"
            "end ModPkg\n"
        )
        rows = scout.analyze_file("ModPkg/Main.lean", src)
        by_n = {d.name: (d, st, reasons) for d, _sl, st, reasons in rows}
        self.assertEqual(by_n["ModPkg.pub_open"][1], "candidate")
        self.assertNotIn("public section Sec", by_n["ModPkg.pub_open"][0].raw)
        self.assertEqual(by_n["ModPkg.pub_lemma"][1], "candidate")
        self.assertEqual(by_n["ModPkg.bad_def"][1], "excluded")
        self.assertIn("def sorry", by_n["ModPkg.bad_def"][2][0])


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
        for repo in (
            "Verified-zkEVM/VCVio", "leanprover/LNSym", "reilabs/proven-zk", "BobDyLean/dylean",
            "leanEthereum/leanVM", "Verified-zkEVM/evm-asm", "Verified-zkEVM/PolyFun",
            "reilabs/lampe", "GaloisInc/zkLean",
        ):
            self.assertEqual(scout.DOMAIN_OF[repo], "cryptography")
        for repo in ("k3nfalt/longtails", "optsuite/optlib", "verified-optimization/CvxLean", "lean-dojo/FloatLib"):
            self.assertEqual(scout.DOMAIN_OF[repo], "optimization")
        self.assertEqual(scout.DOMAIN_OF["cedar-policy/cedar-spec"], "systems")
        self.assertEqual(scout.DOMAIN_OF["teorth/IEANTN"], "math")
        self.assertEqual(len(scout.WATCHLIST), len(set(scout.WATCHLIST)))
        self.assertEqual(set(scout.DOMAINS), {"math", "cryptography", "optimization", "systems"})

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

    def test_refactor_that_keeps_a_sorry_is_not_solved(self):
        # Shape of a real upstream draft PR: the old admit is removed but the
        # restructured proof still ends in `sorry`, so the work is not done.
        patch = (
            "@@ -306,8 +304,9 @@ codes over prime fields\n"
            " theorem exists_rs_epsCa_large_near_capacity\n"
            "-  sorry -- external admit\n"
            "+  have hprimes : True := by\n"
            "+    sorry\n"
            "+  exact of_primes hprimes\n"
        )
        work = {"prs": [{"number": 1572, "url": "u", "text": "", "files": [{"filename": "F.lean", "patch": patch}]}], "issues": []}
        c = cand("CodingTheory.exists_rs_epsCa_large_near_capacity", file="F.lean", line=320)
        self.assertEqual(scout.match_open_work(c, work)[0]["match"], "edits")
        scout.apply_open_work([c], work)
        self.assertEqual(c.status, "candidate")

    def test_pr_that_deletes_the_theorem_is_flagged_not_solved(self):
        patch = (
            "@@ -293,9 +370,4 @@ theorem test_2 {val : BitVec _}\n"
            "-theorem test_write_zero (h : True) :\n"
            "-    True := by\n"
            "-  sorry\n"
            "-\n"
            " end ReadOverlappingWrite\n"
        )
        work = {"prs": [{"number": 197, "url": "u", "text": "", "files": [{"filename": "F.lean", "patch": patch}]}], "issues": []}
        c = cand("ReadOverlappingWrite.test_write_zero", file="F.lean", line=585)
        self.assertEqual(scout.match_open_work(c, work)[0]["match"], "deletes")
        scout.apply_open_work([c], work)
        self.assertEqual(c.status, "candidate")

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


LS_TREE = (
    "100644 blob aaaa\tLICENSE\n"
    "100644 blob bbbb\tlean-toolchain\n"
    "100644 blob cccc\tlake-manifest.json\n"
    "100644 blob dddd\tFoo/Bar.lean\n"
    "100644 blob eeee\tblueprint/src/content.tex\n"
    "100644 blob ffff\tREADME.md\n"
    "100644 blob 1111\tdocs/img.png\n"
    "040000 tree 2222\tFoo\n"
    "160000 commit 3333\tvendor/sub\n"
)


class PrefetchTests(unittest.TestCase):
    def test_wanted_blobs(self):
        self.assertEqual(scout.wanted_blobs(LS_TREE), ["aaaa", "bbbb", "cccc", "dddd", "eeee"])

    def test_prefetch_is_one_batched_blob_fetch(self):
        calls = []

        class R:
            returncode = 0

        def run(cmd, **kw):
            calls.append((cmd, kw))
            return R()
        self.assertEqual(scout.prefetch_blobs("/repo", LS_TREE, run), 5)
        self.assertEqual(len(calls), 1)
        cmd, kw = calls[0]
        self.assertEqual(cmd[:3], ["git", "-C", "/repo"])
        self.assertIn("fetch", cmd)
        self.assertIn("--stdin", cmd)
        self.assertIn("--filter=blob:none", cmd)
        self.assertEqual(kw["input"], "aaaa\nbbbb\ncccc\ndddd\neeee\n")

    def test_prefetch_failure_and_empty_are_harmless(self):
        class Bad:
            returncode = 128
        self.assertEqual(scout.prefetch_blobs("/repo", LS_TREE, lambda *a, **k: Bad()), 0)
        self.assertEqual(scout.prefetch_blobs("/repo", "", lambda *a, **k: self.fail("no call")), 0)


class TimeoutAndLiveTests(unittest.TestCase):
    def test_timeouts_raise_clean_runtime_error_or_fallback(self):
        def timeout_run(cmd, **kw):
            raise subprocess.TimeoutExpired(cmd, kw.get("timeout", 1))

        with self.assertRaisesRegex(RuntimeError, "timed out after 5s"):
            scout.run_gh(["api", "-X", "GET", "repos/o/r/pulls"], timeout=5, run=timeout_run)
        with self.assertRaisesRegex(RuntimeError, "timed out after 7s"):
            scout.git("/repo", "fetch", "origin", timeout=7, run=timeout_run)
        self.assertEqual(scout.prefetch_blobs("/repo", LS_TREE, run=timeout_run, timeout=3), 0)
        self.assertIsNone(scout.show("/repo", "HEAD", "README.md", timeout=3, run=timeout_run))

    def test_live_task_lines_detects_live_crypto_and_math_missions(self):
        live = scout.live_task_lines()
        self.assertIn(("leanprover/LNSym", "Proofs/AES-GCM/AESGCMEncKernelSym.lean"), live)
        self.assertIn(
            ("Verified-zkEVM/ArkLib", "ArkLib/Data/CodingTheory/ProximityGap/CapacityBounds.lean"),
            live,
        )

    def test_checkout_files_chunks_large_file_lists(self):
        calls = []
        files = [f"Pkg/File{i}.lean" for i in range(1205)]
        scout.checkout_files("/tmp/repo", "abc123", files, chunk_size=500, runner=lambda cmd, **kw: calls.append((cmd, kw)))
        self.assertEqual(len(calls), 3)
        self.assertEqual(len(calls[0][0]) - 8, 500)
        self.assertEqual(len(calls[1][0]) - 8, 500)
        self.assertEqual(len(calls[2][0]) - 8, 205)
        self.assertEqual(calls[0][1]["timeout"], scout.GIT_TIMEOUT)


class WatchlistExpansionTests(unittest.TestCase):
    def test_expanded_high_value_repos_registered(self):
        expected = {
            "leanprover-community/physlib": "math",
            "kbuzzard/ClassFieldTheory": "math",
            "frenzymath/FATE": "math",
            "teorth/equational_theories": "math",
            "Verified-zkEVM/rust-lean": "cryptography",
            "Verified-zkEVM/leanerVM": "cryptography",
            "Beneficial-AI-Foundation/dalek-lean-bench": "cryptography",
            "opencompl/lean-mlir": "systems",
            "opencompl/riscv-lean": "systems",
            "digama0/lean4lean": "systems",
            "sunblaze-ucb/verina": "systems",
        }
        for repo, dom in expected.items():
            self.assertIn(repo, scout.WATCHLIST)
            self.assertEqual(scout.DOMAIN_OF[repo], dom)
        self.assertEqual(len(scout.WATCHLIST), len(set(scout.WATCHLIST)))


FC_LEAN = '''import Mathlib

/-!
Problem prose adapted from Wikipedia under CC-BY-SA 4.0.
-/

namespace Erdos123

@[category research open, AMS 11]
theorem erdos_123 (n : Nat) : n + 0 = n := by
  sorry

@[category research solved, AMS 11]
theorem erdos_123_known (n : Nat) : n = n := by
  sorry

@[category graduate, AMS 5]
theorem grad_lemma : True := by
  sorry

@[category undergraduate]
theorem undergrad_lemma : True := by
  sorry

@[category test]
theorem sanity_check : 1 + 1 = 2 := by
  sorry

@[category API]
theorem api_helper : True := by
  sorry

@[category research open, AMS 11]
theorem fill_in_blank : answer(sorry) ↔ True := by
  sorry

@[category research open]
theorem fill_in_blank_spaces : answer ( sorry ) = 42 := by
  sorry

/- Mentioning @[category test] in a doc comment must not exclude this theorem. -/
@[category research open]
theorem comment_mention_ok : True := by
  sorry

/-- Statement text copied from MathOverflow (Creative Commons Attribution-ShareAlike 4.0). -/
@[category research open]
theorem copyleft_doc_thm : True := by
  sorry

end Erdos123
'''


class FormalConjecturesGotchaTests(unittest.TestCase):
    def test_fc_category_extraction_and_exclusion(self):
        rows = scout.analyze_file("FormalConjectures/ErdosProblems/123.lean", FC_LEAN)
        by_n = {}
        for d, sl, st, r in rows:
            by_n.setdefault(d.name, []).append((sl, st, r, d))

        # research open / research solved / graduate / undergraduate are candidates
        for name, expected_cat in (
            ("Erdos123.erdos_123", "research open"),
            ("Erdos123.erdos_123_known", "research solved"),
            ("Erdos123.grad_lemma", "graduate"),
            ("Erdos123.undergrad_lemma", "undergraduate"),
            ("Erdos123.comment_mention_ok", "research open"),
        ):
            self.assertIn(name, by_n)
            self.assertTrue(all(st == "candidate" for _, st, _, _ in by_n[name]), by_n[name])
            self.assertEqual(scout.extract_fc_category(by_n[name][0][3].attr_text), expected_cat)

        # test and API categories are excluded
        for excluded_name, tag in (("Erdos123.sanity_check", "test"), ("Erdos123.api_helper", "API")):
            self.assertIn(excluded_name, by_n)
            for _, st, reasons, _ in by_n[excluded_name]:
                self.assertEqual(st, "excluded")
                self.assertTrue(any(f"@[category {tag}]" in r for r in reasons), reasons)

    def test_answer_sorry_excludes_all_sorry_lines_in_declaration(self):
        rows = scout.analyze_file("FormalConjectures/ErdosProblems/123.lean", FC_LEAN)
        for name in ("Erdos123.fill_in_blank", "Erdos123.fill_in_blank_spaces"):
            matches = [(sl, st, reasons) for d, sl, st, reasons in rows if d.name == name]
            self.assertGreaterEqual(len(matches), 2, f"expected both statement and proof sorry lines for {name}")
            for _, st, reasons in matches:
                self.assertEqual(st, "excluded", f"proof sorry leaked as candidate for {name}: {reasons}")
                self.assertTrue(any("answer(sorry)" in r for r in reasons), reasons)

    def test_copyleft_docstring_marker_detection(self):
        self.assertEqual(
            scout.detect_copyleft_markers("Text under CC-BY-SA 4.0 and cc by-sa 4.0 and GFDL."),
            ["CC-BY-SA 4.0", "GFDL"],
        )
        self.assertEqual(
            scout.detect_copyleft_markers("Licensed under Creative Commons Attribution-ShareAlike 3.0"),
            ["Creative Commons Attribution-ShareAlike"],
        )
        self.assertEqual(scout.detect_copyleft_markers("Pure Apache-2.0 file."), [])


DOWNSTREAM_YML = """
# Mathlib downstream repositories
PrimeNumberTheoremAnd:
  url: https://github.com/AlexKontorovich/PrimeNumberTheoremAnd.git
  branch: main

physlib:
  repo: leanprover-community/physlib
  rev: master

- https://github.com/kbuzzard/ClassFieldTheory
- https://github.com/leanprover-community/mathlib4  # must be skipped
- https://github.com/leanprover-community/physlib   # duplicate must be deduped
"""

RESERVOIR_META = [
    {
        "name": "lean-mlir",
        "stars": 120,
        "license": "Apache-2.0",
        "toolchain": "leanprover/lean4:v4.36.0",
        "sources": [{"type": "git", "host": "github", "repoUrl": "https://github.com/opencompl/lean-mlir"}],
    },
    {
        "name": "tiny-toy",
        "stars": 2,
        "license": "MIT",
        "toolchain": "leanprover/lean4:v4.36.0",
        "sources": [{"type": "git", "host": "github", "repoUrl": "https://github.com/someone/tiny-toy"}],
    },
    {
        "name": "old-pkg",
        "stars": 90,
        "license": "MIT",
        "toolchain": "leanprover/lean4:v4.12.0",
        "sources": [{"type": "git", "host": "github", "repoUrl": "https://github.com/someone/old-pkg"}],
    },
]

RESERVOIR_TREE = {
    "tree": [
        {"path": "README.md", "type": "blob"},
        {"path": "opencompl/lean-mlir/metadata.json", "type": "blob"},
        {"path": "someone/tiny-toy/metadata.json", "type": "blob"},
        {"path": "leanprover-community/mathlib4/metadata.json", "type": "blob"},
    ]
}


class DiscoveryParserTests(unittest.TestCase):
    def test_parse_downstream_repos_yml(self):
        items = scout.parse_downstream_repos_yml(DOWNSTREAM_YML)
        self.assertEqual(
            [i["repo"] for i in items],
            [
                "AlexKontorovich/PrimeNumberTheoremAnd",
                "leanprover-community/physlib",
                "kbuzzard/ClassFieldTheory",
            ],
        )
        self.assertEqual(items[0]["branch"], "main")
        self.assertTrue(all(i["source"] == "mathlib-downstream" for i in items))

    def test_parse_reservoir_metadata_and_tree(self):
        filtered = scout.parse_reservoir_metadata(RESERVOIR_META, min_stars=10, lean_version_prefix="v4.36")
        self.assertEqual([i["repo"] for i in filtered], ["opencompl/lean-mlir"])
        self.assertEqual(filtered[0]["stars"], 120)

        tree_items = scout.parse_reservoir_tree(RESERVOIR_TREE)
        self.assertEqual([i["repo"] for i in tree_items], ["opencompl/lean-mlir", "someone/tiny-toy"])

    def test_discover_repos_offline_and_graceful_errors(self):
        gh = FakeGh({"repos/leanprover/reservoir-index/git/trees/HEAD": RESERVOIR_TREE})
        http_routes = {
            scout.MATHLIB_DOWNSTREAM_YML_URL: DOWNSTREAM_YML,
            f"https://raw.githubusercontent.com/{scout.RESERVOIR_INDEX_REPO}/HEAD/opencompl/lean-mlir/metadata.json": json.dumps(RESERVOIR_META[0]),
            f"https://raw.githubusercontent.com/{scout.RESERVOIR_INDEX_REPO}/HEAD/someone/tiny-toy/metadata.json": json.dumps(RESERVOIR_META[1]),
        }
        items, warnings = scout.discover_repos(
            source="all",
            limit=10,
            min_stars=10,
            toolchain_prefix="v4.36",
            http_get=lambda u: http_routes[u],
            gh=gh,
        )
        self.assertEqual(warnings, [])
        self.assertIn("leanprover-community/physlib", [i["repo"] for i in items])
        self.assertIn("opencompl/lean-mlir", [i["repo"] for i in items])
        self.assertNotIn("someone/tiny-toy", [i["repo"] for i in items])

        # Exclude watchlist filters out already-watched repos cleanly.
        novel, _ = scout.discover_repos(
            source="reservoir",
            limit=5,
            exclude_watchlist=True,
            http_get=lambda u: http_routes[u],
            gh=gh,
        )
        self.assertEqual([i["repo"] for i in novel], ["someone/tiny-toy"])

        # Network failures degrade cleanly into warnings instead of crashing.
        def boom(_):
            raise RuntimeError("timed out after 5s")
        empty, errs = scout.discover_repos(source="all", http_get=boom, gh=boom)
        self.assertEqual(empty, [])
        self.assertEqual(len(errs), 2)


class ScaffoldArenaPackTests(unittest.TestCase):
    def test_topic_sharding_and_arena_pack_scaffolding(self):
        commit = "a" * 40
        info = {
            "repo": "google-deepmind/formal-conjectures",
            "commit": commit,
            "toolchain": "leanprover/lean4:v4.36.0",
            "mathlib": "v4.36.0",
            "license": "Apache-2.0",
            "license_text": "Apache License\nVersion 2.0\n",
            "domain": "math",
            "error": None,
        }
        cands = []
        # 60 open Erdős conjectures -> sharded at shard_size=25 into 25 + 25 + 10 (3 packs, open_conjecture=True)
        for i in range(60):
            cands.append(scout.Candidate(
                repo=info["repo"], commit=commit,
                file=f"FormalConjectures/ErdosProblems/P{i:03d}.lean",
                line=12, kind="theorem", name=f"Erdos.erdos_{i:03d}",
                url=f"https://github.com/{info['repo']}/blob/{commit}/FormalConjectures/ErdosProblems/P{i:03d}.lean#L10-L12",
                status="candidate", reasons=[], blueprint=False, statement_uses_sorry_decl=[],
                already_live=False, statement=f"theorem erdos_{i:03d} (n : Nat) : n + 0 = n",
                domain="math", toolchain="leanprover/lean4:v4.36.0",
                packaging="standalone-mathlib", packageable_now=True,
                category="research open", open_conjecture=True,
                raw_decl=f"theorem erdos_{i:03d} (n : Nat) : n + 0 = n := by\n  sorry",
                imports=["Mathlib"],
            ))
        # 3 graduate number-theory theorems (with a dependency edge) -> 1 non-open pack (no open_conjecture flag)
        for i in range(3):
            cands.append(scout.Candidate(
                repo=info["repo"], commit=commit,
                file=f"FormalConjectures/NumberTheory/N{i}.lean",
                line=8, kind="theorem", name=f"NT.grad_{i}",
                url=f"https://github.com/{info['repo']}/blob/{commit}/FormalConjectures/NumberTheory/N{i}.lean#L7-L8",
                status="candidate", reasons=[], blueprint=False, statement_uses_sorry_decl=[],
                already_live=False, statement=f"theorem grad_{i} : True",
                depends_on=(["NT.grad_0"] if i == 1 else []),
                domain="math", toolchain="leanprover/lean4:v4.36.0",
                packaging="standalone-mathlib", packageable_now=True,
                category="graduate", open_conjecture=False,
                raw_decl=f"theorem grad_{i} : True := by\n  sorry",
                imports=["Mathlib"],
            ))
        # Copyleft-flagged candidate must be skipped by default in --scaffold.
        cands.append(scout.Candidate(
            repo=info["repo"], commit=commit,
            file="FormalConjectures/NumberTheory/Wiki.lean",
            line=5, kind="theorem", name="NT.wiki_flagged",
            url="https://example.invalid", status="candidate", reasons=[],
            blueprint=False, statement_uses_sorry_decl=[], already_live=False,
            statement="theorem wiki_flagged : True",
            category="graduate", open_conjecture=False,
            copyleft_markers=["CC-BY-SA 4.0"],
            raw_decl="theorem wiki_flagged : True := by\n  sorry",
            imports=["Mathlib"],
        ))

        with tempfile.TemporaryDirectory() as tmp:
            packs = scout.scaffold_arena_packs([(info, cands)], tmp, shard_size=25, prefix="fc")
            self.assertEqual(len(packs), 4)
            by_id = {p["mission_id"]: p for p in packs}
            self.assertEqual(by_id["fc-erdos-problems-open-01"]["tasks"], 25)
            self.assertEqual(by_id["fc-erdos-problems-open-02"]["tasks"], 25)
            self.assertEqual(by_id["fc-erdos-problems-open-03"]["tasks"], 10)
            self.assertEqual(by_id["fc-number-theory"]["tasks"], 3)
            self.assertTrue(by_id["fc-erdos-problems-open-01"]["open_conjecture"])
            self.assertFalse(by_id["fc-number-theory"]["open_conjecture"])

            # Inspect generated Arena Pack files for exact Sunstead conventions.
            oc_dir = by_id["fc-erdos-problems-open-01"]["dir"]
            with open(os.path.join(oc_dir, "sunstead.json"), encoding="utf-8") as fh:
                manifest = json.load(fh)
            self.assertTrue(manifest.get("open_conjecture"))
            self.assertIn("UPSTREAM.json", manifest["frozen_paths"])
            self.assertEqual(len(manifest["tasks"]), 25)
            with open(os.path.join(oc_dir, "lean-toolchain"), encoding="utf-8") as fh:
                self.assertEqual(fh.read().strip(), "leanprover/lean4:v4.36.0")
            self.assertTrue(os.path.isfile(os.path.join(oc_dir, "LICENSE")))
            self.assertTrue(os.path.isfile(os.path.join(oc_dir, "lakefile.toml")))

            with open(os.path.join(oc_dir, "UPSTREAM.json"), encoding="utf-8") as fh:
                up_json = json.load(fh)
            self.assertEqual(up_json["commit"], commit)
            self.assertEqual(len(up_json["checks"]), 25)
            # Every verbatim_snippet in UPSTREAM.json must appear in its local stub file!
            for chk in up_json["checks"]:
                with open(os.path.join(oc_dir, chk["local_file"]), encoding="utf-8") as fh:
                    local_txt = fh.read()
                self.assertIn(chk["verbatim_snippet"], local_txt)

            # Generated `./verify` must be executable and AST-parseable with LIB_ROOT & TASKS.
            verify_path = os.path.join(oc_dir, "verify")
            self.assertTrue(os.stat(verify_path).st_mode & stat.S_IXUSR)
            with open(verify_path, encoding="utf-8") as fh:
                tree = ast.parse(fh.read())
            assigns = {t.id: ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) for t in n.targets if isinstance(t, ast.Name) and t.id in ("LIB_ROOT", "TASKS", "FROZEN_FILES")}
            self.assertEqual(len(assigns["TASKS"]), 25)

            # Non-open pack omits open_conjecture, wires intra-pack depends_on, and excludes wiki_flagged!
            with open(os.path.join(by_id["fc-number-theory"]["dir"], "sunstead.json"), encoding="utf-8") as fh:
                nt_manifest = json.load(fh)
            self.assertNotIn("open_conjecture", nt_manifest)
            nt_by_id = {t["id"]: t for t in nt_manifest["tasks"]}
            self.assertEqual(nt_by_id["grad_1"]["depends_on"], ["grad_0"])
            self.assertNotIn("wiki_flagged", nt_by_id)

            # Test REAL `--format json` -> `--from-json` -> `--scaffold` CLI round-trip preserves verbatim LICENSE!
            orig_scout_repo = scout.scout_repo
            orig_live_task_lines = scout.live_task_lines
            verbatim_license = "Apache License\nVersion 2.0, January 2004\nTERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION\nEND OF TERMS AND CONDITIONS\n"
            info_full = {**info, "license_text": verbatim_license}
            scout.scout_repo = lambda repo, workdir, tc, live, check_prs=False: (info_full, cands[:5])
            scout.live_task_lines = lambda: {}
            try:
                json_out, err_out = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(json_out), contextlib.redirect_stderr(err_out):
                    rc1 = scout.main(["--repo", info["repo"], "--format", "json"])
                self.assertEqual(rc1, 0)
            finally:
                scout.scout_repo = orig_scout_repo
                scout.live_task_lines = orig_live_task_lines

            parsed_json = json.loads(json_out.getvalue())
            self.assertEqual(parsed_json[0]["license_text"], verbatim_license)

            json_path = os.path.join(tmp, "scout.json")
            with open(json_path, "w", encoding="utf-8") as fh:
                fh.write(json_out.getvalue())
            out_dir2 = os.path.join(tmp, "cli-out")
            buf_out, buf_err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(buf_out), contextlib.redirect_stderr(buf_err):
                rc2 = scout.main(["--from-json", json_path, "--scaffold", out_dir2, "--shard-size", "25", "--format", "json"])
            self.assertEqual(rc2, 0)
            pack_dir2 = os.path.join(out_dir2, "formal-conjectures-erdos-problems-open")
            self.assertTrue(os.path.isdir(pack_dir2))
            with open(os.path.join(pack_dir2, "LICENSE"), encoding="utf-8") as fh:
                self.assertEqual(fh.read(), verbatim_license, "scaffolded LICENSE must match verbatim upstream license_text from --format json")


class PrebuildCacheScalingTests(unittest.TestCase):
    def test_prebuild_cache_skips_snapshots_filters_toolchain_and_dedups_parallel(self):
        vc_dir = os.path.join(scout.ROOT, "missions", "verifier-common")
        spec = importlib.util.spec_from_file_location("prebuild_cache_under_test", os.path.join(vc_dir, "prebuild_cache.py"))
        pc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pc)

        # Real missions/ scan skips repo-snapshot missions (lnsym-*, curve25519-dalek) cleanly.
        missions_root = os.path.join(scout.ROOT, "missions")
        v436 = pc.discover_mission_dirs([missions_root], toolchain="leanprover/lean4:v4.36.0")
        names = {os.path.basename(d) for d in v436}
        self.assertIn("pnt-analytic-foundations", names)
        self.assertIn("arklib-near-capacity-primes", names)
        self.assertNotIn("lnsym-aes-gcm-armv8", names)
        self.assertNotIn("curve25519-dalek", names)

        # prepare_mission_plan returns None on a repo-snapshot mission and valid plan on classic mission.
        self.assertIsNone(pc.prepare_mission_plan(os.path.join(missions_root, "lnsym-aes-gcm-armv8")))
        plan = pc.prepare_mission_plan(os.path.join(missions_root, "pnt-analytic-foundations"))
        self.assertIsNotNone(plan)
        self.assertEqual(plan["lib_root"], "PntFoundations")
        self.assertEqual(plan["task_count"], 6)

        # Atomic build + idempotent cache-hit reuse + parallel deduplication (mocking lean compile).
        compiled = []
        orig_compile = pc._compile_module
        orig_mathlib = pc.sb._mathlib_lib_paths

        def fake_compile(project_dir, mod, out_dir, lean_path):
            compiled.append(mod)
            segs = pc.sb._validate_mod_name(mod)
            out_olean = os.path.join(out_dir, *segs) + ".olean"
            os.makedirs(os.path.dirname(out_olean), exist_ok=True)
            with open(out_olean, "wb") as fh:
                fh.write(b"fake-olean")
            return out_olean

        pc._compile_module = fake_compile
        pc.sb._mathlib_lib_paths = lambda: ["/fake/mathlib"]
        try:
            with tempfile.TemporaryDirectory() as cache_tmp:
                out_buf = io.StringIO()
                with contextlib.redirect_stdout(out_buf):
                    st1 = pc.build_mission_plan(plan, cache_tmp)
                    st2 = pc.build_mission_plan(plan, cache_tmp)
                self.assertEqual(st1, "built")
                self.assertEqual(st2, "cached")
                self.assertEqual(compiled, ["PntFoundations.Spec", "PntFoundations.SunsteadStatements"])
                meta_path = os.path.join(cache_tmp, plan["cache_key"], "manifest.json")
                self.assertTrue(os.path.isfile(meta_path))
                with open(meta_path, encoding="utf-8") as fh:
                    meta = json.load(fh)
                self.assertEqual(meta["task_count"], 6)
        finally:
            pc._compile_module = orig_compile
            pc.sb._mathlib_lib_paths = orig_mathlib


class NoNetworkTests(unittest.TestCase):
    def test_suite_makes_no_subprocess_calls(self):
        """The offline tests above must never reach gh/git/http: guard subprocess.run & urlopen."""
        orig_run = scout.subprocess.run
        orig_url = scout.urllib.request.urlopen
        scout.subprocess.run = lambda *a, **k: (_ for _ in ()).throw(AssertionError("network/subprocess call in tests"))
        scout.urllib.request.urlopen = lambda *a, **k: (_ for _ in ()).throw(AssertionError("HTTP call in tests"))
        try:
            suite = unittest.defaultTestLoader.loadTestsFromTestCase(CheckPrsTests)
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(MultiToolchainTests))
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(PrefetchTests))
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(TimeoutAndLiveTests))
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(WatchlistExpansionTests))
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(FormalConjecturesGotchaTests))
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(DiscoveryParserTests))
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(ScaffoldArenaPackTests))
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(PrebuildCacheScalingTests))
            result = unittest.TestResult()
            suite.run(result)
            self.assertTrue(result.wasSuccessful(), result.failures + result.errors)
        finally:
            scout.subprocess.run = orig_run
            scout.urllib.request.urlopen = orig_url


if __name__ == "__main__":
    unittest.main()
