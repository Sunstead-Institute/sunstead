// End-to-end SQLite state-machine tests for v2 decompose & refute (`src/decompose.ts`).
// Exercises allowlist gating, depth-1 & depth-2 splits, zero-inflation economics,
// automatic assembly through untouched `/verify`, direct parent bypass, refutation
// teardown + proposer strike, root counterexample badges, and clean mbox/ledger output.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import {
  applyClaim,
  buildLedgerEntry,
  computeFrontier,
  formatSubmissionStatusView,
  generateUnifiedDiff,
  parseStoredCoAuthors,
  renderMbox,
  type MissionManifest,
  type MissionVerifyContract,
  type SubmissionStatusRow,
  type TaskState,
} from "../src/core.ts";
import {
  deactivateAllowlistEntry,
  enrichTaskFilesWithDecomp,
  executeDecompose,
  executeRefute,
  executeSubgoalSubmit,
  getDisputedRootMap,
  handleDirectParentBypass,
  initDecomposeSchema,
  isAllowlisted,
  listAllowlist,
  listMissionDecompositions,
  listMissionRefutations,
  prepareRefute,
  upsertAllowlistEntry,
  type DecomposeHubContext,
  type SqlLike,
  type VerifierActionResponse,
} from "../src/decompose.ts";

const SPEC_SHA = "sha256:" + "1".repeat(64);

function makeManifest(overrides: Partial<MissionManifest> = {}): MissionManifest {
  return {
    id: "arklib-near-capacity-primes",
    title: "ArkLib Pilot",
    tier: 1,
    mode: "dag",
    frozen_paths: ["ArkLibNearCapacity/Spec.lean", "UPSTREAM.json", "lakefile.toml", "lean-toolchain", "verify", "sunstead.json"],
    verifier: { image: "sunstead/verifier-lean4:v0.2", command: ["./verify"] },
    decomposition: {
      enabled: true,
      require_allowlist: true,
      allow_direct_bypass: true,
      max_depth: 2,
    },
    tasks: [
      {
        id: "near_capacity_prime_supply",
        title: "Prove NearCapacityPrimeSupply c",
        target_files: ["ArkLibNearCapacity/PrimeSupply.lean"],
        depends_on: [],
      },
    ],
    ...overrides,
  };
}

const VERIFY_CONTRACT: MissionVerifyContract = {
  lib_root: "ArkLibNearCapacity",
  statement_preamble: "open scoped NNReal",
  frozen_lean_modules: ["ArkLibNearCapacity.Spec"],
  tasks: {
    near_capacity_prime_supply: {
      module: "ArkLibNearCapacity.PrimeSupply",
      theorem: "ArkLibNearCapacity.near_capacity_prime_supply",
      statement: "def near_capacity_prime_supply : Prop := ∀ (c : NNReal), 0 < c → ArkLibNearCapacity.NearCapacityPrimeSupply c",
    },
  },
};

function createTestHub(opts: {
  manifest?: MissionManifest;
  verifier?: (
    path: "/verify" | "/decompose" | "/subgoal" | "/refute",
    files: Record<string, string>,
    body: Record<string, unknown>
  ) => VerifierActionResponse;
} = {}) {
  const db = new DatabaseSync(":memory:");
  const sql = {
    exec<T = Record<string, unknown>>(query: string, ...bindings: unknown[]) {
      const isSelect = /^\s*(?:SELECT|PRAGMA)\b/i.test(query);
      if (isSelect) {
        const stmt = db.prepare(query);
        const rows = stmt.all(...(bindings as never[])) as T[];
        return {
          toArray: () => rows,
          one: () => {
            if (rows.length === 0) throw new Error(`expected 1 row for: ${query}`);
            return rows[0];
          },
        };
      }
      if (bindings.length === 0) {
        db.exec(query);
      } else {
        db.prepare(query).run(...(bindings as never[]));
      }
      return {
        toArray: () => [] as T[],
        one: () => ({}) as T,
      };
    },
  } as unknown as SqlLike;

  // Base tables matching SunsteadHub.initSchema().
  db.exec(`
    CREATE TABLE tasks (
      mission_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      def_json TEXT NOT NULL,
      status TEXT NOT NULL,
      best_score REAL,
      verified_by TEXT,
      lease_contributor TEXT,
      lease_token TEXT,
      lease_expires_at INTEGER,
      lease_ip TEXT,
      attempts INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (mission_id, task_id)
    );
    CREATE TABLE contributors (
      handle TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      github TEXT,
      github_verified_handle TEXT,
      x_handle TEXT,
      linkedin_handle TEXT,
      token_sha256 TEXT NOT NULL UNIQUE,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE submissions (
      id TEXT PRIMARY KEY,
      mission_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      contributor TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'verifying',
      accepted INTEGER NOT NULL DEFAULT 0,
      score REAL,
      points INTEGER NOT NULL DEFAULT 0,
      summary TEXT NOT NULL DEFAULT '',
      patch_sha256 TEXT NOT NULL DEFAULT '',
      proof_id TEXT,
      verify_ms INTEGER NOT NULL DEFAULT 0,
      stage TEXT,
      diagnostics TEXT,
      error TEXT,
      unlocked_dependents_json TEXT,
      created_at INTEGER NOT NULL,
      completed_at INTEGER,
      is_demo INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE mission_files (
      mission_id TEXT NOT NULL,
      rel_path TEXT NOT NULL,
      content TEXT NOT NULL,
      PRIMARY KEY (mission_id, rel_path)
    );
    CREATE TABLE bundle_cache (
      mission_id TEXT PRIMARY KEY,
      tarball BLOB NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE accepted_patches (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      mission_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      submission_id TEXT NOT NULL,
      contributor TEXT NOT NULL,
      summary TEXT NOT NULL,
      patch TEXT NOT NULL,
      patch_sha256 TEXT,
      audit_json TEXT,
      spec_sha256 TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      is_demo INTEGER NOT NULL DEFAULT 0
    );
  `);

  const ensureColumn = (table: string, col: string, colDef: string) => {
    const cols = sql.exec<{ name: string }>(`PRAGMA table_info(${table})`).toArray();
    if (!cols.some((c) => c.name === col)) {
      db.exec(`ALTER TABLE ${table} ADD COLUMN ${col} ${colDef}`);
    }
  };
  initDecomposeSchema(sql, ensureColumn);

  const manifest = opts.manifest ?? makeManifest();
  for (const t of manifest.tasks) {
    sql.exec(
      "INSERT INTO tasks (mission_id, task_id, def_json, status, attempts) VALUES (?, ?, ?, 'open', 0)",
      manifest.id,
      t.id,
      JSON.stringify(t)
    );
  }
  for (const [handle, display] of [
    ["alice", "Alice Architect"],
    ["bob", "Bob Solver"],
    ["carol", "Carol Closer"],
    ["dave", "Dave Refuter"],
  ]) {
    sql.exec(
      "INSERT INTO contributors (handle, display_name, token_sha256, created_at) VALUES (?, ?, ?, 1000)",
      handle,
      display,
      `sha256:${handle.padEnd(64, "0")}`
    );
  }

  let clock = 1700000000;
  let uuidSeq = 0;
  const events: Array<Record<string, unknown>> = [];
  const verifierCalls: Array<{ path: string; body: Record<string, unknown>; files: Record<string, string> }> = [];

  const getTasks = (mid: string): TaskState[] => {
    const disputed = getDisputedRootMap(sql, mid);
    return sql
      .exec<{
        def_json: string;
        status: string;
        best_score: number | null;
        verified_by: string | null;
        lease_contributor: string | null;
        lease_token: string | null;
        lease_expires_at: number | null;
        attempts: number;
      }>("SELECT * FROM tasks WHERE mission_id = ? AND COALESCE(retired, 0) = 0 ORDER BY rowid ASC", mid)
      .toArray()
      .map((r) => {
        const def = JSON.parse(r.def_json);
        const dispute = disputed.get(def.id) ?? null;
        return {
          def,
          status: r.status === "verified" ? "verified" : r.status === "leased" ? "leased" : "open",
          best_score: r.best_score,
          verified_by: r.verified_by,
          active_lease: r.lease_contributor
            ? {
                task_id: def.id,
                contributor: r.lease_contributor,
                lease_token: r.lease_token || "tok",
                expires_at_unix: r.lease_expires_at || clock + 600,
              }
            : null,
          attempts: r.attempts,
          ...(dispute ? { disputed_counterexample: dispute } : {}),
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

  const defaultVerifier = (
    path: "/verify" | "/decompose" | "/subgoal" | "/refute",
    _files: Record<string, string>,
    body: Record<string, unknown>
  ): VerifierActionResponse => {
    const patch = String(body.patch || "");
    const targetFile = Array.isArray(body.target_files) ? String(body.target_files[0]) : "";
    const extracted = patch
      .split("\n")
      .filter((l) => l.startsWith("+") && !l.startsWith("+++ "))
      .map((l) => l.slice(1))
      .join("\n") + "\n";

    if (path === "/decompose") {
      const taskId = String(body.task_id);
      const decompId = String(body.decomp_id);
      const subs = (body.subgoals as Array<{ id: string; statement: string }>) || [];
      const ns = `SunsteadDecomp_${taskId}_${decompId}`;
      const mod = `ArkLibNearCapacity.DecompStatements_${taskId}_${decompId}`;
      const src =
        `import ArkLibNearCapacity.Spec\nnamespace ${ns}\n` +
        subs.map((s) => `def ${s.id} : Prop := (${s.statement})`).join("\n") +
        `\nend ${ns}\n`;
      const hashes: Record<string, string> = {};
      for (const s of subs) {
        hashes[s.id] = "sha256:" + crypto.createHash("sha256").update(`${ns}:${s.id}:${s.statement}`).digest("hex");
      }
      return {
        ok: true,
        score: 1.0,
        summary: `Lean 4 decomposition kernel-replayed ${taskId} -> ${subs.length} subgoals`,
        spec_sha256: SPEC_SHA,
        updated_files: { [targetFile]: extracted },
        normalized_patch: patch,
        verify_ms: 420,
        decomp_statements_module: mod,
        decomp_statements_namespace: ns,
        decomp_statements_source: src,
        subgoal_spec_sha256s: hashes,
      };
    }
    return {
      ok: true,
      score: 1.0,
      summary: `Lean 4 kernel-replayed (${path})`,
      spec_sha256: SPEC_SHA,
      updated_files: targetFile ? { [targetFile]: extracted } : {},
      normalized_patch: patch,
      verify_ms: 210,
    };
  };

  const ctx: DecomposeHubContext = {
    sql,
    mission: {
      manifest,
      spec_sha256: SPEC_SHA,
      seed_files: {
        "ArkLibNearCapacity/Spec.lean": "-- frozen spec\n",
        "ArkLibNearCapacity/PrimeSupply.lean": "import ArkLibNearCapacity.Spec\ntheorem near_capacity_prime_supply : True := by sorry\n",
      },
      verify_contract: VERIFY_CONTRACT,
    },
    hubOrigin: "https://sunstead.org",
    now: () => ++clock,
    sha256Hex: async (text) =>
      "sha256:" + crypto.createHash("sha256").update(text, "utf8").digest("hex"),
    randomUUID: () => `uuid-${++uuidSeq}`,
    getTasks,
    getMissionFiles,
    withMissionLock: async (_mid, fn) => fn(),
    callVerifierAction: async (path, files, body) => {
      verifierCalls.push({ path, body, files });
      const res = (opts.verifier ?? defaultVerifier)(path, files, body);
      return { ok: true, res };
    },
    emit: (ev) => events.push(ev),
  };

  const sumPoints = (handle: string) =>
    sql
      .exec<{ p: number }>(
        "SELECT COALESCE(SUM(CASE WHEN accepted = 1 AND is_demo = 0 THEN points ELSE 0 END), 0) AS p FROM submissions WHERE contributor = ?",
        handle
      )
      .one().p;

  const insertVerifyingSub = (subId: string, taskId: string, contributor: string, patchSha: string) => {
    sql.exec(
      `INSERT INTO submissions (id, mission_id, task_id, contributor, status, accepted, points, summary, patch_sha256, verify_ms, created_at, is_demo)
       VALUES (?, ?, ?, ?, 'verifying', 0, 0, 'Verifying', ?, 0, ?, 0)`,
      subId,
      manifest.id,
      taskId,
      contributor,
      patchSha,
      clock
    );
  };

  return { db, sql, ctx, events, verifierCalls, getTasks, getMissionFiles, sumPoints, insertVerifyingSub };
}

test("allowlist CRUD and Phase 1 allowlist gating on POST /decompose", async () => {
  const { sql, ctx, verifierCalls } = createTestHub();
  assert.equal(isAllowlisted(sql, "alice"), false);

  const redFile = "ArkLibNearCapacity/Decomp_near_capacity_prime_supply_d1.lean";
  const patch = generateUnifiedDiff(redFile, null, "import ArkLibNearCapacity.Spec\n");

  const denied = await executeDecompose(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "alice",
    rawBody: {
      subgoals: [
        { id: "lemma_a", title: "Lemma A", statement: "1 = 1" },
        { id: "lemma_b", title: "Lemma B", statement: "2 = 2" },
      ],
      reduction_file: redFile,
      reduction_theorem: "ArkLibNearCapacity.reduce",
      patch,
    },
  });
  assert.equal(denied.status, 403);
  assert.equal(verifierCalls.length, 0, "unallowlisted request must never wake verifier container");

  upsertAllowlistEntry(sql, { handle: "alice", active: true, added_by: "admin", note: "pilot", now: 100 });
  assert.equal(isAllowlisted(sql, "alice"), true);
  assert.equal(listAllowlist(sql).length, 1);

  assert.equal(deactivateAllowlistEntry(sql, "alice", 101), true);
  assert.equal(isAllowlisted(sql, "alice"), false);
});

test("end-to-end depth-1 decompose -> subgoal proofs -> automatic untouched ./verify closure & Co-authored-by mbox", async () => {
  const { sql, ctx, verifierCalls, getTasks, getMissionFiles, sumPoints, insertVerifyingSub } = createTestHub();
  upsertAllowlistEntry(sql, { handle: "alice", active: true, added_by: "admin", note: "pilot", now: 100 });

  const redFile = "ArkLibNearCapacity/Decomp_near_capacity_prime_supply_d1.lean";
  const redSrc =
    "import ArkLibNearCapacity.Spec\nimport ArkLibNearCapacity.DecompStatements_near_capacity_prime_supply_d1\n" +
    "namespace ArkLibNearCapacity\ntheorem reduce_main (h1 : SunsteadDecomp_near_capacity_prime_supply_d1.lemma_a) (h2 : SunsteadDecomp_near_capacity_prime_supply_d1.lemma_b) : True := trivial\nend ArkLibNearCapacity\n";

  // 1. Alice proposes decomposition (0 pts immediately!).
  const dec = await executeDecompose(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "alice",
    rawBody: {
      decomp_id: "d1",
      subgoals: [
        { id: "lemma_a", title: "Dyadic AP prime lower bound", statement: "1 = 1" },
        { id: "lemma_b", title: "Exponent margin selection", statement: "2 = 2" },
      ],
      reduction_file: redFile,
      reduction_theorem: "ArkLibNearCapacity.reduce_main",
      patch: generateUnifiedDiff(redFile, null, redSrc),
    },
  });
  assert.equal(dec.status, 201);
  assert.equal(dec.body.points_awarded, 0);
  assert.equal(sumPoints("alice"), 0, "proposer earns 0 pts at decompose time");

  const tasksAfterDecomp = getTasks("arklib-near-capacity-primes");
  assert.equal(tasksAfterDecomp.length, 3, "1 root + 2 spawned subgoals");
  const sub1 = tasksAfterDecomp.find((t) => t.def.subgoal_id === "lemma_a")!;
  const sub2 = tasksAfterDecomp.find((t) => t.def.subgoal_id === "lemma_b")!;

  // Active target cap = 1: second decomposition on same parent rejected with 409!
  const dup = await executeDecompose(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "alice",
    rawBody: {
      decomp_id: "d1_alt",
      subgoals: [
        { id: "lemma_c", title: "C", statement: "3 = 3" },
        { id: "lemma_d", title: "D", statement: "4 = 4" },
      ],
      reduction_file: "ArkLibNearCapacity/Decomp_alt.lean",
      reduction_theorem: "ArkLibNearCapacity.red_alt",
      patch: generateUnifiedDiff("ArkLibNearCapacity/Decomp_alt.lean", null, redSrc),
    },
  });
  assert.equal(dup.status, 409);

  // Inspecting subgoal files includes stub target, frozen DecompStatements, and frozen reduction file.
  const sub1Files = enrichTaskFilesWithDecomp(sql, {
    missionId: "arklib-near-capacity-primes",
    task: sub1,
    baseView: { target_files: {}, frozen_files: { "ArkLibNearCapacity/Spec.lean": "-- spec" } },
    verifyContract: VERIFY_CONTRACT,
  });
  assert.ok(sub1.def.target_files[0] in (sub1Files.target_files as Record<string, string>));
  assert.ok(redFile in (sub1Files.frozen_files as Record<string, string>));

  // RFC §7 Attack #5: subgoal solver attempting to edit the frozen reduction file is rejected!
  const attackSubId = "sub-attack-5";
  const attackPatch = generateUnifiedDiff(redFile, redSrc, "-- tampered\n");
  insertVerifyingSub(attackSubId, sub1.def.id, "bob", "sha256:bad");
  const attackRes = await executeSubgoalSubmit(ctx, {
    subId: attackSubId,
    task: sub1,
    contributor: "bob",
    patch: attackPatch,
    patchSha: "sha256:bad",
  });
  assert.equal(attackRes.status, 422);
  assert.match(String(attackRes.body.error), /frozen path/);

  // 2. Bob solves subgoal 1 -> earns solver share (60 pts); Alice's architect share (30 pts) still unvested!
  const sub1Stub = (sub1Files.target_files as Record<string, string>)[sub1.def.target_files[0]];
  const sub1Proof = sub1Stub.replace("sorry", "rfl");
  const sub1Patch = generateUnifiedDiff(sub1.def.target_files[0], sub1Stub, sub1Proof);
  insertVerifyingSub("sub-1", sub1.def.id, "bob", "sha256:sub1");
  const res1 = await executeSubgoalSubmit(ctx, {
    subId: "sub-1",
    task: sub1,
    contributor: "bob",
    patch: sub1Patch,
    patchSha: "sha256:sub1",
  });
  assert.equal(res1.status, 200);
  assert.equal(res1.body.points_awarded, 60);
  assert.equal(res1.body.parent_assembled, false);
  assert.equal(sumPoints("bob"), 60);
  assert.equal(sumPoints("alice"), 0, "architect share must not vest before parent closes");

  // 3. Carol solves final subgoal 2 -> automatic assembly runs untouched POST /verify <T>!
  const sub2Files = enrichTaskFilesWithDecomp(sql, {
    missionId: "arklib-near-capacity-primes",
    task: sub2,
    baseView: { target_files: {}, frozen_files: {} },
    verifyContract: VERIFY_CONTRACT,
  });
  const sub2Stub = (sub2Files.target_files as Record<string, string>)[sub2.def.target_files[0]];
  const sub2Proof = sub2Stub.replace("sorry", "rfl");
  const sub2Patch = generateUnifiedDiff(sub2.def.target_files[0], sub2Stub, sub2Proof);
  insertVerifyingSub("sub-2", sub2.def.id, "carol", "sha256:sub2");
  const res2 = await executeSubgoalSubmit(ctx, {
    subId: "sub-2",
    task: sub2,
    contributor: "carol",
    patch: sub2Patch,
    patchSha: "sha256:sub2",
  });
  assert.equal(res2.status, 200);
  assert.equal(res2.body.points_awarded, 60);
  assert.equal(res2.body.parent_assembled, true);
  assert.equal(res2.body.parent_task_id, "near_capacity_prime_supply");
  assert.equal(res2.body.architect_points_vested, 30);

  // Confirm the final verifier call was the untouched `/verify` endpoint on the root task!
  const lastCall = verifierCalls[verifierCalls.length - 1];
  assert.equal(lastCall.path, "/verify");
  assert.equal(lastCall.body.task_id, "near_capacity_prime_supply");

  // Zero-inflation point total: Alice (30) + Bob (60) + Carol (60) = 150 === parentPoints!
  assert.equal(sumPoints("alice"), 30);
  assert.equal(sumPoints("bob"), 60);
  assert.equal(sumPoints("carol"), 60);
  assert.equal(sumPoints("alice") + sumPoints("bob") + sumPoints("carol"), 150);

  // Root task is verified, mission_files updated with assembled file (no DecompStatements imports).
  const finalRoot = getTasks("arklib-near-capacity-primes").find((t) => t.def.id === "near_capacity_prime_supply")!;
  assert.equal(finalRoot.status, "verified");
  const assembledOnDisk = getMissionFiles("arklib-near-capacity-primes")["ArkLibNearCapacity/PrimeSupply.lean"];
  assert.ok(assembledOnDisk && !assembledOnDisk.includes("import ArkLibNearCapacity.DecompStatements"));

  // History.mbox contains ONLY the single clean assembled root commit (`in_history = 1`) with Co-authored-by trailers!
  const histRows = sql
    .exec<{
      seq: number;
      mission_id: string;
      task_id: string;
      contributor: string;
      summary: string;
      patch: string;
      created_at: number;
      co_authors_json: string | null;
    }>("SELECT * FROM accepted_patches WHERE mission_id = ? AND COALESCE(in_history, 1) = 1 ORDER BY seq ASC", "arklib-near-capacity-primes")
    .toArray();
  assert.equal(histRows.length, 1, "subgoal scratch proofs must stay out of history.mbox");
  assert.equal(histRows[0].task_id, "near_capacity_prime_supply");
  const mbox = renderMbox(
    histRows.map((r) => ({
      ...r,
      display_name: "Carol Closer",
      co_authors: parseStoredCoAuthors(r.co_authors_json),
    }))
  );
  assert.match(mbox, /Co-authored-by: Alice Architect <alice@contributors\.sunstead\.org>/);
  assert.match(mbox, /Co-authored-by: Bob Solver <bob@contributors\.sunstead\.org>/);

  // Public ledger (`/proofs`) contains all 3 records: 2 subgoals + 1 assembled proof!
  const allLedger = sql
    .exec<{ entry_kind: string; patch: string; patch_sha256: string; task_id: string; seq: number; mission_id: string; submission_id: string; contributor: string; summary: string; spec_sha256: string; created_at: number; decomp_meta_json: string | null; co_authors_json: string | null }>(
      "SELECT * FROM accepted_patches ORDER BY seq ASC"
    )
    .toArray();
  assert.deepEqual(
    allLedger.map((r) => r.entry_kind),
    ["subgoal", "subgoal", "assembled"]
  );
  const assembledLedgerEntry = buildLedgerEntry(
    { ...allLedger[2], display_name: "Carol Closer", github: null, verify_ms: 210 },
    { manifest: ctx.mission.manifest, spec_sha256: SPEC_SHA },
    "https://sunstead.org"
  );
  assert.equal(assembledLedgerEntry.entry_kind, "assembled");
  assert.equal(assembledLedgerEntry.co_authors?.length, 3);
});

test("subgoal refutation invalidates decomposition, forfeits architect share, strikes proposer, reopens parent, and pays bounty", async () => {
  const { sql, ctx, getTasks, sumPoints } = createTestHub();
  upsertAllowlistEntry(sql, { handle: "alice", active: true, added_by: "admin", note: "pilot", now: 100 });

  const redFile = "ArkLibNearCapacity/Decomp_bad_d1.lean";
  const dec = await executeDecompose(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "alice",
    rawBody: {
      decomp_id: "d1",
      subgoals: [
        { id: "false_sub", title: "Broken Lemma", statement: "0 = 1" },
        { id: "ok_sub", title: "Other Lemma", statement: "1 = 1" },
      ],
      reduction_file: redFile,
      reduction_theorem: "ArkLibNearCapacity.reduce_bad",
      patch: generateUnifiedDiff(redFile, null, "import ArkLibNearCapacity.Spec\n"),
    },
  });
  assert.equal(dec.status, 201);
  const falseSub = getTasks("arklib-near-capacity-primes").find((t) => t.def.subgoal_id === "false_sub")!;

  // Dave is NOT allowlisted — refutations are open to ALL registered contributors!
  assert.equal(isAllowlisted(sql, "dave"), false);
  const refFile = "ArkLibNearCapacity/RefuteFalseSub.lean";
  const refRes = await executeRefute(ctx, {
    taskId: falseSub.def.id,
    contributor: "dave",
    rawBody: {
      refute_file: refFile,
      refute_theorem: "ArkLibNearCapacity.refute_false_sub",
      patch: generateUnifiedDiff(refFile, null, "import ArkLibNearCapacity.Spec\ntheorem refute_false_sub : ¬ (0 = 1) := by decide\n"),
    },
  });
  assert.equal(refRes.status, 200);
  assert.equal(refRes.body.refuted, true);
  assert.equal(refRes.body.target_kind, "subgoal");
  assert.equal(refRes.body.invalidated_decomp_id, "d1");
  assert.equal(refRes.body.reopened_parent_task_id, "near_capacity_prime_supply");
  assert.equal(refRes.body.points_awarded, 75);

  // Dave gets 75-pt bounty, Alice stays at 0 pts with 1 strike, children retired, parent open!
  assert.equal(sumPoints("dave"), 75);
  assert.equal(sumPoints("alice"), 0);
  const aliceAllow = listAllowlist(sql).find((a) => a.handle === "alice")!;
  assert.equal(aliceAllow.strikes, 1);

  const tasksAfter = getTasks("arklib-near-capacity-primes");
  assert.equal(tasksAfter.length, 1, "all refuted child subgoals must be retired");
  assert.equal(tasksAfter[0].def.id, "near_capacity_prime_supply");
  assert.equal(tasksAfter[0].status, "open");

  const decomps = listMissionDecompositions(sql, "arklib-near-capacity-primes");
  assert.equal(decomps[0].status, "refuted");
  assert.equal(decomps[0].architect_vested, false);
  assert.equal(decomps[0].refuted_subgoal_id, "false_sub");

  // Permanent refutation recorded in /proofs (`entry_kind='refutation'`, `in_history=0`)!
  const refutations = listMissionRefutations(sql, "arklib-near-capacity-primes", "https://sunstead.org");
  assert.equal(refutations.length, 1);
  assert.equal(refutations[0].refuter, "dave");
  const histCount = sql.exec<{ c: number }>("SELECT COUNT(*) AS c FROM accepted_patches WHERE COALESCE(in_history, 1) = 1").one().c;
  assert.equal(histCount, 0, "refuted decomposition must not pollute history.mbox");
});

test("root task refutation flags disputed_counterexample without closing mission or task", async () => {
  const { sql, ctx, getTasks, sumPoints } = createTestHub();
  const refFile = "ArkLibNearCapacity/RefuteRoot.lean";
  const refRes = await executeRefute(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "dave",
    rawBody: {
      refute_file: refFile,
      refute_theorem: "ArkLibNearCapacity.refute_root",
      patch: generateUnifiedDiff(refFile, null, "-- counterexample\n"),
    },
  });
  assert.equal(refRes.status, 200);
  assert.equal(refRes.body.target_kind, "root");
  assert.equal(refRes.body.disputed_counterexample, true);
  assert.equal(sumPoints("dave"), 75);

  const root = getTasks("arklib-near-capacity-primes")[0];
  assert.equal(root.status, "open", "root task must remain open for maintainer upstream bug triage");
  assert.equal(root.disputed_counterexample?.refuter, "dave");
  assert.ok(root.disputed_counterexample?.proof_id);
  assert.deepEqual(
    computeFrontier("dag", getTasks("arklib-near-capacity-primes")),
    [],
    "disputed root task must be removed from the open frontier"
  );
  assert.throws(
    () =>
      applyClaim(
        "dag",
        getTasks("arklib-near-capacity-primes"),
        "near_capacity_prime_supply",
        "alice",
        "tok",
        1700000100,
        1800
      ),
    /counterexample.*cannot be claimed/
  );
});

test("direct parent bypass forfeits unvested architect share and retires open child subgoals", async () => {
  const { sql, ctx, getTasks, sumPoints } = createTestHub();
  upsertAllowlistEntry(sql, { handle: "alice", active: true, added_by: "admin", note: "pilot", now: 100 });

  const redFile = "ArkLibNearCapacity/Decomp_bypass_d1.lean";
  const dec = await executeDecompose(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "alice",
    rawBody: {
      decomp_id: "d1",
      subgoals: [
        { id: "sub_x", title: "X", statement: "1 = 1" },
        { id: "sub_y", title: "Y", statement: "2 = 2" },
      ],
      reduction_file: redFile,
      reduction_theorem: "ArkLibNearCapacity.reduce_xy",
      patch: generateUnifiedDiff(redFile, null, "import ArkLibNearCapacity.Spec\n"),
    },
  });
  assert.equal(dec.status, 201);
  assert.equal(getTasks("arklib-near-capacity-primes").length, 3);

  const bypassed = handleDirectParentBypass(sql, "arklib-near-capacity-primes", "near_capacity_prime_supply", 1700000500);
  assert.deepEqual(bypassed, ["d1"]);
  assert.equal(getTasks("arklib-near-capacity-primes").length, 1, "open child subgoals retired on direct bypass");
  assert.equal(listMissionDecompositions(sql, "arklib-near-capacity-primes")[0].status, "bypassed");
  assert.equal(listMissionDecompositions(sql, "arklib-near-capacity-primes")[0].architect_vested, false);
  assert.equal(sumPoints("alice"), 0, "architect share forfeited on direct bypass");
});

test("depth-2 nested decomposition cascades assembly upward and obeys max depth 2 and zero point inflation", async () => {
  const { sql, ctx, getTasks, sumPoints, insertVerifyingSub, verifierCalls } = createTestHub();
  upsertAllowlistEntry(sql, { handle: "alice", active: true, added_by: "admin", note: "pilot", now: 100 });

  // Depth 1: root -> l1, l2 (150 pts -> architect 30, 60/subgoal)
  const d1 = await executeDecompose(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "alice",
    rawBody: {
      decomp_id: "d1",
      subgoals: [
        { id: "l1", title: "L1", statement: "1 = 1" },
        { id: "l2", title: "L2", statement: "2 = 2" },
      ],
      reduction_file: "ArkLibNearCapacity/Decomp_d1.lean",
      reduction_theorem: "ArkLibNearCapacity.red_d1",
      patch: generateUnifiedDiff("ArkLibNearCapacity/Decomp_d1.lean", null, "import ArkLibNearCapacity.Spec\n"),
    },
  });
  assert.equal(d1.status, 201);
  const l1 = getTasks("arklib-near-capacity-primes").find((t) => t.def.subgoal_id === "l1")!;
  const l2 = getTasks("arklib-near-capacity-primes").find((t) => t.def.subgoal_id === "l2")!;

  // Depth 2: l1 -> a, b (60 pts -> architect 12, 24/subgoal)
  const d2 = await executeDecompose(ctx, {
    taskId: l1.def.id,
    contributor: "alice",
    rawBody: {
      decomp_id: "d2",
      subgoals: [
        { id: "sub_a", title: "A", statement: "3 = 3" },
        { id: "sub_b", title: "B", statement: "4 = 4" },
      ],
      reduction_file: "ArkLibNearCapacity/Decomp_d2.lean",
      reduction_theorem: "ArkLibNearCapacity.red_d2",
      patch: generateUnifiedDiff("ArkLibNearCapacity/Decomp_d2.lean", null, "import ArkLibNearCapacity.Spec\n"),
    },
  });
  assert.equal(d2.status, 201);
  assert.equal(d2.body.depth, 2);

  const subA = getTasks("arklib-near-capacity-primes").find((t) => t.def.subgoal_id === "sub_a")!;
  const subB = getTasks("arklib-near-capacity-primes").find((t) => t.def.subgoal_id === "sub_b")!;

  // Depth 3 must be rejected!
  const d3 = await executeDecompose(ctx, {
    taskId: subA.def.id,
    contributor: "alice",
    rawBody: {
      decomp_id: "d3",
      subgoals: [
        { id: "x1", title: "X1", statement: "5 = 5" },
        { id: "x2", title: "X2", statement: "6 = 6" },
      ],
      reduction_file: "ArkLibNearCapacity/Decomp_d3.lean",
      reduction_theorem: "ArkLibNearCapacity.red_d3",
      patch: generateUnifiedDiff("ArkLibNearCapacity/Decomp_d3.lean", null, "import ArkLibNearCapacity.Spec\n"),
    },
  });
  assert.equal(d3.status, 400);
  assert.match(String(d3.body.error), /depth limit/);

  // Solve sub_a, sub_b -> auto-assembles l1 via /subgoal; then solve l2 -> auto-assembles root via /verify!
  for (const [id, taskObj, solver] of [
    ["s-a", subA, "bob"],
    ["s-b", subB, "bob"],
    ["s-l2", l2, "carol"],
  ] as const) {
    const f = taskObj.def.target_files[0];
    const p = generateUnifiedDiff(f, null, `import ArkLibNearCapacity.Spec\ntheorem p : True := trivial\n`);
    insertVerifyingSub(id, taskObj.def.id, solver, `sha256:${id}`);
    const r = await executeSubgoalSubmit(ctx, { subId: id, task: taskObj, contributor: solver, patch: p, patchSha: `sha256:${id}` });
    assert.equal(r.status, 200);
  }

  // Verify final untouched `/verify` ran and total points <= 150 (Alice 12+30=42, Bob 24+24=48, Carol 60 => 150!).
  assert.equal(verifierCalls[verifierCalls.length - 1].path, "/verify");
  assert.equal(sumPoints("alice"), 42);
  assert.equal(sumPoints("bob"), 48);
  assert.equal(sumPoints("carol"), 60);
  assert.equal(sumPoints("alice") + sumPoints("bob") + sumPoints("carol"), 150);
  assert.equal(getTasks("arklib-near-capacity-primes").find((t) => t.def.id === "near_capacity_prime_supply")!.status, "verified");
});

test("anti-gaming: self-refutation pays 0 bounty and duplicate root refutation is rejected with 409", async () => {
  const { sql, ctx, getTasks, sumPoints } = createTestHub();
  upsertAllowlistEntry(sql, { handle: "alice", active: true, added_by: "admin", note: "pilot", now: 100 });

  // 1. Alice proposes a split and then refutes her own false subgoal -> split invalidated + strike, but 0 pts!
  const dec = await executeDecompose(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "alice",
    rawBody: {
      decomp_id: "d_self",
      subgoals: [
        { id: "bad_self", title: "Bad Self", statement: "0 = 1" },
        { id: "ok_other", title: "Other", statement: "2 = 2" },
      ],
      reduction_file: "ArkLibNearCapacity/Decomp_self.lean",
      reduction_theorem: "ArkLibNearCapacity.red_self",
      patch: generateUnifiedDiff("ArkLibNearCapacity/Decomp_self.lean", null, "import ArkLibNearCapacity.Spec\n"),
    },
  });
  assert.equal(dec.status, 201);
  const badSub = getTasks("arklib-near-capacity-primes").find((t) => t.def.subgoal_id === "bad_self")!;

  const selfRef = await executeRefute(ctx, {
    taskId: badSub.def.id,
    contributor: "alice",
    rawBody: {
      refute_file: "ArkLibNearCapacity/RefuteSelf.lean",
      refute_theorem: "ArkLibNearCapacity.refute_self",
      patch: generateUnifiedDiff("ArkLibNearCapacity/RefuteSelf.lean", null, "import ArkLibNearCapacity.Spec\n"),
    },
  });
  assert.equal(selfRef.status, 200);
  assert.equal(selfRef.body.refuted, true);
  assert.equal(selfRef.body.points_awarded, 0, "self-refutation must award 0 bounty points");
  assert.equal(sumPoints("alice"), 0);
  assert.equal(listAllowlist(sql).find((a) => a.handle === "alice")?.strikes, 1);

  // 2. Bob refutes the root task -> succeeds once (+75 pts); second root refutation -> 409 Conflict!
  const rootRef1 = await executeRefute(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "bob",
    rawBody: {
      refute_file: "ArkLibNearCapacity/RefuteRoot1.lean",
      refute_theorem: "ArkLibNearCapacity.refute_root1",
      patch: generateUnifiedDiff("ArkLibNearCapacity/RefuteRoot1.lean", null, "import ArkLibNearCapacity.Spec\n"),
    },
  });
  assert.equal(rootRef1.status, 200);
  assert.equal(rootRef1.body.points_awarded, 75);
  assert.equal(sumPoints("bob"), 75);

  const rootRef2 = await executeRefute(ctx, {
    taskId: "near_capacity_prime_supply",
    contributor: "bob",
    rawBody: {
      refute_file: "ArkLibNearCapacity/RefuteRoot2.lean",
      refute_theorem: "ArkLibNearCapacity.refute_root2",
      patch: generateUnifiedDiff("ArkLibNearCapacity/RefuteRoot2.lean", null, "import ArkLibNearCapacity.Spec\n"),
    },
  });
  assert.equal(rootRef2.status, 409);
  assert.match(String(rootRef2.body.error), /already has a kernel-verified counterexample/);
  assert.equal(sumPoints("bob"), 75, "duplicate root refutation must not farm additional bounty");
});

test("async refute updates pre-inserted verifying submission row on accepted, rejected, and sandbox error", async () => {
  // 1. Accepted path with existingSubmissionId + upstream_disputed root task still allowed to upgrade to kernel counterexample!
  {
    const { sql, ctx, getTasks, insertVerifyingSub } = createTestHub();
    // Mark root task upstream_disputed in def_json; frontier excludes it, but kernel refutation is still allowed!
    const rootBefore = getTasks("arklib-near-capacity-primes")[0];
    const updatedDef = {
      ...rootBefore.def,
      upstream_disputed: {
        source: "upstream",
        reason: "known false upstream",
        url: "https://github.com/teorth/IEANTN/issues/268",
        recorded_at: "2026-11-26",
      },
    };
    sql.exec(
      "UPDATE tasks SET def_json = ? WHERE mission_id = ? AND task_id = ?",
      JSON.stringify(updatedDef),
      "arklib-near-capacity-primes",
      "near_capacity_prime_supply"
    );
    assert.deepEqual(computeFrontier("dag", getTasks("arklib-near-capacity-primes")), []);

    const refPatch = generateUnifiedDiff(
      "ArkLibNearCapacity/RefuteAsync.lean",
      null,
      "import ArkLibNearCapacity.Spec\n"
    );
    const body = {
      refute_file: "ArkLibNearCapacity/RefuteAsync.lean",
      refute_theorem: "ArkLibNearCapacity.refute_async",
      patch: refPatch,
    };
    const prep = prepareRefute(ctx, { taskId: "near_capacity_prime_supply", rawBody: body });
    assert.equal(prep.ok, true, "upstream-disputed root task must still allow kernel-verified refutation");

    const subId = "sub-async-refute-ok";
    insertVerifyingSub(subId, "near_capacity_prime_supply", "dave", "sha256:" + "1".repeat(64));
    const res = await executeRefute(ctx, {
      taskId: "near_capacity_prime_supply",
      contributor: "dave",
      rawBody: body,
      existingSubmissionId: subId,
      createdAt: 1700000010,
      prepared: prep.ok ? prep.prepared : undefined,
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.submission_id, subId);

    const row = sql
      .exec<SubmissionStatusRow>(
        `SELECT id, mission_id, task_id, contributor, status, accepted, score, points,
                summary, patch_sha256, proof_id, verify_ms, stage, diagnostics, error,
                unlocked_dependents_json, created_at, completed_at
         FROM submissions WHERE id = ?`,
        subId
      )
      .one();
    const view = formatSubmissionStatusView(row, "https://sunstead.org");
    assert.equal(view.status, "accepted");
    assert.equal(view.accepted, true);
    assert.equal(view.points_awarded, 75);
    assert.ok(view.proof_id);
    assert.ok(view.permalink?.includes(view.proof_id!));
    assert.ok(view.completed_at !== null);
  }

  // 2. Rejected verification updates verifying submission row to status='rejected' with diagnostics.
  {
    const { sql, ctx, insertVerifyingSub } = createTestHub();
    ctx.callVerifierAction = async () => ({
      ok: true,
      res: {
        ok: false,
        summary: "refute theorem type mismatch",
        spec_sha256: ctx.mission.spec_sha256,
        verify_ms: 42,
        stage: "kernel",
        diagnostics: "expected ¬ T",
      },
    });
    const subId = "sub-async-refute-rej";
    insertVerifyingSub(subId, "near_capacity_prime_supply", "dave", "sha256:" + "2".repeat(64));
    const res = await executeRefute(ctx, {
      taskId: "near_capacity_prime_supply",
      contributor: "dave",
      rawBody: {
        refute_file: "ArkLibNearCapacity/RefuteBad.lean",
        refute_theorem: "ArkLibNearCapacity.refute_bad",
        patch: generateUnifiedDiff("ArkLibNearCapacity/RefuteBad.lean", null, "-- bad\n"),
      },
      existingSubmissionId: subId,
    });
    assert.equal(res.status, 422);
    const row = sql
      .exec<SubmissionStatusRow>(
        `SELECT id, mission_id, task_id, contributor, status, accepted, score, points,
                summary, patch_sha256, proof_id, verify_ms, stage, diagnostics, error,
                unlocked_dependents_json, created_at, completed_at
         FROM submissions WHERE id = ?`,
        subId
      )
      .one();
    const view = formatSubmissionStatusView(row, "https://sunstead.org");
    assert.equal(view.status, "rejected");
    assert.equal(view.accepted, false);
    assert.equal(view.stage, "kernel");
    assert.equal(view.diagnostics, "expected ¬ T");
  }

  // 3. Container failure updates verifying submission row to status='error' (never stuck in verifying).
  {
    const { sql, ctx, insertVerifyingSub } = createTestHub();
    ctx.callVerifierAction = async () => ({
      ok: false,
      status: 503,
      error: "verifier container unavailable",
    });
    const subId = "sub-async-refute-err";
    insertVerifyingSub(subId, "near_capacity_prime_supply", "dave", "sha256:" + "3".repeat(64));
    const res = await executeRefute(ctx, {
      taskId: "near_capacity_prime_supply",
      contributor: "dave",
      rawBody: {
        refute_file: "ArkLibNearCapacity/RefuteErr.lean",
        refute_theorem: "ArkLibNearCapacity.refute_err",
        patch: generateUnifiedDiff("ArkLibNearCapacity/RefuteErr.lean", null, "-- err\n"),
      },
      existingSubmissionId: subId,
    });
    assert.equal(res.status, 503);
    const row = sql
      .exec<SubmissionStatusRow>(
        `SELECT id, mission_id, task_id, contributor, status, accepted, score, points,
                summary, patch_sha256, proof_id, verify_ms, stage, diagnostics, error,
                unlocked_dependents_json, created_at, completed_at
         FROM submissions WHERE id = ?`,
        subId
      )
      .one();
    const view = formatSubmissionStatusView(row, "https://sunstead.org");
    assert.equal(view.status, "error");
    assert.equal(view.accepted, false);
    assert.equal(view.stage, "sandbox");
    assert.equal(view.error, "verifier container unavailable");
  }
});
