/**
 * v2 Theorem Decomposition & Kernel-Verified Refutations (docs/RFC-DECOMPOSE.md).
 *
 * Isolates all SQLite queries, allowlist checks, zero-inflation economics,
 * automatic untouched `./verify <T>` assembly, direct parent bypass, and
 * refutation teardown behind a lightweight `SqlLike` interface so the full
 * state machine is directly testable in Node with `node:sqlite`.
 */
import {
  applyVerdict,
  assembleDecomposedLeanFile,
  buildSubgoalStubSource,
  buildSubgoalTaskId,
  checkDecompositionEligibility,
  computeDecompPointSplit,
  computeOpenConjectureRefutePoints,
  computePoints,
  computeRefutationBounty,
  extractPropStatementExpr,
  generateUnifiedDiff,
  isOpenConjectureTask,
  isTaskUnlocked,
  parseDecomposeRequest,
  parseRefuteRequest,
  proofIdFromPatchSha,
  sanitizeFailureDiagnostics,
  validatePatch,
  type AssembledProofNode,
  type CoAuthor,
  type DecompositionStatus,
  type DisputedCounterexample,
  type FailureStage,
  type MissionManifest,
  type MissionVerifyContract,
  type RefutedResolution,
  type SubgoalSpec,
  type TaskDefinition,
  type TaskState,
} from "./core.ts";

export type SqlLike = Pick<SqlStorage, "exec">;

export interface VerifierActionResponse {
  ok: boolean;
  score?: number | null;
  summary: string;
  stage?: FailureStage;
  diagnostics?: string;
  spec_sha256: string;
  updated_files?: Record<string, string>;
  normalized_patch?: string;
  verify_ms: number;
  decomp_statements_module?: string;
  decomp_statements_namespace?: string;
  decomp_statements_source?: string;
  subgoal_spec_sha256s?: Record<string, string>;
}

export type AllowlistRow = {
  handle: string;
  active: number;
  added_by: string;
  note: string | null;
  strikes: number;
  created_at: number;
  updated_at: number;
};

export type DecompositionRow = {
  decomp_id: string;
  mission_id: string;
  root_task_id: string;
  parent_task_id: string;
  parent_decomp_id: string | null;
  depth: number;
  proposer: string;
  status: DecompositionStatus;
  subgoals_json: string;
  decomp_statements_module: string;
  decomp_statements_namespace: string;
  decomp_statements_source: string;
  reduction_file: string;
  reduction_module: string;
  reduction_theorem: string;
  reduction_source: string;
  reduction_patch: string;
  reduction_sha256: string;
  parent_points: number;
  solver_points_per_subgoal: number;
  architect_points: number;
  architect_vested: number;
  refuted_subgoal_id: string | null;
  refutation_id: string | null;
  created_at: number;
  closed_at: number | null;
};

export type RefutationRow = {
  id: string;
  mission_id: string;
  task_id: string;
  root_task_id: string;
  decomp_id: string | null;
  subgoal_id: string | null;
  target_kind: "subgoal" | "root";
  refuter: string;
  summary: string;
  patch: string;
  patch_sha256: string;
  spec_sha256: string;
  points: number;
  verify_ms: number;
  created_at: number;
  is_demo: number;
  resolves_conjecture?: number;
};

export interface DecomposeHubContext {
  sql: SqlLike;
  scoringProvenanceJson: string;
  mission: {
    manifest: MissionManifest;
    spec_sha256: string;
    seed_files?: Record<string, string>;
    verify_contract?: MissionVerifyContract;
  };
  hubOrigin: string;
  now: () => number;
  sha256Hex: (text: string) => Promise<string>;
  randomUUID: () => string;
  getTasks: (missionId: string) => TaskState[];
  getMissionFiles: (missionId: string) => Record<string, string>;
  withMissionLock: <T>(missionId: string, fn: () => Promise<T>) => Promise<T>;
  callVerifierAction: (
    path: "/verify" | "/decompose" | "/subgoal" | "/refute",
    files: Record<string, string>,
    body: Record<string, unknown>
  ) => Promise<{ ok: true; res: VerifierActionResponse } | { ok: false; status: number; error: string }>;
  emit: (ev: {
    kind: string;
    mission_id: string;
    task_id: string | null;
    contributor: string | null;
    accepted: boolean | null;
    score: number | null;
    summary: string;
    timestamp: number;
    submission_id?: string | null;
  }) => void;
}

export function initDecomposeSchema(
  sql: SqlLike,
  ensureColumn: (table: string, col: string, colDef: string) => void
): void {
  sql.exec(`
    CREATE TABLE IF NOT EXISTS decomposition_allowlist (
      handle TEXT PRIMARY KEY,
      active INTEGER NOT NULL DEFAULT 1,
      added_by TEXT NOT NULL,
      note TEXT,
      strikes INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS decompositions (
      decomp_id TEXT NOT NULL,
      mission_id TEXT NOT NULL,
      root_task_id TEXT NOT NULL,
      parent_task_id TEXT NOT NULL,
      parent_decomp_id TEXT,
      depth INTEGER NOT NULL DEFAULT 1,
      proposer TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      subgoals_json TEXT NOT NULL,
      decomp_statements_module TEXT NOT NULL,
      decomp_statements_namespace TEXT NOT NULL,
      decomp_statements_source TEXT NOT NULL,
      reduction_file TEXT NOT NULL,
      reduction_module TEXT NOT NULL,
      reduction_theorem TEXT NOT NULL,
      reduction_source TEXT NOT NULL,
      reduction_patch TEXT NOT NULL,
      reduction_sha256 TEXT NOT NULL,
      parent_points INTEGER NOT NULL DEFAULT 0,
      solver_points_per_subgoal INTEGER NOT NULL DEFAULT 0,
      architect_points INTEGER NOT NULL DEFAULT 0,
      architect_vested INTEGER NOT NULL DEFAULT 0,
      refuted_subgoal_id TEXT,
      refutation_id TEXT,
      created_at INTEGER NOT NULL,
      closed_at INTEGER,
      PRIMARY KEY (mission_id, root_task_id, decomp_id)
    );

    CREATE TABLE IF NOT EXISTS decomp_subgoal_proofs (
      mission_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      decomp_id TEXT NOT NULL,
      root_task_id TEXT NOT NULL,
      subgoal_id TEXT NOT NULL,
      contributor TEXT NOT NULL,
      source TEXT NOT NULL,
      patch TEXT NOT NULL,
      patch_sha256 TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (mission_id, task_id)
    );

    CREATE TABLE IF NOT EXISTS refutations (
      id TEXT PRIMARY KEY,
      mission_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      root_task_id TEXT NOT NULL,
      decomp_id TEXT,
      subgoal_id TEXT,
      target_kind TEXT NOT NULL,
      refuter TEXT NOT NULL,
      summary TEXT NOT NULL,
      patch TEXT NOT NULL,
      patch_sha256 TEXT NOT NULL,
      spec_sha256 TEXT NOT NULL,
      points INTEGER NOT NULL DEFAULT 0,
      verify_ms INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      is_demo INTEGER NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_decompositions_parent
      ON decompositions(mission_id, parent_task_id, status);
    CREATE INDEX IF NOT EXISTS idx_decompositions_proposer
      ON decompositions(proposer, status);
    CREATE INDEX IF NOT EXISTS idx_refutations_mission
      ON refutations(mission_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_refutations_sha
      ON refutations(patch_sha256);
  `);

  ensureColumn("tasks", "is_dynamic", "INTEGER NOT NULL DEFAULT 0");
  ensureColumn("tasks", "parent_task_id", "TEXT");
  ensureColumn("tasks", "root_task_id", "TEXT");
  ensureColumn("tasks", "decomp_id", "TEXT");
  ensureColumn("tasks", "subgoal_id", "TEXT");
  ensureColumn("tasks", "decomp_depth", "INTEGER NOT NULL DEFAULT 0");
  ensureColumn("tasks", "subgoal_spec_sha256", "TEXT");
  ensureColumn("tasks", "retired", "INTEGER NOT NULL DEFAULT 0");

  ensureColumn("accepted_patches", "entry_kind", "TEXT NOT NULL DEFAULT 'proof'");
  ensureColumn("accepted_patches", "in_history", "INTEGER NOT NULL DEFAULT 1");
  ensureColumn("accepted_patches", "co_authors_json", "TEXT");
  ensureColumn("accepted_patches", "decomp_meta_json", "TEXT");

  ensureColumn("submissions", "kind", "TEXT NOT NULL DEFAULT 'submit'");
  ensureColumn("refutations", "resolves_conjecture", "INTEGER NOT NULL DEFAULT 0");
}

// ---------------------------------------------------------------------------
// Allowlist helpers

export function listAllowlist(sql: SqlLike): Array<{
  handle: string;
  active: boolean;
  added_by: string;
  note: string | null;
  strikes: number;
  created_at: number;
  updated_at: number;
}> {
  return sql
    .exec<AllowlistRow>(
      "SELECT handle, active, added_by, note, strikes, created_at, updated_at FROM decomposition_allowlist ORDER BY handle ASC"
    )
    .toArray()
    .map((r) => ({
      ...r,
      active: r.active !== 0,
    }));
}

export function isAllowlisted(sql: SqlLike, handle: string): boolean {
  const rows = sql
    .exec<{ active: number }>(
      "SELECT active FROM decomposition_allowlist WHERE handle = ? LIMIT 1",
      handle
    )
    .toArray();
  return rows.length > 0 && rows[0].active !== 0;
}

export function upsertAllowlistEntry(
  sql: SqlLike,
  opts: {
    handle: string;
    active: boolean;
    added_by: string;
    note: string | null;
    reset_strikes?: boolean;
    now: number;
  }
) {
  sql.exec(
    `INSERT INTO decomposition_allowlist (handle, active, added_by, note, strikes, created_at, updated_at)
     VALUES (?, ?, ?, ?, 0, ?, ?)
     ON CONFLICT(handle) DO UPDATE SET
       active = excluded.active,
       added_by = excluded.added_by,
       note = COALESCE(excluded.note, decomposition_allowlist.note),
       strikes = CASE WHEN ? = 1 THEN 0 ELSE decomposition_allowlist.strikes END,
       updated_at = excluded.updated_at`,
    opts.handle,
    opts.active ? 1 : 0,
    opts.added_by,
    opts.note,
    opts.now,
    opts.now,
    opts.reset_strikes ? 1 : 0
  );
  const row = sql
    .exec<AllowlistRow>(
      "SELECT handle, active, added_by, note, strikes, created_at, updated_at FROM decomposition_allowlist WHERE handle = ?",
      opts.handle
    )
    .one();
  return { ...row, active: row.active !== 0 };
}

export function deactivateAllowlistEntry(sql: SqlLike, handle: string, now: number): boolean {
  const existing = sql
    .exec<{ handle: string }>("SELECT handle FROM decomposition_allowlist WHERE handle = ?", handle)
    .toArray();
  if (existing.length === 0) return false;
  sql.exec(
    "UPDATE decomposition_allowlist SET active = 0, updated_at = ? WHERE handle = ?",
    now,
    handle
  );
  return true;
}

// ---------------------------------------------------------------------------
// Read helpers for mission detail, task files, and refutation badges

export function parseSubgoalsJson(raw: string): SubgoalSpec[] {
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as SubgoalSpec[]) : [];
  } catch {
    return [];
  }
}

export function getDecompositionRow(
  sql: SqlLike,
  missionId: string,
  rootTaskId: string,
  decompId: string
): DecompositionRow | null {
  const rows = sql
    .exec<DecompositionRow>(
      `SELECT * FROM decompositions WHERE mission_id = ? AND root_task_id = ? AND decomp_id = ? LIMIT 1`,
      missionId,
      rootTaskId,
      decompId
    )
    .toArray();
  return rows.length > 0 ? rows[0] : null;
}

export function listMissionDecompositions(sql: SqlLike, missionId: string) {
  const rows = sql
    .exec<DecompositionRow>(
      "SELECT * FROM decompositions WHERE mission_id = ? ORDER BY created_at DESC",
      missionId
    )
    .toArray();
  return rows.map((r) => {
    const subgoals = parseSubgoalsJson(r.subgoals_json);
    const verifiedCount = sql
      .exec<{ c: number }>(
        `SELECT COUNT(*) AS c FROM tasks
         WHERE mission_id = ? AND parent_task_id = ? AND decomp_id = ? AND status = 'verified'`,
        missionId,
        r.parent_task_id,
        r.decomp_id
      )
      .one().c;
    return {
      decomp_id: r.decomp_id,
      mission_id: r.mission_id,
      root_task_id: r.root_task_id,
      parent_task_id: r.parent_task_id,
      parent_decomp_id: r.parent_decomp_id,
      depth: r.depth,
      proposer: r.proposer,
      status: r.status,
      subgoals,
      verified_subgoals: verifiedCount,
      total_subgoals: subgoals.length,
      decomp_statements_module: r.decomp_statements_module,
      decomp_statements_namespace: r.decomp_statements_namespace,
      reduction_file: r.reduction_file,
      reduction_module: r.reduction_module,
      reduction_theorem: r.reduction_theorem,
      reduction_sha256: r.reduction_sha256,
      parent_points: r.parent_points,
      solver_points_per_subgoal: r.solver_points_per_subgoal,
      architect_points: r.architect_points,
      architect_vested: r.architect_vested !== 0,
      refuted_subgoal_id: r.refuted_subgoal_id,
      refutation_id: r.refutation_id,
      created_at: r.created_at,
      closed_at: r.closed_at,
    };
  });
}

export function listMissionRefutations(sql: SqlLike, missionId: string, hubOrigin: string) {
  return sql
    .exec<RefutationRow>(
      "SELECT * FROM refutations WHERE mission_id = ? ORDER BY created_at DESC LIMIT 30",
      missionId
    )
    .toArray()
    .map((r) => {
      const pid = proofIdFromPatchSha(r.patch_sha256);
      return {
        refutation_id: r.id,
        mission_id: r.mission_id,
        task_id: r.task_id,
        root_task_id: r.root_task_id,
        decomp_id: r.decomp_id,
        subgoal_id: r.subgoal_id,
        target_kind: r.target_kind,
        resolves_conjecture: Boolean(r.resolves_conjecture),
        refuter: r.refuter,
        summary: r.summary,
        patch_sha256: r.patch_sha256,
        proof_id: pid,
        permalink: `${hubOrigin}/proofs/${pid}`,
        points_awarded: r.points,
        verify_ms: r.verify_ms,
        created_at: r.created_at,
      };
    });
}

export function getDisputedRootMap(sql: SqlLike, missionId: string): Map<string, DisputedCounterexample> {
  const rows = sql
    .exec<RefutationRow>(
      `SELECT * FROM refutations
       WHERE mission_id = ? AND target_kind = 'root' AND COALESCE(resolves_conjecture, 0) = 0
       ORDER BY created_at DESC`,
      missionId
    )
    .toArray();
  const map = new Map<string, DisputedCounterexample>();
  for (const r of rows) {
    if (!map.has(r.task_id)) {
      map.set(r.task_id, {
        refutation_id: r.id,
        refuter: r.refuter,
        proof_id: proofIdFromPatchSha(r.patch_sha256),
        summary: r.summary,
        created_at: r.created_at,
      });
    }
  }
  return map;
}

export function getResolvedRefutationMap(sql: SqlLike, missionId: string): Map<string, RefutedResolution> {
  const rows = sql
    .exec<RefutationRow>(
      `SELECT * FROM refutations
       WHERE mission_id = ? AND target_kind = 'root' AND COALESCE(resolves_conjecture, 0) = 1
       ORDER BY created_at DESC`,
      missionId
    )
    .toArray();
  const map = new Map<string, RefutedResolution>();
  for (const r of rows) {
    if (!map.has(r.task_id)) {
      map.set(r.task_id, {
        refutation_id: r.id,
        refuter: r.refuter,
        proof_id: proofIdFromPatchSha(r.patch_sha256),
        summary: r.summary,
        created_at: r.created_at,
      });
    }
  }
  return map;
}

/** Batch-load all root refutations grouped by mission_id (eliminates N+1 queries at 50+ missions). */
export function getAllRootRefutationMaps(sql: SqlLike): {
  disputedByMission: Map<string, Map<string, DisputedCounterexample>>;
  resolvedByMission: Map<string, Map<string, RefutedResolution>>;
} {
  const rows = sql
    .exec<RefutationRow>(
      `SELECT * FROM refutations
       WHERE target_kind = 'root'
       ORDER BY created_at DESC`
    )
    .toArray();
  const disputedByMission = new Map<string, Map<string, DisputedCounterexample>>();
  const resolvedByMission = new Map<string, Map<string, RefutedResolution>>();
  for (const r of rows) {
    const entry = {
      refutation_id: r.id,
      refuter: r.refuter,
      proof_id: proofIdFromPatchSha(r.patch_sha256),
      summary: r.summary,
      created_at: r.created_at,
    };
    const bucket = r.resolves_conjecture ? resolvedByMission : disputedByMission;
    let m = bucket.get(r.mission_id);
    if (!m) {
      m = new Map();
      bucket.set(r.mission_id, m);
    }
    if (!m.has(r.task_id)) {
      m.set(r.task_id, entry);
    }
  }
  return { disputedByMission, resolvedByMission };
}

export function enrichTaskFilesWithDecomp(
  sql: SqlLike,
  opts: {
    missionId: string;
    task: TaskState;
    baseView: Record<string, unknown>;
    verifyContract?: MissionVerifyContract;
  }
): Record<string, unknown> {
  const { missionId, task, baseView, verifyContract } = opts;
  const decompId = task.def.decomp_id;
  const rootTaskId = task.def.root_task_id;
  if (!decompId || !rootTaskId || !task.def.subgoal_id) {
    // Root task: attach active decomposition summary if one exists.
    const active = sql
      .exec<DecompositionRow>(
        `SELECT * FROM decompositions WHERE mission_id = ? AND parent_task_id = ? AND status = 'active' LIMIT 1`,
        missionId,
        task.def.id
      )
      .toArray();
    if (active.length === 0) return baseView;
    const d = active[0];
    return {
      ...baseView,
      active_decomposition: {
        decomp_id: d.decomp_id,
        proposer: d.proposer,
        depth: d.depth,
        reduction_file: d.reduction_file,
        reduction_sha256: d.reduction_sha256,
        decomp_statements_module: d.decomp_statements_module,
        subgoals: parseSubgoalsJson(d.subgoals_json),
      },
    };
  }

  const decomp = getDecompositionRow(sql, missionId, rootTaskId, decompId);
  if (!decomp) return baseView;
  const subgoals = parseSubgoalsJson(decomp.subgoals_json);
  const sub = subgoals.find((s) => s.id === task.def.subgoal_id);
  if (!sub) return baseView;

  const proofRows = sql
    .exec<{ source: string }>(
      "SELECT source FROM decomp_subgoal_proofs WHERE mission_id = ? AND task_id = ? LIMIT 1",
      missionId,
      task.def.id
    )
    .toArray();
  const libRoot = verifyContract?.lib_root ?? sub.target_file.split("/")[0];
  const stubSource =
    proofRows.length > 0
      ? proofRows[0].source
      : buildSubgoalStubSource({
          libRoot,
          decompStatementsModule: decomp.decomp_statements_module,
          decompStatementsNamespace: decomp.decomp_statements_namespace,
          subgoalId: sub.id,
          subgoalTitle: sub.title,
          subgoalTheorem: sub.subgoal_theorem,
          statementPreamble: verifyContract?.statement_preamble,
        });

  const decompStmtsRel = decomp.decomp_statements_module.replace(/\./g, "/") + ".lean";
  const targetFiles = {
    ...((baseView.target_files as Record<string, string>) || {}),
    [sub.target_file]: stubSource,
  };
  const frozenFiles = {
    ...((baseView.frozen_files as Record<string, string>) || {}),
    [decompStmtsRel]: decomp.decomp_statements_source,
    [decomp.reduction_file]: decomp.reduction_source,
  };

  return {
    ...baseView,
    spec_sha256: sub.subgoal_spec_sha256,
    target_files: targetFiles,
    frozen_files: frozenFiles,
    decomposition: {
      decomp_id: decomp.decomp_id,
      parent_task_id: decomp.parent_task_id,
      root_task_id: decomp.root_task_id,
      depth: decomp.depth,
      proposer: decomp.proposer,
      status: decomp.status,
      subgoal_id: sub.id,
      subgoal_title: sub.title,
      subgoal_statement: sub.statement,
      subgoal_spec_sha256: sub.subgoal_spec_sha256,
      subgoal_module: sub.subgoal_module,
      subgoal_theorem: sub.subgoal_theorem,
      decomp_statements_module: decomp.decomp_statements_module,
      decomp_statements_namespace: decomp.decomp_statements_namespace,
      reduction_file: decomp.reduction_file,
      reduction_sha256: decomp.reduction_sha256,
      solver_points: decomp.solver_points_per_subgoal,
    },
  };
}

// ---------------------------------------------------------------------------
// 1. POST /api/missions/:id/tasks/:task/decompose

function lookupContributorDisplayName(sql: SqlLike, handle: string): string {
  const rows = sql
    .exec<{ display_name: string }>("SELECT display_name FROM contributors WHERE handle = ? LIMIT 1", handle)
    .toArray();
  return rows.length > 0 && rows[0].display_name ? rows[0].display_name : handle;
}

function resolveTaskPointValue(
  sql: SqlLike,
  manifest: MissionManifest,
  task: TaskState
): number {
  if (manifest.demo) return 0;
  if (task.def.decomp_id && task.def.root_task_id) {
    const parentDecomp = getDecompositionRow(
      sql,
      manifest.id,
      task.def.root_task_id,
      task.def.decomp_id
    );
    if (parentDecomp) return parentDecomp.solver_points_per_subgoal;
  }
  return computePoints(manifest, task, task.best_score, 1.0);
}

export async function executeDecompose(
  ctx: DecomposeHubContext,
  params: {
    taskId: string;
    contributor: string;
    rawBody: unknown;
  }
): Promise<{ status: number; body: Record<string, unknown> }> {
  const { sql, mission } = ctx;
  const missionId = mission.manifest.id;
  const { taskId, contributor, rawBody } = params;

  const tasks = ctx.getTasks(missionId);
  const task = tasks.find((t) => t.def.id === taskId);
  if (!task) {
    return { status: 404, body: { error: `unknown task: ${taskId}` } };
  }

  const contract = mission.verify_contract;
  if (!contract) {
    return {
      status: 400,
      body: { error: `mission '${missionId}' does not expose a classic Lean verifier contract for decomposition` },
    };
  }

  const activeOnTarget = sql
    .exec<{ c: number }>(
      "SELECT COUNT(*) AS c FROM decompositions WHERE mission_id = ? AND parent_task_id = ? AND status = 'active'",
      missionId,
      taskId
    )
    .one().c;
  const activeByContrib = sql
    .exec<{ c: number }>(
      "SELECT COUNT(*) AS c FROM decompositions WHERE proposer = ? AND status = 'active'",
      contributor
    )
    .one().c;

  let eligibility: { depth: number; max_depth: number };
  try {
    eligibility = checkDecompositionEligibility({
      manifest: mission.manifest,
      task,
      allTasks: tasks,
      contributor,
      isAllowlisted: isAllowlisted(sql, contributor),
      activeDecompsOnTarget: activeOnTarget,
      activeDecompsByContributor: activeByContrib,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const code = /not on the Phase 1 decomposition allowlist/.test(msg)
      ? 403
      : /already verified|already refuted|already has an active|blocked on|cannot be decomposed/.test(msg)
        ? 409
        : /cap reached/.test(msg)
          ? 429
          : 400;
    return { status: code, body: { error: msg } };
  }

  const rootTaskId = task.def.root_task_id || task.def.id;
  let parentDecompPayload: { decomp_id: string; subgoal_id: string; subgoals: Array<{ id: string; statement: string }> } | undefined;
  let parentDecompId: string | null = null;
  if (eligibility.depth > 1) {
    if (!task.def.decomp_id || !task.def.subgoal_id) {
      return { status: 400, body: { error: "nested decomposition target is missing parent decomposition metadata" } };
    }
    const parentRow = getDecompositionRow(sql, missionId, rootTaskId, task.def.decomp_id);
    if (!parentRow || parentRow.status !== "active") {
      return { status: 409, body: { error: `parent decomposition '${task.def.decomp_id}' is not active` } };
    }
    parentDecompId = parentRow.decomp_id;
    parentDecompPayload = {
      decomp_id: parentRow.decomp_id,
      subgoal_id: task.def.subgoal_id,
      subgoals: parseSubgoalsJson(parentRow.subgoals_json).map((s) => ({
        id: s.id,
        statement: s.statement,
      })),
    };
  }

  // Pick a clean default decomp_id if caller omitted one (e.g. d1, d2).
  const defaultDecompId = `d${eligibility.depth}`;
  let parsed: ReturnType<typeof parseDecomposeRequest>;
  try {
    parsed = parseDecomposeRequest(rawBody, {
      libRoot: contract.lib_root,
      frozenPaths: mission.manifest.frozen_paths,
      defaultDecompId,
    });
  } catch (e) {
    return { status: 422, body: { error: e instanceof Error ? e.message : String(e), stage: "patch" } };
  }

  // Ensure decomp_id was not previously used on (mission_id, root_task_id).
  const existingDecomp = getDecompositionRow(sql, missionId, rootTaskId, parsed.decomp_id);
  if (existingDecomp) {
    return {
      status: 409,
      body: {
        error: `decomp_id '${parsed.decomp_id}' already exists on '${rootTaskId}' (status=${existingDecomp.status}); choose a distinct decomp_id`,
      },
    };
  }

  // Ensure reduction_file doesn't collide with existing root task target files.
  const rootTargets = new Set(mission.manifest.tasks.flatMap((t) => t.target_files));
  if (rootTargets.has(parsed.reduction_file)) {
    return {
      status: 422,
      body: {
        error: `reduction_file '${parsed.reduction_file}' must be a dedicated decomposition file, not an existing task target file`,
        stage: "patch",
      },
    };
  }

  const now = ctx.now();
  const subId = ctx.randomUUID();
  const patchSha = await ctx.sha256Hex(parsed.patch);

  // Call the verifier container `POST /decompose` (never cache scratch state into mission cache).
  const vCall = await ctx.callVerifierAction("/decompose", ctx.getMissionFiles(missionId), {
    mission_id: missionId,
    task_id: rootTaskId,
    decomp_id: parsed.decomp_id,
    subgoals: parsed.subgoals.map((s) => ({ id: s.id, statement: s.statement })),
    reduction_module: parsed.reduction_module,
    reduction_theorem: parsed.reduction_theorem,
    ...(parentDecompPayload ? { parent_decomp: parentDecompPayload } : {}),
    patch: parsed.patch,
    frozen_paths: mission.manifest.frozen_paths,
    target_files: [parsed.reduction_file],
    timeout_sec: mission.manifest.verifier.timeout_sec ?? 120,
    cache_state: false,
  });

  if (!vCall.ok) {
    return {
      status: vCall.status,
      body: { accepted: false, error: vCall.error, stage: "sandbox" },
    };
  }
  const cRes = vCall.res;
  const finishedAt = ctx.now();

  if (!cRes.ok || cRes.spec_sha256 !== mission.spec_sha256) {
    const reason =
      !cRes.ok
        ? cRes.summary || "decomposition verification failed"
        : `spec hash mismatch: expected '${mission.spec_sha256}', got '${cRes.spec_sha256}'`;
    const diag = sanitizeFailureDiagnostics(cRes.stage, cRes.diagnostics);
    sql.exec(
      `INSERT INTO submissions
       (id, mission_id, task_id, contributor, status, accepted, score, points, summary, patch_sha256, verify_ms, stage, diagnostics, error, created_at, completed_at, is_demo, kind)
       VALUES (?, ?, ?, ?, 'rejected', 0, NULL, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'decompose')`,
      subId,
      missionId,
      taskId,
      contributor,
      reason,
      patchSha,
      cRes.verify_ms ?? 0,
      diag.stage ?? null,
      diag.diagnostics ?? null,
      reason,
      now,
      finishedAt,
      mission.manifest.demo ? 1 : 0
    );
    ctx.emit({
      kind: "submission_rejected",
      submission_id: subId,
      mission_id: missionId,
      task_id: taskId,
      contributor,
      accepted: false,
      score: null,
      summary: `decomposition rejected: ${reason}`,
      timestamp: finishedAt,
    });
    return {
      status: 422,
      body: {
        accepted: false,
        submission_id: subId,
        error: reason,
        verify_ms: cRes.verify_ms ?? 0,
        ...diag,
      },
    };
  }

  const reductionSource = cRes.updated_files?.[parsed.reduction_file];
  if (typeof reductionSource !== "string" || !reductionSource.trim()) {
    return {
      status: 502,
      body: { accepted: false, error: "verifier did not return verified reduction file contents", stage: "sandbox" },
    };
  }
  const decompStmtsModule =
    cRes.decomp_statements_module || `${contract.lib_root}.DecompStatements_${rootTaskId}_${parsed.decomp_id}`;
  const decompStmtsNs =
    cRes.decomp_statements_namespace || `SunsteadDecomp_${rootTaskId}_${parsed.decomp_id}`;
  const decompStmtsSource = cRes.decomp_statements_source || "";
  if (!decompStmtsSource.trim()) {
    return {
      status: 502,
      body: { accepted: false, error: "verifier did not return frozen DecompStatements source", stage: "sandbox" },
    };
  }
  const subgoalHashes = cRes.subgoal_spec_sha256s || {};
  const reductionSha256 = await ctx.sha256Hex(reductionSource);
  const storedPatch =
    cRes.normalized_patch && cRes.normalized_patch.trim() ? cRes.normalized_patch : parsed.patch;
  const storedPatchSha = await ctx.sha256Hex(storedPatch);

  // Build deterministic SubgoalSpec list (outside lock, pure computation).
  const subgoalSpecs: SubgoalSpec[] = await Promise.all(
    parsed.subgoals.map(async (s) => {
      const childTaskId = buildSubgoalTaskId(taskId, parsed.decomp_id, s.id);
      const subMod = `${contract.lib_root}.Decomp_${rootTaskId}_${parsed.decomp_id}_${s.id}`;
      const subThm = `${contract.lib_root}.decomp_${parsed.decomp_id}_${s.id}`;
      const targetFile = subMod.replace(/\./g, "/") + ".lean";
      const subSpecHash =
        subgoalHashes[s.id] ||
        (await ctx.sha256Hex(`${mission.spec_sha256}\0${decompStmtsNs}\0${s.id}\0${s.statement}`));
      return {
        id: s.id,
        title: s.title,
        statement: s.statement,
        task_id: childTaskId,
        subgoal_module: subMod,
        subgoal_theorem: subThm,
        target_file: targetFile,
        subgoal_spec_sha256: subSpecHash,
      };
    })
  );

  return ctx.withMissionLock(missionId, async () => {
    // Re-check concurrency invariants atomically under the mission lock.
    const latestTasks = ctx.getTasks(missionId);
    const latestTask = latestTasks.find((t) => t.def.id === taskId);
    if (!latestTask || latestTask.status === "verified" || latestTask.status === "refuted") {
      return { status: 409, body: { accepted: false, error: `task '${taskId}' is no longer open` } };
    }
    const latestActiveOnTarget = sql
      .exec<{ c: number }>(
        "SELECT COUNT(*) AS c FROM decompositions WHERE mission_id = ? AND parent_task_id = ? AND status = 'active'",
        missionId,
        taskId
      )
      .one().c;
    if (latestActiveOnTarget >= 1) {
      return { status: 409, body: { accepted: false, error: `task '${taskId}' already has an active decomposition` } };
    }
    const latestActiveByContrib = sql
      .exec<{ c: number }>(
        "SELECT COUNT(*) AS c FROM decompositions WHERE proposer = ? AND status = 'active'",
        contributor
      )
      .one().c;
    if (latestActiveByContrib >= 3) {
      return { status: 429, body: { accepted: false, error: `active decomposition cap reached for '${contributor}'` } };
    }
    if (getDecompositionRow(sql, missionId, rootTaskId, parsed.decomp_id)) {
      return { status: 409, body: { accepted: false, error: `decomp_id '${parsed.decomp_id}' was already created` } };
    }

    const parentPoints = resolveTaskPointValue(sql, mission.manifest, latestTask);
    const split = computeDecompPointSplit(parentPoints, subgoalSpecs.length);
    const ts = ctx.now();

    sql.exec(
      `INSERT INTO decompositions (
         decomp_id, mission_id, root_task_id, parent_task_id, parent_decomp_id, depth,
         proposer, status, subgoals_json,
         decomp_statements_module, decomp_statements_namespace, decomp_statements_source,
         reduction_file, reduction_module, reduction_theorem, reduction_source,
         reduction_patch, reduction_sha256,
         parent_points, solver_points_per_subgoal, architect_points, architect_vested,
         created_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)`,
      parsed.decomp_id,
      missionId,
      rootTaskId,
      taskId,
      parentDecompId,
      eligibility.depth,
      contributor,
      JSON.stringify(subgoalSpecs),
      decompStmtsModule,
      decompStmtsNs,
      decompStmtsSource,
      parsed.reduction_file,
      parsed.reduction_module,
      parsed.reduction_theorem,
      reductionSource,
      storedPatch,
      reductionSha256,
      parentPoints,
      split.solver_points_per_subgoal,
      split.architect_points,
      ts
    );

    // Spawn k dynamic child subgoal tasks.
    for (const s of subgoalSpecs) {
      const childDef: TaskDefinition = {
        id: s.task_id,
        title: s.title,
        description: `Decomposition subgoal \`${s.id}\` of \`${taskId}\` (decomp \`${parsed.decomp_id}\`, proposed by ${contributor}).`,
        target_files: [s.target_file],
        depends_on: [],
        parent_task_id: taskId,
        root_task_id: rootTaskId,
        decomp_id: parsed.decomp_id,
        subgoal_id: s.id,
        decomp_depth: eligibility.depth,
        subgoal_spec_sha256: s.subgoal_spec_sha256,
        subgoal_statement: s.statement,
        subgoal_module: s.subgoal_module,
        subgoal_theorem: s.subgoal_theorem,
        decomp_statements_module: decompStmtsModule,
        decomp_statements_namespace: decompStmtsNs,
        reduction_file: parsed.reduction_file,
      };
      sql.exec(
        `INSERT INTO tasks (
           mission_id, task_id, def_json, status, best_score, attempts,
           is_dynamic, parent_task_id, root_task_id, decomp_id, subgoal_id,
           decomp_depth, subgoal_spec_sha256, retired
         ) VALUES (?, ?, ?, 'open', NULL, 0, 1, ?, ?, ?, ?, ?, ?, 0)`,
        missionId,
        s.task_id,
        JSON.stringify(childDef),
        taskId,
        rootTaskId,
        parsed.decomp_id,
        s.id,
        eligibility.depth,
        s.subgoal_spec_sha256
      );
    }

    // Record 0-point decompose submission (proposer vests architect share only on closure).
    sql.exec(
      `INSERT INTO submissions
       (id, mission_id, task_id, contributor, status, accepted, score, points, summary, patch_sha256, verify_ms, created_at, completed_at, is_demo, kind)
       VALUES (?, ?, ?, ?, 'accepted', 1, 1.0, 0, ?, ?, ?, ?, ?, ?, 'decompose')`,
      subId,
      missionId,
      taskId,
      contributor,
      cRes.summary,
      storedPatchSha,
      cRes.verify_ms ?? 0,
      now,
      ts,
      mission.manifest.demo ? 1 : 0
    );

    ctx.emit({
      kind: "task_decomposed",
      submission_id: subId,
      mission_id: missionId,
      task_id: taskId,
      contributor,
      accepted: true,
      score: null,
      summary: `${contributor} decomposed ${taskId} into ${subgoalSpecs.length} kernel-verified subgoals (${parsed.decomp_id})`,
      timestamp: ts,
    });

    return {
      status: 201,
      body: {
        accepted: true,
        submission_id: subId,
        mission_id: missionId,
        parent_task_id: taskId,
        root_task_id: rootTaskId,
        decomp_id: parsed.decomp_id,
        depth: eligibility.depth,
        proposer: contributor,
        points_awarded: 0,
        economics: {
          parent_points: parentPoints,
          solver_points_per_subgoal: split.solver_points_per_subgoal,
          architect_points_unvested: split.architect_points,
          max_total_points: split.max_total_points,
        },
        decomp_statements_module: decompStmtsModule,
        decomp_statements_namespace: decompStmtsNs,
        decomp_statements_source: decompStmtsSource,
        reduction_file: parsed.reduction_file,
        reduction_sha256: reductionSha256,
        subgoals: subgoalSpecs,
        verify_ms: cRes.verify_ms ?? 0,
        summary: cRes.summary,
      },
    };
  });
}

// ---------------------------------------------------------------------------
// 2. Subgoal submission + automatic untouched `./verify <T>` assembly

function buildAssembledProofTree(
  sql: SqlLike,
  missionId: string,
  decomp: DecompositionRow
): { ok: true; tree: AssembledProofNode; contributors: Map<string, "proposer" | "solver"> } | { ok: false; error: string } {
  const subgoals = parseSubgoalsJson(decomp.subgoals_json);
  const contributors = new Map<string, "proposer" | "solver">();
  contributors.set(decomp.proposer, "proposer");

  const children: AssembledProofNode[] = [];
  for (const sub of subgoals) {
    // Prefer an active/completed nested depth-2 decomposition if one closed this subgoal.
    const childDecompRows = sql
      .exec<DecompositionRow>(
        `SELECT * FROM decompositions
         WHERE mission_id = ? AND parent_task_id = ? AND status = 'completed'
         ORDER BY closed_at DESC LIMIT 1`,
        missionId,
        sub.task_id
      )
      .toArray();
    if (childDecompRows.length > 0) {
      const nested = buildAssembledProofTree(sql, missionId, childDecompRows[0]);
      if (!nested.ok) return nested;
      for (const [h, role] of nested.contributors.entries()) {
        if (!contributors.has(h)) contributors.set(h, role);
      }
      children.push(nested.tree);
      continue;
    }

    const proofRows = sql
      .exec<{ contributor: string; source: string }>(
        "SELECT contributor, source FROM decomp_subgoal_proofs WHERE mission_id = ? AND task_id = ? LIMIT 1",
        missionId,
        sub.task_id
      )
      .toArray();
    if (proofRows.length === 0) {
      return { ok: false, error: `missing verified proof source for subgoal '${sub.task_id}'` };
    }
    if (!contributors.has(proofRows[0].contributor)) {
      contributors.set(proofRows[0].contributor, "solver");
    }
    children.push({
      kind: "leaf",
      label: sub.id,
      theorem: sub.subgoal_theorem,
      source: proofRows[0].source,
    });
  }

  return {
    ok: true,
    tree: {
      kind: "decomp",
      decomp_id: decomp.decomp_id,
      decomp_statements_module: decomp.decomp_statements_module,
      decomp_statements_source: decomp.decomp_statements_source,
      reduction_theorem: decomp.reduction_theorem,
      reduction_source: decomp.reduction_source,
      children,
    },
    contributors,
  };
}

async function tryAutoAssembleDecomposition(
  ctx: DecomposeHubContext,
  decomp: DecompositionRow,
  triggerContributor: string
): Promise<{
  assembled: boolean;
  parent_task_id?: string;
  parent_proof_id?: string;
  parent_permalink?: string;
  architect_points_vested?: number;
  root_assembled?: boolean;
  root_proof_id?: string;
  root_permalink?: string;
  assembly_error?: string;
}> {
  const { sql, mission } = ctx;
  const missionId = mission.manifest.id;
  const contract = mission.verify_contract;
  if (!contract) {
    return { assembled: false, assembly_error: "missing mission verify contract" };
  }

  const subgoals = parseSubgoalsJson(decomp.subgoals_json);
  const verifiedCount = sql
    .exec<{ c: number }>(
      `SELECT COUNT(*) AS c FROM tasks
       WHERE mission_id = ? AND parent_task_id = ? AND decomp_id = ? AND status = 'verified' AND COALESCE(retired, 0) = 0`,
      missionId,
      decomp.parent_task_id,
      decomp.decomp_id
    )
    .one().c;
  if (verifiedCount < subgoals.length) {
    return { assembled: false };
  }

  const treeRes = buildAssembledProofTree(sql, missionId, decomp);
  if (!treeRes.ok) {
    return { assembled: false, assembly_error: treeRes.error };
  }

  const baseImports =
    contract.frozen_lean_modules.length > 0
      ? contract.frozen_lean_modules
      : [`${contract.lib_root}.Spec`];

  const knownRootNamespaces = new Set<string>([contract.lib_root]);
  for (const [rel, src] of Object.entries(mission.seed_files || {})) {
    if (!rel.endsWith(".lean")) continue;
    for (const line of src.split(/\r?\n/)) {
      const m = line.match(/^\s*namespace\s+([A-Za-z_][A-Za-z0-9_']*(?:\.[A-Za-z_][A-Za-z0-9_']*)*)\s*(?:--.*)?$/);
      if (m) knownRootNamespaces.add(m[1]);
    }
  }
  const knownNsList = Array.from(knownRootNamespaces);

  const coAuthors: CoAuthor[] = Array.from(treeRes.contributors.entries()).map(([handle, role]) => ({
    handle,
    display_name: lookupContributorDisplayName(sql, handle),
    role,
  }));

  // Depth-2 decomposition closes a depth-1 parent subgoal, then cascades upward!
  if (decomp.depth > 1 && decomp.parent_decomp_id) {
    const parentDecomp = getDecompositionRow(sql, missionId, decomp.root_task_id, decomp.parent_decomp_id);
    if (!parentDecomp || parentDecomp.status !== "active") {
      return { assembled: false, assembly_error: "parent depth-1 decomposition is no longer active" };
    }
    const parentSubs = parseSubgoalsJson(parentDecomp.subgoals_json);
    const parentSub = parentSubs.find((s) => s.task_id === decomp.parent_task_id);
    if (!parentSub) {
      return { assembled: false, assembly_error: "parent subgoal definition not found" };
    }
    const assembledSubSrc = assembleDecomposedLeanFile({
      baseImports,
      keepImports: [parentDecomp.decomp_statements_module],
      knownRootNamespaces: knownNsList,
      statementPreamble: contract.statement_preamble,
      targetTheorem: parentSub.subgoal_theorem,
      targetTypeExpr: `${parentDecomp.decomp_statements_namespace}.${parentSub.id}`,
      root: treeRes.tree,
    });
    const stubSrc = buildSubgoalStubSource({
      libRoot: contract.lib_root,
      decompStatementsModule: parentDecomp.decomp_statements_module,
      decompStatementsNamespace: parentDecomp.decomp_statements_namespace,
      subgoalId: parentSub.id,
      subgoalTitle: parentSub.title,
      subgoalTheorem: parentSub.subgoal_theorem,
      statementPreamble: contract.statement_preamble,
    });
    const assembledDiff = generateUnifiedDiff(parentSub.target_file, stubSrc, assembledSubSrc);
    const currentFiles = {
      ...ctx.getMissionFiles(missionId),
      [parentDecomp.reduction_file]: parentDecomp.reduction_source,
      [parentSub.target_file]: stubSrc,
    };
    const vCall = await ctx.callVerifierAction("/subgoal", currentFiles, {
      mission_id: missionId,
      task_id: decomp.root_task_id,
      decomp_id: parentDecomp.decomp_id,
      subgoals: parentSubs.map((s) => ({ id: s.id, statement: s.statement })),
      subgoal_id: parentSub.id,
      subgoal_module: parentSub.subgoal_module,
      subgoal_theorem: parentSub.subgoal_theorem,
      frozen_extra_files: { [parentDecomp.reduction_file]: parentDecomp.reduction_sha256 },
      patch: assembledDiff,
      frozen_paths: mission.manifest.frozen_paths,
      target_files: [parentSub.target_file],
      timeout_sec: mission.manifest.verifier.timeout_sec ?? 120,
      cache_state: false,
    });
    if (!vCall.ok || !vCall.res.ok) {
      const err = !vCall.ok ? vCall.error : vCall.res.summary;
      return { assembled: false, assembly_error: `nested subgoal assembly failed: ${err}` };
    }
    const storedPatch =
      vCall.res.normalized_patch && vCall.res.normalized_patch.trim()
        ? vCall.res.normalized_patch
        : assembledDiff;
    const storedSha = await ctx.sha256Hex(storedPatch);
    const proofId = proofIdFromPatchSha(storedSha);
    const finishedAt = ctx.now();
    const vestPoints = mission.manifest.demo ? 0 : decomp.architect_points;

    await ctx.withMissionLock(missionId, async () => {
      const latest = getDecompositionRow(sql, missionId, decomp.root_task_id, decomp.decomp_id);
      if (!latest || latest.status !== "active") return;
      sql.exec(
        `UPDATE decompositions
         SET status = 'completed', architect_vested = 1, closed_at = ?
         WHERE mission_id = ? AND root_task_id = ? AND decomp_id = ?`,
        finishedAt,
        missionId,
        decomp.root_task_id,
        decomp.decomp_id
      );
      sql.exec(
        `INSERT INTO decomp_subgoal_proofs
         (mission_id, task_id, decomp_id, root_task_id, subgoal_id, contributor, source, patch, patch_sha256, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(mission_id, task_id) DO UPDATE SET
           source = excluded.source, patch = excluded.patch, patch_sha256 = excluded.patch_sha256`,
        missionId,
        parentSub.task_id,
        parentDecomp.decomp_id,
        decomp.root_task_id,
        parentSub.id,
        triggerContributor,
        assembledSubSrc,
        storedPatch,
        storedSha,
        finishedAt
      );
      sql.exec(
        `UPDATE tasks
         SET status = 'verified', best_score = 1.0, verified_by = ?,
             lease_contributor = NULL, lease_token = NULL, lease_expires_at = NULL, lease_ip = NULL
         WHERE mission_id = ? AND task_id = ?`,
        triggerContributor,
        missionId,
        parentSub.task_id
      );
      const asmSubId = ctx.randomUUID();
      sql.exec(
        `INSERT INTO accepted_patches
         (mission_id, task_id, submission_id, contributor, summary, patch, spec_sha256, created_at, patch_sha256, is_demo, entry_kind, in_history, co_authors_json, decomp_meta_json, scoring_provenance_json)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'assembled', 0, ?, ?, ?)`,
        missionId,
        parentSub.task_id,
        asmSubId,
        triggerContributor,
        `Assembled depth-${decomp.depth} decomposition ${decomp.decomp_id} for subgoal ${parentSub.id}`,
        storedPatch,
        parentSub.subgoal_spec_sha256,
        finishedAt,
        storedSha,
        mission.manifest.demo ? 1 : 0,
        JSON.stringify(coAuthors),
        JSON.stringify({
          decomp_id: decomp.decomp_id,
          parent_task_id: decomp.parent_task_id,
          root_task_id: decomp.root_task_id,
          subgoal_id: parentSub.id,
          subgoal_title: parentSub.title,
          proposer: decomp.proposer,
          depth: decomp.depth,
        }),
        ctx.scoringProvenanceJson
      );
      if (vestPoints > 0) {
        sql.exec(
          `INSERT INTO submissions
           (id, mission_id, task_id, contributor, status, accepted, score, points, summary, patch_sha256, proof_id, verify_ms, created_at, completed_at, is_demo, kind)
           VALUES (?, ?, ?, ?, 'accepted', 1, 1.0, ?, ?, ?, ?, ?, ?, ?, 0, 'architect_vest')`,
          ctx.randomUUID(),
          missionId,
          parentSub.task_id,
          decomp.proposer,
          vestPoints,
          `Architect share vested for decomposition ${decomp.decomp_id} (+${vestPoints} pts)`,
          storedSha,
          proofId,
          vCall.res.verify_ms ?? 0,
          finishedAt,
          finishedAt
        );
      }
    });

    // Cascade upward: check if depth-1 parent decomposition is now also complete!
    const refreshedParent = getDecompositionRow(sql, missionId, decomp.root_task_id, parentDecomp.decomp_id);
    const cascade = refreshedParent
      ? await tryAutoAssembleDecomposition(ctx, refreshedParent, triggerContributor)
      : { assembled: false };
    return {
      assembled: true,
      parent_task_id: parentSub.task_id,
      parent_proof_id: proofId,
      parent_permalink: `${ctx.hubOrigin}/proofs/${proofId}`,
      architect_points_vested: vestPoints,
      ...(cascade.assembled
        ? {
            root_assembled: true,
            root_proof_id: cascade.parent_proof_id,
            root_permalink: cascade.parent_permalink,
          }
        : {}),
      ...(cascade.assembly_error ? { assembly_error: cascade.assembly_error } : {}),
    };
  }

  // Depth-1 decomposition closes root task T through the ORIGINAL UNTOUCHED `./verify <T>`!
  const rootTaskDef = mission.manifest.tasks.find((t) => t.id === decomp.root_task_id);
  const taskContract = contract.tasks[decomp.root_task_id];
  if (!rootTaskDef || !taskContract) {
    return { assembled: false, assembly_error: `missing root task contract for '${decomp.root_task_id}'` };
  }
  const targetFile = rootTaskDef.target_files[0];
  const liveFiles = ctx.getMissionFiles(missionId);
  const currentTargetContent =
    targetFile in liveFiles
      ? liveFiles[targetFile]
      : (mission.seed_files?.[targetFile] ?? null);

  const assembledSource = assembleDecomposedLeanFile({
    baseImports,
    knownRootNamespaces: knownNsList,
    statementPreamble: contract.statement_preamble,
    targetTheorem: taskContract.theorem,
    targetTypeExpr: extractPropStatementExpr(taskContract.statement),
    root: treeRes.tree,
  });
  const assembledPatch = generateUnifiedDiff(targetFile, currentTargetContent, assembledSource);

  // Run the ORIGINAL UNTOUCHED `./verify <T>` endpoint!
  const verifyCall = await ctx.callVerifierAction("/verify", liveFiles, {
    mission_id: missionId,
    task_id: decomp.root_task_id,
    patch: assembledPatch,
    frozen_paths: mission.manifest.frozen_paths,
    target_files: rootTaskDef.target_files,
    timeout_sec: mission.manifest.verifier.timeout_sec ?? 180,
  });

  if (!verifyCall.ok) {
    return { assembled: false, assembly_error: `untouched ./verify call failed: ${verifyCall.error}` };
  }
  const vRes = verifyCall.res;
  if (!vRes.ok || vRes.spec_sha256 !== mission.spec_sha256) {
    return {
      assembled: false,
      assembly_error: `untouched ./verify rejected assembled proof of '${decomp.root_task_id}': ${vRes.summary}`,
    };
  }

  const storedPatch =
    vRes.normalized_patch && vRes.normalized_patch.trim() ? vRes.normalized_patch : assembledPatch;
  const storedPatchSha = await ctx.sha256Hex(storedPatch);
  const proofId = proofIdFromPatchSha(storedPatchSha);
  const permalink = `${ctx.hubOrigin}/proofs/${proofId}`;
  const finishedAt = ctx.now();
  const vestPoints = mission.manifest.demo ? 0 : decomp.architect_points;

  return ctx.withMissionLock(missionId, async () => {
    const latestDecomp = getDecompositionRow(sql, missionId, decomp.root_task_id, decomp.decomp_id);
    const latestTasks = ctx.getTasks(missionId);
    const latestRoot = latestTasks.find((t) => t.def.id === decomp.root_task_id);
    if (
      !latestDecomp ||
      latestDecomp.status !== "active" ||
      !latestRoot ||
      latestRoot.status === "verified" ||
      latestRoot.status === "refuted"
    ) {
      return { assembled: false, assembly_error: "root task was closed concurrently" };
    }

    const outcome = applyVerdict(
      mission.manifest.mode,
      mission.manifest.score_direction ?? "maximize",
      mission.manifest.frozen_paths,
      mission.spec_sha256,
      latestTasks,
      decomp.root_task_id,
      storedPatch,
      {
        ok: vRes.ok,
        score: vRes.score ?? 1.0,
        summary: vRes.summary,
        spec_sha256: vRes.spec_sha256,
      }
    );

    const updatedFiles = vRes.updated_files && Object.keys(vRes.updated_files).length > 0
      ? vRes.updated_files
      : { [targetFile]: assembledSource };
    for (const [relPath, content] of Object.entries(updatedFiles)) {
      sql.exec(
        `INSERT INTO mission_files (mission_id, rel_path, content)
         VALUES (?, ?, ?)
         ON CONFLICT(mission_id, rel_path) DO UPDATE SET content = excluded.content`,
        missionId,
        relPath,
        content
      );
    }
    sql.exec("DELETE FROM bundle_cache WHERE mission_id = ?", missionId);

    sql.exec(
      `UPDATE tasks
       SET status = 'verified',
           best_score = ?,
           verified_by = ?,
           lease_contributor = NULL,
           lease_token = NULL,
           lease_expires_at = NULL,
           lease_ip = NULL,
           attempts = attempts + 1
       WHERE mission_id = ? AND task_id = ?`,
      outcome.new_best_score,
      triggerContributor,
      missionId,
      decomp.root_task_id
    );

    sql.exec(
      `UPDATE decompositions
       SET status = 'completed', architect_vested = 1, closed_at = ?
       WHERE mission_id = ? AND root_task_id = ? AND decomp_id = ?`,
      finishedAt,
      missionId,
      decomp.root_task_id,
      decomp.decomp_id
    );

    const asmSubmissionId = ctx.randomUUID();
    const asmSummary = `Assembled proof of ${decomp.root_task_id} via decomposition ${decomp.decomp_id} (${subgoals.length} subgoals) — ${vRes.summary}`;
    sql.exec(
      `INSERT INTO submissions
       (id, mission_id, task_id, contributor, status, accepted, score, points, summary, patch_sha256, proof_id, verify_ms, unlocked_dependents_json, created_at, completed_at, is_demo, kind)
       VALUES (?, ?, ?, ?, 'accepted', 1, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, 'assembled')`,
      asmSubmissionId,
      missionId,
      decomp.root_task_id,
      triggerContributor,
      outcome.new_best_score,
      asmSummary,
      storedPatchSha,
      proofId,
      vRes.verify_ms ?? 0,
      JSON.stringify(outcome.unlocked_dependents),
      finishedAt,
      finishedAt,
      mission.manifest.demo ? 1 : 0
    );

    // Record architect share vesting (only once root T passes untouched `./verify <T>`!).
    if (vestPoints > 0) {
      sql.exec(
        `INSERT INTO submissions
         (id, mission_id, task_id, contributor, status, accepted, score, points, summary, patch_sha256, proof_id, verify_ms, created_at, completed_at, is_demo, kind)
         VALUES (?, ?, ?, ?, 'accepted', 1, ?, ?, ?, ?, ?, ?, ?, ?, 0, 'architect_vest')`,
        ctx.randomUUID(),
        missionId,
        decomp.root_task_id,
        decomp.proposer,
        outcome.new_best_score,
        vestPoints,
        `Architect share vested for ${decomp.root_task_id} (${decomp.decomp_id}, +${vestPoints} pts)`,
        storedPatchSha,
        proofId,
        vRes.verify_ms ?? 0,
        finishedAt,
        finishedAt
      );
    }

    // Record ONE clean root commit in `accepted_patches` (`in_history = 1`) with Co-authored-by attribution!
    sql.exec(
      `INSERT INTO accepted_patches
       (mission_id, task_id, submission_id, contributor, summary, patch, spec_sha256, created_at, patch_sha256, is_demo, entry_kind, in_history, co_authors_json, decomp_meta_json, scoring_provenance_json)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'assembled', 1, ?, ?, ?)`,
      missionId,
      decomp.root_task_id,
      asmSubmissionId,
      triggerContributor,
      asmSummary,
      storedPatch,
      mission.spec_sha256,
      finishedAt,
      storedPatchSha,
      mission.manifest.demo ? 1 : 0,
      JSON.stringify(coAuthors),
      JSON.stringify({
        decomp_id: decomp.decomp_id,
        parent_task_id: decomp.parent_task_id,
        root_task_id: decomp.root_task_id,
        proposer: decomp.proposer,
        depth: decomp.depth,
        subgoal_count: subgoals.length,
        architect_points_vested: vestPoints,
      }),
      ctx.scoringProvenanceJson
    );

    ctx.emit({
      kind: "submission_accepted",
      submission_id: asmSubmissionId,
      mission_id: missionId,
      task_id: decomp.root_task_id,
      contributor: triggerContributor,
      accepted: true,
      score: outcome.new_best_score,
      summary: `${asmSummary} (architect +${vestPoints} pts vested)`,
      timestamp: finishedAt,
    });

    return {
      assembled: true,
      parent_task_id: decomp.root_task_id,
      parent_proof_id: proofId,
      parent_permalink: permalink,
      architect_points_vested: vestPoints,
    };
  });
}

export async function executeSubgoalSubmit(
  ctx: DecomposeHubContext,
  params: {
    subId: string;
    task: TaskState;
    contributor: string;
    patch: string;
    patchSha: string;
  }
): Promise<{ status: number; body: Record<string, unknown> }> {
  const { sql, mission } = ctx;
  const missionId = mission.manifest.id;
  const { subId, task, contributor, patch, patchSha } = params;
  const taskId = task.def.id;
  const rootTaskId = task.def.root_task_id;
  const decompId = task.def.decomp_id;
  const subgoalId = task.def.subgoal_id;

  const failAndRecord = (status: number, reason: string, stage?: FailureStage | null, diagnostics?: string | null, verifyMs = 0) => {
    const finishedAt = ctx.now();
    const diag = sanitizeFailureDiagnostics(stage, diagnostics);
    sql.exec("UPDATE tasks SET attempts = attempts + 1 WHERE mission_id = ? AND task_id = ?", missionId, taskId);
    sql.exec(
      `UPDATE submissions
       SET status = ?, accepted = 0, points = 0, summary = ?, patch_sha256 = ?, verify_ms = ?, stage = ?, diagnostics = ?, error = ?, completed_at = ?, kind = 'subgoal'
       WHERE id = ?`,
      status >= 500 ? "error" : "rejected",
      reason,
      patchSha,
      verifyMs,
      diag.stage ?? null,
      diag.diagnostics ?? null,
      reason,
      finishedAt,
      subId
    );
    ctx.emit({
      kind: "submission_rejected",
      submission_id: subId,
      mission_id: missionId,
      task_id: taskId,
      contributor,
      accepted: false,
      score: null,
      summary: reason,
      timestamp: finishedAt,
    });
    return {
      status,
      body: {
        accepted: false,
        status: status >= 500 ? "error" : "rejected",
        submission_id: subId,
        error: reason,
        verify_ms: verifyMs,
        ...diag,
      },
    };
  };

  if (!rootTaskId || !decompId || !subgoalId) {
    return failAndRecord(400, "subgoal task is missing decomposition metadata", "sandbox");
  }
  const decomp = getDecompositionRow(sql, missionId, rootTaskId, decompId);
  if (!decomp || decomp.status !== "active") {
    return failAndRecord(409, `decomposition '${decompId}' is no longer active`);
  }
  const subgoals = parseSubgoalsJson(decomp.subgoals_json);
  const sub = subgoals.find((s) => s.id === subgoalId);
  if (!sub) {
    return failAndRecord(404, `unknown subgoal '${subgoalId}' in decomposition '${decompId}'`);
  }

  // Enforce RFC §7 Attack #5 before waking container: reduction file is frozen!
  const effectiveFrozen = [...mission.manifest.frozen_paths, decomp.reduction_file];
  try {
    validatePatch(patch, effectiveFrozen, [sub.target_file]);
  } catch (e) {
    const detail = e instanceof Error ? e.message : String(e);
    return failAndRecord(422, `policy rejected: ${detail}`, "patch", detail);
  }

  const contract = mission.verify_contract;
  const libRoot = contract?.lib_root ?? sub.target_file.split("/")[0];
  const stubSource = buildSubgoalStubSource({
    libRoot,
    decompStatementsModule: decomp.decomp_statements_module,
    decompStatementsNamespace: decomp.decomp_statements_namespace,
    subgoalId: sub.id,
    subgoalTitle: sub.title,
    subgoalTheorem: sub.subgoal_theorem,
    statementPreamble: contract?.statement_preamble,
  });
  const currentFiles = {
    ...ctx.getMissionFiles(missionId),
    [decomp.reduction_file]: decomp.reduction_source,
    [sub.target_file]: stubSource,
  };

  const vCall = await ctx.callVerifierAction("/subgoal", currentFiles, {
    mission_id: missionId,
    task_id: rootTaskId,
    decomp_id: decomp.decomp_id,
    subgoals: subgoals.map((s) => ({ id: s.id, statement: s.statement })),
    subgoal_id: sub.id,
    subgoal_module: sub.subgoal_module,
    subgoal_theorem: sub.subgoal_theorem,
    frozen_extra_files: { [decomp.reduction_file]: decomp.reduction_sha256 },
    patch,
    frozen_paths: mission.manifest.frozen_paths,
    target_files: [sub.target_file],
    timeout_sec: mission.manifest.verifier.timeout_sec ?? 120,
    cache_state: false,
  });

  if (!vCall.ok) {
    return failAndRecord(vCall.status, vCall.error, "sandbox");
  }
  const cRes = vCall.res;
  if (!cRes.ok || cRes.spec_sha256 !== mission.spec_sha256) {
    const reason = !cRes.ok
      ? cRes.summary || "subgoal verification failed"
      : `spec hash mismatch: expected '${mission.spec_sha256}', got '${cRes.spec_sha256}'`;
    return failAndRecord(422, reason, cRes.stage, cRes.diagnostics, cRes.verify_ms ?? 0);
  }

  const verifiedSource = cRes.updated_files?.[sub.target_file];
  if (typeof verifiedSource !== "string" || !verifiedSource.trim()) {
    return failAndRecord(502, "verifier did not return verified subgoal file contents", "sandbox");
  }
  const storedPatch =
    cRes.normalized_patch && cRes.normalized_patch.trim() ? cRes.normalized_patch : patch;
  const storedPatchSha = await ctx.sha256Hex(storedPatch);
  const proofId = proofIdFromPatchSha(storedPatchSha);
  const permalink = `${ctx.hubOrigin}/proofs/${proofId}`;
  const verifyMs = cRes.verify_ms ?? 0;

  const commitResult = await ctx.withMissionLock(missionId, async () => {
    const latestDecomp = getDecompositionRow(sql, missionId, rootTaskId, decompId);
    if (!latestDecomp || latestDecomp.status !== "active") {
      return { ok: false as const, status: 409, reason: `decomposition '${decompId}' is no longer active` };
    }
    const latestTasks = ctx.getTasks(missionId);
    const latestTask = latestTasks.find((t) => t.def.id === taskId);
    if (!latestTask || latestTask.status === "verified") {
      return { ok: false as const, status: 409, reason: `subgoal '${taskId}' is already verified` };
    }

    const finishedAt = ctx.now();
    const awardedPoints = mission.manifest.demo ? 0 : latestDecomp.solver_points_per_subgoal;

    // Retire any active depth-2 decomposition under this subgoal if bypassed directly!
    handleDirectParentBypass(sql, missionId, taskId, finishedAt);

    sql.exec(
      `INSERT INTO decomp_subgoal_proofs
       (mission_id, task_id, decomp_id, root_task_id, subgoal_id, contributor, source, patch, patch_sha256, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(mission_id, task_id) DO UPDATE SET
         contributor = excluded.contributor,
         source = excluded.source,
         patch = excluded.patch,
         patch_sha256 = excluded.patch_sha256,
         created_at = excluded.created_at`,
      missionId,
      taskId,
      decompId,
      rootTaskId,
      sub.id,
      contributor,
      verifiedSource,
      storedPatch,
      storedPatchSha,
      finishedAt
    );

    sql.exec(
      `UPDATE tasks
       SET status = 'verified',
           best_score = 1.0,
           verified_by = ?,
           lease_contributor = NULL,
           lease_token = NULL,
           lease_expires_at = NULL,
           lease_ip = NULL,
           attempts = attempts + 1
       WHERE mission_id = ? AND task_id = ?`,
      contributor,
      missionId,
      taskId
    );

    sql.exec(
      `UPDATE submissions
       SET status = 'accepted', accepted = 1, score = 1.0, points = ?, summary = ?,
           patch_sha256 = ?, proof_id = ?, verify_ms = ?, completed_at = ?, kind = 'subgoal'
       WHERE id = ?`,
      awardedPoints,
      cRes.summary,
      storedPatchSha,
      proofId,
      verifyMs,
      finishedAt,
      subId
    );

    // Record subgoal proof in ledger (`in_history = 0` so history.mbox stays clean).
    sql.exec(
      `INSERT INTO accepted_patches
       (mission_id, task_id, submission_id, contributor, summary, patch, spec_sha256, created_at, patch_sha256, is_demo, entry_kind, in_history, decomp_meta_json, scoring_provenance_json)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'subgoal', 0, ?, ?)`,
      missionId,
      taskId,
      subId,
      contributor,
      cRes.summary,
      storedPatch,
      sub.subgoal_spec_sha256,
      finishedAt,
      storedPatchSha,
      mission.manifest.demo ? 1 : 0,
      JSON.stringify({
        decomp_id: decompId,
        parent_task_id: latestDecomp.parent_task_id,
        root_task_id: rootTaskId,
        subgoal_id: sub.id,
        subgoal_title: sub.title,
        proposer: latestDecomp.proposer,
        depth: latestDecomp.depth,
      }),
      ctx.scoringProvenanceJson
    );

    ctx.emit({
      kind: "submission_accepted",
      submission_id: subId,
      mission_id: missionId,
      task_id: taskId,
      contributor,
      accepted: true,
      score: 1.0,
      summary: `${cRes.summary} (+${awardedPoints} pts)`,
      timestamp: finishedAt,
    });

    return { ok: true as const, awardedPoints, decomp: latestDecomp };
  });

  if (!commitResult.ok) {
    return failAndRecord(commitResult.status, commitResult.reason, null, null, verifyMs);
  }

  // Trigger automatic assembly if this was the final subgoal of `decomp`!
  const assembly = await tryAutoAssembleDecomposition(ctx, commitResult.decomp, contributor);

  return {
    status: 200,
    body: {
      accepted: true,
      status: "accepted",
      submission_id: subId,
      task_id: taskId,
      subgoal_id: sub.id,
      decomp_id: decompId,
      contributor,
      points_awarded: commitResult.awardedPoints,
      score: 1.0,
      unlocked_dependents: [],
      patch_sha256: storedPatchSha,
      proof_id: proofId,
      permalink,
      verify_ms: verifyMs,
      summary: cRes.summary,
      parent_assembled: assembly.assembled,
      ...(assembly.parent_task_id ? { parent_task_id: assembly.parent_task_id } : {}),
      ...(assembly.parent_proof_id ? { parent_proof_id: assembly.parent_proof_id } : {}),
      ...(assembly.parent_permalink ? { parent_permalink: assembly.parent_permalink } : {}),
      ...(assembly.architect_points_vested !== undefined
        ? { architect_points_vested: assembly.architect_points_vested }
        : {}),
      ...(assembly.root_assembled ? { root_assembled: true, root_proof_id: assembly.root_proof_id, root_permalink: assembly.root_permalink } : {}),
      ...(assembly.assembly_error ? { assembly_error: assembly.assembly_error } : {}),
    },
  };
}

// ---------------------------------------------------------------------------
// 3. Direct parent bypass teardown (forfeits unvested architect share, retires open children)

export function retireDecompositionTree(
  sql: SqlLike,
  missionId: string,
  parentTaskId: string,
  terminalStatus: "bypassed" | "refuted" | "cancelled",
  now: number,
  extra?: { refuted_subgoal_id?: string | null; refutation_id?: string | null }
): string[] {
  const activeDecomps = sql
    .exec<{ decomp_id: string; root_task_id: string; subgoals_json: string }>(
      `SELECT decomp_id, root_task_id, subgoals_json FROM decompositions
       WHERE mission_id = ? AND parent_task_id = ? AND status = 'active'`,
      missionId,
      parentTaskId
    )
    .toArray();

  const retiredIds: string[] = [];
  for (const d of activeDecomps) {
    retiredIds.push(d.decomp_id);
    sql.exec(
      `UPDATE decompositions
       SET status = ?, architect_vested = 0,
           refuted_subgoal_id = COALESCE(?, refuted_subgoal_id),
           refutation_id = COALESCE(?, refutation_id),
           closed_at = ?
       WHERE mission_id = ? AND root_task_id = ? AND decomp_id = ?`,
      terminalStatus,
      extra?.refuted_subgoal_id ?? null,
      extra?.refutation_id ?? null,
      now,
      missionId,
      d.root_task_id,
      d.decomp_id
    );
    const subs = parseSubgoalsJson(d.subgoals_json);
    for (const s of subs) {
      // Recursively retire any depth-2 decomposition under child subgoals.
      retireDecompositionTree(sql, missionId, s.task_id, terminalStatus, now);
      sql.exec(
        `UPDATE tasks
         SET retired = 1,
             lease_contributor = NULL,
             lease_token = NULL,
             lease_expires_at = NULL,
             lease_ip = NULL
         WHERE mission_id = ? AND task_id = ?`,
        missionId,
        s.task_id
      );
    }
  }
  return retiredIds;
}

export function handleDirectParentBypass(
  sql: SqlLike,
  missionId: string,
  parentTaskId: string,
  now: number
): string[] {
  return retireDecompositionTree(sql, missionId, parentTaskId, "bypassed", now);
}

// ---------------------------------------------------------------------------
// 4. POST /api/missions/:id/tasks/:task/refute (open to all registered contributors!)

export interface PreparedRefute {
  task: TaskState;
  isSubgoal: boolean;
  resolvesConjecture: boolean;
  decomp: DecompositionRow | null;
  subgoals: SubgoalSpec[];
  sub: SubgoalSpec | undefined;
  rootTaskId: string;
  parsed: ReturnType<typeof parseRefuteRequest>;
}

export type PrepareRefuteResult =
  | { ok: true; prepared: PreparedRefute }
  | { ok: false; status: number; body: Record<string, unknown> };

/**
 * Synchronous pre-validation for `POST .../refute` so both sync and async
 * (`?async=1`) handlers reject invalid targets/patches BEFORE recording rate
 * limits, inserting a `verifying` submission, or waking a verifier container.
 */
export function prepareRefute(
  ctx: Pick<DecomposeHubContext, "sql" | "mission" | "getTasks">,
  params: { taskId: string; rawBody: unknown }
): PrepareRefuteResult {
  const { sql, mission } = ctx;
  const missionId = mission.manifest.id;
  const { taskId, rawBody } = params;

  if (mission.manifest.mode !== "dag") {
    return { ok: false, status: 400, body: { error: "refutations are only supported on DAG missions" } };
  }

  const tasks = ctx.getTasks(missionId);
  const task = tasks.find((t) => t.def.id === taskId);
  if (!task) {
    return { ok: false, status: 404, body: { error: `unknown task: ${taskId}` } };
  }
  if (task.status === "verified") {
    return { ok: false, status: 409, body: { error: `task '${taskId}' is already kernel-verified` } };
  }
  if (task.status === "refuted") {
    return { ok: false, status: 409, body: { error: `task '${taskId}' is already kernel-refuted` } };
  }

  const isSubgoal = Boolean(task.def.decomp_id && task.def.subgoal_id && task.def.root_task_id);
  const resolvesConjecture = !isSubgoal && isOpenConjectureTask(mission.manifest, task.def);
  let decomp: DecompositionRow | null = null;
  let subgoals: SubgoalSpec[] = [];
  let sub: SubgoalSpec | undefined;
  if (isSubgoal) {
    decomp = getDecompositionRow(sql, missionId, task.def.root_task_id!, task.def.decomp_id!);
    if (!decomp || decomp.status !== "active") {
      return { ok: false, status: 409, body: { error: `decomposition '${task.def.decomp_id}' is not active` } };
    }
    subgoals = parseSubgoalsJson(decomp.subgoals_json);
    sub = subgoals.find((s) => s.id === task.def.subgoal_id);
    if (!sub) {
      return { ok: false, status: 404, body: { error: `subgoal '${task.def.subgoal_id}' not found` } };
    }
  } else {
    // Note: if a root task is marked `upstream_disputed` in hub metadata, we still
    // allow `POST .../refute` so contributors can upgrade an informal upstream
    // notice to a kernel-verified counterexample. Only a pre-existing kernel-verified
    // root refutation blocks further root refutations.
    const existingRootRef = sql
      .exec<{ id: string }>(
        "SELECT id FROM refutations WHERE mission_id = ? AND task_id = ? AND target_kind = 'root' LIMIT 1",
        missionId,
        taskId
      )
      .toArray();
    if (existingRootRef.length > 0) {
      return {
        ok: false,
        status: 409,
        body: { error: `root task '${taskId}' already has a kernel-verified counterexample (${existingRootRef[0].id})` },
      };
    }
  }

  const libRoot = mission.verify_contract?.lib_root ?? null;
  const frozenPaths = decomp
    ? [...mission.manifest.frozen_paths, decomp.reduction_file]
    : mission.manifest.frozen_paths;

  let parsed: ReturnType<typeof parseRefuteRequest>;
  try {
    parsed = parseRefuteRequest(rawBody, { libRoot, frozenPaths });
  } catch (e) {
    return {
      ok: false,
      status: 422,
      body: { error: e instanceof Error ? e.message : String(e), stage: "patch" },
    };
  }

  const rootTaskId = isSubgoal ? task.def.root_task_id! : task.def.id;
  return {
    ok: true,
    prepared: { task, isSubgoal, resolvesConjecture, decomp, subgoals, sub, rootTaskId, parsed },
  };
}

export async function executeRefute(
  ctx: DecomposeHubContext,
  params: {
    taskId: string;
    contributor: string;
    rawBody: unknown;
    existingSubmissionId?: string;
    createdAt?: number;
    prepared?: PreparedRefute;
  }
): Promise<{ status: number; body: Record<string, unknown> }> {
  const { sql, mission } = ctx;
  const missionId = mission.manifest.id;
  const { taskId, contributor, rawBody, existingSubmissionId } = params;

  let prep = params.prepared;
  if (!prep) {
    const check = prepareRefute(ctx, { taskId, rawBody });
    if (!check.ok) {
      return { status: check.status, body: check.body };
    }
    prep = check.prepared;
  }

  const { isSubgoal, resolvesConjecture, decomp, subgoals, sub, rootTaskId, parsed } = prep;
  const now = params.createdAt ?? ctx.now();
  const subId = existingSubmissionId ?? ctx.randomUUID();
  const patchSha = await ctx.sha256Hex(parsed.patch);

  const persistSubmission = (rec: {
    status: "accepted" | "rejected" | "error";
    accepted: boolean;
    score: number | null;
    points: number;
    summary: string;
    patch_sha256: string;
    proof_id?: string | null;
    verify_ms: number;
    stage?: string | null;
    diagnostics?: string | null;
    error?: string | null;
    completed_at: number;
  }) => {
    if (existingSubmissionId) {
      sql.exec(
        `UPDATE submissions
         SET status = ?,
             accepted = ?,
             score = ?,
             points = ?,
             summary = ?,
             patch_sha256 = ?,
             proof_id = ?,
             verify_ms = ?,
             stage = ?,
             diagnostics = ?,
             error = ?,
             completed_at = ?,
             kind = 'refute'
         WHERE id = ?`,
        rec.status,
        rec.accepted ? 1 : 0,
        rec.score,
        rec.points,
        rec.summary,
        rec.patch_sha256,
        rec.proof_id ?? null,
        rec.verify_ms,
        rec.stage ?? null,
        rec.diagnostics ?? null,
        rec.error ?? null,
        rec.completed_at,
        subId
      );
    } else {
      sql.exec(
        `INSERT INTO submissions
         (id, mission_id, task_id, contributor, status, accepted, score, points, summary, patch_sha256, proof_id, verify_ms, stage, diagnostics, error, created_at, completed_at, is_demo, kind)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'refute')`,
        subId,
        missionId,
        taskId,
        contributor,
        rec.status,
        rec.accepted ? 1 : 0,
        rec.score,
        rec.points,
        rec.summary,
        rec.patch_sha256,
        rec.proof_id ?? null,
        rec.verify_ms,
        rec.stage ?? null,
        rec.diagnostics ?? null,
        rec.error ?? null,
        now,
        rec.completed_at,
        mission.manifest.demo ? 1 : 0
      );
    }
  };

  const verifierReq: Record<string, unknown> = {
    mission_id: missionId,
    task_id: rootTaskId,
    refute_module: parsed.refute_module,
    refute_theorem: parsed.refute_theorem,
    patch: parsed.patch,
    frozen_paths: mission.manifest.frozen_paths,
    target_files: [parsed.refute_file],
    timeout_sec: mission.manifest.verifier.timeout_sec ?? 120,
    cache_state: false,
  };
  if (isSubgoal && decomp && sub) {
    verifierReq.decomp_id = decomp.decomp_id;
    verifierReq.subgoals = subgoals.map((s) => ({ id: s.id, statement: s.statement }));
    verifierReq.subgoal_id = sub.id;
  }

  const vCall = await ctx.callVerifierAction("/refute", ctx.getMissionFiles(missionId), verifierReq);
  if (!vCall.ok) {
    const failedAt = ctx.now();
    if (existingSubmissionId) {
      persistSubmission({
        status: "error",
        accepted: false,
        score: null,
        points: 0,
        summary: vCall.error,
        patch_sha256: patchSha,
        verify_ms: 0,
        stage: "sandbox",
        error: vCall.error,
        completed_at: failedAt,
      });
      ctx.emit({
        kind: "submission_rejected",
        submission_id: subId,
        mission_id: missionId,
        task_id: taskId,
        contributor,
        accepted: false,
        score: null,
        summary: `refutation error: ${vCall.error}`,
        timestamp: failedAt,
      });
    }
    return {
      status: vCall.status,
      body: {
        accepted: false,
        ...(existingSubmissionId ? { status: "error", submission_id: subId } : {}),
        error: vCall.error,
        stage: "sandbox",
      },
    };
  }
  const cRes = vCall.res;
  const finishedAt = ctx.now();

  if (!cRes.ok || cRes.spec_sha256 !== mission.spec_sha256) {
    const reason = !cRes.ok
      ? cRes.summary || "refutation verification failed"
      : `spec hash mismatch: expected '${mission.spec_sha256}', got '${cRes.spec_sha256}'`;
    const diag = sanitizeFailureDiagnostics(cRes.stage, cRes.diagnostics);
    persistSubmission({
      status: "rejected",
      accepted: false,
      score: null,
      points: 0,
      summary: reason,
      patch_sha256: patchSha,
      verify_ms: cRes.verify_ms ?? 0,
      stage: diag.stage ?? null,
      diagnostics: diag.diagnostics ?? null,
      error: reason,
      completed_at: finishedAt,
    });
    ctx.emit({
      kind: "submission_rejected",
      submission_id: subId,
      mission_id: missionId,
      task_id: taskId,
      contributor,
      accepted: false,
      score: null,
      summary: `refutation rejected: ${reason}`,
      timestamp: finishedAt,
    });
    return {
      status: 422,
      body: {
        accepted: false,
        status: "rejected",
        submission_id: subId,
        error: reason,
        verify_ms: cRes.verify_ms ?? 0,
        ...diag,
      },
    };
  }

  const storedPatch =
    cRes.normalized_patch && cRes.normalized_patch.trim() ? cRes.normalized_patch : parsed.patch;
  const storedPatchSha = await ctx.sha256Hex(storedPatch);
  const proofId = proofIdFromPatchSha(storedPatchSha);
  const permalink = `${ctx.hubOrigin}/proofs/${proofId}`;
  const refutationId = ctx.randomUUID();
  // Prevent self-refutation bounty farming: a proposer may cleanly retract their own false
  // subgoal (invalidating the split + recording a strike), but earns 0 bounty points.
  const isSelfRefutation = Boolean(isSubgoal && decomp && decomp.proposer === contributor);

  return ctx.withMissionLock(missionId, async () => {
    const ts = ctx.now();
    let invalidatedDecompId: string | null = null;
    let reopenedParentTaskId: string | null = null;
    let proposerFlagged: string | null = null;
    let retiredDecomps: string[] = [];
    let bounty: number;

    const rejectLockRace = (msg: string) => {
      if (existingSubmissionId) {
        persistSubmission({
          status: "rejected",
          accepted: false,
          score: null,
          points: 0,
          summary: msg,
          patch_sha256: storedPatchSha,
          verify_ms: cRes.verify_ms ?? 0,
          error: msg,
          completed_at: ts,
        });
        ctx.emit({
          kind: "submission_rejected",
          submission_id: subId,
          mission_id: missionId,
          task_id: taskId,
          contributor,
          accepted: false,
          score: null,
          summary: msg,
          timestamp: ts,
        });
      }
      return {
        status: 409,
        body: {
          accepted: false,
          ...(existingSubmissionId ? { status: "rejected", submission_id: subId } : {}),
          error: msg,
        },
      };
    };

    if (isSubgoal && decomp && sub) {
      const latestDecomp = getDecompositionRow(sql, missionId, rootTaskId, decomp.decomp_id);
      if (!latestDecomp || latestDecomp.status !== "active") {
        return rejectLockRace(`decomposition '${decomp.decomp_id}' was already closed`);
      }
      invalidatedDecompId = latestDecomp.decomp_id;
      reopenedParentTaskId = latestDecomp.parent_task_id;
      proposerFlagged = latestDecomp.proposer;
      bounty = isSelfRefutation ? 0 : computeRefutationBounty(mission.manifest);

      // Invalidate decomposition, forfeit architect share, retire all sibling/nested subgoals.
      retireDecompositionTree(sql, missionId, latestDecomp.parent_task_id, "refuted", ts, {
        refuted_subgoal_id: sub.id,
        refutation_id: refutationId,
      });

      // Restore parent task to clean open state (if not already resolved).
      sql.exec(
        `UPDATE tasks
         SET status = CASE WHEN status IN ('verified', 'refuted') THEN status ELSE 'open' END
         WHERE mission_id = ? AND task_id = ?`,
        missionId,
        latestDecomp.parent_task_id
      );

      // Record strike against proposer on decomposition_allowlist for maintainer review.
      sql.exec(
        `UPDATE decomposition_allowlist
         SET strikes = strikes + 1, updated_at = ?
         WHERE handle = ?`,
        ts,
        latestDecomp.proposer
      );
    } else {
      const latestTasks = ctx.getTasks(missionId);
      const latestTask = latestTasks.find((t) => t.def.id === taskId);
      if (!latestTask || latestTask.status === "verified") {
        return rejectLockRace(`task '${taskId}' is already kernel-verified`);
      }
      if (latestTask.status === "refuted") {
        return rejectLockRace(`task '${taskId}' is already kernel-refuted`);
      }
      // Prevent concurrent or repeated bounty farming on an already-refuted/disputed root task.
      const existingRootRef = sql
        .exec<{ id: string }>(
          "SELECT id FROM refutations WHERE mission_id = ? AND task_id = ? AND target_kind = 'root' LIMIT 1",
          missionId,
          taskId
        )
        .toArray();
      if (existingRootRef.length > 0) {
        return rejectLockRace(
          `root task '${taskId}' already has a kernel-verified counterexample (${existingRootRef[0].id})`
        );
      }

      if (resolvesConjecture) {
        // Two-sided open conjecture: kernel-verified `¬ T` resolves the conjecture cleanly
        // for full task points, with zero-inflation protection deducting any prior subgoal
        // solver or nested depth-2 architect_vest points already earned by this contributor
        // under the same root conjecture.
        const fullPoints = computeOpenConjectureRefutePoints(mission.manifest, latestTask);
        const priorSubgoalPoints = sql
          .exec<{ p: number }>(
            `SELECT COALESCE(SUM(s.effective_points), 0) AS p
             FROM scored_submissions s
             JOIN tasks t ON t.mission_id = s.mission_id AND t.task_id = s.task_id
             WHERE s.mission_id = ? AND s.contributor = ? AND s.accepted = 1 AND s.is_demo = 0
               AND COALESCE(s.kind, 'submit') IN ('subgoal', 'architect_vest')
               AND t.root_task_id = ?`,
            missionId,
            contributor,
            rootTaskId
          )
          .one().p;
        bounty = Math.max(0, fullPoints - priorSubgoalPoints);

        // Retire any active decomposition tree cleanly without penalizing the proposer
        // (disproving a genuine open conjecture is not a proposer formalization error).
        retiredDecomps = retireDecompositionTree(sql, missionId, taskId, "refuted", ts, {
          refutation_id: refutationId,
        });

        sql.exec(
          `UPDATE tasks
           SET status = 'refuted',
               best_score = 1.0,
               verified_by = ?,
               lease_contributor = NULL,
               lease_token = NULL,
               lease_expires_at = NULL,
               lease_ip = NULL,
               attempts = attempts + 1
           WHERE mission_id = ? AND task_id = ?`,
          contributor,
          missionId,
          taskId
        );
      } else {
        bounty = computeRefutationBounty(mission.manifest);
      }
    }

    const specAtRefute = isSubgoal && sub ? sub.subgoal_spec_sha256 : mission.spec_sha256;

    sql.exec(
      `INSERT INTO refutations
       (id, mission_id, task_id, root_task_id, decomp_id, subgoal_id, target_kind, refuter, summary, patch, patch_sha256, spec_sha256, points, verify_ms, created_at, is_demo, resolves_conjecture)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      refutationId,
      missionId,
      taskId,
      rootTaskId,
      invalidatedDecompId,
      sub?.id ?? null,
      isSubgoal ? "subgoal" : "root",
      contributor,
      cRes.summary,
      storedPatch,
      storedPatchSha,
      specAtRefute,
      bounty,
      cRes.verify_ms ?? 0,
      ts,
      mission.manifest.demo ? 1 : 0,
      resolvesConjecture ? 1 : 0
    );

    persistSubmission({
      status: "accepted",
      accepted: true,
      score: 1.0,
      points: bounty,
      summary: cRes.summary,
      patch_sha256: storedPatchSha,
      proof_id: proofId,
      verify_ms: cRes.verify_ms ?? 0,
      completed_at: ts,
    });

    // Permanently store the verified counterexample in the public ledger (`in_history = 0`).
    sql.exec(
      `INSERT INTO accepted_patches
       (mission_id, task_id, submission_id, contributor, summary, patch, spec_sha256, created_at, patch_sha256, is_demo, entry_kind, in_history, decomp_meta_json, scoring_provenance_json)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'refutation', 0, ?, ?)`,
      missionId,
      taskId,
      subId,
      contributor,
      cRes.summary,
      storedPatch,
      specAtRefute,
      ts,
      storedPatchSha,
      mission.manifest.demo ? 1 : 0,
      JSON.stringify({
        refutation_id: refutationId,
        target_kind: isSubgoal ? "subgoal" : "root",
        root_task_id: rootTaskId,
        ...(resolvesConjecture ? { open_conjecture: true, resolution: "refuted" } : {}),
        ...(invalidatedDecompId ? { decomp_id: invalidatedDecompId } : {}),
        ...(reopenedParentTaskId ? { parent_task_id: reopenedParentTaskId } : {}),
        ...(sub ? { subgoal_id: sub.id, subgoal_title: sub.title } : {}),
        ...(proposerFlagged ? { proposer: proposerFlagged } : {}),
      }),
      ctx.scoringProvenanceJson
    );

    ctx.emit({
      kind: isSubgoal ? "decomposition_refuted" : "task_refuted",
      submission_id: subId,
      mission_id: missionId,
      task_id: taskId,
      contributor,
      accepted: true,
      score: resolvesConjecture ? 1.0 : null,
      summary: isSubgoal
        ? `${contributor} refuted subgoal ${sub?.id} (invalidated ${invalidatedDecompId}, reopened ${reopenedParentTaskId}, +${bounty} pts)`
        : resolvesConjecture
          ? `${contributor} refuted open conjecture ${taskId} (¬ ${taskId} kernel-verified, resolved, +${bounty} pts)`
          : `${contributor} verified counterexample ¬ ${taskId} (flagged disputed_counterexample, +${bounty} pts)`,
      timestamp: ts,
    });

    return {
      status: 200,
      body: {
        refuted: true,
        accepted: true,
        status: "accepted",
        refutation_id: refutationId,
        submission_id: subId,
        target_kind: isSubgoal ? "subgoal" : "root",
        mission_id: missionId,
        task_id: taskId,
        ...(invalidatedDecompId
          ? {
              invalidated_decomp_id: invalidatedDecompId,
              reopened_parent_task_id: reopenedParentTaskId,
              proposer_flagged: proposerFlagged,
            }
          : resolvesConjecture
            ? {
                resolved: true,
                resolution: "refuted",
                open_conjecture: true,
                task_status: "refuted",
                ...(retiredDecomps.length > 0 ? { retired_decompositions: retiredDecomps } : {}),
              }
            : {
                disputed_counterexample: true,
              }),
        contributor,
        points_awarded: bounty,
        patch_sha256: storedPatchSha,
        proof_id: proofId,
        permalink,
        verify_ms: cRes.verify_ms ?? 0,
        summary: cRes.summary,
      },
    };
  });
}
