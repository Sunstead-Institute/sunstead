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
  globMatches,
  normalizeRelPath,
  validatePatch,
  type MissionManifest,
  type TaskState,
} from "../src/core.ts";

function task(id: string, over: Partial<TaskState> = {}, deps: string[] = []): TaskState {
  return {
    def: { id, title: id, target_files: [`src/${id}.rs`], depends_on: deps },
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

const FROZEN = ["src/spec.rs", "tests/**", "verify", "sunstead.json"];
const SPEC = "sha256:abc";

function mission(mode: "dag" | "hillclimb", tier = 3): MissionManifest {
  return {
    id: "m",
    title: "m",
    tier,
    mode,
    frozen_paths: FROZEN,
    verifier: { image: "x", command: ["./verify"] },
    score_direction: "minimize",
    tasks: [],
  };
}

// ---------------------------------------------------------------- paths

test("normalizeRelPath rejects traversal, absolute and backslash paths", () => {
  for (const bad of ["../etc/passwd", "a/../../x", "/etc/passwd", "src\\x.rs", "", "a/b/.."]) {
    assert.throws(() => normalizeRelPath(bad), /unsafe/, bad);
  }
  assert.equal(normalizeRelPath("a/src/./x.rs"), "src/x.rs");
  assert.equal(normalizeRelPath("b/src/x.rs"), "src/x.rs");
});

test("extractPatchPaths rejects binary and symlink patches", () => {
  assert.throws(() => extractPatchPaths("diff --git a/x b/x\nGIT binary patch\n"), /binary/);
  assert.throws(() => extractPatchPaths("Binary files a/x and b/x differ\n"), /binary/);
  assert.throws(
    () => extractPatchPaths("diff --git a/x b/x\nnew file mode 120000\n"),
    /symlink/
  );
  assert.throws(() => extractPatchPaths(""), /empty/);
});

test("extractPatchPaths sees rename and copy targets", () => {
  const p = "diff --git a/src/a.rs b/src/b.rs\nrename from src/a.rs\nrename to verify\n";
  assert.deepEqual(extractPatchPaths(p), ["src/a.rs", "src/b.rs", "verify"]);
});

test("globMatches handles *, ** and exact paths", () => {
  assert.ok(globMatches("tests/**", "tests/a/b.rs"));
  assert.ok(globMatches("tests/**", "tests/x.rs"));
  assert.ok(globMatches("src/*.rs", "src/x.rs"));
  assert.ok(!globMatches("src/*.rs", "src/a/x.rs"));
  assert.ok(globMatches("verify", "verify"));
  assert.ok(!globMatches("verify", "verify2"));
});

test("validatePatch blocks frozen paths and files outside target_files", () => {
  assert.throws(() => validatePatch(patchFor("src/spec.rs"), FROZEN, ["src/x.rs"]), /frozen/);
  assert.throws(() => validatePatch(patchFor("tests/t.rs"), FROZEN, []), /frozen/);
  assert.throws(() => validatePatch(patchFor("src/y.rs"), FROZEN, ["src/x.rs"]), /outside/);
  assert.deepEqual(validatePatch(patchFor("src/x.rs"), FROZEN, ["src/x.rs"]), ["src/x.rs"]);
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
  const p = patchFor("src/x.rs");
  assert.throws(
    () => applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "x", p, { ...ok, spec_sha256: "sha256:other" }),
    /spec hash mismatch/
  );
  assert.throws(
    () => applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "x", p, { ...ok, ok: false }),
    /verification failed/
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
    () => applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "b", patchFor("src/b.rs"), ok),
    /blocked/
  );
  const r = applyVerdict("dag", "maximize", FROZEN, SPEC, tasks, "a", patchFor("src/a.rs"), ok);
  assert.deepEqual(r.unlocked_dependents, ["b"]);
  const done = [task("a", { status: "verified" })];
  assert.throws(
    () => applyVerdict("dag", "maximize", FROZEN, SPEC, done, "a", patchFor("src/a.rs"), ok),
    /already verified/
  );
});

// ---------------------------------------------------------------- hill-climb

test("hill-climb accepts only strict improvements in the score direction", () => {
  const p = patchFor("src/x.rs");
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

test("DAG points depend on tier and dependencies", () => {
  assert.equal(computePoints(mission("dag", 1), task("a"), null, 1), 150);
  assert.equal(computePoints(mission("dag", 1), task("b", {}, ["a"]), null, 1), 250);
  assert.equal(computePoints(mission("dag", 3), task("a"), null, 1), 100);
  assert.equal(computePoints(mission("dag", 3), task("b", {}, ["a"]), null, 1), 150);
});
