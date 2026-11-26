// Unit tests for the hub's core rules (src/core.ts).
// Run with: npm test   (node --test with built-in TypeScript type stripping)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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
  buildLedgerEntry,
  buildLedgerProof,
  isLedgerPagePath,
  parseLedgerQuery,
  PROOF_HASH_RE,
  proofIdFromPatchSha,
  LEDGER_DEFAULT_LIMIT,
  LEDGER_MAX_LIMIT,
  buildTaskFilesView,
  sanitizeFailureDiagnostics,
  MAX_DIAGNOSTICS_CHARS,
  resolveVerifierKind,
  SUPPORTED_VERIFIER_TOOLCHAINS,
  normalizeGithubHandle,
  normalizeXHandle,
  normalizeLinkedinHandle,
  parseProfilePatch,
  gatePublicSocialHandles,
  buildPublicSocialLinks,
  publicVerifierImage,
  buildMissionLocalSetup,
  renderRepoSnapshotBootstrapScript,
  HILLCLIMB_LOG_SCALE,
  VerifierSlotPool,
  VERIFIER_POOL_SIZE,
  verifierSlotName,
  isMissionCompleted,
  sortMissionSummaries,
  constantTimeEqual,
  shouldRunAsyncSubmit,
  formatSubmissionStatusView,
  computeDecompPointSplit,
  computeRefutationBounty,
  checkDecompositionEligibility,
  parseDecomposeRequest,
  parseRefuteRequest,
  buildSubgoalStubSource,
  assembleDecomposedLeanFile,
  generateUnifiedDiff,
  extractPropStatementExpr,
  MAX_SUBGOAL_STATEMENT_BYTES,
  type AcceptedProofRow,
  type MissionManifest,
  type SubmissionStatusRow,
  type TaskState,
} from "../src/core.ts";
import { renderJoinTxt } from "../src/join_txt.ts";
import { spawnSync } from "node:child_process";

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

test("rank mission only permits coefficient table patches", () => {
  const manifest = JSON.parse(readFileSync(new URL(
    "../../missions/matrix-rank444-f2/sunstead.json", import.meta.url
  ), "utf8")) as MissionManifest;
  const [rank] = manifest.tasks;
  assert.equal(manifest.score_direction, "minimize");
  assert.equal(rank.baseline_score, 47);
  assert.deepEqual(rank.target_files, ["Rank444/Certificate.lean"]);
  for (const file of ["Rank444/Bound.lean", "Rank444/Spec.lean", "verify"]) {
    assert.throws(() => validatePatch(patchFor(file), manifest.frozen_paths, rank.target_files), /frozen/);
  }
  validatePatch(patchFor(rank.target_files[0]), manifest.frozen_paths, rank.target_files);
});

test("aes-sbox-circuit mission isolates independent total and AND circuit targets", () => {
  const manifest = JSON.parse(readFileSync(new URL(
    "../../missions/aes-sbox-circuit/sunstead.json", import.meta.url
  ), "utf8")) as MissionManifest;
  assert.equal(manifest.mode, "hillclimb");
  assert.equal(manifest.score_direction, "minimize");
  assert.equal(manifest.tier, 2);
  const byId = Object.fromEntries(manifest.tasks.map((t) => [t.id, t]));
  assert.equal(byId.minimize_total_gates.baseline_score, 130);
  assert.equal(byId.minimize_and_gates.baseline_score, 36);
  assert.deepEqual(byId.minimize_total_gates.target_files, ["AesSbox/TotalCircuit.lean"]);
  assert.deepEqual(byId.minimize_and_gates.target_files, ["AesSbox/AndCircuit.lean"]);
  for (const file of ["AesSbox/Spec.lean", "AesSbox/TotalBound.lean", "AesSbox/AndBound.lean", "verify"]) {
    assert.throws(
      () => validatePatch(patchFor(file), manifest.frozen_paths, byId.minimize_total_gates.target_files),
      /frozen/
    );
  }
  assert.throws(
    () => validatePatch(patchFor("AesSbox/AndCircuit.lean"), manifest.frozen_paths, byId.minimize_total_gates.target_files),
    /outside/
  );
  validatePatch(patchFor("AesSbox/TotalCircuit.lean"), manifest.frozen_paths, byId.minimize_total_gates.target_files);
  validatePatch(patchFor("AesSbox/AndCircuit.lean"), manifest.frozen_paths, byId.minimize_and_gates.target_files);
});

test("sorting-networks-opt mission isolates independent n=9..16 network targets", () => {
  const manifest = JSON.parse(readFileSync(new URL(
    "../../missions/sorting-networks-opt/sunstead.json", import.meta.url
  ), "utf8")) as MissionManifest;
  assert.equal(manifest.mode, "hillclimb");
  assert.equal(manifest.score_direction, "minimize");
  assert.equal(manifest.tier, 2);
  const byId = Object.fromEntries(manifest.tasks.map((t) => [t.id, t]));
  const expected: Record<string, [number, string]> = {
    sort_n9: [26, "SortNet/Net9.lean"],
    sort_n10: [31, "SortNet/Net10.lean"],
    sort_n11: [37, "SortNet/Net11.lean"],
    sort_n12: [41, "SortNet/Net12.lean"],
    sort_n13: [48, "SortNet/Net13.lean"],
    sort_n14: [53, "SortNet/Net14.lean"],
    sort_n15: [59, "SortNet/Net15.lean"],
    sort_n16: [63, "SortNet/Net16.lean"],
  };
  for (const [id, [baseline, target]] of Object.entries(expected)) {
    assert.equal(byId[id].baseline_score, baseline);
    assert.deepEqual(byId[id].target_files, [target]);
    validatePatch(patchFor(target), manifest.frozen_paths, byId[id].target_files);
  }
  for (const file of ["SortNet/Spec.lean", "SortNet/Bound9.lean", "SortNet/Bound16.lean", "verify"]) {
    assert.throws(
      () => validatePatch(patchFor(file), manifest.frozen_paths, byId.sort_n9.target_files),
      /frozen/
    );
  }
  assert.throws(
    () => validatePatch(patchFor("SortNet/Net10.lean"), manifest.frozen_paths, byId.sort_n9.target_files),
    /outside/
  );
});

test("crypto-sbox-circuits mission isolates all 6 independent S-box circuit targets", () => {
  const manifest = JSON.parse(readFileSync(new URL(
    "../../missions/crypto-sbox-circuits/sunstead.json", import.meta.url
  ), "utf8")) as MissionManifest;
  assert.equal(manifest.mode, "hillclimb");
  assert.equal(manifest.score_direction, "minimize");
  assert.equal(manifest.tier, 2);
  assert.equal(manifest.tasks.length, 6);
  const byId = Object.fromEntries(manifest.tasks.map((t) => [t.id, t]));
  assert.equal(byId.sm4_total_gates.baseline_score, 130);
  assert.equal(byId.sm4_and_gates.baseline_score, 36);
  assert.equal(byId.aes_inv_total_gates.baseline_score, 129);
  assert.equal(byId.aes_inv_and_gates.baseline_score, 36);
  assert.equal(byId.camellia_total_gates.baseline_score, 130);
  assert.equal(byId.camellia_and_gates.baseline_score, 36);
  for (const file of [
    "CryptoSbox/Spec.lean",
    "CryptoSbox/Sm4TotalBound.lean",
    "CryptoSbox/AesInvTotalBound.lean",
    "CryptoSbox/CamelliaAndBound.lean",
    "verify",
  ]) {
    assert.throws(
      () => validatePatch(patchFor(file), manifest.frozen_paths, byId.sm4_total_gates.target_files),
      /frozen/
    );
  }
  assert.throws(
    () => validatePatch(patchFor("CryptoSbox/CamelliaTotalCircuit.lean"), manifest.frozen_paths, byId.sm4_total_gates.target_files),
    /outside/
  );
  for (const t of manifest.tasks) {
    validatePatch(patchFor(t.target_files[0]), manifest.frozen_paths, t.target_files);
  }
});

test("Wave 4 arenas isolate independent targets and freeze specs/bounds", () => {
  const depthManifest = JSON.parse(readFileSync(new URL(
    "../../missions/sorting-networks-depth-opt/sunstead.json", import.meta.url
  ), "utf8")) as MissionManifest;
  assert.equal(depthManifest.mode, "hillclimb");
  assert.equal(depthManifest.score_direction, "minimize");
  assert.equal(depthManifest.tasks.length, 8);
  const depthById = Object.fromEntries(depthManifest.tasks.map((t) => [t.id, t]));
  for (let n = 9; n <= 16; n++) {
    assert.equal(depthById[`depth_n${n}`].baseline_score, n);
    validatePatch(patchFor(`SortDepth/Layers${n}.lean`), depthManifest.frozen_paths, depthById[`depth_n${n}`].target_files);
  }
  assert.throws(
    () => validatePatch(patchFor("SortDepth/Spec.lean"), depthManifest.frozen_paths, depthById.depth_n9.target_files),
    /frozen/
  );
  assert.throws(
    () => validatePatch(patchFor("SortDepth/Layers10.lean"), depthManifest.frozen_paths, depthById.depth_n9.target_files),
    /outside/
  );

  const xorManifest = JSON.parse(readFileSync(new URL(
    "../../missions/crypto-linear-xor-opt/sunstead.json", import.meta.url
  ), "utf8")) as MissionManifest;
  assert.equal(xorManifest.mode, "hillclimb");
  assert.equal(xorManifest.score_direction, "minimize");
  assert.equal(xorManifest.tasks.length, 6);
  const xorById = Object.fromEntries(xorManifest.tasks.map((t) => [t.id, t]));
  assert.equal(xorById.aes_mixcolumns_xor.baseline_score, 152);
  assert.equal(xorById.aes_invmixcolumns_xor.baseline_score, 440);
  assert.equal(xorById.sm4_linear_l_xor.baseline_score, 128);
  assert.equal(xorById.sm4_key_lprime_xor.baseline_score, 64);
  assert.equal(xorById.aria_diffusion_xor.baseline_score, 96);
  assert.equal(xorById.camellia_p_xor.baseline_score, 36);
  for (const t of xorManifest.tasks) {
    validatePatch(patchFor(t.target_files[0]), xorManifest.frozen_paths, t.target_files);
  }
  assert.throws(
    () => validatePatch(patchFor("CryptoLinearXor/Spec.lean"), xorManifest.frozen_paths, xorById.aes_mixcolumns_xor.target_files),
    /frozen/
  );

  for (const [dir, count] of [
    ["ieantn-buthe-partial-rh", 6],
    ["ieantn-explicit-pnt-applications", 6],
  ] as const) {
    const m = JSON.parse(readFileSync(new URL(
      `../../missions/${dir}/sunstead.json`, import.meta.url
    ), "utf8")) as MissionManifest;
    assert.equal(m.mode, "dag");
    assert.equal(m.tier, 1);
    assert.equal(m.tasks.length, count);
    assert.throws(
      () => validatePatch(patchFor("IEANTN/Spec.lean"), m.frozen_paths, m.tasks[0].target_files),
      /frozen/
    );
    for (const t of m.tasks) {
      validatePatch(patchFor(t.target_files[0]), m.frozen_paths, t.target_files);
    }
  }
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

test("hill-climb points follow the log ratio, reward tight open records, and prevent farming", () => {
  const m = mission("hillclimb", 2);
  const t = task("x");
  assert.equal(HILLCLIMB_LOG_SCALE, 5000);
  assert.equal(computePoints(m, t, 10000, 9999), 0, "a 0.01% improvement earns nothing");
  assert.equal(computePoints(m, t, 47, 46), 107, "breaking 47->46 on matrix-rank444-f2 awards meaningful credit");
  assert.equal(computePoints(m, t, 23, 22), 222, "breaking 23->22 on <3,3,3> awards substantial credit");
  assert.equal(computePoints(m, t, 1000, 500), Math.floor(5000 * Math.log(2)), "halving earns floor(5000 ln 2)");
  assert.equal(computePoints(m, t, 100, 200), Math.floor(5000 * Math.log(2)), "maximize direction uses the same ratio");
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
  const cmd = howToRebuild("https://sunstead.org", "pnt-analytic-foundations");
  assert.equal(
    cmd,
    "mkdir 'pnt-analytic-foundations' && cd 'pnt-analytic-foundations' && " +
      "curl -sL 'https://sunstead.org/api/missions/pnt-analytic-foundations/bundle.tar.gz?base=seed' | tar xz && " +
      "curl -sL 'https://sunstead.org/api/missions/pnt-analytic-foundations/history.mbox' | git am"
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

// ---------------------------------------------------------------- proof ledger

const LEDGER_SHA = "ab".repeat(32);

function ledgerMission(over: Partial<MissionManifest> = {}) {
  return {
    manifest: mission("dag", 1, {
      id: "pnt-analytic-foundations",
      title: "PNT+ analytic foundations",
      upstream: { repo: "AlexKontorovich/PrimeNumberTheoremAnd", commit: "e990613" + "0".repeat(33), license: "Apache-2.0" },
      tasks: [
        {
          id: "liouville",
          title: "Liouville lemma",
          target_files: ["PNT/Liouville.lean"],
          upstream_url: "https://github.com/AlexKontorovich/PrimeNumberTheoremAnd/blob/x/PNT.lean#L1",
        },
      ],
      ...over,
    }),
    spec_sha256: "sha256:aaa",
  };
}

test("ledger entries carry provenance, attribution, spec status and a permalink", () => {
  const e = buildLedgerEntry({ ...proofRow(), patch_sha256: `sha256:${LEDGER_SHA}` }, ledgerMission(), "https://sunstead.org");
  assert.equal(e.permalink, `https://sunstead.org/proofs/${LEDGER_SHA}`);
  assert.equal(e.proof_id, LEDGER_SHA);
  assert.equal(e.patch_sha256, `sha256:${LEDGER_SHA}`, "same form as the task proof endpoint");
  assert.equal(e.mission_title, "PNT+ analytic foundations");
  assert.equal(e.task_title, "Liouville lemma");
  assert.equal(e.mission_retired, false);
  assert.equal(e.mission_demo, false);
  assert.equal(e.spec_is_current, true);
  assert.deepEqual(e.upstream, {
    repo: "AlexKontorovich/PrimeNumberTheoremAnd",
    commit: "e990613" + "0".repeat(33),
    license: "Apache-2.0",
    task_url: "https://github.com/AlexKontorovich/PrimeNumberTheoremAnd/blob/x/PNT.lean#L1",
  });
  assert.equal(e.display_name, "Codex Dirichlet");
  assert.deepEqual(e.files, ["PNT/Liouville.lean"]);
  assert.equal("audit" in e, false);
  assert.equal("patch" in e, false, "list entries leave the patch body to the permalink");
});

test("ledger keeps proofs from retired missions and flags demo and stale-spec proofs", () => {
  const retired = buildLedgerEntry({ ...proofRow(), patch_sha256: `sha256:${LEDGER_SHA}` }, null, "https://h");
  assert.equal(retired.mission_retired, true);
  assert.equal(retired.mission_demo, false);
  assert.equal(retired.mission_title, null);
  assert.equal(retired.upstream, null);
  assert.equal(retired.spec_is_current, false);

  const retiredDemo = buildLedgerEntry(
    {
      ...proofRow({ mission_id: "onboarding-sandbox", task_id: "decoder_injective", is_demo: 1 }),
      patch_sha256: `sha256:${LEDGER_SHA}`,
    },
    null,
    "https://h"
  );
  assert.equal(retiredDemo.mission_retired, true);
  assert.equal(retiredDemo.mission_demo, true);
  assert.equal(retiredDemo.mission_title, null);
  assert.equal(retiredDemo.upstream, null);
  assert.equal(retiredDemo.spec_is_current, false);
  assert.equal(retiredDemo.github, null, "retired demo proofs must not unlock public social links on their own");
  assert.deepEqual(retiredDemo.social_links, []);

  const retiredDemoWithResearchProof = buildLedgerEntry(
    {
      ...proofRow({ mission_id: "onboarding-sandbox", task_id: "decoder_injective", is_demo: 1 }),
      patch_sha256: `sha256:${LEDGER_SHA}`,
    },
    null,
    "https://h",
    1
  );
  assert.equal(retiredDemoWithResearchProof.mission_retired, true);
  assert.equal(retiredDemoWithResearchProof.mission_demo, true);
  assert.equal(retiredDemoWithResearchProof.github, "codex-dirichlet");

  const demo = buildLedgerEntry(
    { ...proofRow({ spec_sha256: "sha256:old" }), patch_sha256: `sha256:${LEDGER_SHA}` },
    ledgerMission({ demo: true, upstream: undefined }),
    "https://h"
  );
  assert.equal(demo.mission_demo, true);
  assert.equal(demo.spec_is_current, false);
  assert.equal(demo.upstream, null);
});

test("ledger permalink view includes the patch and how to reproduce it", () => {
  const p = buildLedgerProof({ ...proofRow(), patch_sha256: `sha256:${LEDGER_SHA}` }, ledgerMission(), "https://sunstead.org");
  assert.match(p.patch, /\+  exact foo/);
  assert.equal(p.submission_id, "sub-1");
  assert.equal(p.task_proof_url, "https://sunstead.org/api/missions/pnt-analytic-foundations/tasks/liouville/proof");
  assert.equal(p.history_mbox, "https://sunstead.org/api/missions/pnt-analytic-foundations/history.mbox");
  assert.match(p.how_to_rebuild, /\| git am$/);
});

test("ledger entries carry an upstream verify command only where one upstream sorry exists", () => {
  const row = { ...proofRow(), patch_sha256: `sha256:${LEDGER_SHA}` };
  const e = buildLedgerEntry(row, ledgerMission(), "https://sunstead.org");
  assert.equal(e.verify_command, `curl -fsSLO 'https://sunstead.org/verify.py' && python3 verify.py ${LEDGER_SHA}`);
  const dev = buildLedgerProof(row, ledgerMission(), "http://localhost:8787");
  assert.equal(
    dev.verify_command,
    `curl -fsSLO 'http://localhost:8787/verify.py' && python3 verify.py ${LEDGER_SHA} --hub 'http://localhost:8787'`
  );
  assert.equal(buildLedgerEntry(row, ledgerMission({ demo: true }), "https://sunstead.org").verify_command, null);
  assert.equal(buildLedgerEntry(row, null, "https://sunstead.org").verify_command, null, "retired mission");
  assert.equal(buildLedgerEntry({ ...row, entry_kind: "subgoal" }, ledgerMission(), "https://sunstead.org").verify_command, null);
  assert.equal(buildLedgerEntry({ ...row, entry_kind: "refutation" }, ledgerMission(), "https://sunstead.org").verify_command, null);
  const noUrl = ledgerMission({
    tasks: [{ id: "liouville", title: "Liouville lemma", target_files: ["PNT/Liouville.lean"] }],
  });
  assert.equal(buildLedgerEntry(row, noUrl, "https://sunstead.org").verify_command, null, "hill-climb style task");
  assert.equal(buildLedgerEntry({ ...row, patch_sha256: "sha256:<script>" }, ledgerMission(), "https://sunstead.org").verify_command, null);
});

test("parseLedgerQuery clamps limit and ignores bad cursors", () => {
  const q = (s: string) => parseLedgerQuery(new URLSearchParams(s));
  assert.deepEqual(q(""), { limit: LEDGER_DEFAULT_LIMIT, before: null, missionId: null });
  assert.equal(q("limit=10").limit, 10);
  assert.equal(q("limit=100000").limit, LEDGER_MAX_LIMIT);
  for (const bad of ["limit=0", "limit=-3", "limit=abc", "limit=2.5"]) assert.equal(q(bad).limit, LEDGER_DEFAULT_LIMIT, bad);
  assert.equal(q("before=42").before, 42);
  for (const bad of ["before=0", "before=-1", "before=x", "before=1.5", "before="]) assert.equal(q(bad).before, null, bad);
  assert.equal(q("mission_id=onboarding-sandbox").missionId, "onboarding-sandbox");
});

test("ledger page paths and proof ids accept only lowercase 64-hex hashes", () => {
  for (const ok of ["/proofs", "/proofs/", `/proofs/${LEDGER_SHA}`, `/proofs/${LEDGER_SHA}/`]) assert.ok(isLedgerPagePath(ok), ok);
  for (const bad of ["/proofsx", "/proofs/abc", `/proofs/${LEDGER_SHA.toUpperCase()}`, `/proofs/${LEDGER_SHA}/x`, "/proofs.html/"]) {
    assert.ok(!isLedgerPagePath(bad), bad);
  }
  assert.ok(PROOF_HASH_RE.test(LEDGER_SHA));
  assert.ok(!PROOF_HASH_RE.test(LEDGER_SHA + "0"));
  assert.ok(!PROOF_HASH_RE.test("<script>"));
  assert.equal(proofIdFromPatchSha(`sha256:${LEDGER_SHA}`), LEDGER_SHA);
});

test("sanitizeFailureDiagnostics accepts known stages and caps diagnostic length", () => {
  assert.deepEqual(sanitizeFailureDiagnostics("compile", "  file.lean:3:2: error  "), {
    stage: "compile",
    diagnostics: "file.lean:3:2: error",
  });
  assert.deepEqual(sanitizeFailureDiagnostics("bogus_stage", "   "), {});
  const huge = "x".repeat(MAX_DIAGNOSTICS_CHARS + 500);
  const clipped = sanitizeFailureDiagnostics("kernel", huge);
  assert.equal(clipped.stage, "kernel");
  assert.equal(clipped.diagnostics?.length, MAX_DIAGNOSTICS_CHARS);
});

test("buildTaskFilesView overlays mutable target files while keeping frozen files strictly from seed", () => {
  const m = mission("dag", 1, {
    id: "pnt-analytic-foundations",
    frozen_paths: ["PntFoundations/Spec.lean", "lakefile.toml", "verify"],
  });
  const t = task("liouville", {
    def: {
      id: "liouville",
      title: "Prove Liouville",
      target_files: ["PntFoundations/Liouville.lean"],
      depends_on: [],
      upstream_url: "https://github.com/example/repo/blob/abc/File.lean#L10",
    },
  });
  const view = buildTaskFilesView({
    mission: m,
    specSha256: SPEC,
    task: t,
    unlocked: true,
    seedFiles: {
      "PntFoundations/Spec.lean": "def spec := 1\n",
      "PntFoundations/Liouville.lean": "theorem t : True := by sorry\n",
      "PntFoundations/Other.lean": "theorem other : True := by sorry\n",
      "lakefile.toml": "name = \"Pnt\"\n",
    },
    liveOverlay: {
      "PntFoundations/Liouville.lean": "theorem t : True := trivial\n",
      // Even if a rogue key existed in overlay, frozen files must never come from overlay.
      "PntFoundations/Spec.lean": "def spec := 999\n",
    },
  });
  assert.equal(view.mission_id, "pnt-analytic-foundations");
  assert.equal(view.task_id, "liouville");
  assert.equal(view.unlocked, true);
  assert.equal(view.spec_sha256, SPEC);
  assert.deepEqual(view.target_files, {
    "PntFoundations/Liouville.lean": "theorem t : True := trivial\n",
  });
  assert.deepEqual(view.frozen_files, {
    "PntFoundations/Spec.lean": "def spec := 1\n",
    "lakefile.toml": "name = \"Pnt\"\n",
  });
});

// ---------------------------------------------------------------- multi-toolchain routing

test("resolveVerifierKind routes by pinned toolchain or image and fails closed on unknown ones", () => {
  assert.equal(resolveVerifierKind({ image: "sunstead/verifier-lean4:v0.2" }), "lean4");
  assert.equal(
    resolveVerifierKind({
      image: "sunstead/verifier-lean4:v0.2",
      toolchain: "leanprover/lean4:v4.36.0",
    }),
    "lean4"
  );
  assert.equal(
    resolveVerifierKind({
      image: "sunstead/verifier-lean4-v4.35.0:v0.1",
      toolchain: "leanprover/lean4:v4.35.0",
    }),
    "lean4-v4.35.0"
  );
  assert.equal(resolveVerifierKind({ image: "sunstead/verifier-lean4-v4.35.0:v0.1" }), "lean4-v4.35.0");
  assert.equal(
    resolveVerifierKind({
      image: "sunstead/verifier-lean4-v4.31.0:v0.1",
      toolchain: "leanprover/lean4:v4.31.0",
    }),
    "lean4-v4.31.0"
  );
  assert.equal(resolveVerifierKind({ image: "sunstead/verifier-lean4-v4.31.0:v0.1" }), "lean4-v4.31.0");
  assert.throws(
    () =>
      resolveVerifierKind({
        image: "sunstead/verifier-lean4-v4.28.0:v0.1",
        toolchain: "leanprover/lean4:v4.28.0",
      }),
    /unsupported verifier toolchain/
  );
  assert.throws(
    () => resolveVerifierKind({ image: "sunstead/verifier-rust:v0.1" }),
    /unsupported verifier image/
  );
  assert.equal(SUPPORTED_VERIFIER_TOOLCHAINS["lean4"].toolchain, "leanprover/lean4:v4.36.0");
  assert.equal(SUPPORTED_VERIFIER_TOOLCHAINS["lean4-v4.35.0"].toolchain, "leanprover/lean4:v4.35.0");
  assert.equal(SUPPORTED_VERIFIER_TOOLCHAINS["lean4-v4.31.0"].toolchain, "leanprover/lean4:v4.31.0");
});

// ---------------------------------------------------------------- contributor social links

test("social handle validators normalize strict handles, clear empty/null, and reject raw URLs or XSS", () => {
  assert.equal(normalizeGithubHandle("@octocat-42"), "octocat-42");
  assert.equal(normalizeGithubHandle("a"), "a");
  assert.equal(normalizeGithubHandle(null), null);
  assert.equal(normalizeGithubHandle("   "), null);

  assert.equal(normalizeXHandle("@Alice_99"), "Alice_99");
  assert.equal(normalizeXHandle("x"), "x");
  assert.equal(normalizeXHandle(""), null);

  assert.equal(normalizeLinkedinHandle("in/ada-lovelace"), "ada-lovelace");
  assert.equal(normalizeLinkedinHandle("/in/ada-lovelace-1"), "ada-lovelace-1");
  assert.equal(normalizeLinkedinHandle("ada-lovelace"), "ada-lovelace");
  assert.equal(normalizeLinkedinHandle(null), null);

  for (const bad of [
    "https://github.com/octocat",
    "http://evil.example/x",
    "javascript:alert(1)",
    "data:text/html,<script>",
    "-leading",
    "trailing-",
    "octocat?tab=stars",
    "octocat/repo",
    "<script>alert(1)</script>",
    "a".repeat(40),
    123 as unknown,
    {} as unknown,
  ]) {
    assert.throws(() => normalizeGithubHandle(bad), /github/, String(bad));
  }

  for (const bad of [
    "https://x.com/alice",
    "javascript:alert(1)",
    "alice-dash",
    "a".repeat(16),
    "alice?foo=bar",
    "alice/status/1",
    42 as unknown,
  ]) {
    assert.throws(() => normalizeXHandle(bad), /x/, String(bad));
  }

  for (const bad of [
    "https://www.linkedin.com/in/ada-lovelace",
    "linkedin.com/in/ada",
    "javascript:alert(1)",
    "ab",
    "ada_underscore",
    "in/ada?trk=spam",
    "a".repeat(101),
    true as unknown,
  ]) {
    assert.throws(() => normalizeLinkedinHandle(bad), /linkedin/, String(bad));
  }
});

test("parseProfilePatch supports partial updates, explicit clearing, and rejects invalid fields", () => {
  assert.deepEqual(parseProfilePatch({}), { hasUpdates: false });
  assert.deepEqual(
    parseProfilePatch({
      display_name: "  Ada\nLovelace  ",
      github: "@ada-gh",
      x: "@ada_x",
      linkedin: "/in/ada-lovelace",
    }),
    {
      hasUpdates: true,
      display_name: "Ada Lovelace",
      github: "ada-gh",
      x: "ada_x",
      linkedin: "ada-lovelace",
    }
  );
  assert.deepEqual(
    parseProfilePatch({ github: null, x: "", linkedin: "   ", display_name: "" }),
    { hasUpdates: true, display_name: null, github: null, x: null, linkedin: null }
  );
  assert.throws(() => parseProfilePatch({ github: "https://github.com/ada" }), /handle only/);
  assert.throws(() => parseProfilePatch({ display_name: 99 }), /display_name/);
});

test("proof-gated public social links hide 0-proof and demo-only contributors and emit canonical URLs for >= 1 non-demo proof", () => {
  const handles = { github: "codex-dirichlet", x: "dirichlet_x", linkedin: "codex-dirichlet" };
  assert.deepEqual(gatePublicSocialHandles(handles, 0), { github: null, x: null, linkedin: null });
  assert.deepEqual(buildPublicSocialLinks(handles, 0), []);

  assert.deepEqual(gatePublicSocialHandles(handles, 1), handles);
  assert.deepEqual(buildPublicSocialLinks(handles, 1), [
    { platform: "github", handle: "codex-dirichlet", url: "https://github.com/codex-dirichlet" },
    { platform: "x", handle: "dirichlet_x", url: "https://x.com/dirichlet_x" },
    { platform: "linkedin", handle: "codex-dirichlet", url: "https://www.linkedin.com/in/codex-dirichlet" },
  ]);

  // Defense-in-depth: malformed legacy handles are dropped even if nonDemoVerifiedCount >= 1.
  assert.deepEqual(
    gatePublicSocialHandles(
      { github: "javascript:alert(1)", x: "ok_user", linkedin: "../etc/passwd" },
      5
    ),
    { github: null, x: "ok_user", linkedin: null }
  );

  // Ledger & task proof views apply the non-demo proof gate.
  const rowWithLinks = {
    ...proofRow({ github: "ada", x: "ada_x", linkedin: "ada-lovelace" }),
    patch_sha256: `sha256:${LEDGER_SHA}`,
  };
  const demoEntry = buildLedgerEntry(rowWithLinks, ledgerMission({ demo: true }), "https://sunstead.org", 0);
  assert.equal(demoEntry.github, null);
  assert.equal(demoEntry.x, null);
  assert.equal(demoEntry.linkedin, null);
  assert.deepEqual(demoEntry.social_links, []);

  const realEntry = buildLedgerEntry(rowWithLinks, ledgerMission(), "https://sunstead.org", 1);
  assert.equal(realEntry.github, "ada");
  assert.equal(realEntry.x, "ada_x");
  assert.equal(realEntry.linkedin, "ada-lovelace");
  assert.equal(realEntry.social_links.length, 3);

  const gatedProof = buildProofView(rowWithLinks, {
    hubOrigin: "https://sunstead.org",
    currentSpecSha256: "sha256:aaa",
    patchSha256: `sha256:${LEDGER_SHA}`,
    nonDemoVerifiedCount: 0,
  });
  assert.equal(gatedProof.github, null);
  assert.equal(gatedProof.x, null);
  assert.equal(gatedProof.linkedin, null);
  assert.deepEqual(gatedProof.social_links, []);
});

test("web/app.js renders social links strictly from validated handles with safe rel attributes and no XSS", async () => {
  const fs = await import("node:fs");
  const path = await import("node:path");
  const vm = await import("node:vm");
  const appSrc = fs.readFileSync(
    path.resolve(path.dirname(new URL(import.meta.url).pathname), "../../web/app.js"),
    "utf8"
  );
  // Extract escapeHtml + handle regexes + SOCIAL_ICONS + renderSocialLinksHtml into an isolated VM context.
  const sandbox: Record<string, unknown> = {};
  const escapeMatch = appSrc.match(/function escapeHtml\(s\)[\s\S]*?\n\}/);
  const socialMatch = appSrc.match(
    /const GITHUB_HANDLE_RE =[\s\S]*?function renderSocialLinksHtml\(entry\)[\s\S]*?\n\}/
  );
  assert.ok(escapeMatch && socialMatch, "expected social rendering helpers in web/app.js");
  vm.runInNewContext(`${escapeMatch[0]}\n${socialMatch[0]}\nthis.renderSocialLinksHtml = renderSocialLinksHtml;`, sandbox);
  const render = sandbox.renderSocialLinksHtml as (e: Record<string, unknown>) => string;

  const clean = render({ github: "octocat", x: "octo_x", linkedin: "octo-cat" });
  assert.match(clean, /href="https:\/\/github\.com\/octocat"/);
  assert.match(clean, /href="https:\/\/x\.com\/octo_x"/);
  assert.match(clean, /href="https:\/\/www\.linkedin\.com\/in\/octo-cat"/);
  assert.equal((clean.match(/rel="noopener noreferrer nofollow ugc"/g) || []).length, 3);
  assert.equal((clean.match(/target="_blank"/g) || []).length, 3);

  // Adversarial handles / raw URLs / XSS payloads must render nothing.
  assert.equal(
    render({
      github: 'javascript:alert(1)" onclick="x',
      x: "<script>alert(1)</script>",
      linkedin: "https://evil.example/in/x",
    }),
    ""
  );
});

// ---------------------------------------------------------------- GHCR images, /join.txt & repo-snapshot bootstrap

test("publicVerifierImage maps local verifier tags to ghcr.io/sunstead-institute", () => {
  assert.equal(
    publicVerifierImage("sunstead/verifier-lean4:v0.2"),
    "ghcr.io/sunstead-institute/verifier-lean4:v0.2"
  );
  assert.equal(
    publicVerifierImage("sunstead/verifier-lean4-v4.35.0:v0.1"),
    "ghcr.io/sunstead-institute/verifier-lean4-v4.35.0:v0.1"
  );
  assert.equal(
    publicVerifierImage("sunstead/verifier-lean4-v4.31.0:v0.1"),
    "ghcr.io/sunstead-institute/verifier-lean4-v4.31.0:v0.1"
  );
  assert.equal(
    publicVerifierImage("ghcr.io/sunstead-institute/verifier-lean4:v0.2"),
    "ghcr.io/sunstead-institute/verifier-lean4:v0.2"
  );
});

test("buildMissionLocalSetup & renderRepoSnapshotBootstrapScript produce accurate per-mission setup commands", () => {
  const loadManifest = (id: string) =>
    JSON.parse(
      readFileSync(new URL(`../../missions/${id}/sunstead.json`, import.meta.url), "utf8")
    ) as MissionManifest;

  const gcm = loadManifest("lnsym-gcm-gmult-armv8");
  const gcmSetup = buildMissionLocalSetup(gcm, "https://sunstead.org");
  assert.equal(gcmSetup.mode, "repo-snapshot");
  assert.equal(gcmSetup.toolchain, "leanprover/lean4:v4.35.0");
  assert.equal(gcmSetup.verifier_image, "ghcr.io/sunstead-institute/verifier-lean4-v4.35.0:v0.1");
  assert.equal(gcmSetup.uses_mathlib, false);
  assert.equal(gcmSetup.bootstrap_script_url, "https://sunstead.org/api/missions/lnsym-gcm-gmult-armv8/bootstrap.sh");
  assert.match(gcmSetup.bootstrap_cmd ?? "", /lnsym-gcm-gmult-armv8\/bootstrap\.sh' \| bash$/);
  assert.match(gcmSetup.docker_verify_cmd, /ghcr\.io\/sunstead-institute\/verifier-lean4-v4\.35\.0:v0\.1/);

  const script = renderRepoSnapshotBootstrapScript(gcm, "https://sunstead.org");
  assert.match(script, /49f8a1d9e46f8dcfc345f4bc15d35b0ba845ff5c/);
  assert.match(script, /ghcr\.io\/sunstead-institute\/verifier-lean4-v4\.35\.0:v0\.1/);
  assert.match(script, /\.\.\/lnsym-gcm-gmult-armv8-upstream/);
  assert.match(script, /Proofs\/AES-GCM\/GCMGmultV8Sym\.lean/);
  // Generated script must be syntactically valid bash.
  const syntax = spawnSync("bash", ["-n"], { input: script, encoding: "utf8" });
  assert.equal(syntax.status, 0, syntax.stderr);

  const ieantn = loadManifest("ieantn-chebyshev-kernel");
  const ieantnSetup = buildMissionLocalSetup(ieantn, "https://sunstead.org");
  assert.equal(ieantnSetup.mode, "standalone");
  assert.equal(ieantnSetup.toolchain, "leanprover/lean4:v4.36.0");
  assert.equal(ieantnSetup.verifier_image, "ghcr.io/sunstead-institute/verifier-lean4:v0.2");
  assert.equal(ieantnSetup.bootstrap_cmd, null);
  assert.ok(ieantnSetup.native_setup_steps.includes("lake exe cache get"));
  assert.throws(() => renderRepoSnapshotBootstrapScript(ieantn, "https://sunstead.org"), /not a repo-snapshot/);

  const rank = loadManifest("matrix-rank444-f2");
  const rankSetup = buildMissionLocalSetup(rank, "https://sunstead.org");
  assert.equal(rankSetup.mode, "hillclimb");
  assert.equal(rankSetup.toolchain, "leanprover/lean4:v4.36.0");
  assert.equal(rankSetup.verifier_image, "ghcr.io/sunstead-institute/verifier-lean4:v0.2");
  assert.ok(rankSetup.notes.some((n) => n.includes("minimize") && n.includes("47")));
});

test("renderJoinTxt uses ghcr.io/sunstead-institute, accurate per-mission toolchains, gist auth, hill-climb and repo-snapshot bootstrap", () => {
  const loadManifest = (id: string) =>
    JSON.parse(
      readFileSync(new URL(`../../missions/${id}/sunstead.json`, import.meta.url), "utf8")
    ) as MissionManifest;

  const gcm = loadManifest("lnsym-gcm-gmult-armv8");
  const ieantn = loadManifest("ieantn-chebyshev-kernel");
  const rank = loadManifest("matrix-rank444-f2");

  const txt = renderJoinTxt("https://sunstead.org", [
    {
      manifest: gcm,
      tasks: gcm.tasks.map((def) => ({
        def,
        status: "open",
        best_score: null,
        verified_by: null,
        active_lease: null,
        attempts: 0,
      })),
    },
    {
      manifest: ieantn,
      tasks: ieantn.tasks.map((def) => ({
        def,
        status: "open",
        best_score: null,
        verified_by: null,
        active_lease: null,
        attempts: 0,
      })),
    },
    {
      manifest: rank,
      tasks: rank.tasks.map((def) => ({
        def,
        status: "open",
        best_score: 47,
        verified_by: null,
        active_lease: null,
        attempts: 0,
      })),
    },
  ]);

  assert.ok(!txt.includes("sunstead-org"), "must never reference wrong GHCR org sunstead-org");
  assert.match(txt, /ghcr\.io\/sunstead-institute\/verifier-lean4:v0\.2/);
  assert.match(txt, /ghcr\.io\/sunstead-institute\/verifier-lean4-v4\.35\.0:v0\.1/);
  assert.match(txt, /leanprover\/lean4:v4\.36\.0/);
  assert.match(txt, /leanprover\/lean4:v4\.35\.0/);
  assert.match(txt, /\/api\/me\/verify\/github\/start/);
  assert.match(txt, /\/api\/me\/verify\/github\/confirm/);
  assert.match(txt, /lnsym-gcm-gmult-armv8\/bootstrap\.sh/);
  assert.match(txt, /reduce_rank \(best: 47, minimize\)/);
  assert.match(txt, /Rank444\/Certificate\.lean/);
  assert.match(txt, /submit\?async=1/);
  assert.match(txt, /floor\(5000 x \|ln\(new\/old\)\|\)/);
});

// ---------------------------------------------------------------- async submit, pooling, sorting & UI

test("VerifierSlotPool fans out concurrent verifications on one mission and prefers warm affinity slots", async () => {
  assert.equal(VERIFIER_POOL_SIZE.lean4, 6);
  assert.equal(VERIFIER_POOL_SIZE["lean4-v4.35.0"], 4);
  assert.equal(VERIFIER_POOL_SIZE["lean4-v4.31.0"], 4);
  assert.equal(verifierSlotName("lean4", "sunstead/verifier-lean4:v0.2", 2), "lean4:sunstead/verifier-lean4:v0.2:slot-2");

  const pool = new VerifierSlotPool({ lean4: 2, "lean4-v4.35.0": 2, "lean4-v4.31.0": 2 });
  const s0 = await pool.acquire("lean4", "img:v1", "mission-a");
  const s1 = await pool.acquire("lean4", "img:v1", "mission-a");
  assert.notEqual(s0, s1, "concurrent submissions on the same mission use distinct slots");

  // Third concurrent caller waits until one of the 2 slots is released.
  let thirdResolved = false;
  const thirdPromise = pool.acquire("lean4", "img:v1", "mission-b").then((slot) => {
    thirdResolved = true;
    return slot;
  });
  await Promise.resolve();
  assert.equal(thirdResolved, false);

  pool.release("lean4", "img:v1", s1);
  const s2 = await thirdPromise;
  assert.equal(s2, s1);

  pool.release("lean4", "img:v1", s0);
  pool.release("lean4", "img:v1", s2);

  // Idle affinity: mission-b should re-acquire slot s2 (warm for mission-b), mission-a gets s0.
  const warmB = await pool.acquire("lean4", "img:v1", "mission-b");
  assert.equal(warmB, s2);
  const warmA = await pool.acquire("lean4", "img:v1", "mission-a");
  assert.equal(warmA, s0);
  pool.release("lean4", "img:v1", warmB);
  pool.release("lean4", "img:v1", warmA);
});

test("shouldRunAsyncSubmit respects query flag, JSON body, and Prefer header", () => {
  const u = (s: string) => new URL(`https://sunstead.org/api/missions/m/tasks/t/submit${s}`);
  assert.equal(shouldRunAsyncSubmit(u(""), {}, new Headers()), false);
  assert.equal(shouldRunAsyncSubmit(u("?async=1"), {}, new Headers()), true);
  assert.equal(shouldRunAsyncSubmit(u("?async=true"), {}, new Headers()), true);
  assert.equal(shouldRunAsyncSubmit(u("?async=0"), { async: true }, new Headers({ Prefer: "respond-async" })), false);
  assert.equal(shouldRunAsyncSubmit(u(""), { async: true }, new Headers()), true);
  assert.equal(shouldRunAsyncSubmit(u(""), {}, new Headers({ Prefer: "respond-async" })), true);
});

test("formatSubmissionStatusView reports verifying, accepted (with normalized proof_id/permalink), and rejected states", () => {
  const baseRow: SubmissionStatusRow = {
    id: "sub-123",
    mission_id: "pnt-analytic-foundations",
    task_id: "liouville",
    contributor: "alice",
    status: "verifying",
    accepted: 0,
    score: null,
    points: 0,
    summary: "Verifying…",
    patch_sha256: `sha256:${LEDGER_SHA}`,
    proof_id: null,
    verify_ms: 0,
    stage: null,
    diagnostics: null,
    error: null,
    unlocked_dependents_json: null,
    created_at: 1000,
    completed_at: null,
  };
  const pending = formatSubmissionStatusView(baseRow, "https://sunstead.org");
  assert.equal(pending.status, "verifying");
  assert.equal(pending.accepted, null);
  assert.equal(pending.proof_id, null);
  assert.equal(pending.permalink, null);

  const accepted = formatSubmissionStatusView(
    {
      ...baseRow,
      status: "accepted",
      accepted: 1,
      points: 150,
      proof_id: LEDGER_SHA,
      unlocked_dependents_json: JSON.stringify(["next_lemma"]),
      verify_ms: 4200,
      completed_at: 1005,
    },
    "https://sunstead.org"
  );
  assert.equal(accepted.status, "accepted");
  assert.equal(accepted.accepted, true);
  assert.equal(accepted.patch_sha256, `sha256:${LEDGER_SHA}`);
  assert.equal(accepted.proof_id, LEDGER_SHA);
  assert.equal(accepted.permalink, `https://sunstead.org/proofs/${LEDGER_SHA}`);
  assert.deepEqual(accepted.unlocked_dependents, ["next_lemma"]);

  const rejected = formatSubmissionStatusView(
    {
      ...baseRow,
      status: "rejected",
      accepted: 0,
      stage: "axioms",
      diagnostics: "sorryAx detected",
      error: "non-standard axioms",
      completed_at: 1004,
    },
    "https://sunstead.org"
  );
  assert.equal(rejected.status, "rejected");
  assert.equal(rejected.accepted, false);
  assert.equal(rejected.stage, "axioms");
  assert.equal(rejected.diagnostics, "sorryAx detected");
  assert.equal(rejected.error, "non-standard axioms");
});

test("sortMissionSummaries places active Tier 1 DAGs first, then Tier 2 hill-climb, then Completed Showcase, then demo", () => {
  const sorted = sortMissionSummaries([
    { id: "matrix-rank444-f2", tier: 2, mode: "hillclimb", demo: false, total_tasks: 1, verified_tasks: 1 },
    { id: "pnt-analytic-foundations", tier: 1, mode: "dag", demo: false, total_tasks: 6, verified_tasks: 6 },
    { id: "onboarding-sandbox", tier: 0, mode: "dag", demo: true, total_tasks: 4, verified_tasks: 2 },
    { id: "arklib-near-capacity-primes", tier: 1, mode: "dag", demo: false, total_tasks: 1, verified_tasks: 0 },
    { id: "lnsym-aes-gcm-armv8", tier: 1, mode: "dag", demo: false, total_tasks: 1, verified_tasks: 1 },
    { id: "curve25519-dalek", tier: 1, mode: "dag", demo: false, total_tasks: 2, verified_tasks: 0 },
  ]);
  assert.deepEqual(
    sorted.map((m) => m.id),
    [
      "arklib-near-capacity-primes",
      "curve25519-dalek",
      "matrix-rank444-f2",
      "lnsym-aes-gcm-armv8",
      "pnt-analytic-foundations",
      "onboarding-sandbox",
    ]
  );
  assert.equal(isMissionCompleted(sorted[2]), false, "hillclimb missions stay open even when tasks are verified");
  assert.equal(isMissionCompleted(sorted[3]), true);
  assert.equal(isMissionCompleted(sorted[0]), false);
});

test("constantTimeEqual compares bearer tokens exactly", () => {
  assert.equal(constantTimeEqual("secret-token", "secret-token"), true);
  assert.equal(constantTimeEqual("secret-token", "secret-tokeN"), false);
  assert.equal(constantTimeEqual("short", "longer"), false);
});

test("web/app.js hill-climb nodePalette preserves CLAIMED/OPEN status and SSE invalidates proofCache", async () => {
  const vm = await import("node:vm");
  const appJs = readFileSync(new URL("../../web/app.js", import.meta.url), "utf8");
  const paletteMatch = appJs.match(/function nodePalette\(task, mode\) \{[\s\S]*?\n\}/);
  assert.ok(paletteMatch, "nodePalette(task, mode) must exist in web/app.js");
  assert.match(appJs, /state\.proofCache\.delete\(`\$\{ev\.mission_id\}\/\$\{ev\.task_id\}`\)/);
  assert.match(appJs, /state\.proofCache\.clear\(\)/);
  assert.match(appJs, /completed-missions-section/);

  const ctx: Record<string, unknown> = {};
  vm.runInNewContext(`${paletteMatch[0]}\nthis.nodePalette = nodePalette;`, ctx);
  const nodePalette = ctx.nodePalette as (t: Record<string, unknown>, mode: string) => { badge: string };

  assert.equal(
    nodePalette({ unlocked: true, status: "verified", active_lease: { contributor: "alice" } }, "hillclimb").badge,
    "CLAIMED"
  );
  assert.equal(
    nodePalette({ unlocked: true, status: "verified", active_lease: null }, "hillclimb").badge,
    "RECORD · OPEN"
  );
  assert.equal(
    nodePalette({ unlocked: true, status: "verified", active_lease: null }, "dag").badge,
    "VERIFIED"
  );
  assert.equal(
    nodePalette(
      {
        unlocked: true,
        status: "open",
        active_lease: null,
        disputed_counterexample: { refuter: "bob", proof_id: "a".repeat(64) },
      },
      "dag"
    ).badge,
    "DISPUTED ¬T"
  );
  assert.match(appJs, /decomp-cluster/);
  assert.match(appJs, /decomp-edge/);
  assert.match(appJs, /ledger-badge-refute/);
  assert.match(appJs, /task_decomposed/);
  assert.match(appJs, /decomposition_refuted/);
});

// ---------------------------------------------------------------- v2 decompose & refute core rules

test("v2 zero-inflation point splitting and refutation bounties", () => {
  const s2 = computeDecompPointSplit(150, 2);
  assert.equal(s2.architect_points, 30);
  assert.equal(s2.solver_points_per_subgoal, 60);
  assert.equal(s2.max_total_points, 150);
  assert.ok(s2.max_total_points <= 150);

  const s3 = computeDecompPointSplit(250, 3);
  assert.equal(s3.architect_points, 50);
  assert.equal(s3.solver_points_per_subgoal, 66);
  assert.equal(s3.max_total_points, 248);
  assert.ok(s3.max_total_points <= 250, "total must never exceed parent points");

  // Depth-2 split of a 60-pt subgoal also preserves zero-inflation.
  const nested = computeDecompPointSplit(s2.solver_points_per_subgoal, 2);
  assert.equal(nested.architect_points, 12);
  assert.equal(nested.solver_points_per_subgoal, 24);
  assert.equal(nested.max_total_points, 60);

  // Demo missions always yield 0 points / 0 bounty.
  assert.equal(computeDecompPointSplit(0, 2).max_total_points, 0);
  assert.equal(computeRefutationBounty({ tier: 1, demo: false }), 75);
  assert.equal(computeRefutationBounty({ tier: 2, demo: false }), 50);
  assert.equal(computeRefutationBounty({ tier: 1, demo: true }), 0);
});

test("v2 checkDecompositionEligibility enforces allowlist, pilot flag, depth <= 2, and active caps", () => {
  const pilot = mission("dag", 1, {
    decomposition: { enabled: true, require_allowlist: true, allow_direct_bypass: true, max_depth: 2 },
  });
  const t = task("root_t");

  assert.throws(
    () =>
      checkDecompositionEligibility({
        manifest: mission("dag", 1),
        task: t,
        allTasks: [t],
        contributor: "alice",
        isAllowlisted: true,
        activeDecompsOnTarget: 0,
        activeDecompsByContributor: 0,
      }),
    /not enabled/
  );
  assert.throws(
    () =>
      checkDecompositionEligibility({
        manifest: pilot,
        task: t,
        allTasks: [t],
        contributor: "bob",
        isAllowlisted: false,
        activeDecompsOnTarget: 0,
        activeDecompsByContributor: 0,
      }),
    /allowlist/
  );
  assert.throws(
    () =>
      checkDecompositionEligibility({
        manifest: pilot,
        task: t,
        allTasks: [t],
        contributor: "alice",
        isAllowlisted: true,
        activeDecompsOnTarget: 1,
        activeDecompsByContributor: 0,
      }),
    /already has an active decomposition/
  );
  assert.throws(
    () =>
      checkDecompositionEligibility({
        manifest: pilot,
        task: t,
        allTasks: [t],
        contributor: "alice",
        isAllowlisted: true,
        activeDecompsOnTarget: 0,
        activeDecompsByContributor: 3,
      }),
    /cap reached/
  );
  const depth2Task = task("root_t__d1__sub1__d2__sub2", {
    def: { id: "root_t__d1__sub1__d2__sub2", title: "d2", target_files: ["M/S.lean"], decomp_depth: 2 },
  });
  assert.throws(
    () =>
      checkDecompositionEligibility({
        manifest: pilot,
        task: depth2Task,
        allTasks: [depth2Task],
        contributor: "alice",
        isAllowlisted: true,
        activeDecompsOnTarget: 0,
        activeDecompsByContributor: 0,
      }),
    /depth limit/
  );

  const ok1 = checkDecompositionEligibility({
    manifest: pilot,
    task: t,
    allTasks: [t],
    contributor: "alice",
    isAllowlisted: true,
    activeDecompsOnTarget: 0,
    activeDecompsByContributor: 2,
  });
  assert.equal(ok1.depth, 1);
});

test("v2 parseDecomposeRequest and parseRefuteRequest enforce subgoal bounds, statement size, and path scoping", () => {
  const redFile = "ArkLibNearCapacity/Decomp_near_capacity_prime_supply_d1.lean";
  const goodPatch = generateUnifiedDiff(redFile, null, "import ArkLibNearCapacity.Spec\n");

  // 1 subgoal rejected (< 2)
  assert.throws(
    () =>
      parseDecomposeRequest(
        {
          subgoals: [{ id: "only_one", title: "One", statement: "True" }],
          reduction_file: redFile,
          reduction_theorem: "ArkLibNearCapacity.red",
          patch: goodPatch,
        },
        { libRoot: "ArkLibNearCapacity", frozenPaths: ["ArkLibNearCapacity/Spec.lean"], defaultDecompId: "d1" }
      ),
    /between 2 and 6/
  );

  // Oversized statement (> 4 KB) rejected
  assert.throws(
    () =>
      parseDecomposeRequest(
        {
          subgoals: [
            { id: "sub_a", title: "A", statement: "x".repeat(MAX_SUBGOAL_STATEMENT_BYTES + 1) },
            { id: "sub_b", title: "B", statement: "1 = 1" },
          ],
          reduction_file: redFile,
          reduction_theorem: "ArkLibNearCapacity.red",
          patch: goodPatch,
        },
        { libRoot: "ArkLibNearCapacity", frozenPaths: ["ArkLibNearCapacity/Spec.lean"], defaultDecompId: "d1" }
      ),
    /4096 bytes/
  );

  // Reserved DecompStatements_* module path rejected
  assert.throws(
    () =>
      parseDecomposeRequest(
        {
          subgoals: [
            { id: "sub_a", title: "A", statement: "1 = 1" },
            { id: "sub_b", title: "B", statement: "2 = 2" },
          ],
          reduction_file: "ArkLibNearCapacity/DecompStatements_t_d1.lean",
          reduction_theorem: "ArkLibNearCapacity.red",
          patch: generateUnifiedDiff("ArkLibNearCapacity/DecompStatements_t_d1.lean", null, "-- hi\n"),
        },
        { libRoot: "ArkLibNearCapacity", frozenPaths: ["ArkLibNearCapacity/Spec.lean"], defaultDecompId: "d1" }
      ),
    /reserved/
  );

  const parsed = parseDecomposeRequest(
    {
      subgoals: [
        { id: "sub_a", title: "Subgoal A", statement: "def sub_a : Prop := ∀ n : Nat, n = n" },
        { id: "sub_b", title: "Subgoal B", statement: "def sub_b : Prop := ∀ m : Nat, m + 0 = m" },
      ],
      reduction_file: redFile,
      reduction_theorem: "ArkLibNearCapacity.reduce_main",
      patch: goodPatch,
    },
    { libRoot: "ArkLibNearCapacity", frozenPaths: ["ArkLibNearCapacity/Spec.lean"], defaultDecompId: "d1" }
  );
  assert.equal(parsed.decomp_id, "d1");
  assert.equal(parsed.reduction_module, "ArkLibNearCapacity.Decomp_near_capacity_prime_supply_d1");

  const refPatch = generateUnifiedDiff("ArkLibNearCapacity/RefuteSub.lean", null, "import ArkLibNearCapacity.Spec\n");
  const parsedRef = parseRefuteRequest(
    { refute_theorem: "ArkLibNearCapacity.refute_sub", patch: refPatch },
    { libRoot: "ArkLibNearCapacity", frozenPaths: ["ArkLibNearCapacity/Spec.lean"] }
  );
  assert.equal(parsedRef.refute_file, "ArkLibNearCapacity/RefuteSub.lean");
  assert.equal(parsedRef.refute_module, "ArkLibNearCapacity.RefuteSub");
});

test("v2 assembleDecomposedLeanFile strips DecompStatements imports and renderMbox emits Co-authored-by trailers", () => {
  const assembled = assembleDecomposedLeanFile({
    baseImports: ["ArkLibNearCapacity.Spec"],
    statementPreamble: "open scoped NNReal",
    targetTheorem: "ArkLibNearCapacity.near_capacity_prime_supply",
    targetTypeExpr: extractPropStatementExpr(
      "def near_capacity_prime_supply : Prop := ∀ (c : NNReal), 0 < c → ArkLibNearCapacity.NearCapacityPrimeSupply c"
    ),
    root: {
      kind: "decomp",
      decomp_id: "d1",
      decomp_statements_module: "ArkLibNearCapacity.DecompStatements_t_d1",
      decomp_statements_source:
        "import ArkLibNearCapacity.Spec\nnamespace SunsteadDecomp_t_d1\ndef l1 : Prop := True\ndef l2 : Prop := True\nend SunsteadDecomp_t_d1\n",
      reduction_theorem: "ArkLibNearCapacity.red",
      reduction_source:
        "import ArkLibNearCapacity.Spec\nimport ArkLibNearCapacity.DecompStatements_t_d1\nnamespace ArkLibNearCapacity\ntheorem red (h1 : SunsteadDecomp_t_d1.l1) (h2 : SunsteadDecomp_t_d1.l2) : True := trivial\nend ArkLibNearCapacity\n",
      children: [
        {
          kind: "leaf",
          label: "l1",
          theorem: "ArkLibNearCapacity.p1",
          source:
            "import ArkLibNearCapacity.Spec\nimport ArkLibNearCapacity.DecompStatements_t_d1\nnamespace ArkLibNearCapacity\ntheorem p1 : SunsteadDecomp_t_d1.l1 := trivial\nend ArkLibNearCapacity\n",
        },
        {
          kind: "leaf",
          label: "l2",
          theorem: "ArkLibNearCapacity.p2",
          source:
            "import ArkLibNearCapacity.Spec\nimport ArkLibNearCapacity.DecompStatements_t_d1\nnamespace ArkLibNearCapacity\ntheorem p2 : SunsteadDecomp_t_d1.l2 := trivial\nend ArkLibNearCapacity\n",
        },
      ],
    },
  });

  assert.ok(!assembled.includes("import ArkLibNearCapacity.DecompStatements_t_d1"));
  assert.match(assembled, /^import ArkLibNearCapacity\.Spec/m);
  assert.match(assembled, /namespace SunsteadDecomp_t_d1/);
  assert.match(assembled, /theorem near_capacity_prime_supply :/);
  assert.match(assembled, /SunsteadAssembled_3\.ArkLibNearCapacity\.red SunsteadAssembled_1\.ArkLibNearCapacity\.p1 SunsteadAssembled_2\.ArkLibNearCapacity\.p2/);

  const stub = buildSubgoalStubSource({
    libRoot: "ArkLibNearCapacity",
    decompStatementsModule: "ArkLibNearCapacity.DecompStatements_t_d1",
    decompStatementsNamespace: "SunsteadDecomp_t_d1",
    subgoalId: "l1",
    subgoalTitle: "First Lemma",
    subgoalTheorem: "ArkLibNearCapacity.decomp_d1_l1",
  });
  assert.match(stub, /theorem decomp_d1_l1 : SunsteadDecomp_t_d1\.l1 := by\n  sorry/);

  const mbox = renderMbox([
    {
      seq: 7,
      mission_id: "arklib-near-capacity-primes",
      task_id: "near_capacity_prime_supply",
      contributor: "carol",
      display_name: "Carol",
      summary: "Assembled proof via decomposition d1",
      patch: generateUnifiedDiff("ArkLibNearCapacity/PrimeSupply.lean", "-- old\n", assembled),
      created_at: 1700000100,
      co_authors: [
        { handle: "alice", display_name: "Alice Architect", role: "proposer" },
        { handle: "bob", display_name: "Bob Solver", role: "solver" },
        { handle: "carol", display_name: "Carol", role: "solver" }, // primary author deduped
      ],
    },
  ]);
  assert.match(mbox, /Co-authored-by: Alice Architect <alice@contributors\.sunstead\.org>/);
  assert.match(mbox, /Co-authored-by: Bob Solver <bob@contributors\.sunstead\.org>/);
  assert.ok(!mbox.includes("Co-authored-by: Carol <carol@contributors.sunstead.org>"));
  assert.match(mbox, /Sunstead-Submission: 7/);

  // ArkLib #1352 pilot manifest opt-in verification
  const arkManifest = JSON.parse(
    readFileSync(new URL("../../missions/arklib-near-capacity-primes/sunstead.json", import.meta.url), "utf8")
  ) as MissionManifest;
  assert.equal(arkManifest.decomposition?.enabled, true);
  assert.equal(arkManifest.decomposition?.require_allowlist, true);
  assert.equal(arkManifest.decomposition?.allow_direct_bypass, true);
  assert.equal(arkManifest.decomposition?.max_depth, 2);

  // /join.txt documents decompose & refute
  const joinTxt = renderJoinTxt("https://sunstead.org", [
    {
      manifest: arkManifest,
      tasks: arkManifest.tasks.map((def) => ({
        def,
        status: "open",
        best_score: null,
        verified_by: null,
        active_lease: null,
        attempts: 0,
      })),
    },
  ]);
  assert.match(joinTxt, /decompose_task/);
  assert.match(joinTxt, /refute_task/);
  assert.match(joinTxt, /\/decompose/);
  assert.match(joinTxt, /\/refute/);
});
