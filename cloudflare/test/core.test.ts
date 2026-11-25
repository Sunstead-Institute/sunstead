// Unit tests for the hub's core rules (src/core.ts).
// Run with: npm test   (node --test with built-in TypeScript type stripping)
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  applyClaim,
  applyVerdict,
  computeFrontier,
  computePoints,
  extractPatchPaths,
  filesStateSha256,
  globMatches,
  normalizeRelPath,
  renderMbox,
  validatePatch,
  buildProofView,
  howToRebuild,
  sseHello,
  SSE_RETRY_MS,
  type AcceptedProofRow,
  type MissionManifest,
  type TaskState,
} from "../src/core.ts";

function task(id: string, over: Partial<TaskState> = {}, deps: string[] = []): TaskState {
  return {
    def: { id, title: id, target_files: [`MetaComplexity/${id}.lean`], depends_on: deps },
    status: "open",
    best_score: null,
    verified_by: null,
    active_lease: null,
    attempts: 0,
    ...over,
  };
}

function patchFor(...paths: string[]): string {
  return paths
    .map((p) => `diff --git a/${p} b/${p}\n--- a/${p}\n+++ b/${p}\n@@ -1 +1 @@\n-x\n+y\n`)
    .join("");
}

const FROZEN = ["MetaComplexity/Spec.lean", "lakefile.toml", "lean-toolchain", "verify", "sunstead.json"];
const SPEC = "sha256:abc";

function mission(
  mode: "dag" | "hillclimb",
  tier = 1,
  extra: Partial<MissionManifest> = {}
): MissionManifest {
  return {
    id: "m",
    title: "m",
    tier,
    mode,
    frozen_paths: FROZEN,
    verifier: { image: "sunstead/verifier-lean4:v0.1", command: ["./verify"] },
    score_direction: "minimize",
    tasks: [],
    ...extra,
  };
}

// ---------------------------------------------------------------- paths & diffs

test("normalizeRelPath rejects traversal, absolute and backslash paths", () => {
  for (const bad of ["../etc/passwd", "a/../../x", "/etc/passwd", "src\\x.lean", "", "a/b/.."]) {
    assert.throws(() => normalizeRelPath(bad), /unsafe/, bad);
  }
  assert.equal(normalizeRelPath("a/MetaComplexity/./Pigeonhole.lean"), "MetaComplexity/Pigeonhole.lean");
  assert.equal(normalizeRelPath("b/MetaComplexity/Pigeonhole.lean"), "MetaComplexity/Pigeonhole.lean");
});

test("extractPatchPaths rejects binary and symlink patches", () => {
  assert.throws(() => extractPatchPaths("diff --git a/x b/x\nGIT binary patch\n"), /binary/);
  assert.throws(() => extractPatchPaths("Binary files a/x and b/x differ\n"), /binary/);
  assert.throws(
    () => extractPatchPaths("diff --git a/x b/x\nnew file mode 120000\n"),
    /symlink/
  );
  assert.throws(
    () => extractPatchPaths("diff --git a/x b/x\ndeleted file mode 120000\n"),
    /symlink/
  );
  assert.throws(() => extractPatchPaths(""), /empty/);
});

test("extractPatchPaths sees rename and copy targets", () => {
  const p = "diff --git a/MetaComplexity/A.lean b/MetaComplexity/B.lean\nrename from MetaComplexity/A.lean\nrename to verify\n";
  assert.deepEqual(extractPatchPaths(p), ["MetaComplexity/A.lean", "MetaComplexity/B.lean", "verify"]);
});

test("extractPatchPaths allows deleting Lean `-- ` comments and adding `++ ` lines inside hunks", () => {
  const leanDiff = [
    "diff --git a/MetaComplexity/Pigeonhole.lean b/MetaComplexity/Pigeonhole.lean",
    "index 1111111..2222222 100644",
    "--- a/MetaComplexity/Pigeonhole.lean",
    "+++ b/MetaComplexity/Pigeonhole.lean",
    "@@ -1,5 +1,5 @@",
    " import MetaComplexity.Spec",
    "--- TODO: prove pigeonhole",
    "--- another comment with /dev/null and ../etc/passwd",
    "+++ a + b",
    "+++ c ++ d",
    " end MetaComplexity",
    "",
  ].join("\n");
  assert.deepEqual(
    validatePatch(leanDiff, FROZEN, ["MetaComplexity/Pigeonhole.lean"]),
    ["MetaComplexity/Pigeonhole.lean"]
  );
});

test("extractPatchPaths handles single-line hunks (omitted counts) and multi-hunk diffs", () => {
  const multiHunk = [
    "diff --git a/MetaComplexity/Pigeonhole.lean b/MetaComplexity/Pigeonhole.lean",
    "--- a/MetaComplexity/Pigeonhole.lean",
    "+++ b/MetaComplexity/Pigeonhole.lean",
    "@@ -1 +1 @@",
    "--- single-line comment removed",
    "+++ single-line addition",
    "@@ -10,3 +10,3 @@ theorem foo",
    " context line",
    "--- second hunk lean comment",
    "+++ second hunk ++ line",
    "\\ No newline at end of file",
    " tail context",
    "",
  ].join("\n");
  assert.deepEqual(
    validatePatch(multiHunk, FROZEN, ["MetaComplexity/Pigeonhole.lean"]),
    ["MetaComplexity/Pigeonhole.lean"]
  );
});

test("extractPatchPaths distinguishes adversarial `--- a/verify` inside hunk vs outside hunk", () => {
  // Inside a hunk: literally deleting the line `-- a/verify` from the allowed target file.
  const insideHunk = [
    "diff --git a/MetaComplexity/Pigeonhole.lean b/MetaComplexity/Pigeonhole.lean",
    "--- a/MetaComplexity/Pigeonhole.lean",
    "+++ b/MetaComplexity/Pigeonhole.lean",
    "@@ -1,2 +1,2 @@",
    "--- a/verify",
    "+++ b/verify",
    " end MetaComplexity",
    "",
  ].join("\n");
  assert.deepEqual(
    validatePatch(insideHunk, FROZEN, ["MetaComplexity/Pigeonhole.lean"]),
    ["MetaComplexity/Pigeonhole.lean"]
  );

  // Outside a hunk (second file in plain unified diff without `diff --git` header): MUST reject!
  const outsideHunk = [
    "--- a/MetaComplexity/Pigeonhole.lean",
    "+++ b/MetaComplexity/Pigeonhole.lean",
    "@@ -1 +1 @@",
    "-old",
    "+new",
    "--- a/verify",
    "+++ b/verify",
    "@@ -1 +1 @@",
    "-x",
    "+y",
    "",
  ].join("\n");
  assert.deepEqual(extractPatchPaths(outsideHunk), ["MetaComplexity/Pigeonhole.lean", "verify"]);
  assert.throws(
    () => validatePatch(outsideHunk, FROZEN, ["MetaComplexity/Pigeonhole.lean"]),
    /frozen/
  );

  // Truncated hunk where oldRem already hit 0 (new-file hunk @@ -0,0 +1,2 @@):
  // a `--- a/verify` line cannot be a `-` hunk line and must be parsed as a header!
  const sneakyAfterNewFileHunk = [
    "--- /dev/null",
    "+++ b/MetaComplexity/Pigeonhole.lean",
    "@@ -0,0 +1,2 @@",
    "+line1",
    "--- a/verify",
    "+++ b/verify",
    "@@ -1 +1 @@",
    "-a",
    "+b",
    "",
  ].join("\n");
  assert.throws(
    () => validatePatch(sneakyAfterNewFileHunk, FROZEN, ["MetaComplexity/Pigeonhole.lean"]),
    /frozen/
  );
});

test("globMatches handles *, ** and exact paths", () => {
  assert.ok(globMatches("MetaComplexity/**", "MetaComplexity/a/b.lean"));
  assert.ok(globMatches("MetaComplexity/**", "MetaComplexity/Spec.lean"));
  assert.ok(globMatches("MetaComplexity/*.lean", "MetaComplexity/Spec.lean"));
  assert.ok(!globMatches("MetaComplexity/*.lean", "MetaComplexity/a/Spec.lean"));
  assert.ok(globMatches("verify", "verify"));
  assert.ok(!globMatches("verify", "verify2"));
});

test("validatePatch blocks frozen paths and files outside target_files", () => {
  assert.throws(
    () => validatePatch(patchFor("MetaComplexity/Spec.lean"), FROZEN, ["MetaComplexity/X.lean"]),
    /frozen/
  );
  assert.throws(() => validatePatch(patchFor("verify"), FROZEN, []), /frozen/);
  assert.throws(
    () => validatePatch(patchFor("MetaComplexity/Y.lean"), FROZEN, ["MetaComplexity/X.lean"]),
    /outside/
  );
  assert.deepEqual(
    validatePatch(patchFor("MetaComplexity/X.lean"), FROZEN, ["MetaComplexity/X.lean"]),
    ["MetaComplexity/X.lean"]
  );
});

// ---------------------------------------------------------------- DAG

test("frontier and claims respect dependencies", () => {
  const tasks = [task("a"), task("b", {}, ["a"])];
  assert.deepEqual(computeFrontier("dag", tasks), ["a"]);
  assert.throws(() => applyClaim("dag", tasks, "b", "alice", "t", 0, 600), /blocked/);
  const { lease } = applyClaim("dag", tasks, "a", "alice", "t", 1000, 99999);
  assert.equal(lease.expires_at_unix, 1000 + 3600, "lease duration is capped at 1h");
});

test("an active lease blocks other claimants but not after expiry", () => {
  const leased = task("a", {
    active_lease: { task_id: "a", contributor: "alice", lease_token: "t", expires_at_unix: 2000 },
  });
  assert.throws(() => applyClaim("dag", [leased], "a", "bob", "u", 1500, 600), /actively leased/);
  assert.doesNotThrow(() => applyClaim("dag", [leased], "a", "bob", "u", 2001, 600));
});

test("applyVerdict requires a passing verdict on the pinned spec", () => {
  const tasks = [task("x")];
  const ok = { ok: true, score: 1, summary: "", spec_sha256: SPEC };
  const p = patchFor("MetaComplexity/x.lean");
  assert.throws(
    () => applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "x", p, { ...ok, spec_sha256: "sha256:other" }),
    /spec hash mismatch/
  );
  assert.throws(
    () => applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "x", p, { ...ok, ok: false, summary: "git apply failed", spec_sha256: "" }),
    /verification failed: git apply failed/
  );
  assert.throws(
    () => applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "x", patchFor("verify"), ok),
    /frozen/
  );
  const r = applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "x", p, ok);
  assert.equal(r.updated_status, "verified");
});

test("applyVerdict refuses blocked and already-verified DAG tasks, and reports unlocks", () => {
  const ok = { ok: true, score: 1, summary: "", spec_sha256: SPEC };
  const tasks = [task("a"), task("b", {}, ["a"])];
  assert.throws(
    () => applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "b", patchFor("MetaComplexity/b.lean"), ok),
    /blocked/
  );
  const r = applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "a", patchFor("MetaComplexity/a.lean"), ok);
  assert.deepEqual(r.unlocked_dependents, ["b"]);
  const done = [task("a", { status: "verified" })];
  assert.throws(
    () => applyVerdict("dag", "maximize", FROZEN, SPEC, done, "a", patchFor("MetaComplexity/a.lean"), ok),
    /already verified/
  );
});

// ---------------------------------------------------------------- hill-climb & demo

test("hill-climb accepts only strict improvements in the score direction", () => {
  const p = patchFor("MetaComplexity/x.lean");
  const tasks = [task("x", { best_score: 1000, status: "verified" })];
  const v = (score: number | null) => ({ ok: true, score, summary: "", spec_sha256: SPEC });
  assert.throws(() => applyVerdict("hillclimb", "minimize", FROZEN, SPEC, tasks, "x", p, v(1000)), /strictly/);
  assert.throws(() => applyVerdict("hillclimb", "minimize", FROZEN, SPEC, tasks, "x", p, v(1200)), /strictly/);
  assert.throws(() => applyVerdict("hillclimb", "minimize", FROZEN, SPEC, tasks, "x", p, v(null)), /numeric/);
  assert.equal(applyVerdict("hillclimb", "minimize", FROZEN, SPEC, tasks, "x", p, v(999)).new_best_score, 999);
  assert.equal(applyVerdict("hillclimb", "maximize", FROZEN, SPEC, tasks, "x", p, v(1001)).new_best_score, 1001);
});

test("hill-climb points follow the log ratio, so farming tiny steps never pays", () => {
  const m = mission("hillclimb", 2);
  const t = task("x");
  assert.equal(computePoints(m, t, 1000, 999), 0, "a 0.1% improvement earns nothing");
  assert.equal(computePoints(m, t, 1000, 500), 173, "halving earns floor(250 ln 2)");
  assert.equal(computePoints(m, t, 1000, 150), 474);
  assert.equal(computePoints(m, t, 100, 200), 173, "maximize direction uses the same ratio");
  assert.equal(computePoints(m, t, null, 500), 100, "first record without a baseline");
  let farmed = 0;
  for (let s = 1000; s > 150; s--) farmed += computePoints(m, t, s, s - 1);
  assert.ok(farmed <= computePoints(m, t, 1000, 150), `step-by-step farming earned ${farmed}`);
});

test("demo missions award 0 points in both hillclimb and dag modes", () => {
  const demoHill = mission("hillclimb", 2, { demo: true });
  const demoDag = mission("dag", 1, { demo: true });
  assert.equal(computePoints(demoHill, task("x"), 1000, 150), 0);
  assert.equal(computePoints(demoHill, task("x"), null, 150), 0);
  assert.equal(computePoints(demoDag, task("a"), null, 1), 0);
  assert.equal(computePoints(demoDag, task("b", {}, ["a"]), null, 1), 0);
});

test("DAG points depend on tier and dependencies", () => {
  assert.equal(computePoints(mission("dag", 1), task("a"), null, 1), 150);
  assert.equal(computePoints(mission("dag", 1), task("b", {}, ["a"]), null, 1), 250);
  assert.equal(computePoints(mission("dag", 2), task("a"), null, 1), 100);
  assert.equal(computePoints(mission("dag", 2), task("b", {}, ["a"]), null, 1), 150);
});

test("filesStateSha256 matches the verifier server's files_sha256", async () => {
  // Vectors computed with the Python implementation in verifier_server.py.
  assert.equal(
    await filesStateSha256({ "src/b.rs": "fn b() {}\n", "src/a.rs": "\u00e9\n" }),
    "sha256:362445fe35ae3d719173ae2561e3aa0a61d41d06d820e5f58f7feddc5f385493"
  );
  assert.equal(
    await filesStateSha256({}),
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  );
});

test("renderMbox escapes From lines in body and diff and prevents bare --- separator in summary", () => {
  const mbox = renderMbox([
    {
      seq: 1,
      mission_id: "m",
      task_id: "t",
      contributor: "alice",
      display_name: "Alice <x>",
      summary: "ok\nFrom here\n---\n---   \nafter",
      patch: "From preamble\ndiff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-x\n+y\n",
      created_at: 0,
    },
  ]);
  assert.match(mbox, /^From 0{39}1 Mon Sep 17 00:00:00 2001\n/);
  assert.match(mbox, /\nFrom: Alice x <alice@contributors\.sunstead\.org>\n/);
  assert.match(mbox, /\nSubject: \[PATCH\] m: verify t\n/);
  assert.match(mbox, /\n>From here\n/);
  assert.match(mbox, /\n ---\n ---   \nafter\n/);
  assert.match(mbox, /\n---\n>From preamble\ndiff --git a\/f b\/f\n/);
  // Exactly one bare `---` separator line before the diff (plus `--- a/f` in the diff itself).
  const bareDashes = mbox.split("\n").filter((l) => /^---[ \t]*$/.test(l));
  assert.equal(bareDashes.length, 1);
});

function proofRow(over: Partial<AcceptedProofRow> = {}): AcceptedProofRow {
  return {
    seq: 7,
    mission_id: "pnt-analytic-foundations",
    task_id: "liouville",
    submission_id: "sub-1",
    contributor: "codex-dirichlet",
    display_name: "Codex Dirichlet",
    github: "codex-dirichlet",
    summary: "kernel replay ok",
    patch:
      "--- a/PNT/Liouville.lean\n+++ b/PNT/Liouville.lean\n@@ -1,1 +1,1 @@\n-  sorry\n+  exact foo\n",
    spec_sha256: "sha256:aaa",
    created_at: 1_790_000_000,
    verify_ms: 63_000,
    ...over,
  };
}

test("buildProofView returns attribution, timing, files, spec status and rebuild commands", () => {
  const v = buildProofView(proofRow(), {
    hubOrigin: "https://sunstead.org",
    currentSpecSha256: "sha256:aaa",
    patchSha256: "sha256:ppp",
  });
  assert.equal(v.contributor, "codex-dirichlet");
  assert.equal(v.display_name, "Codex Dirichlet");
  assert.equal(v.github, "codex-dirichlet");
  assert.equal(v.verify_ms, 63_000);
  assert.equal(v.accepted_at, 1_790_000_000);
  assert.equal(v.spec_is_current, true);
  assert.equal(v.patch_sha256, "sha256:ppp");
  assert.deepEqual(v.files, ["PNT/Liouville.lean"]);
  assert.match(v.patch, /\+  exact foo/);
  assert.equal(v.history_mbox, "https://sunstead.org/api/missions/pnt-analytic-foundations/history.mbox");
  assert.match(v.how_to_rebuild, /\| git am$/);
});

test("buildProofView flags proofs accepted under an older spec and falls back on missing names", () => {
  const v = buildProofView(proofRow({ spec_sha256: "sha256:old", display_name: "", github: null, verify_ms: null }), {
    hubOrigin: "http://127.0.0.1:8787",
    currentSpecSha256: "sha256:new",
    patchSha256: "sha256:ppp",
  });
  assert.equal(v.spec_is_current, false);
  assert.equal(v.display_name, "codex-dirichlet");
  assert.equal(v.github, null);
  assert.equal(v.verify_ms, null);
});

test("howToRebuild quotes URLs so shells do not glob ?base=seed", () => {
  const cmd = howToRebuild("https://sunstead.org", "onboarding-sandbox");
  assert.equal(
    cmd,
    "mkdir 'onboarding-sandbox' && cd 'onboarding-sandbox' && " +
      "curl -sL 'https://sunstead.org/api/missions/onboarding-sandbox/bundle.tar.gz?base=seed' | tar xz && " +
      "curl -sL 'https://sunstead.org/api/missions/onboarding-sandbox/history.mbox' | git am"
  );
  assert.match(howToRebuild("https://h", "it's"), /mkdir 'it'\\''s'/);
});

test("SSE streams open with a retry directive so clients reconnect fast after a deploy", () => {
  const hello = sseHello();
  // The `retry:` field must be its own line, before the blank line that ends the event.
  assert.match(hello, /^retry: \d+\n/);
  assert.equal(hello, `retry: ${SSE_RETRY_MS}\n: connected\n\n`);
  assert.ok(SSE_RETRY_MS >= 1000 && SSE_RETRY_MS <= 5000);
});
