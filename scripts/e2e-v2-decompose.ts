#!/usr/bin/env -S node --experimental-strip-types
/**
 * End-to-end live Lean 4 kernel test for v2 `decompose` & `refute` (RFC-DECOMPOSE.md).
 *
 * Spins up `verifier_server.py` inside the real `sunstead/verifier-lean4:v0.2`
 * container and drives the real TypeScript Hub state machine (`cloudflare/src/decompose.ts`
 * over `node:sqlite`) through TWO full kernel-verified scenarios:
 *
 * 1. Depth-1 decomposition -> subgoal proofs (Bob & Carol) -> Hub auto-assembles
 *    target file & runs ORIGINAL UNTOUCHED `./verify <T>` -> clean `history.mbox`
 *    with `Co-authored-by:` trailers -> verified `git am` replay!
 * 2. Real `arklib-near-capacity-primes` (ArkLib Issue #1352) pilot:
 *    allowlisted `POST /decompose` (Mathlib v4.36.0) -> open `POST /refute`
 *    (`¬ L_1`) by non-allowlisted contributor -> decomposition invalidated,
 *    architect share forfeited, proposer struck, parent reopened, bounty paid!
 *
 * Usage:
 *   ./scripts/build-verifiers.sh v4.36.0
 *   node --experimental-strip-types scripts/e2e-v2-decompose.ts
 */
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import {
  filesStateSha256,
  generateUnifiedDiff,
  parseStoredCoAuthors,
  renderMbox,
  type MissionManifest,
  type MissionVerifyContract,
  type TaskState,
} from "../cloudflare/src/core.ts";
import {
  enrichTaskFilesWithDecomp,
  executeDecompose,
  executeRefute,
  executeSubgoalSubmit,
  getDisputedRootMap,
  initDecomposeSchema,
  listAllowlist,
  listMissionDecompositions,
  listMissionRefutations,
  upsertAllowlistEntry,
  type DecomposeHubContext,
  type SqlLike,
  type VerifierActionResponse,
} from "../cloudflare/src/decompose.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const IMAGE = process.env.SUNSTEAD_VERIFIER_IMAGE || "sunstead/verifier-lean4:v0.2";
const PORT = Number(process.env.SUNSTEAD_V2_E2E_PORT || 18089);

function computeSpecSha256(missionDir: string, frozenPaths: string[]): string {
  const files: Array<{ rel: string; abs: string }> = [];
  const walk = (d: string) => {
    for (const ent of fs.readdirSync(d, { withFileTypes: true })) {
      if ([".git", ".lake", "target"].includes(ent.name)) continue;
      const full = path.join(d, ent.name);
      if (ent.isDirectory()) walk(full);
      else if (ent.isFile()) {
        const rel = path.relative(missionDir, full).split(path.sep).join("/");
        if (frozenPaths.includes(rel)) files.push({ rel, abs: full });
      }
    }
  };
  walk(missionDir);
  files.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
  const h = crypto.createHash("sha256");
  for (const f of files) {
    const data = fs.readFileSync(f.abs);
    const len = Buffer.alloc(8);
    len.writeBigUInt64LE(BigInt(data.length));
    h.update(Buffer.from(f.rel, "utf8"));
    h.update(Buffer.from([0]));
    h.update(len);
    h.update(Buffer.from([0]));
    h.update(data);
    h.update(Buffer.from("\n", "utf8"));
  }
  return `sha256:${h.digest("hex")}`;
}

function createSqliteHub(
  manifest: MissionManifest,
  specSha: string,
  seedFiles: Record<string, string>,
  contract: MissionVerifyContract,
  verifierUrl: string
) {
  const db = new DatabaseSync(":memory:");
  const sql = {
    exec<T = Record<string, unknown>>(query: string, ...bindings: unknown[]) {
      const isSelect = /^\s*(?:SELECT|PRAGMA)\b/i.test(query);
      if (isSelect) {
        const rows = db.prepare(query).all(...(bindings as never[])) as T[];
        return {
          toArray: () => rows,
          one: () => {
            if (rows.length === 0) throw new Error(`expected 1 row for: ${query}`);
            return rows[0];
          },
        };
      }
      if (bindings.length === 0) db.exec(query);
      else db.prepare(query).run(...(bindings as never[]));
      return { toArray: () => [] as T[], one: () => ({}) as T };
    },
  } as unknown as SqlLike;

  db.exec(`
    CREATE TABLE tasks (
      mission_id TEXT NOT NULL, task_id TEXT NOT NULL, def_json TEXT NOT NULL,
      status TEXT NOT NULL, best_score REAL, verified_by TEXT,
      lease_contributor TEXT, lease_token TEXT, lease_expires_at INTEGER, lease_ip TEXT,
      attempts INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (mission_id, task_id)
    );
    CREATE TABLE contributors (
      handle TEXT PRIMARY KEY, display_name TEXT NOT NULL, github TEXT,
      github_verified_handle TEXT, x_handle TEXT, linkedin_handle TEXT,
      token_sha256 TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL
    );
    CREATE TABLE submissions (
      id TEXT PRIMARY KEY, mission_id TEXT NOT NULL, task_id TEXT NOT NULL,
      contributor TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'verifying',
      accepted INTEGER NOT NULL DEFAULT 0, score REAL, points INTEGER NOT NULL DEFAULT 0,
      summary TEXT NOT NULL DEFAULT '', patch_sha256 TEXT NOT NULL DEFAULT '',
      proof_id TEXT, verify_ms INTEGER NOT NULL DEFAULT 0, stage TEXT, diagnostics TEXT,
      error TEXT, unlocked_dependents_json TEXT, created_at INTEGER NOT NULL,
      completed_at INTEGER, is_demo INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE mission_files (
      mission_id TEXT NOT NULL, rel_path TEXT NOT NULL, content TEXT NOT NULL,
      PRIMARY KEY (mission_id, rel_path)
    );
    CREATE TABLE bundle_cache (mission_id TEXT PRIMARY KEY, tarball BLOB NOT NULL, updated_at INTEGER NOT NULL);
    CREATE TABLE accepted_patches (
      seq INTEGER PRIMARY KEY AUTOINCREMENT, mission_id TEXT NOT NULL, task_id TEXT NOT NULL,
      submission_id TEXT NOT NULL, contributor TEXT NOT NULL, summary TEXT NOT NULL,
      patch TEXT NOT NULL, patch_sha256 TEXT, audit_json TEXT, spec_sha256 TEXT NOT NULL,
      created_at INTEGER NOT NULL, is_demo INTEGER NOT NULL DEFAULT 0
    );
  `);
  initDecomposeSchema(sql, (t, c, d) => {
    const cols = sql.exec<{ name: string }>(`PRAGMA table_info(${t})`).toArray();
    if (!cols.some((x) => x.name === c)) db.exec(`ALTER TABLE ${t} ADD COLUMN ${c} ${d}`);
  });
  for (const t of manifest.tasks) {
    sql.exec(
      "INSERT INTO tasks (mission_id, task_id, def_json, status, attempts) VALUES (?, ?, ?, 'open', 0)",
      manifest.id,
      t.id,
      JSON.stringify(t)
    );
  }
  for (const [h, name] of [
    ["alice", "Alice Architect"],
    ["bob", "Bob Solver"],
    ["carol", "Carol Closer"],
    ["dave", "Dave Refuter"],
  ]) {
    sql.exec(
      "INSERT INTO contributors (handle, display_name, token_sha256, created_at) VALUES (?, ?, ?, 1000)",
      h,
      name,
      `sha256:${h.padEnd(64, "0")}`
    );
  }

  let clock = Math.floor(Date.now() / 1000);
  let seq = 0;
  const getTasks = (mid: string): TaskState[] => {
    const disputed = getDisputedRootMap(sql, mid);
    return sql
      .exec<{ def_json: string; status: string; best_score: number | null; verified_by: string | null; attempts: number }>(
        "SELECT def_json, status, best_score, verified_by, attempts FROM tasks WHERE mission_id = ? AND COALESCE(retired, 0) = 0 ORDER BY rowid ASC",
        mid
      )
      .toArray()
      .map((r) => {
        const def = JSON.parse(r.def_json);
        const d = disputed.get(def.id) ?? null;
        return {
          def,
          status: r.status === "verified" ? "verified" : r.status === "leased" ? "leased" : "open",
          best_score: r.best_score,
          verified_by: r.verified_by,
          active_lease: null,
          attempts: r.attempts,
          ...(d ? { disputed_counterexample: d } : {}),
        };
      });
  };
  const getMissionFiles = (mid: string): Record<string, string> => {
    const out: Record<string, string> = {};
    for (const r of sql
      .exec<{ rel_path: string; content: string }>("SELECT rel_path, content FROM mission_files WHERE mission_id = ?", mid)
      .toArray()) {
      out[r.rel_path] = r.content;
    }
    return out;
  };

  const ctx: DecomposeHubContext = {
    sql,
    mission: { manifest, spec_sha256: specSha, seed_files: seedFiles, verify_contract: contract },
    hubOrigin: "https://sunstead.org",
    now: () => ++clock,
    sha256Hex: async (text) => "sha256:" + crypto.createHash("sha256").update(text, "utf8").digest("hex"),
    randomUUID: () => `live-sub-${++seq}`,
    getTasks,
    getMissionFiles,
    withMissionLock: async (_mid, fn) => fn(),
    callVerifierAction: async (endpoint, files, body) => {
      const sha = await filesStateSha256(files);
      const resp = await fetch(`${verifierUrl}${endpoint}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...body, current_files_sha256: sha, current_files: files }),
      });
      if (!resp.ok) {
        return { ok: false, status: 502, error: `HTTP ${resp.status}: ${await resp.text()}` };
      }
      return { ok: true, res: (await resp.json()) as VerifierActionResponse };
    },
    emit: () => {},
  };

  const sumPoints = (handle: string) =>
    sql
      .exec<{ p: number }>(
        "SELECT COALESCE(SUM(CASE WHEN accepted = 1 AND is_demo = 0 THEN points ELSE 0 END), 0) AS p FROM submissions WHERE contributor = ?",
        handle
      )
      .one().p;

  return { db, sql, ctx, getTasks, getMissionFiles, sumPoints };
}

async function waitForHealth(url: string) {
  for (let i = 0; i < 40; i++) {
    try {
      const r = await fetch(`${url}/health`);
      if (r.ok) return;
    } catch {
      // retry
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`verifier server at ${url} did not become healthy`);
}

async function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sunstead-v2-e2e-"));
  const missionsMount = path.join(tmpDir, "missions");
  fs.mkdirSync(missionsMount, { recursive: true });

  // 1. Copy real `arklib-near-capacity-primes` mission.
  fs.cpSync(
    path.join(ROOT, "missions", "arklib-near-capacity-primes"),
    path.join(missionsMount, "arklib-near-capacity-primes"),
    { recursive: true }
  );

  // 2. Create a fast pure-Lean provable test mission for full `decompose -> subgoals -> untouched ./verify` closure!
  const toyDir = path.join(missionsMount, "v2-e2e-toy");
  fs.mkdirSync(path.join(toyDir, "ToyDecomp"), { recursive: true });
  const toySpec = `namespace ToyDecomp\ndef TargetProp (n : Nat) : Prop := n + 0 = n ∧ 0 + n = n\nend ToyDecomp\n`;
  const toyTarget = `import ToyDecomp.Spec\n\nnamespace ToyDecomp\ntheorem main_target : ∀ n : Nat, TargetProp n := by\n  sorry\nend ToyDecomp\n`;
  const toyVerify = `#!/usr/bin/env python3
import sys
sys.path.insert(0, "/opt/sunstead")
from sunstead_sandbox import emit, lean_verify

LIB_ROOT = "ToyDecomp"
FROZEN_FILES = ["ToyDecomp/Spec.lean", "lakefile.toml", "lean-toolchain"]
TASKS = {
    "main_target": {
        "module": "ToyDecomp.MainTarget",
        "theorem": "ToyDecomp.main_target",
        "statement": "def main_target : Prop := ∀ n : Nat, ToyDecomp.TargetProp n",
    },
}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        emit(False, "usage: ./verify <task_id>")
    lean_verify(sys.argv[1], lib_root=LIB_ROOT, frozen_files=FROZEN_FILES, tasks=TASKS, uses_mathlib=False, timeout_sec=90)
`;
  const toyManifest: MissionManifest = {
    id: "v2-e2e-toy",
    title: "v2 Live E2E Toy Mission",
    tier: 1,
    mode: "dag",
    frozen_paths: ["ToyDecomp/Spec.lean", "lakefile.toml", "lean-toolchain", "verify", "sunstead.json"],
    verifier: { image: IMAGE, command: ["./verify"], timeout_sec: 90 },
    decomposition: { enabled: true, require_allowlist: true, allow_direct_bypass: true, max_depth: 2 },
    tasks: [
      {
        id: "main_target",
        title: "Prove TargetProp n",
        target_files: ["ToyDecomp/MainTarget.lean"],
        depends_on: [],
      },
    ],
  };
  fs.writeFileSync(path.join(toyDir, "ToyDecomp", "Spec.lean"), toySpec);
  fs.writeFileSync(path.join(toyDir, "ToyDecomp", "MainTarget.lean"), toyTarget);
  fs.writeFileSync(path.join(toyDir, "lakefile.toml"), 'name = "ToyDecomp"\n[[lean_lib]]\nname = "ToyDecomp"\n');
  fs.writeFileSync(path.join(toyDir, "lean-toolchain"), "leanprover/lean4:v4.36.0\n");
  fs.writeFileSync(path.join(toyDir, "sunstead.json"), JSON.stringify(toyManifest, null, 2) + "\n");
  fs.writeFileSync(path.join(toyDir, "verify"), toyVerify, { mode: 0o755 });

  const cid = execFileSync(
    "docker",
    [
      "create",
      "--cpus=2", "--memory=6144m", "--pids-limit=512",
      "-p", `127.0.0.1:${PORT}:8080`,
      IMAGE,
      "python3", "/opt/verifier_server.py",
    ],
    { encoding: "utf8" }
  ).trim();
  execFileSync("docker", [
    "cp",
    path.join(ROOT, "cloudflare/containers/verifier_server.py"),
    `${cid}:/opt/verifier_server.py`,
  ]);
  execFileSync("docker", ["cp", missionsMount, `${cid}:/missions`]);
  execFileSync("docker", ["start", cid], { stdio: "ignore" });

  const baseUrl = `http://127.0.0.1:${PORT}`;
  try {
    await waitForHealth(baseUrl);
    console.log(`[e2e-v2] verifier_server.py healthy at ${baseUrl}`);

    // =========================================================================
    // SCENARIO 1: Live Lean 4 kernel decompose -> subgoals -> auto untouched `./verify` -> git am!
    // =========================================================================
    const toySpecSha = computeSpecSha256(toyDir, toyManifest.frozen_paths);
    const toyContract: MissionVerifyContract = {
      lib_root: "ToyDecomp",
      statement_preamble: "",
      frozen_lean_modules: ["ToyDecomp.Spec"],
      tasks: {
        main_target: {
          module: "ToyDecomp.MainTarget",
          theorem: "ToyDecomp.main_target",
          statement: "def main_target : Prop := ∀ n : Nat, ToyDecomp.TargetProp n",
        },
      },
    };
    const toyHub = createSqliteHub(
      toyManifest,
      toySpecSha,
      { "ToyDecomp/Spec.lean": toySpec, "ToyDecomp/MainTarget.lean": toyTarget },
      toyContract,
      baseUrl
    );
    upsertAllowlistEntry(toyHub.sql, { handle: "alice", active: true, added_by: "admin", note: "e2e", now: 100 });

    const redFile = "ToyDecomp/Decomp_main_target_d1.lean";
    const redSrc = [
      "import ToyDecomp.Spec",
      "import ToyDecomp.DecompStatements_main_target_d1",
      "",
      "namespace ToyDecomp",
      "theorem reduce_main",
      "    (h1 : SunsteadDecomp_main_target_d1.right_zero)",
      "    (h2 : SunsteadDecomp_main_target_d1.left_zero) :",
      "    ∀ n : Nat, TargetProp n := by",
      "  intro n",
      "  exact ⟨h1 n, h2 n⟩",
      "end ToyDecomp",
      "",
    ].join("\n");

    const dec = await executeDecompose(toyHub.ctx, {
      taskId: "main_target",
      contributor: "alice",
      rawBody: {
        decomp_id: "d1",
        subgoals: [
          { id: "right_zero", title: "Right additive identity", statement: "def right_zero : Prop := ∀ n : Nat, n + 0 = n" },
          { id: "left_zero", title: "Left additive identity", statement: "def left_zero : Prop := ∀ n : Nat, 0 + n = n" },
        ],
        reduction_file: redFile,
        reduction_theorem: "ToyDecomp.reduce_main",
        patch: generateUnifiedDiff(redFile, null, redSrc),
      },
    });
    assert.equal(dec.status, 201, `decompose failed: ${JSON.stringify(dec.body)}`);
    assert.equal(dec.body.points_awarded, 0);
    console.log(`[e2e-v2] PASS 1a: live Lean kernel verified decomposition (${dec.body.verify_ms} ms)`);

    const sub1 = toyHub.getTasks("v2-e2e-toy").find((t) => t.def.subgoal_id === "right_zero")!;
    const sub2 = toyHub.getTasks("v2-e2e-toy").find((t) => t.def.subgoal_id === "left_zero")!;

    // Bob solves subgoal 1 (`right_zero`)
    const sub1Files = enrichTaskFilesWithDecomp(toyHub.sql, {
      missionId: "v2-e2e-toy",
      task: sub1,
      baseView: { target_files: {}, frozen_files: {} },
      verifyContract: toyContract,
    });
    const sub1Stub = (sub1Files.target_files as Record<string, string>)[sub1.def.target_files[0]];
    const sub1Proof = sub1Stub.replace("sorry", "intro n; exact Nat.add_zero n");
    const sub1Patch = generateUnifiedDiff(sub1.def.target_files[0], sub1Stub, sub1Proof);
    toyHub.sql.exec(
      "INSERT INTO submissions (id, mission_id, task_id, contributor, status, accepted, points, summary, patch_sha256, verify_ms, created_at, is_demo) VALUES ('sub-live-1', 'v2-e2e-toy', ?, 'bob', 'verifying', 0, 0, '', 'sha256:1', 0, 100, 0)",
      sub1.def.id
    );
    const r1 = await executeSubgoalSubmit(toyHub.ctx, {
      subId: "sub-live-1",
      task: sub1,
      contributor: "bob",
      patch: sub1Patch,
      patchSha: "sha256:1",
    });
    assert.equal(r1.status, 200, `subgoal 1 failed: ${JSON.stringify(r1.body)}`);
    assert.equal(r1.body.parent_assembled, false);
    assert.equal(toyHub.sumPoints("bob"), 60);
    assert.equal(toyHub.sumPoints("alice"), 0);
    console.log(`[e2e-v2] PASS 1b: live Lean kernel verified subgoal 1 (${r1.body.verify_ms} ms)`);

    // Carol solves subgoal 2 (`left_zero`) -> automatic assembly through UNTOUCHED `./verify main_target`!
    const sub2Files = enrichTaskFilesWithDecomp(toyHub.sql, {
      missionId: "v2-e2e-toy",
      task: sub2,
      baseView: { target_files: {}, frozen_files: {} },
      verifyContract: toyContract,
    });
    const sub2Stub = (sub2Files.target_files as Record<string, string>)[sub2.def.target_files[0]];
    const sub2Proof = sub2Stub.replace("sorry", "intro n; exact Nat.zero_add n");
    const sub2Patch = generateUnifiedDiff(sub2.def.target_files[0], sub2Stub, sub2Proof);
    toyHub.sql.exec(
      "INSERT INTO submissions (id, mission_id, task_id, contributor, status, accepted, points, summary, patch_sha256, verify_ms, created_at, is_demo) VALUES ('sub-live-2', 'v2-e2e-toy', ?, 'carol', 'verifying', 0, 0, '', 'sha256:2', 0, 101, 0)",
      sub2.def.id
    );
    const r2 = await executeSubgoalSubmit(toyHub.ctx, {
      subId: "sub-live-2",
      task: sub2,
      contributor: "carol",
      patch: sub2Patch,
      patchSha: "sha256:2",
    });
    assert.equal(r2.status, 200, `subgoal 2 / assembly failed: ${JSON.stringify(r2.body)}`);
    assert.equal(r2.body.parent_assembled, true, `expected auto-assembly to pass untouched ./verify: ${JSON.stringify(r2.body)}`);
    assert.equal(r2.body.architect_points_vested, 30);
    assert.equal(toyHub.sumPoints("alice"), 30);
    assert.equal(toyHub.sumPoints("bob"), 60);
    assert.equal(toyHub.sumPoints("carol"), 60);
    console.log(`[e2e-v2] PASS 1c: automatic assembly passed UNTOUCHED ./verify main_target! (Alice 30 + Bob 60 + Carol 60 = 150 pts)`);

    // Verify `history.mbox` replays cleanly via `git am` onto the clean seed repo!
    const histRows = toyHub.sql
      .exec<{ seq: number; mission_id: string; task_id: string; contributor: string; summary: string; patch: string; created_at: number; co_authors_json: string | null }>(
        "SELECT * FROM accepted_patches WHERE mission_id = 'v2-e2e-toy' AND COALESCE(in_history, 1) = 1 ORDER BY seq ASC"
      )
      .toArray();
    assert.equal(histRows.length, 1);
    const mbox = renderMbox(
      histRows.map((r) => ({ ...r, display_name: "Carol Closer", co_authors: parseStoredCoAuthors(r.co_authors_json) }))
    );
    assert.match(mbox, /Co-authored-by: Alice Architect <alice@contributors\.sunstead\.org>/);
    assert.match(mbox, /Co-authored-by: Bob Solver <bob@contributors\.sunstead\.org>/);

    const replayDir = path.join(tmpDir, "replay-git");
    fs.cpSync(toyDir, replayDir, { recursive: true });
    execFileSync("git", ["init", "-q", "-b", "main"], { cwd: replayDir });
    execFileSync("git", ["config", "user.name", "Test"], { cwd: replayDir });
    execFileSync("git", ["config", "user.email", "test@localhost"], { cwd: replayDir });
    execFileSync("git", ["add", "."], { cwd: replayDir });
    execFileSync("git", ["commit", "-q", "-m", "seed"], { cwd: replayDir });
    const am = spawnSync("git", ["am"], { cwd: replayDir, input: mbox, encoding: "utf8" });
    assert.equal(am.status, 0, `git am failed: ${am.stderr}`);
    const logMsg = execFileSync("git", ["log", "-1", "--pretty=%B"], { cwd: replayDir, encoding: "utf8" });
    assert.match(logMsg, /Co-authored-by: Alice Architect/);
    assert.match(logMsg, /Co-authored-by: Bob Solver/);
    console.log(`[e2e-v2] PASS 1d: history.mbox replayed cleanly with git am & Co-authored-by trailers!`);

    // =========================================================================
    // SCENARIO 2: Real `arklib-near-capacity-primes` (ArkLib #1352) pilot:
    //             allowlisted decompose -> non-allowlisted refute ¬ L_1 rollback!
    // =========================================================================
    const arkDir = path.join(missionsMount, "arklib-near-capacity-primes");
    const arkManifest = JSON.parse(fs.readFileSync(path.join(arkDir, "sunstead.json"), "utf8")) as MissionManifest;
    const arkSpecSha = computeSpecSha256(arkDir, arkManifest.frozen_paths);
    const arkContract: MissionVerifyContract = {
      lib_root: "ArkLibNearCapacity",
      statement_preamble: "",
      frozen_lean_modules: ["ArkLibNearCapacity.Spec"],
      tasks: {
        near_capacity_prime_supply: {
          module: "ArkLibNearCapacity.PrimeSupply",
          theorem: "ArkLibNearCapacity.near_capacity_prime_supply",
          statement: "def near_capacity_prime_supply : Prop := ∀ (c : NNReal), 0 < c → ArkLibNearCapacity.NearCapacityPrimeSupply c",
        },
      },
    };
    const arkHub = createSqliteHub(
      arkManifest,
      arkSpecSha,
      {
        "ArkLibNearCapacity/Spec.lean": fs.readFileSync(path.join(arkDir, "ArkLibNearCapacity/Spec.lean"), "utf8"),
        "ArkLibNearCapacity/PrimeSupply.lean": fs.readFileSync(path.join(arkDir, "ArkLibNearCapacity/PrimeSupply.lean"), "utf8"),
      },
      arkContract,
      baseUrl
    );
    upsertAllowlistEntry(arkHub.sql, { handle: "alice", active: true, added_by: "admin", note: "arklib pilot", now: 100 });

    const arkRedFile = "ArkLibNearCapacity/Decomp_near_capacity_prime_supply_d1.lean";
    const arkRedSrc = [
      "import ArkLibNearCapacity.Spec",
      "import ArkLibNearCapacity.DecompStatements_near_capacity_prime_supply_d1",
      "",
      "open scoped NNReal",
      "namespace ArkLibNearCapacity",
      "theorem reduce_ark",
      "    (h1 : SunsteadDecomp_near_capacity_prime_supply_d1.bad_ap_bound)",
      "    (h2 : SunsteadDecomp_near_capacity_prime_supply_d1.aux_margin) :",
      "    ∀ (c : NNReal), 0 < c → NearCapacityPrimeSupply c := by",
      "  intro c hc",
      "  have h01 : (0 : Nat) = 1 := h1 1 (h2 1)",
      "  exact False.elim (Nat.zero_ne_one h01)",
      "end ArkLibNearCapacity",
      "",
    ].join("\n");

    const arkDec = await executeDecompose(arkHub.ctx, {
      taskId: "near_capacity_prime_supply",
      contributor: "alice",
      rawBody: {
        decomp_id: "d1",
        subgoals: [
          { id: "bad_ap_bound", title: "Flawed AP bound", statement: "def bad_ap_bound : Prop := ∀ n : Nat, n = n → (0 : Nat) = 1" },
          { id: "aux_margin", title: "Auxiliary margin", statement: "def aux_margin : Prop := ∀ n : Nat, n = n" },
        ],
        reduction_file: arkRedFile,
        reduction_theorem: "ArkLibNearCapacity.reduce_ark",
        patch: generateUnifiedDiff(arkRedFile, null, arkRedSrc),
      },
    });
    assert.equal(arkDec.status, 201, `ArkLib decompose failed: ${JSON.stringify(arkDec.body)}`);
    const badSub = arkHub.getTasks("arklib-near-capacity-primes").find((t) => t.def.subgoal_id === "bad_ap_bound")!;
    console.log(`[e2e-v2] PASS 2a: real ArkLib #1352 (Mathlib v4.36.0) decomposition accepted (${arkDec.body.verify_ms} ms)`);

    // Dave (NOT allowlisted) submits real Lean 4 proof of `¬ bad_ap_bound`!
    const refFile = "ArkLibNearCapacity/RefuteBadAp.lean";
    const refSrc = [
      "import ArkLibNearCapacity.Spec",
      "import ArkLibNearCapacity.DecompStatements_near_capacity_prime_supply_d1",
      "",
      "namespace ArkLibNearCapacity",
      "theorem refute_bad_ap : ¬ SunsteadDecomp_near_capacity_prime_supply_d1.bad_ap_bound := by",
      "  intro h",
      "  exact Nat.zero_ne_one (h 0 rfl)",
      "end ArkLibNearCapacity",
      "",
    ].join("\n");
    const arkRef = await executeRefute(arkHub.ctx, {
      taskId: badSub.def.id,
      contributor: "dave",
      rawBody: {
        refute_file: refFile,
        refute_theorem: "ArkLibNearCapacity.refute_bad_ap",
        patch: generateUnifiedDiff(refFile, null, refSrc),
      },
    });
    assert.equal(arkRef.status, 200, `ArkLib refute failed: ${JSON.stringify(arkRef.body)}`);
    assert.equal(arkRef.body.refuted, true);
    assert.equal(arkRef.body.invalidated_decomp_id, "d1");
    assert.equal(arkRef.body.reopened_parent_task_id, "near_capacity_prime_supply");
    assert.equal(arkRef.body.points_awarded, 75);
    assert.equal(arkHub.sumPoints("dave"), 75);
    assert.equal(arkHub.sumPoints("alice"), 0);
    assert.equal(listAllowlist(arkHub.sql).find((a) => a.handle === "alice")?.strikes, 1);
    assert.equal(arkHub.getTasks("arklib-near-capacity-primes").length, 1);
    assert.equal(listMissionDecompositions(arkHub.sql, "arklib-near-capacity-primes")[0].status, "refuted");
    assert.equal(listMissionRefutations(arkHub.sql, "arklib-near-capacity-primes", "https://sunstead.org").length, 1);
    console.log(`[e2e-v2] PASS 2b: real ArkLib #1352 refutation (¬ bad_ap_bound) rolled back split, struck proposer, reopened parent & paid 75 pts (${arkRef.body.verify_ms} ms)`);

    console.log("\nALL LIVE LEAN 4 V2 DECOMPOSE & REFUTE E2E CHECKS PASSED!");
  } finally {
    spawnSync("docker", ["rm", "-f", cid], { stdio: "ignore" });
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
