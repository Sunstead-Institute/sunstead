/**
 * Sunstead core rules (frozen-path policy, DAG readiness, task transitions,
 * points) for the Cloudflare hub. Unit tests: cloudflare/test/core.test.ts.
 */

export type MissionMode = "dag" | "hillclimb";
export type ScoreDirection = "maximize" | "minimize";
export type TaskStatus = "open" | "leased" | "verified" | "refuted";
export type VerifierKind = "lean4" | "lean4-v4.35.0" | "lean4-v4.31.0";

export interface VerifierConfig {
  image: string;
  toolchain?: string;
  command: string[];
  timeout_sec?: number;
  memory_mb?: number;
}

export interface RepoSnapshotConfig {
  mode: "repo-snapshot";
  snapshot_id: string;
  lean_options?: string[];
  allowed_import_prefixes?: string[];
  allow_module_system?: boolean;
}

export const SUPPORTED_VERIFIER_TOOLCHAINS: Record<
  VerifierKind,
  { toolchain: string; container_app: string; default_image: string; max_instances: number }
> = {
  lean4: {
    toolchain: "leanprover/lean4:v4.36.0",
    container_app: "sunstead-verifier-lean4",
    default_image: "sunstead/verifier-lean4:v0.2",
    max_instances: 6,
  },
  "lean4-v4.35.0": {
    toolchain: "leanprover/lean4:v4.35.0",
    container_app: "sunstead-verifier-lean4-v435",
    default_image: "sunstead/verifier-lean4-v4.35.0:v0.1",
    max_instances: 4,
  },
  "lean4-v4.31.0": {
    toolchain: "leanprover/lean4:v4.31.0",
    container_app: "sunstead-verifier-lean4-v431",
    default_image: "sunstead/verifier-lean4-v4.31.0:v0.1",
    max_instances: 4,
  },
};

export const VERIFIER_POOL_SIZE: Record<VerifierKind, number> = {
  lean4: SUPPORTED_VERIFIER_TOOLCHAINS.lean4.max_instances,
  "lean4-v4.35.0": SUPPORTED_VERIFIER_TOOLCHAINS["lean4-v4.35.0"].max_instances,
  "lean4-v4.31.0": SUPPORTED_VERIFIER_TOOLCHAINS["lean4-v4.31.0"].max_instances,
};

/**
 * How long an idle verifier container stays up (`sleepAfter` in containers.ts).
 * A slot released less than this long ago is still running with Lean and Mathlib
 * in its page cache; a cold one has to start and read several GB of `.olean`s
 * first, which cost 30-40 s per Mathlib submission in production (Nov 2026).
 */
export const VERIFIER_WARM_MS = 10 * 60 * 1000;

/**
 * Affinity-aware container slot pool across each toolchain's `maxInstances`.
 * Concurrent verifications on the same mission fan out across distinct container
 * slots instead of queueing on a single per-mission container. Idle slots are
 * picked warmest first: a running container for the same mission, then the most
 * recently used running container, and only then a cold one.
 */
export class VerifierSlotPool {
  private readonly sizes: Record<VerifierKind, number>;
  private readonly pools = new Map<
    string,
    {
      busy: boolean[];
      lastMission: Array<string | null>;
      lastUsed: number[];
      releasedAt: number[];
      waiters: Array<{ missionId: string; resolve: (slot: number) => void }>;
      tick: number;
    }
  >();

  private readonly now: () => number;
  private readonly warmMs: number;

  constructor(
    sizes: Record<VerifierKind, number> = VERIFIER_POOL_SIZE,
    now: () => number = () => Date.now(),
    warmMs: number = VERIFIER_WARM_MS
  ) {
    this.sizes = { ...sizes };
    this.now = now;
    this.warmMs = warmMs;
  }

  private getPool(kind: VerifierKind, image: string) {
    const key = `${kind}:${image}`;
    let pool = this.pools.get(key);
    if (!pool) {
      const size = Math.max(1, this.sizes[kind] ?? 1);
      pool = {
        busy: Array<boolean>(size).fill(false),
        lastMission: Array<string | null>(size).fill(null),
        lastUsed: Array<number>(size).fill(0),
        releasedAt: Array<number>(size).fill(Number.NEGATIVE_INFINITY),
        waiters: [],
        tick: 0,
      };
      this.pools.set(key, pool);
    }
    return pool;
  }

  async acquire(kind: VerifierKind, image: string, missionId: string): Promise<number> {
    const pool = this.getPool(kind, image);
    const now = this.now();
    const idle = (i: number) => !pool.busy[i];
    const warm = (i: number) => now - pool.releasedAt[i] < this.warmMs;
    const pick = (ok: (i: number) => boolean) => {
      let best = -1;
      for (let i = 0; i < pool.busy.length; i++) {
        if (ok(i) && (best === -1 || pool.lastUsed[i] > pool.lastUsed[best])) best = i;
      }
      return best;
    };
    // 1. A still-running slot that last verified this mission.
    let chosen = pick((i) => idle(i) && warm(i) && pool.lastMission[i] === missionId);
    // 2. Any still-running slot, most recently used first (Lean + Mathlib stay in its page cache).
    if (chosen === -1) chosen = pick((i) => idle(i) && warm(i));
    // 3. A cold slot that last ran this mission, else the most recently used cold slot.
    if (chosen === -1) chosen = pick((i) => idle(i) && pool.lastMission[i] === missionId);
    if (chosen === -1) chosen = pick(idle);
    if (chosen !== -1) {
      pool.busy[chosen] = true;
      pool.lastMission[chosen] = missionId;
      pool.lastUsed[chosen] = ++pool.tick;
      return chosen;
    }
    // 4. All slots busy: queue FIFO until a running verification finishes.
    return new Promise<number>((resolve) => {
      pool.waiters.push({ missionId, resolve });
    });
  }

  release(kind: VerifierKind, image: string, slot: number): void {
    const pool = this.getPool(kind, image);
    if (slot < 0 || slot >= pool.busy.length) return;
    if (pool.waiters.length > 0) {
      // Hand off to a waiter matching this slot's warm mission if one is queued; else FIFO.
      const warmIdx = pool.waiters.findIndex((w) => w.missionId === pool.lastMission[slot]);
      const next = pool.waiters.splice(warmIdx >= 0 ? warmIdx : 0, 1)[0];
      pool.lastMission[slot] = next.missionId;
      pool.lastUsed[slot] = ++pool.tick;
      next.resolve(slot);
      return;
    }
    pool.busy[slot] = false;
    pool.releasedAt[slot] = this.now();
  }

  async withSlot<T>(
    kind: VerifierKind,
    image: string,
    missionId: string,
    fn: (slot: number) => Promise<T>
  ): Promise<T> {
    const slot = await this.acquire(kind, image, missionId);
    try {
      return await fn(slot);
    } finally {
      this.release(kind, image, slot);
    }
  }
}

export function verifierSlotName(kind: VerifierKind, image: string, slot: number): string {
  return `${kind}:${image}:slot-${slot}`;
}

/**
 * Resolve a mission's verifier configuration (`toolchain` and/or `image`) to the
 * matching Cloudflare Container routing key. Fails closed on unsupported
 * toolchains or non-Lean images so missions can never route to the wrong kernel.
 */
export function resolveVerifierKind(verifier: Pick<VerifierConfig, "image" | "toolchain">): VerifierKind {
  const tc = (verifier.toolchain ?? "").trim();
  const img = (verifier.image ?? "").trim();
  if (tc) {
    if (tc === "leanprover/lean4:v4.36.0") return "lean4";
    if (tc === "leanprover/lean4:v4.35.0") return "lean4-v4.35.0";
    if (tc === "leanprover/lean4:v4.31.0") return "lean4-v4.31.0";
    throw new Error(`unsupported verifier toolchain: ${tc}`);
  }
  if (img.includes("lean4-v4.35.0")) return "lean4-v4.35.0";
  if (img.includes("lean4-v4.31.0")) return "lean4-v4.31.0";
  if (img.includes("lean4")) return "lean4";
  throw new Error(`unsupported verifier image: ${img}`);
}

export interface UpstreamProvenance {
  repo: string;
  commit: string;
  license: string;
  issue_url?: string;
}

export interface DecompositionPolicy {
  enabled: boolean;
  /** Phase 1 default: require explicit maintainer allowlist (`true`). */
  require_allowlist?: boolean;
  /** Default true: direct proof of parent T immediately closes T and retires open children. */
  allow_direct_bypass?: boolean;
  /** Max nesting depth (default 2, capped at MAX_DECOMPOSE_DEPTH). */
  max_depth?: number;
}

export interface VerifyTaskContract {
  module: string;
  theorem: string;
  statement: string;
}

export interface MissionVerifyContract {
  lib_root: string;
  statement_preamble: string;
  frozen_lean_modules: string[];
  tasks: Record<string, VerifyTaskContract>;
}

export interface DisputedCounterexample {
  refutation_id: string;
  refuter: string;
  proof_id: string | null;
  summary: string;
  created_at: number;
}

export interface RefutedResolution {
  refutation_id: string;
  refuter: string;
  proof_id: string | null;
  summary: string;
  created_at: number;
}

export interface UpstreamDispute {
  source: string;
  reason: string;
  url?: string;
  recorded_at: string;
}

export type UpstreamAnchorKind =
  | "in_place_sorry"
  | "challenge_node"
  | "extracted_lemma"
  | "optimization_spec"
  | "none";

export interface TaskDefinition {
  id: string;
  title: string;
  description?: string;
  target_files: string[];
  depends_on?: string[];
  baseline_score?: number | null;
  /**
   * Best result known outside Sunstead for a hill-climb task (literature, public
   * circuit collections, or a reproducible stock heuristic). Injected from
   * `missions/best-known.json` by `scripts/sync-assets.mjs`; full log-ratio points
   * are paid only for the part of an improvement that goes beyond it.
   */
  best_known?: BestKnown | null;
  /**
   * Hub-only notice that a task's pinned upstream statement is known to be false
   * or misstated upstream. Injected from `missions/task-disputes.json` by
   * `scripts/sync-assets.mjs` without altering any mission's `spec_sha256`.
   */
  upstream_disputed?: UpstreamDispute | null;
  upstream_url?: string;
  /** Optional explicit override for how `upstream_url` anchors into the upstream repo. */
  upstream_anchor?: UpstreamAnchorKind;
  /** Optional per-task override for two-sided open-conjecture resolution (`¬ T` resolves task); inherits mission.open_conjecture. */
  open_conjecture?: boolean;
  /** Dynamic decomposition subgoal fields (v2). */
  parent_task_id?: string | null;
  root_task_id?: string | null;
  decomp_id?: string | null;
  subgoal_id?: string | null;
  decomp_depth?: number;
  subgoal_spec_sha256?: string | null;
  subgoal_statement?: string | null;
  subgoal_module?: string | null;
  subgoal_theorem?: string | null;
  decomp_statements_module?: string | null;
  decomp_statements_namespace?: string | null;
  reduction_file?: string | null;
}

export type BestKnownKind = "literature" | "collection" | "heuristic" | "derived" | "proxy" | "record";

export interface BestKnown {
  value: number;
  /** How the value was established; see docs/BEST-KNOWN.md. */
  kind: BestKnownKind;
  /** Human-readable citation (authors, title, year) or how to reproduce it. */
  source: string;
  url: string;
  /** The value is a proven optimum: nothing can beat it, so the task only pays the match bonus. */
  proven_optimal?: boolean;
  /** Date (YYYY-MM-DD) the value was last checked against the literature. */
  checked: string;
  note?: string;
}

export interface MissionManifest {
  id: string;
  title: string;
  description?: string;
  tier: number;
  mode: MissionMode;
  repo?: string;
  upstream?: UpstreamProvenance;
  snapshot?: RepoSnapshotConfig;
  decomposition?: DecompositionPolicy;
  /** True when tasks are open mathematical conjectures resolvable by either proving `T` or kernel-refuting `¬ T`. */
  open_conjecture?: boolean;
  frozen_paths: string[];
  verifier: VerifierConfig;
  score_direction?: ScoreDirection;
  /** Demo/sandbox missions exercise the machinery and award 0 leaderboard points. */
  demo?: boolean;
  tasks: TaskDefinition[];
}

export interface Lease {
  task_id: string;
  contributor: string;
  lease_token: string;
  expires_at_unix: number;
}

export interface TaskState {
  def: TaskDefinition;
  status: TaskStatus;
  best_score: number | null;
  verified_by: string | null;
  active_lease: Lease | null;
  attempts: number;
  disputed_counterexample?: DisputedCounterexample | null;
  refuted_resolution?: RefutedResolution | null;
}

/** True when a root task is an open conjecture resolvable by kernel-verified `¬ T` via POST .../refute. */
export function isOpenConjectureTask(
  mission: Pick<MissionManifest, "open_conjecture">,
  task: Pick<TaskDefinition, "open_conjecture" | "decomp_id">
): boolean {
  // Spawned decomposition subgoals are never open conjectures themselves; refuting `¬ L_i`
  // invalidates the decomposition and reopens the parent task.
  if (task.decomp_id) return false;
  if (typeof task.open_conjecture === "boolean") return task.open_conjecture;
  return Boolean(mission.open_conjecture);
}

/** True when a DAG task is terminally resolved (either proved `verified` or open-conjecture `refuted`). */
export function isTaskResolved(task: Pick<TaskState, "status">): boolean {
  return task.status === "verified" || task.status === "refuted";
}

export interface Verdict {
  ok: boolean;
  score?: number | null;
  summary: string;
  spec_sha256: string;
}

export function normalizeRelPath(raw: string): string {
  const trimmed = raw.trim().replace(/^"+|"+$/g, "");
  if (
    !trimmed ||
    trimmed.startsWith("/") ||
    trimmed.includes("\0") ||
    trimmed.includes("\\")
  ) {
    throw new Error(`unsafe or non-normalized path in patch: ${raw}`);
  }
  const stripped = trimmed.startsWith("a/")
    ? trimmed.slice(2)
    : trimmed.startsWith("b/")
      ? trimmed.slice(2)
      : trimmed;

  const parts: string[] = [];
  for (const seg of stripped.split("/")) {
    if (!seg || seg === ".") continue;
    if (seg === "..") {
      throw new Error(`unsafe or non-normalized path in patch: ${raw}`);
    }
    parts.push(seg);
  }
  if (parts.length === 0) {
    throw new Error(`unsafe or non-normalized path in patch: ${raw}`);
  }
  return parts.join("/");
}

const HUNK_HEADER_RE = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;

export function extractPatchPaths(patch: string): string[] {
  const paths = new Set<string>();
  let oldRem = 0;
  let newRem = 0;

  for (const line of patch.split(/\r?\n/)) {
    if (oldRem > 0 || newRem > 0) {
      if (line.startsWith("\\ ")) {
        continue;
      }
      if (line.startsWith(" ") && oldRem > 0 && newRem > 0) {
        oldRem -= 1;
        newRem -= 1;
        continue;
      }
      if (line.startsWith("-") && oldRem > 0) {
        oldRem -= 1;
        continue;
      }
      if (line.startsWith("+") && newRem > 0) {
        newRem -= 1;
        continue;
      }
      if (line === "" && oldRem > 0 && newRem > 0) {
        oldRem -= 1;
        newRem -= 1;
        continue;
      }
      // Line does not belong to the active hunk; return to header state and parse it below.
      oldRem = 0;
      newRem = 0;
    }

    if (line.startsWith("GIT binary patch") || line.startsWith("Binary files ")) {
      throw new Error("binary patches are forbidden");
    }
    if (
      line.startsWith("new file mode 120") ||
      line.startsWith("deleted file mode 120") ||
      line.startsWith("old mode 120") ||
      line.startsWith("new mode 120")
    ) {
      throw new Error("symlink mode changes (120000) are forbidden");
    }

    const hunk = HUNK_HEADER_RE.exec(line);
    if (hunk) {
      oldRem = hunk[2] !== undefined ? Number(hunk[2]) : 1;
      newRem = hunk[4] !== undefined ? Number(hunk[4]) : 1;
      continue;
    }

    if (line.startsWith("diff --git ")) {
      const rest = line.slice("diff --git ".length).trim();
      const tokens = rest.split(/\s+/);
      if (tokens.length >= 2) {
        paths.add(normalizeRelPath(tokens[0]));
        paths.add(normalizeRelPath(tokens[1]));
      }
    } else if (line.startsWith("rename from ")) {
      paths.add(normalizeRelPath(line.slice("rename from ".length)));
    } else if (line.startsWith("rename to ")) {
      paths.add(normalizeRelPath(line.slice("rename to ".length)));
    } else if (line.startsWith("copy from ")) {
      paths.add(normalizeRelPath(line.slice("copy from ".length)));
    } else if (line.startsWith("copy to ")) {
      paths.add(normalizeRelPath(line.slice("copy to ".length)));
    } else if (line.startsWith("--- ")) {
      const p = line.slice(4).split("\t")[0].trim();
      if (p !== "/dev/null") paths.add(normalizeRelPath(p));
    } else if (line.startsWith("+++ ")) {
      const p = line.slice(4).split("\t")[0].trim();
      if (p !== "/dev/null") paths.add(normalizeRelPath(p));
    }
  }
  if (paths.size === 0) {
    throw new Error("patch is empty or modifies no files");
  }
  return Array.from(paths).sort();
}

function segmentMatches(pat: string, seg: string): boolean {
  const dp = Array.from({ length: pat.length + 1 }, () =>
    Array<boolean>(seg.length + 1).fill(false)
  );
  dp[0][0] = true;
  for (let i = 1; i <= pat.length; i++) {
    if (pat[i - 1] === "*") dp[i][0] = dp[i - 1][0];
  }
  for (let i = 1; i <= pat.length; i++) {
    for (let j = 1; j <= seg.length; j++) {
      if (pat[i - 1] === "*") {
        dp[i][j] = dp[i - 1][j] || dp[i][j - 1];
      } else if (pat[i - 1] === "?" || pat[i - 1] === seg[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      }
    }
  }
  return dp[pat.length][seg.length];
}

function matchSegments(pat: string[], path: string[]): boolean {
  if (pat.length === 0 && path.length === 0) return true;
  if (pat[0] === "**") {
    return matchSegments(pat.slice(1), path) || (path.length > 0 && matchSegments(pat, path.slice(1)));
  }
  if (pat.length > 0 && path.length > 0) {
    return segmentMatches(pat[0], path[0]) && matchSegments(pat.slice(1), path.slice(1));
  }
  return false;
}

export function globMatches(pattern: string, relPath: string): boolean {
  return matchSegments(
    pattern.split("/").filter(Boolean),
    relPath.split("/").filter(Boolean)
  );
}

export function validateTouchedPaths(
  touched: string[],
  frozenPaths: string[],
  targetFiles: string[]
): void {
  if (touched.length === 0) {
    throw new Error("patch is empty or modifies no files");
  }
  for (const raw of touched) {
    const path = normalizeRelPath(raw);
    for (const frozen of frozenPaths) {
      if (globMatches(frozen, path)) {
        throw new Error(`patch modifies frozen path '${path}' (matched '${frozen}')`);
      }
    }
    if (targetFiles.length > 0 && !targetFiles.some((t) => globMatches(t, path))) {
      throw new Error(`patch modifies '${path}', which is outside allowed target_files`);
    }
  }
}

export function validatePatch(
  patch: string,
  frozenPaths: string[],
  targetFiles: string[]
): string[] {
  const touched = extractPatchPaths(patch);
  validateTouchedPaths(touched, frozenPaths, targetFiles);
  return touched;
}

export function isTaskDisputed(
  task: Pick<TaskState, "def" | "disputed_counterexample">
): boolean {
  return Boolean(task.disputed_counterexample || task.def.upstream_disputed);
}

export function taskDisputeReason(
  task: Pick<TaskState, "def" | "disputed_counterexample">
): string | null {
  if (task.disputed_counterexample) {
    const ref = task.disputed_counterexample;
    return `task '${task.def.id}' has a kernel-verified counterexample (${ref.refutation_id} by ${ref.refuter})`;
  }
  if (task.def.upstream_disputed) {
    const u = task.def.upstream_disputed;
    return `task '${task.def.id}' is marked upstream-disputed${u.url ? ` (${u.url})` : ""}: ${u.reason}`;
  }
  return null;
}

export function isTaskUnlocked(
  task: TaskState,
  allTasks: TaskState[],
  byId?: ReadonlyMap<string, TaskState>
): boolean {
  const deps = task.def.depends_on || [];
  if (deps.length === 0) return true;
  return deps.every((depId) => {
    const found = byId ? byId.get(depId) : allTasks.find((other) => other.def.id === depId);
    return found?.status === "verified";
  });
}

export function computeFrontier(mode: MissionMode, tasks: TaskState[]): string[] {
  const byId = new Map<string, TaskState>(tasks.map((t) => [t.def.id, t]));
  return tasks
    .filter((t) => {
      if (isTaskDisputed(t)) return false;
      const unlocked = isTaskUnlocked(t, tasks, byId);
      return mode === "dag" ? unlocked && !isTaskResolved(t) : unlocked;
    })
    .map((t) => t.def.id);
}

export function applyClaim(
  mode: MissionMode,
  allTasks: TaskState[],
  taskId: string,
  contributor: string,
  leaseToken: string,
  nowUnix: number,
  leaseDurationSec: number
): { lease: Lease; updated_status: TaskStatus } {
  const task = allTasks.find((t) => t.def.id === taskId);
  if (!task) throw new Error(`task not found: ${taskId}`);
  const disputeMsg = taskDisputeReason(task);
  if (disputeMsg) {
    throw new Error(`${disputeMsg} and cannot be claimed`);
  }
  if (!isTaskUnlocked(task, allTasks)) {
    throw new Error(`task '${taskId}' is blocked on unverified dependencies`);
  }
  if (mode === "dag" && task.status === "verified") {
    throw new Error(`task '${taskId}' is already verified`);
  }
  if (mode === "dag" && task.status === "refuted") {
    throw new Error(`task '${taskId}' is already refuted`);
  }
  if (
    task.active_lease &&
    task.active_lease.expires_at_unix > nowUnix &&
    task.active_lease.contributor !== contributor
  ) {
    throw new Error(
      `task '${taskId}' is actively leased by '${task.active_lease.contributor}' until ${task.active_lease.expires_at_unix}`
    );
  }

  const lease: Lease = {
    task_id: taskId,
    contributor,
    lease_token: leaseToken,
    expires_at_unix: nowUnix + Math.max(60, Math.min(leaseDurationSec, 3600)),
  };
  return {
    lease,
    updated_status: task.status === "verified" ? "verified" : "leased",
  };
}

export function applyVerdict(
  mode: MissionMode,
  scoreDirection: ScoreDirection,
  frozenPaths: string[],
  expectedSpecSha256: string,
  allTasks: TaskState[],
  taskId: string,
  patch: string,
  verdict: Verdict
): { updated_status: TaskStatus; new_best_score: number | null; unlocked_dependents: string[] } {
  const task = allTasks.find((t) => t.def.id === taskId);
  if (!task) throw new Error(`task not found: ${taskId}`);
  if (!isTaskUnlocked(task, allTasks)) {
    throw new Error(`task '${taskId}' is blocked on unverified dependencies`);
  }
  if (mode === "dag" && task.status === "verified") {
    throw new Error(`task '${taskId}' is already verified`);
  }
  if (mode === "dag" && task.status === "refuted") {
    throw new Error(`task '${taskId}' is already refuted`);
  }

  validatePatch(patch, frozenPaths, task.def.target_files);

  if (!verdict.ok) {
    throw new Error(`verification failed: ${verdict.summary}`);
  }
  if (verdict.spec_sha256 !== expectedSpecSha256) {
    throw new Error(
      `spec hash mismatch: expected '${expectedSpecSha256}', got '${verdict.spec_sha256}'`
    );
  }

  let newBestScore: number | null;
  if (mode === "dag") {
    newBestScore = verdict.score ?? task.best_score;
  } else {
    const submitted = verdict.score;
    if (submitted === null || submitted === undefined || !Number.isFinite(submitted)) {
      throw new Error("hillclimb verdict missing numeric score");
    }
    if (task.best_score !== null) {
      const improved =
        scoreDirection === "maximize" ? submitted > task.best_score : submitted < task.best_score;
      if (!improved) {
        throw new Error(
          `hillclimb score ${submitted} does not strictly improve on best ${task.best_score}`
        );
      }
    }
    newBestScore = submitted;
  }

  const simulated = allTasks.map((t) =>
    t.def.id === taskId ? { ...t, status: "verified" as TaskStatus } : t
  );
  const simulatedById = new Map<string, TaskState>(simulated.map((t) => [t.def.id, t]));
  const unlockedDependents = simulated
    .filter(
      (c) =>
        (c.def.depends_on || []).includes(taskId) &&
        isTaskUnlocked(c, simulated, simulatedById) &&
        !isTaskResolved(c)
    )
    .map((t) => t.def.id);

  return {
    updated_status: "verified",
    new_best_score: newBestScore,
    unlocked_dependents: unlockedDependents,
  };
}

/**
 * Scale factor for hill-climb log-ratio scoring: floor(5000 * |ln(new / old)|).
 * Additivity of log ratios guarantees that splitting an improvement into tiny
 * steps can never earn more than landing it in one step, while giving tight open
 * world records (e.g. 47 -> 46 on matrix-rank444-f2 = 107 base pts + 150 crown)
 * research credit commensurate with Tier 1 DAG proofs (150-250 pts).
 */
export const HILLCLIMB_LOG_SCALE = 5000;

/** Flat points for a record that reaches (ties) the best known value without beating it. */
export const MATCH_BEST_KNOWN_POINTS = 25;
/** Flat points for a record within NEAR_BEST_KNOWN_FRACTION of the best known value, but short of it. */
export const NEAR_BEST_KNOWN_POINTS = 10;
export const NEAR_BEST_KNOWN_FRACTION = 0.05;

function strictlyBetter(direction: ScoreDirection, a: number, b: number): boolean {
  return direction === "minimize" ? a < b : a > b;
}

/** True when `score` strictly beats the task's best known value (false when none is recorded). */
export function beatsBestKnown(
  direction: ScoreDirection,
  bestKnown: BestKnown | null | undefined,
  score: number | null
): boolean {
  if (!bestKnown || score === null || !Number.isFinite(bestKnown.value)) return false;
  return strictlyBetter(direction, score, bestKnown.value);
}

function logRatioPoints(previous: number, next: number): number {
  if (previous > 0 && next > 0) {
    return Math.max(0, Math.floor(HILLCLIMB_LOG_SCALE * Math.abs(Math.log(next / previous))));
  }
  // Non-positive scores: fall back to relative change against |previous|.
  const rel = Math.abs(next - previous) / Math.max(Math.abs(previous), 1);
  return Math.max(0, Math.floor(HILLCLIMB_LOG_SCALE * rel));
}

/**
 * Points for an accepted submission.
 *
 * Demo missions (`mission.demo === true`) earn 0 leaderboard points.
 * DAG tasks pay a flat amount by tier and depth.
 *
 * Hill-climb records are scored against the task's `best_known` value (the best
 * result known outside Sunstead), not against the naive seed:
 * - The part of an improvement that goes beyond both the previous record and
 *   best_known pays floor(HILLCLIMB_LOG_SCALE * |ln(new / reference)|), where the
 *   reference is whichever of the two is better. Log ratios are additive, so
 *   splitting one improvement into many small records never earns more.
 * - A record that ties best_known pays MATCH_BEST_KNOWN_POINTS.
 * - A record short of best_known but within NEAR_BEST_KNOWN_FRACTION of it pays
 *   NEAR_BEST_KNOWN_POINTS; anything further away pays 0.
 * Reproducing a published result therefore earns a small flat amount, never a
 * breakthrough's worth. Tasks without best_known keep the legacy rule (log ratio
 * against the previous record; the first record with no baseline pays 100); CI
 * requires best_known on every non-demo hill-climb task.
 */
export function computePoints(
  mission: MissionManifest,
  task: TaskState,
  previousBest: number | null,
  newScore: number | null
): number {
  if (mission.demo) return 0;
  const hasDeps = (task.def.depends_on?.length ?? 0) > 0;
  if (mission.mode === "hillclimb") {
    const direction: ScoreDirection = mission.score_direction ?? "maximize";
    const bestKnown = task.def.best_known;
    if (bestKnown && Number.isFinite(bestKnown.value) && newScore !== null) {
      const b = bestKnown.value;
      const reference =
        previousBest !== null && strictlyBetter(direction, previousBest, b) ? previousBest : b;
      if (strictlyBetter(direction, newScore, reference)) return logRatioPoints(reference, newScore);
      if (newScore === b) return MATCH_BEST_KNOWN_POINTS;
      const gap = Math.abs(newScore - b) / Math.max(Math.abs(b), 1);
      return gap <= NEAR_BEST_KNOWN_FRACTION ? NEAR_BEST_KNOWN_POINTS : 0;
    }
    if (previousBest === null || newScore === null) return 100;
    return logRatioPoints(previousBest, newScore);
  }
  if (mission.tier === 1) {
    return hasDeps ? 250 : 150;
  }
  return hasDeps ? 150 : 100;
}

export interface SortableMissionSummary {
  id: string;
  tier: number;
  mode: MissionMode;
  demo?: boolean;
  total_tasks: number;
  verified_tasks: number;
  refuted_tasks?: number;
}

/** A DAG mission with every task resolved (proved or open-conjecture refuted) belongs in the Completed Showcase; hill-climb tracks stay open. */
export function isMissionCompleted(
  m: Pick<SortableMissionSummary, "mode" | "total_tasks" | "verified_tasks" | "refuted_tasks">
): boolean {
  return m.mode === "dag" && m.total_tasks > 0 && m.verified_tasks + (m.refuted_tasks ?? 0) >= m.total_tasks;
}

/**
 * Canonical mission ordering for `/api/missions`, `/join.txt`, and the homepage:
 * 1. Active (incomplete) non-demo missions first, with Tier 1 Blueprint DAGs ahead of Tier 2 optimization tracks.
 * 2. Completed (100% verified) non-demo DAG showcase missions next.
 * 3. Any `demo: true` sandbox missions last.
 */
export function sortMissionSummaries<T extends SortableMissionSummary>(missions: T[]): T[] {
  return [...missions].sort((a, b) => {
    const aDemo = a.demo ? 1 : 0;
    const bDemo = b.demo ? 1 : 0;
    if (aDemo !== bDemo) return aDemo - bDemo;

    const aDone = isMissionCompleted(a) ? 1 : 0;
    const bDone = isMissionCompleted(b) ? 1 : 0;
    if (aDone !== bDone) return aDone - bDone;

    // Positive tiers sort ascending (Tier 1 before Tier 2); Tier 0 goes after positive tiers.
    const aTier = a.tier > 0 ? a.tier : Number.MAX_SAFE_INTEGER;
    const bTier = b.tier > 0 ? b.tier : Number.MAX_SAFE_INTEGER;
    if (aTier !== bTier) return aTier - bTier;

    // Within the same tier, Blueprint DAGs come before hill-climb tracks.
    const aMode = a.mode === "dag" ? 0 : 1;
    const bMode = b.mode === "dag" ? 0 : 1;
    if (aMode !== bMode) return aMode - bMode;

    return a.id.localeCompare(b.id);
  });
}

export interface FilterableMissionSummary extends SortableMissionSummary {
  title: string;
  open_conjecture?: boolean;
  upstream?: Pick<UpstreamProvenance, "repo"> | null;
  verifier_toolchain?: string;
  frontier_task_ids: string[];
}

export interface MissionListFilters {
  mode?: MissionMode;
  tier?: number;
  open_conjecture?: boolean;
  toolchain?: string;
  has_frontier?: boolean;
  demo?: boolean;
  q?: string;
}

function parseBoolQueryParam(raw: string | null): boolean | undefined {
  if (raw === null) return undefined;
  const v = raw.trim().toLowerCase();
  if (v === "true" || v === "1") return true;
  if (v === "false" || v === "0") return false;
  return undefined;
}

/** Parse optional filter query parameters for `GET /api/missions`. */
export function parseMissionListFilters(params: URLSearchParams): MissionListFilters {
  const out: MissionListFilters = {};
  const rawMode = params.get("mode")?.trim().toLowerCase();
  if (rawMode === "dag" || rawMode === "hillclimb") {
    out.mode = rawMode;
  }
  const rawTier = params.get("tier")?.trim();
  if (rawTier) {
    const tier = Number(rawTier);
    if (Number.isInteger(tier) && tier > 0) {
      out.tier = tier;
    }
  }
  const openConj = parseBoolQueryParam(params.get("open_conjecture"));
  if (openConj !== undefined) out.open_conjecture = openConj;
  const rawToolchain = params.get("toolchain")?.trim();
  if (rawToolchain) out.toolchain = rawToolchain;
  const hasFrontier = parseBoolQueryParam(params.get("has_frontier"));
  if (hasFrontier !== undefined) out.has_frontier = hasFrontier;
  const demo = parseBoolQueryParam(params.get("demo"));
  if (demo !== undefined) out.demo = demo;
  const q = params.get("q")?.trim();
  if (q) out.q = q;
  return out;
}

/**
 * Filter mission summaries for `GET /api/missions`.
 * Returns all summaries unchanged when no filters are supplied.
 */
export function filterMissionSummaries<T extends FilterableMissionSummary>(
  summaries: T[],
  filters: MissionListFilters = {}
): T[] {
  const tcFilter = filters.toolchain?.trim().toLowerCase() || "";
  const qFilter = filters.q?.trim().toLowerCase() || "";
  return summaries.filter((m) => {
    if (filters.mode !== undefined && m.mode !== filters.mode) return false;
    if (filters.tier !== undefined && m.tier !== filters.tier) return false;
    if (
      typeof filters.open_conjecture === "boolean" &&
      Boolean(m.open_conjecture) !== filters.open_conjecture
    ) {
      return false;
    }
    if (tcFilter) {
      const tc = (m.verifier_toolchain ?? "leanprover/lean4:v4.36.0").toLowerCase();
      if (!tc.includes(tcFilter)) return false;
    }
    if (filters.has_frontier === true && m.frontier_task_ids.length === 0) {
      return false;
    }
    if (typeof filters.demo === "boolean" && Boolean(m.demo) !== filters.demo) {
      return false;
    }
    if (qFilter) {
      const matched =
        m.id.toLowerCase().includes(qFilter) ||
        m.title.toLowerCase().includes(qFilter) ||
        (m.upstream?.repo ?? "").toLowerCase().includes(qFilter);
      if (!matched) return false;
    }
    return true;
  });
}

export const FRONTIER_DEFAULT_LIMIT = 50;
export const FRONTIER_MAX_LIMIT = 200;

export interface MissionWithTasks {
  manifest: MissionManifest;
  tasks: TaskState[];
}

export interface GlobalFrontierFilters {
  include_demo?: boolean;
  unclaimed?: boolean;
  mode?: MissionMode;
  tier?: number;
  open_conjecture?: boolean;
  toolchain?: string;
  mission?: string;
  q?: string;
  limit?: number;
  offset?: number;
}

export interface GlobalFrontierEntry {
  mission_id: string;
  mission_title: string;
  task_id: string;
  title: string;
  mode: MissionMode;
  tier: number;
  open_conjecture: boolean;
  toolchain: string;
  verifier_image: string;
  status: TaskStatus;
  leased: boolean;
  lease_contributor: string | null;
  best_score: number | null;
  best_known: BestKnown | null;
  upstream_url: string | null;
  target_files: string[];
  depends_on: string[];
}

export interface GlobalFrontierResponse {
  total_matching: number;
  limit: number;
  offset: number;
  returned: number;
  tasks: GlobalFrontierEntry[];
}

/** Parse query parameters for `GET /api/frontier`. */
export function parseFrontierQuery(params: URLSearchParams): GlobalFrontierFilters {
  const out: GlobalFrontierFilters = {};
  const includeDemo = parseBoolQueryParam(params.get("include_demo"));
  if (includeDemo !== undefined) out.include_demo = includeDemo;
  const unclaimed = parseBoolQueryParam(params.get("unclaimed"));
  if (unclaimed !== undefined) out.unclaimed = unclaimed;
  const rawMode = params.get("mode")?.trim().toLowerCase();
  if (rawMode === "dag" || rawMode === "hillclimb") {
    out.mode = rawMode;
  }
  const rawTier = params.get("tier")?.trim();
  if (rawTier) {
    const tier = Number(rawTier);
    if (Number.isInteger(tier) && tier > 0) {
      out.tier = tier;
    }
  }
  const openConj = parseBoolQueryParam(params.get("open_conjecture"));
  if (openConj !== undefined) out.open_conjecture = openConj;
  const rawToolchain = params.get("toolchain")?.trim();
  if (rawToolchain) out.toolchain = rawToolchain;
  const rawMission = (params.get("mission") ?? params.get("mission_id"))?.trim();
  if (rawMission) out.mission = rawMission;
  const q = params.get("q")?.trim();
  if (q) out.q = q;
  const rawLimit = params.get("limit")?.trim();
  if (rawLimit) {
    const parsed = Number(rawLimit);
    if (Number.isFinite(parsed)) out.limit = parsed;
  }
  const rawOffset = params.get("offset")?.trim();
  if (rawOffset) {
    const parsed = Number(rawOffset);
    if (Number.isFinite(parsed)) out.offset = parsed;
  }
  return out;
}

/**
 * Build the paginated, deterministically prioritized global frontier (`GET /api/frontier`).
 *
 * Priority order:
 * 1. Unclaimed tasks (`leased === false`) before leased tasks.
 * 2. Tier 1 before Tier 2 (positive tiers ascending; Tier 0 last).
 * 3. DAG / open-conjecture tasks before hill-climb tasks.
 * 4. Mission order (input order) then task order within the mission.
 */
export function buildGlobalFrontier(
  missionsWithTasks: MissionWithTasks[],
  filters: GlobalFrontierFilters = {}
): GlobalFrontierResponse {
  const limit =
    filters.limit !== undefined && Number.isFinite(filters.limit)
      ? Math.max(1, Math.min(Math.floor(filters.limit), FRONTIER_MAX_LIMIT))
      : FRONTIER_DEFAULT_LIMIT;
  const offset =
    filters.offset !== undefined && Number.isFinite(filters.offset)
      ? Math.max(0, Math.floor(filters.offset))
      : 0;
  const tcFilter = filters.toolchain?.trim().toLowerCase() || "";
  const missionFilter = filters.mission?.trim() || "";
  const qFilter = filters.q?.trim().toLowerCase() || "";

  const matched: Array<{
    entry: GlobalFrontierEntry;
    missionOrder: number;
    taskOrder: number;
  }> = [];

  for (let missionOrder = 0; missionOrder < missionsWithTasks.length; missionOrder++) {
    const { manifest, tasks } = missionsWithTasks[missionOrder];
    if (!filters.include_demo && manifest.demo) continue;
    if (missionFilter && manifest.id !== missionFilter) continue;
    if (filters.mode !== undefined && manifest.mode !== filters.mode) continue;
    if (filters.tier !== undefined && manifest.tier !== filters.tier) continue;

    const toolchain = (manifest.verifier.toolchain ?? "leanprover/lean4:v4.36.0").trim();
    if (tcFilter && !toolchain.toLowerCase().includes(tcFilter)) continue;

    const verifierImage = publicVerifierImage(manifest.verifier.image);
    const frontierSet = new Set(computeFrontier(manifest.mode, tasks));
    if (frontierSet.size === 0) continue;

    for (let taskOrder = 0; taskOrder < tasks.length; taskOrder++) {
      const task = tasks[taskOrder];
      if (!frontierSet.has(task.def.id)) continue;

      const leased = task.active_lease !== null;
      if (filters.unclaimed === true && leased) continue;

      const openConjecture = isOpenConjectureTask(manifest, task.def);
      if (
        typeof filters.open_conjecture === "boolean" &&
        openConjecture !== filters.open_conjecture
      ) {
        continue;
      }

      if (qFilter) {
        const hay =
          manifest.id.toLowerCase().includes(qFilter) ||
          manifest.title.toLowerCase().includes(qFilter) ||
          task.def.id.toLowerCase().includes(qFilter) ||
          task.def.title.toLowerCase().includes(qFilter);
        if (!hay) continue;
      }

      matched.push({
        entry: {
          mission_id: manifest.id,
          mission_title: manifest.title,
          task_id: task.def.id,
          title: task.def.title,
          mode: manifest.mode,
          tier: manifest.tier,
          open_conjecture: openConjecture,
          toolchain,
          verifier_image: verifierImage,
          status: task.status,
          leased,
          lease_contributor: task.active_lease?.contributor ?? null,
          best_score: task.best_score,
          best_known: task.def.best_known ?? null,
          upstream_url: task.def.upstream_url ?? null,
          target_files: [...task.def.target_files],
          depends_on: [...(task.def.depends_on ?? [])],
        },
        missionOrder,
        taskOrder,
      });
    }
  }

  matched.sort((a, b) => {
    const aLeased = a.entry.leased ? 1 : 0;
    const bLeased = b.entry.leased ? 1 : 0;
    if (aLeased !== bLeased) return aLeased - bLeased;

    const aTier = a.entry.tier > 0 ? a.entry.tier : Number.MAX_SAFE_INTEGER;
    const bTier = b.entry.tier > 0 ? b.entry.tier : Number.MAX_SAFE_INTEGER;
    if (aTier !== bTier) return aTier - bTier;

    const aMode = a.entry.mode === "dag" ? 0 : 1;
    const bMode = b.entry.mode === "dag" ? 0 : 1;
    if (aMode !== bMode) return aMode - bMode;

    if (a.missionOrder !== b.missionOrder) return a.missionOrder - b.missionOrder;
    return a.taskOrder - b.taskOrder;
  });

  const page = matched.slice(offset, offset + limit).map((m) => m.entry);
  return {
    total_matching: matched.length,
    limit,
    offset,
    returned: page.length,
    tasks: page,
  };
}

/**
 * Content hash of a mission's accepted (non-seed) files, so the hub can ask a
 * warm verifier container "do you already hold this state?" instead of
 * sending every file on every request. Must match `files_sha256` in
 * cloudflare/containers/verifier_server.py.
 *
 * For each file, sorted by path: path, 0x00, u64-LE byte length, 0x00, bytes, 0x0a.
 */
export async function filesStateSha256(files: Record<string, string>): Promise<string> {
  const enc = new TextEncoder();
  const parts: Uint8Array[] = [];
  for (const rel of Object.keys(files).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))) {
    const data = enc.encode(files[rel]);
    const len = new Uint8Array(8);
    new DataView(len.buffer).setBigUint64(0, BigInt(data.byteLength), true);
    parts.push(enc.encode(rel), new Uint8Array([0]), len, new Uint8Array([0]), data, new Uint8Array([10]));
  }
  const total = parts.reduce((n, p) => n + p.byteLength, 0);
  const buf = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    buf.set(p, off);
    off += p.byteLength;
  }
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", buf));
  return "sha256:" + Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

export interface CoAuthor {
  handle: string;
  display_name?: string;
  role?: "proposer" | "solver" | "assembler";
}

export type LedgerEntryKind = "proof" | "subgoal" | "assembled" | "refutation";

/** One accepted patch, rendered as an mbox message `git am` can apply. */
export interface AcceptedPatch {
  seq: number;
  mission_id: string;
  task_id: string;
  contributor: string;
  display_name: string;
  summary: string;
  patch: string;
  created_at: number;
  co_authors?: CoAuthor[];
}

function escapeMboxFromLine(line: string): string {
  return /^From /.test(line) ? ">" + line : line;
}

export function renderMbox(patches: AcceptedPatch[]): string {
  const out: string[] = [];
  for (const p of patches) {
    const date = new Date(p.created_at * 1000).toUTCString().replace("GMT", "+0000");
    const name = p.display_name.replace(/[<>"\r\n]/g, "").trim() || p.contributor;
    const summary = p.summary.replace(/\r/g, "");
    const body = summary
      .split("\n")
      .map((l) => {
        const escaped = escapeMboxFromLine(l);
        // Prevent summary lines from injecting a bare `---` patch separator for `git mailinfo`.
        return /^---[ \t]*$/.test(escaped) ? " " + escaped : escaped;
      })
      .join("\n");
    const trailers: string[] = [];
    const seenCo = new Set<string>([p.contributor]);
    for (const ca of p.co_authors || []) {
      const handle = String(ca.handle || "").trim().toLowerCase().replace(/[^a-z0-9._-]/g, "");
      if (!handle || seenCo.has(handle)) continue;
      seenCo.add(handle);
      const caName = (ca.display_name || handle).replace(/[<>"\r\n]/g, "").trim() || handle;
      trailers.push(`Co-authored-by: ${caName} <${handle}@contributors.sunstead.org>`);
    }
    trailers.push(`Sunstead-Submission: ${p.seq}`);
    const normalizedDiff = p.patch
      .replace(/\r\n/g, "\n")
      .split("\n")
      .map(escapeMboxFromLine)
      .join("\n");
    const diff = normalizedDiff.endsWith("\n") ? normalizedDiff : normalizedDiff + "\n";
    out.push(
      `From ${String(p.seq).padStart(40, "0")} Mon Sep 17 00:00:00 2001\n` +
        `From: ${name} <${p.contributor}@contributors.sunstead.org>\n` +
        `Date: ${date}\n` +
        `Subject: [PATCH] ${p.mission_id}: verify ${p.task_id}\n\n` +
        `${body}\n\n${trailers.join("\n")}\n---\n` +
        diff +
        `--\nsunstead\n\n`
    );
  }
  return out.join("");
}

/** One accepted patch for a task, joined with its contributor and submission rows. */
export type AcceptedProofRow = {
  seq: number;
  mission_id: string;
  task_id: string;
  submission_id: string;
  contributor: string;
  display_name: string;
  github: string | null;
  github_verified_handle?: string | null;
  x?: string | null;
  linkedin?: string | null;
  summary: string;
  patch: string;
  spec_sha256: string;
  created_at: number;
  verify_ms: number | null;
  is_demo?: number;
  entry_kind?: string | null;
  co_authors_json?: string | null;
  decomp_meta_json?: string | null;
};

/** Constant-time string comparison for bearer secrets. */
export function constantTimeEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  let diff = aBytes.length ^ bBytes.length;
  const maxLen = Math.max(aBytes.length, bBytes.length);
  for (let i = 0; i < maxLen; i++) {
    diff |= (aBytes[i] ?? 0) ^ (bBytes[i] ?? 0);
  }
  return diff === 0;
}

export type SubmissionStatus = "verifying" | "accepted" | "rejected" | "error";

export type SubmissionStatusRow = {
  id: string;
  mission_id: string;
  task_id: string;
  contributor: string;
  status: string;
  accepted: number;
  score: number | null;
  points: number;
  summary: string;
  patch_sha256: string;
  proof_id: string | null;
  verify_ms: number;
  stage: string | null;
  diagnostics: string | null;
  error: string | null;
  unlocked_dependents_json: string | null;
  created_at: number;
  completed_at: number | null;
};

/** Determine whether a `POST .../submit` request opted into async (`202 Accepted`) mode. */
export function shouldRunAsyncSubmit(
  url: URL,
  body: { async?: unknown },
  headers: Headers
): boolean {
  const q = url.searchParams.get("async")?.toLowerCase();
  if (q === "1" || q === "true") return true;
  if (q === "0" || q === "false") return false;
  if (body.async === true) return true;
  if (body.async === false) return false;
  const prefer = headers.get("Prefer") || "";
  return /\brespond-async\b/i.test(prefer);
}

/** Public view of a single submission (`GET /api/submissions/:id`), supporting sync & async polling. */
export function formatSubmissionStatusView(row: SubmissionStatusRow, hubOrigin: string) {
  let status: SubmissionStatus;
  if (row.status === "verifying" || row.status === "accepted" || row.status === "rejected" || row.status === "error") {
    status = row.status;
  } else {
    status = row.accepted !== 0 ? "accepted" : "rejected";
  }
  const accepted = status === "accepted" ? true : status === "verifying" ? null : false;
  const rawProofId =
    row.proof_id ||
    (status === "accepted" && row.patch_sha256 ? proofIdFromPatchSha(row.patch_sha256) : null);
  const proofId = rawProofId && PROOF_HASH_RE.test(rawProofId) ? rawProofId : null;
  let unlockedDependents: string[] = [];
  if (row.unlocked_dependents_json) {
    try {
      const parsed = JSON.parse(row.unlocked_dependents_json);
      if (Array.isArray(parsed)) {
        unlockedDependents = parsed.filter((x): x is string => typeof x === "string");
      }
    } catch {
      unlockedDependents = [];
    }
  }
  const diag = sanitizeFailureDiagnostics(row.stage, row.diagnostics);
  return {
    submission_id: row.id,
    status,
    mission_id: row.mission_id,
    task_id: row.task_id,
    contributor: row.contributor,
    accepted,
    score: row.score,
    points_awarded: row.points,
    summary: row.summary,
    patch_sha256: row.patch_sha256,
    proof_id: proofId,
    permalink: proofId ? `${hubOrigin}/proofs/${proofId}` : null,
    unlocked_dependents: unlockedDependents,
    verify_ms: row.verify_ms,
    ...(diag.stage ? { stage: diag.stage } : {}),
    ...(diag.diagnostics ? { diagnostics: diag.diagnostics } : {}),
    ...(row.error ? { error: row.error } : {}),
    created_at: row.created_at,
    completed_at: row.completed_at,
  };
}

/**
 * Age threshold (seconds) after which a `verifying` submission is considered
 * orphaned across a Durable Object restart/deploy or container failure.
 * Comfortably exceeds max 240s container timeout + slot queueing.
 */
export const STALE_VERIFYING_SEC = 600;
export const STALE_VERIFYING_ERROR =
  "Verification was interrupted before completion (hub restart or container timeout); please resubmit.";
export const STALE_VERIFYING_SUMMARY =
  "Verification interrupted before completion; please resubmit.";

export type StaleReaperSql = Pick<SqlStorage, "exec">;

/** True when a submission row has remained in `verifying` for at least `maxAgeSec`. */
export function isSubmissionVerifyingStale(
  row: Pick<SubmissionStatusRow, "status" | "created_at">,
  nowUnix: number,
  maxAgeSec = STALE_VERIFYING_SEC
): boolean {
  const safeMaxAge = Number.isFinite(maxAgeSec) ? Math.max(0, Math.floor(maxAgeSec)) : STALE_VERIFYING_SEC;
  return row.status === "verifying" && nowUnix - row.created_at >= safeMaxAge;
}

/**
 * Reap orphaned `verifying` submissions whose `created_at <= nowUnix - maxAgeSec`.
 * Updates matching rows to `status = 'error'` (`stage = 'sandbox'`) and returns
 * the reaped submission IDs.
 */
export function reapStaleVerifyingSubmissions(
  sql: StaleReaperSql,
  nowUnix: number,
  maxAgeSec = STALE_VERIFYING_SEC
): string[] {
  const safeMaxAge = Number.isFinite(maxAgeSec) ? Math.max(0, Math.floor(maxAgeSec)) : STALE_VERIFYING_SEC;
  const cutoff = nowUnix - safeMaxAge;
  const stale = sql
    .exec<{ id: string }>(
      `SELECT id
       FROM submissions
       WHERE status = 'verifying' AND created_at <= ?
       ORDER BY created_at ASC, id ASC`,
      cutoff
    )
    .toArray();
  if (stale.length === 0) return [];
  sql.exec(
    `UPDATE submissions
     SET status = 'error',
         accepted = 0,
         points = 0,
         stage = 'sandbox',
         error = ?,
         summary = ?,
         completed_at = ?
     WHERE status = 'verifying' AND created_at <= ?`,
    STALE_VERIFYING_ERROR,
    STALE_VERIFYING_SUMMARY,
    nowUnix,
    cutoff
  );
  return stale.map((r) => r.id);
}

/**
 * Lazily reap a single fetched submission row if it is stale in `verifying`,
 * returning the updated `error` row so polling agents never hang indefinitely.
 */
export function reapStaleVerifyingSubmissionById(
  sql: StaleReaperSql,
  row: SubmissionStatusRow,
  nowUnix: number,
  maxAgeSec = STALE_VERIFYING_SEC
): SubmissionStatusRow {
  if (!isSubmissionVerifyingStale(row, nowUnix, maxAgeSec)) return row;
  const safeMaxAge = Number.isFinite(maxAgeSec) ? Math.max(0, Math.floor(maxAgeSec)) : STALE_VERIFYING_SEC;
  const cutoff = nowUnix - safeMaxAge;
  sql.exec(
    `UPDATE submissions
     SET status = 'error',
         accepted = 0,
         points = 0,
         stage = 'sandbox',
         error = ?,
         summary = ?,
         completed_at = ?
     WHERE id = ? AND status = 'verifying' AND created_at <= ?`,
    STALE_VERIFYING_ERROR,
    STALE_VERIFYING_SUMMARY,
    nowUnix,
    row.id,
    cutoff
  );
  return {
    ...row,
    status: "error",
    accepted: 0,
    points: 0,
    stage: "sandbox",
    error: STALE_VERIFYING_ERROR,
    summary: STALE_VERIFYING_SUMMARY,
    completed_at: nowUnix,
  };
}

// ---------------------------------------------------------------------------
// Contributor social handles (strict handle-only validation + proof-gated display)

export const GITHUB_HANDLE_RE = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
export const X_HANDLE_RE = /^[A-Za-z0-9_]{1,15}$/;
export const LINKEDIN_HANDLE_RE = /^[A-Za-z0-9-]{3,100}$/;

export interface ContributorSocialHandles {
  github: string | null;
  x: string | null;
  linkedin: string | null;
}

export function verifiedGithubHandle(visible: string | null, verified?: string | null): string | null {
  return visible && visible.toLowerCase() === verified?.toLowerCase() ? visible : null;
}

export interface SocialLink {
  platform: "github" | "x" | "linkedin";
  handle: string;
  url: string;
}

function rejectRawUrlOrBadType(field: string, raw: unknown): string | null {
  if (raw === null || raw === undefined) return null;
  if (typeof raw !== "string") {
    throw new Error(`${field} must be a handle string or null`);
  }
  const trimmed = raw.trim();
  if (!trimmed) return null;
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(trimmed) || trimmed.includes("://") || /[?#\s]/.test(trimmed)) {
    throw new Error(`${field} must be a handle only (not a URL)`);
  }
  return trimmed;
}

export function normalizeGithubHandle(raw: unknown): string | null {
  const val = rejectRawUrlOrBadType("github", raw);
  if (val === null) return null;
  const cleaned = val.startsWith("@") ? val.slice(1) : val;
  if (!GITHUB_HANDLE_RE.test(cleaned)) {
    throw new Error(
      "invalid github handle: use 1-39 alphanumeric characters or single hyphens, no leading/trailing hyphen or URL"
    );
  }
  return cleaned;
}

export function normalizeXHandle(raw: unknown): string | null {
  const val = rejectRawUrlOrBadType("x", raw);
  if (val === null) return null;
  const cleaned = val.startsWith("@") ? val.slice(1) : val;
  if (!X_HANDLE_RE.test(cleaned)) {
    throw new Error(
      "invalid x handle: use 1-15 letters, digits, or underscores (no URL)"
    );
  }
  return cleaned;
}

export function normalizeLinkedinHandle(raw: unknown): string | null {
  const val = rejectRawUrlOrBadType("linkedin", raw);
  if (val === null) return null;
  let cleaned = val;
  if (cleaned.startsWith("/in/")) cleaned = cleaned.slice(4);
  else if (cleaned.startsWith("in/")) cleaned = cleaned.slice(3);
  if (!LINKEDIN_HANDLE_RE.test(cleaned)) {
    throw new Error(
      "invalid linkedin handle: use 3-100 letters, digits, or hyphens (optional leading in/, no URL)"
    );
  }
  return cleaned;
}

export interface ParsedProfilePatch {
  hasUpdates: boolean;
  display_name?: string | null;
  github?: string | null;
  x?: string | null;
  linkedin?: string | null;
}

/** Validate a `PATCH /api/me` payload; null or "" clears a field, omitted fields stay unchanged. */
export function parseProfilePatch(body: Record<string, unknown>): ParsedProfilePatch {
  const out: ParsedProfilePatch = { hasUpdates: false };
  if ("display_name" in body && body.display_name !== undefined) {
    out.hasUpdates = true;
    if (body.display_name === null) {
      out.display_name = null;
    } else if (typeof body.display_name === "string") {
      const cleaned = body.display_name.trim().replace(/[\r\n\t]+/g, " ").slice(0, 64);
      out.display_name = cleaned || null;
    } else {
      throw new Error("display_name must be a string or null");
    }
  }
  if ("github" in body && body.github !== undefined) {
    out.hasUpdates = true;
    out.github = normalizeGithubHandle(body.github);
  }
  if ("x" in body && body.x !== undefined) {
    out.hasUpdates = true;
    out.x = normalizeXHandle(body.x);
  }
  if ("linkedin" in body && body.linkedin !== undefined) {
    out.hasUpdates = true;
    out.linkedin = normalizeLinkedinHandle(body.linkedin);
  }
  return out;
}

function safeStoredHandle(val: string | null | undefined, re: RegExp): string | null {
  if (typeof val !== "string") return null;
  const trimmed = val.trim();
  return re.test(trimmed) ? trimmed : null;
}

/**
 * Anti-spam proof gate for public contributor links: outbound links are only
 * surfaced publicly once the contributor has at least one accepted non-demo proof.
 */
export function gatePublicSocialHandles(
  handles: Partial<ContributorSocialHandles>,
  nonDemoVerifiedCount: number
): ContributorSocialHandles {
  if (!Number.isFinite(nonDemoVerifiedCount) || nonDemoVerifiedCount < 1) {
    return { github: null, x: null, linkedin: null };
  }
  return {
    github: safeStoredHandle(handles.github, GITHUB_HANDLE_RE),
    x: safeStoredHandle(handles.x, X_HANDLE_RE),
    linkedin: safeStoredHandle(handles.linkedin, LINKEDIN_HANDLE_RE),
  };
}

/** Construct canonical https:// links strictly from validated handles. */
export function buildSocialLinksFromHandles(handles: Partial<ContributorSocialHandles>): SocialLink[] {
  const links: SocialLink[] = [];
  const gh = safeStoredHandle(handles.github, GITHUB_HANDLE_RE);
  if (gh) links.push({ platform: "github", handle: gh, url: `https://github.com/${gh}` });
  const x = safeStoredHandle(handles.x, X_HANDLE_RE);
  if (x) links.push({ platform: "x", handle: x, url: `https://x.com/${x}` });
  const li = safeStoredHandle(handles.linkedin, LINKEDIN_HANDLE_RE);
  if (li) links.push({ platform: "linkedin", handle: li, url: `https://www.linkedin.com/in/${li}` });
  return links;
}

export function buildPublicSocialLinks(
  handles: Partial<ContributorSocialHandles>,
  nonDemoVerifiedCount: number
): SocialLink[] {
  return buildSocialLinksFromHandles(gatePublicSocialHandles(handles, nonDemoVerifiedCount));
}

/** Shell-safe single-quoted argument. */
function shellQuote(s: string): string {
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

export const GHCR_REGISTRY_PREFIX = "ghcr.io/sunstead-institute";

/**
 * Map a local Sunstead verifier image tag (`sunstead/verifier-lean4:v0.2`) to
 * its public GHCR reference (`ghcr.io/sunstead-institute/verifier-lean4:v0.2`).
 */
export function publicVerifierImage(image: string): string {
  const trimmed = image.trim();
  if (
    trimmed.startsWith("ghcr.io/") ||
    trimmed.startsWith("registry.cloudflare.com/")
  ) {
    return trimmed;
  }
  const stripped = trimmed.replace(/^sunstead\//, "");
  return `${GHCR_REGISTRY_PREFIX}/${stripped}`;
}

export interface MissionLocalSetup {
  mode: "repo-snapshot" | "hillclimb" | "standalone";
  toolchain: string;
  verifier_image: string;
  local_verifier_image: string;
  uses_mathlib: boolean;
  bundle_url: string;
  bootstrap_script_url: string | null;
  bootstrap_cmd: string | null;
  docker_verify_cmd: string;
  native_setup_steps: string[];
  notes: string[];
}

function missionUsesMathlib(manifest: MissionManifest): boolean {
  if (manifest.snapshot?.mode === "repo-snapshot") {
    return (manifest.snapshot.allowed_import_prefixes ?? []).includes("Mathlib");
  }
  return !manifest.demo;
}

/**
 * Per-mission local iteration and offline Docker verification instructions,
 * surfaced by both `GET /api/missions/:id` (`local_setup`) and `/join.txt`.
 */
export function buildMissionLocalSetup(
  manifest: MissionManifest,
  hubOrigin: string
): MissionLocalSetup {
  const base = hubOrigin.replace(/\/+$/, "");
  const toolchain = (manifest.verifier.toolchain ?? "leanprover/lean4:v4.36.0").trim();
  const localImage = manifest.verifier.image.trim();
  const publicImage = publicVerifierImage(localImage);
  const isSnapshot = manifest.snapshot?.mode === "repo-snapshot";
  const usesMathlib = missionUsesMathlib(manifest);
  const mode: MissionLocalSetup["mode"] = isSnapshot
    ? "repo-snapshot"
    : manifest.mode === "hillclimb"
      ? "hillclimb"
      : "standalone";
  const bundleUrl = `${base}/api/missions/${encodeURIComponent(manifest.id)}/bundle.tar.gz`;
  const bootstrapScriptUrl = isSnapshot
    ? `${base}/api/missions/${encodeURIComponent(manifest.id)}/bootstrap.sh`
    : null;
  const bootstrapCmd = bootstrapScriptUrl
    ? `curl -fsSL ${shellQuote(bootstrapScriptUrl)} | bash`
    : null;
  const firstTask = manifest.tasks[0]?.id ?? "<TASK_ID>";
  const firstTarget = manifest.tasks[0]?.target_files[0] ?? "<TARGET_FILE>";
  const dockerVerifyCmd = [
    `IMAGE=${shellQuote(publicImage)}   # or local ${localImage}`,
    `CID=$(docker create --network=none -w /work "$IMAGE" ./verify ${shellQuote(firstTask)})`,
    `docker cp . "$CID:/work" && docker start -a "$CID"`,
    `docker rm -f "$CID" >/dev/null`,
  ].join("\n");

  const nativeSteps: string[] = [
    `mkdir -p ${shellQuote(`work-${manifest.id}`)} && cd ${shellQuote(`work-${manifest.id}`)}`,
    `curl -fsSL ${shellQuote(bundleUrl)} | tar xz`,
  ];
  const notes: string[] = [];

  if (isSnapshot && manifest.upstream) {
    const upDir = `../${manifest.id}-upstream`;
    nativeSteps.push(
      `# Repo-snapshot bundle contains only target file(s) & metadata (not upstream lakefile/deps).`,
      `# Bootstrap the pinned upstream checkout outside this dir so git diff & docker cp stay clean:`,
      bootstrapCmd!
    );
    notes.push(
      `Repo-snapshot mission pinned to ${manifest.upstream.repo}@${manifest.upstream.commit.slice(0, 12)} (${toolchain}).`,
      `Edit and build inside ${upDir} with \`lake build\`, then copy modified target file(s) back into this bundle directory before running \`git diff -- ${firstTarget}\` or Docker verification.`,
      `Docker image ${publicImage} already embeds all prebuilt upstream .olean dependencies offline.`
    );
  } else if (manifest.mode === "hillclimb") {
    const dir = manifest.score_direction === "minimize" ? "minimize" : "maximize";
    const baseline = manifest.tasks[0]?.baseline_score;
    if (usesMathlib) {
      nativeSteps.push("lake exe cache get");
    }
    nativeSteps.push("lake build");
    notes.push(
      `Hill-climb mission (${dir}${baseline !== null && baseline !== undefined ? `, baseline: ${baseline}` : ""}): only strict improvements over the live best_score are accepted.`,
      `Full points are paid only for beating each task's best_known value (the best result known outside Sunstead, shown in the task's \`def.best_known\`); reproducing a known result earns a small flat amount.`,
      `Edit only the task's certificate target file(s) (e.g. ${firstTarget}); never touch frozen Spec/Bound/verify files.`
    );
  } else {
    if (usesMathlib) {
      nativeSteps.push("lake exe cache get");
    }
    nativeSteps.push("lake build");
    notes.push(
      `Standalone Lean 4 mission (${toolchain}${usesMathlib ? ", Mathlib" : ", zero Mathlib"}).`
    );
  }

  return {
    mode,
    toolchain,
    verifier_image: publicImage,
    local_verifier_image: localImage,
    uses_mathlib: usesMathlib,
    bundle_url: bundleUrl,
    bootstrap_script_url: bootstrapScriptUrl,
    bootstrap_cmd: bootstrapCmd,
    docker_verify_cmd: dockerVerifyCmd,
    native_setup_steps: nativeSteps,
    notes,
  };
}

const UPSTREAM_REPO_RE = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const COMMIT_SHA_RE = /^[0-9a-f]{40}$/;

/**
 * Render a ready-to-run bash bootstrap script (`GET /api/missions/:id/bootstrap.sh`)
 * for a repo-snapshot mission. Shallow-clones the exact pinned 40-char upstream
 * commit outside the bundle directory, overlays the live target `.lean` file(s)
 * from the bundle, optionally fetches Mathlib cache, and prints exact build/sync
 * commands while keeping the bundle directory clean for `git diff` and Docker.
 */
export function renderRepoSnapshotBootstrapScript(
  manifest: MissionManifest,
  hubOrigin: string
): string {
  if (manifest.snapshot?.mode !== "repo-snapshot") {
    throw new Error(`mission '${manifest.id}' is not a repo-snapshot mission`);
  }
  const up = manifest.upstream;
  if (!up || !UPSTREAM_REPO_RE.test(up.repo) || !COMMIT_SHA_RE.test(up.commit)) {
    throw new Error(`mission '${manifest.id}' has missing or malformed upstream pin`);
  }
  const allTargets = Array.from(
    new Set(manifest.tasks.flatMap((t) => t.target_files))
  ).sort();
  if (allTargets.length === 0) {
    throw new Error(`mission '${manifest.id}' has no target_files`);
  }
  for (const tf of allTargets) {
    normalizeRelPath(tf);
  }
  const setup = buildMissionLocalSetup(manifest, hubOrigin);
  const quotedTargets = allTargets.map(shellQuote).join(" ");
  const defaultUpstreamDir = `../${manifest.id}-upstream`;
  const repoUrl = `https://github.com/${up.repo}.git`;

  return `#!/usr/bin/env bash
# Sunstead local bootstrap for repo-snapshot mission: ${manifest.id}
# Upstream: https://github.com/${up.repo}@${up.commit} (${up.license})
# Toolchain: ${setup.toolchain}
# Public verifier image: ${setup.verifier_image}
set -euo pipefail

MISSION_ID=${shellQuote(manifest.id)}
UPSTREAM_URL="\${SUNSTEAD_UPSTREAM_URL:-${repoUrl}}"
UPSTREAM_COMMIT=${shellQuote(up.commit)}
USES_MATHLIB=${setup.uses_mathlib ? "1" : "0"}
BUNDLE_DIR="\${SUNSTEAD_BUNDLE_DIR:-$PWD}"
UPSTREAM_DIR="\${SUNSTEAD_UPSTREAM_DIR:-$BUNDLE_DIR/${defaultUpstreamDir}}"
TARGETS=(${quotedTargets})

if [ ! -f "$BUNDLE_DIR/UPSTREAM.json" ] || [ ! -f "$BUNDLE_DIR/sunstead.json" ]; then
  echo "Run this script from your extracted bundle directory (containing UPSTREAM.json and sunstead.json)," >&2
  echo "or set SUNSTEAD_BUNDLE_DIR=/path/to/work-$MISSION_ID." >&2
  echo "To download the live bundle first:" >&2
  echo "  mkdir -p work-$MISSION_ID && cd work-$MISSION_ID && curl -fsSL ${shellQuote(setup.bundle_url)} | tar xz" >&2
  exit 1
fi

case "$UPSTREAM_DIR" in
  "$BUNDLE_DIR"|"$BUNDLE_DIR"/*)
    echo "Refusing SUNSTEAD_UPSTREAM_DIR inside BUNDLE_DIR ($UPSTREAM_DIR): keep it outside so git diff and docker cp stay clean." >&2
    exit 1
    ;;
esac

if [ ! -d "$UPSTREAM_DIR/.git" ]; then
  echo "==> Shallow-cloning $UPSTREAM_URL at pinned commit \${UPSTREAM_COMMIT:0:12} into $UPSTREAM_DIR..."
  mkdir -p "$UPSTREAM_DIR"
  git -C "$UPSTREAM_DIR" init -q
  git -C "$UPSTREAM_DIR" remote add origin "$UPSTREAM_URL"
  git -C "$UPSTREAM_DIR" fetch --quiet --depth=1 origin "$UPSTREAM_COMMIT"
  git -C "$UPSTREAM_DIR" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
fi

ACTUAL_SHA="$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
if [ "$ACTUAL_SHA" != "$UPSTREAM_COMMIT" ]; then
  echo "Upstream checkout at $UPSTREAM_DIR is at $ACTUAL_SHA, expected pinned $UPSTREAM_COMMIT" >&2
  exit 1
fi

echo "==> Overlaying live target file(s) from $BUNDLE_DIR into $UPSTREAM_DIR..."
for rel in "\${TARGETS[@]}"; do
  if [ ! -f "$BUNDLE_DIR/$rel" ]; then
    echo "Missing target file in bundle: $BUNDLE_DIR/$rel" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$UPSTREAM_DIR/$rel")"
  cp "$BUNDLE_DIR/$rel" "$UPSTREAM_DIR/$rel"
done

if [ "$USES_MATHLIB" = "1" ] && [ "\${SUNSTEAD_SKIP_CACHE:-0}" != "1" ] && command -v lake >/dev/null 2>&1; then
  echo "==> Fetching prebuilt Mathlib oleans (lake exe cache get)..."
  (cd "$UPSTREAM_DIR" && lake exe cache get) || true
fi

cat <<EOF

Ready! Local upstream workspace: $UPSTREAM_DIR
Bundle directory (clean for git diff & Docker): $BUNDLE_DIR

Next steps:
  1. Edit target file(s) and iterate with native Lean (${setup.toolchain}) in $UPSTREAM_DIR:
       cd $(printf '%q' "$UPSTREAM_DIR")
       lake build
  2. Copy your proved target file(s) back into the bundle directory:
       $(for t in ${quotedTargets}; do printf 'cp %q/%s %q/%s && ' "$UPSTREAM_DIR" "$t" "$BUNDLE_DIR" "$t"; done | sed 's/ && $//')
  3. Verify offline in the exact Hub verifier container:
       cd $(printf '%q' "$BUNDLE_DIR")
       IMAGE=${shellQuote(setup.verifier_image)}
       CID=\\$(docker create --network=none -w /work "\\$IMAGE" ./verify ${shellQuote(manifest.tasks[0]?.id ?? "<TASK_ID>")})
       docker cp . "\\$CID:/work" && docker start -a "\\$CID" && docker rm -f "\\$CID" >/dev/null
  4. Generate a strictly scoped patch from the bundle directory:
       git diff -- ${quotedTargets}
EOF
`;
}

/**
 * Commands that rebuild the mission's live state, including this proof, from
 * the public seed bundle and history (URLs quoted so zsh does not glob `?`).
 */
export function howToRebuild(hubOrigin: string, missionId: string): string {
  const base = `${hubOrigin}/api/missions/${encodeURIComponent(missionId)}`;
  return (
    `mkdir ${shellQuote(missionId)} && cd ${shellQuote(missionId)} && ` +
    `curl -sL ${shellQuote(`${base}/bundle.tar.gz?base=seed`)} | tar xz && ` +
    `curl -sL ${shellQuote(`${base}/history.mbox`)} | git am`
  );
}

/**
 * Classify how a task's `upstream_url` anchors into its pinned upstream repository:
 * - `in_place_sorry`: verbatim top-level `sorry` in upstream (e.g. LNSym, PNT, curve25519-dalek).
 * - `challenge_node`: IEANTN `Challenge.lean` node declaration (verifiable by `/verify.py`
 *   directly against `Challenge.lean`; upstream PRs land under `Solutions/`).
 * - `extracted_lemma`: mission extracted a nested `sorry` into its own top-level theorem
 *   (e.g. `arklib-near-capacity-primes`); `/verify.py` cannot splice automatically.
 * - `optimization_spec`: hill-climb optimization track pinned to an upstream specification/table.
 * - `none`: demo/retired mission or task with no upstream link.
 */
export function resolveUpstreamAnchor(
  manifest: Pick<MissionManifest, "id" | "mode" | "demo" | "upstream"> | null,
  taskDef: Pick<TaskDefinition, "upstream_url" | "upstream_anchor"> | null
): UpstreamAnchorKind {
  if (!manifest || manifest.demo || !manifest.upstream || !taskDef?.upstream_url) {
    return "none";
  }
  if (taskDef.upstream_anchor) {
    return taskDef.upstream_anchor;
  }
  if (manifest.mode === "hillclimb") {
    return "optimization_spec";
  }
  if (/\/IEANTN\/Nodes\/[^/]+\/[^/]+\/Challenge\.lean(?:#|$)/.test(taskDef.upstream_url)) {
    return "challenge_node";
  }
  if (manifest.id === "arklib-near-capacity-primes") {
    return "extracted_lemma";
  }
  return "in_place_sorry";
}

/**
 * Command that checks one ledger proof against its upstream repository with the
 * standalone public verifier (`/verify.py`, scripts/sunstead_verify.py), so the
 * check trusts the upstream repo and stock Lean rather than Sunstead. Null when
 * the entry has no single upstream `sorry` to check against (demo and retired
 * missions, hill-climb tasks, extracted lemmas, decomposition subgoals,
 * refutations, assembled roots).
 */
export function verifyCommand(
  hubOrigin: string,
  proofId: string | null,
  entry: {
    entry_kind: string;
    mission_demo: boolean;
    mission_mode?: MissionMode | null;
    upstream: { task_url: string | null; anchor_kind?: UpstreamAnchorKind } | null;
  }
): string | null {
  if (!proofId || !/^[0-9a-f]{64}$/.test(proofId)) return null;
  if (entry.entry_kind !== "proof" || entry.mission_demo || !entry.upstream?.task_url) return null;
  if (entry.mission_mode === "hillclimb") return null;
  const anchor = entry.upstream.anchor_kind;
  if (anchor !== undefined && anchor !== "in_place_sorry" && anchor !== "challenge_node") {
    return null;
  }
  const hubArg = hubOrigin === "https://sunstead.org" ? "" : ` --hub ${shellQuote(hubOrigin)}`;
  return `curl -fsSLO ${shellQuote(`${hubOrigin}/verify.py`)} && python3 verify.py ${proofId}${hubArg}`;
}

/**
 * Public view of a task's accepted proof (GET /api/missions/:id/tasks/:task/proof).
 * `currentSpecSha256` is the mission's spec hash now; a proof accepted under an
 * older spec is still shown, but flagged.
 */
export function buildProofView(
  row: AcceptedProofRow,
  opts: {
    hubOrigin: string;
    currentSpecSha256: string;
    patchSha256: string;
    nonDemoVerifiedCount?: number;
  }
) {
  const nonDemoCount = opts.nonDemoVerifiedCount ?? 1;
  const social = gatePublicSocialHandles(
    { github: row.github, x: row.x ?? null, linkedin: row.linkedin ?? null },
    nonDemoCount
  );
  const entryKind = normalizeEntryKind(row.entry_kind);
  const decompMeta = parseStoredDecompMeta(row.decomp_meta_json);
  return {
    mission_id: row.mission_id,
    task_id: row.task_id,
    seq: row.seq,
    entry_kind: entryKind,
    submission_id: row.submission_id,
    contributor: row.contributor,
    display_name: row.display_name || row.contributor,
    github: social.github,
    github_verified_handle: verifiedGithubHandle(social.github, row.github_verified_handle),
    x: social.x,
    linkedin: social.linkedin,
    social_links: buildSocialLinksFromHandles(social),
    summary: row.summary,
    accepted_at: row.created_at,
    verify_ms: row.verify_ms,
    spec_sha256: row.spec_sha256,
    spec_is_current: row.spec_sha256 === opts.currentSpecSha256,
    patch_sha256: opts.patchSha256,
    files: extractPatchPaths(row.patch),
    patch: row.patch,
    history_mbox: `${opts.hubOrigin}/api/missions/${encodeURIComponent(row.mission_id)}/history.mbox`,
    how_to_rebuild: howToRebuild(opts.hubOrigin, row.mission_id),
    ...(decompMeta ? { decomposition: decompMeta } : {}),
  };
}

// Reconnect delay sent at the start of every /api/events stream. A deploy resets
// the hub Durable Object (code_update_strategy in cloudflare.config.ts), which
// drops every stream; EventSource clients reconnect after this many ms.
export const SSE_RETRY_MS = 2_000;

/** First bytes of every /api/events stream: the reconnect delay and a comment. */
export function sseHello(): string {
  return `retry: ${SSE_RETRY_MS}\n: connected\n\n`;
}

// ---------------------------------------------------------------------------
// Public proof ledger (GET /api/proofs, GET /api/proofs/:patch_sha256, /proofs pages)

/**
 * A ledger permalink key: the bare hex SHA-256 of the accepted patch exactly as
 * stored. The API's `patch_sha256` fields carry the same hash as `sha256:<hex>`.
 */
export const PROOF_HASH_RE = /^[0-9a-f]{64}$/;

/** `sha256:<hex>` (as stored) to the bare hex used in /proofs/<id> URLs. */
export function proofIdFromPatchSha(patchSha256: string): string {
  return patchSha256.replace(/^sha256:/, "");
}

export const LEDGER_DEFAULT_LIMIT = 50;
export const LEDGER_MAX_LIMIT = 200;

/** accepted_patches row (with contributor join) as the ledger reads it. */
export type LedgerRow = AcceptedProofRow & { patch_sha256: string };

/** What the ledger needs to know about a mission; null when it has been retired. */
export type LedgerMissionInfo = {
  manifest: MissionManifest;
  spec_sha256: string;
} | null;

/** Parse ?limit= and ?before= for GET /api/proofs. Bad values fall back to defaults. */
export function parseLedgerQuery(params: URLSearchParams): {
  limit: number;
  before: number | null;
  missionId: string | null;
} {
  const rawLimit = Number(params.get("limit"));
  const limit =
    Number.isInteger(rawLimit) && rawLimit > 0 ? Math.min(rawLimit, LEDGER_MAX_LIMIT) : LEDGER_DEFAULT_LIMIT;
  const rawBefore = Number(params.get("before"));
  const before = params.has("before") && Number.isInteger(rawBefore) && rawBefore > 0 ? rawBefore : null;
  const missionId = params.get("mission_id") || null;
  return { limit, before, missionId };
}

export function parseStoredCoAuthors(raw: string | null | undefined): CoAuthor[] {
  if (!raw || typeof raw !== "string") return [];
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((x): x is Record<string, unknown> => Boolean(x) && typeof x === "object" && typeof (x as Record<string, unknown>).handle === "string")
      .map((x) => ({
        handle: String(x.handle),
        ...(typeof x.display_name === "string" ? { display_name: x.display_name } : {}),
        ...(x.role === "proposer" || x.role === "solver" || x.role === "assembler" ? { role: x.role } : {}),
      }));
  } catch {
    return [];
  }
}

export function parseStoredDecompMeta(raw: string | null | undefined): Record<string, unknown> | null {
  if (!raw || typeof raw !== "string") return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

function normalizeEntryKind(raw: string | null | undefined): LedgerEntryKind {
  if (raw === "subgoal" || raw === "assembled" || raw === "refutation") return raw;
  return "proof";
}

/**
 * One ledger entry. Mission and task titles and upstream provenance come from the
 * live manifest; a proof from a retired mission keeps its record but has none.
 */
export function buildLedgerEntry(
  row: LedgerRow,
  mission: LedgerMissionInfo,
  hubOrigin: string,
  nonDemoVerifiedCount?: number
) {
  const manifest = mission?.manifest ?? null;
  const decompMeta = parseStoredDecompMeta(row.decomp_meta_json);
  const rootTaskId =
    typeof decompMeta?.root_task_id === "string" ? decompMeta.root_task_id : row.task_id;
  const taskDef =
    manifest?.tasks.find((t) => t.id === row.task_id) ??
    manifest?.tasks.find((t) => t.id === rootTaskId) ??
    null;
  const upstream = manifest?.upstream ?? null;
  const isDemo = Boolean(manifest?.demo || row.is_demo);
  const effectiveNonDemo = nonDemoVerifiedCount ?? (isDemo ? 0 : 1);
  const social = gatePublicSocialHandles(
    { github: row.github, x: row.x ?? null, linkedin: row.linkedin ?? null },
    effectiveNonDemo
  );
  const entryKind = normalizeEntryKind(row.entry_kind);
  const coAuthors = parseStoredCoAuthors(row.co_authors_json);
  const taskTitle =
    typeof decompMeta?.subgoal_title === "string" && entryKind !== "assembled"
      ? entryKind === "refutation"
        ? `Refutation: ¬ (${decompMeta.subgoal_title})`
        : decompMeta.subgoal_title
      : entryKind === "refutation" && taskDef?.title
        ? `Refutation: ¬ (${taskDef.title})`
        : taskDef?.title ?? null;
  const proofId = proofIdFromPatchSha(row.patch_sha256);
  const anchorKind = resolveUpstreamAnchor(manifest, taskDef);
  const upstreamView = upstream
    ? {
        repo: upstream.repo,
        commit: upstream.commit,
        license: upstream.license,
        task_url: taskDef?.upstream_url ?? null,
        anchor_kind: anchorKind,
      }
    : null;
  const upVerifyCmd = verifyCommand(hubOrigin, proofId, {
    entry_kind: entryKind,
    mission_demo: isDemo,
    mission_mode: manifest?.mode ?? null,
    upstream: upstreamView,
  });
  const missionReplay =
    manifest !== null && entryKind !== "refutation" && entryKind !== "subgoal"
      ? {
          bundle_url: `${hubOrigin}/api/missions/${encodeURIComponent(row.mission_id)}/bundle.tar.gz?base=seed`,
          history_mbox_url: `${hubOrigin}/api/missions/${encodeURIComponent(row.mission_id)}/history.mbox`,
          command: howToRebuild(hubOrigin, row.mission_id),
        }
      : null;
  const upstreamReplay =
    upVerifyCmd && (anchorKind === "in_place_sorry" || anchorKind === "challenge_node")
      ? {
          kind: anchorKind,
          script_url: `${hubOrigin}/verify.py`,
          command: upVerifyCmd,
        }
      : null;
  return {
    proof_id: proofId,
    patch_sha256: row.patch_sha256,
    permalink: `${hubOrigin}/proofs/${proofId}`,
    seq: row.seq,
    entry_kind: entryKind,
    mission_id: row.mission_id,
    mission_title: manifest?.title ?? null,
    mission_retired: manifest === null,
    mission_demo: isDemo,
    task_id: row.task_id,
    task_title: taskTitle,
    upstream: upstreamView,
    verify_command: upVerifyCmd,
    verification: {
      mission_replay: missionReplay,
      upstream_replay: upstreamReplay,
    },
    contributor: row.contributor,
    display_name: row.display_name || row.contributor,
    github: social.github,
    github_verified_handle: verifiedGithubHandle(social.github, row.github_verified_handle),
    x: social.x,
    linkedin: social.linkedin,
    social_links: buildSocialLinksFromHandles(social),
    accepted_at: row.created_at,
    verify_ms: row.verify_ms,
    spec_sha256: row.spec_sha256,
    spec_is_current: mission !== null && row.spec_sha256 === mission.spec_sha256,
    files: extractPatchPaths(row.patch),
    ...(coAuthors.length > 0 ? { co_authors: coAuthors } : {}),
    ...(decompMeta ? { decomposition: decompMeta } : {}),
  };
}

/** Full permalink view: ledger entry plus the patch and how to reproduce it. */
export function buildLedgerProof(
  row: LedgerRow,
  mission: LedgerMissionInfo,
  hubOrigin: string,
  nonDemoVerifiedCount?: number
) {
  return {
    ...buildLedgerEntry(row, mission, hubOrigin, nonDemoVerifiedCount),
    submission_id: row.submission_id,
    summary: row.summary,
    patch: row.patch,
    task_proof_url: `${hubOrigin}/api/missions/${encodeURIComponent(row.mission_id)}/tasks/${encodeURIComponent(row.task_id)}/proof`,
    history_mbox: `${hubOrigin}/api/missions/${encodeURIComponent(row.mission_id)}/history.mbox`,
    how_to_rebuild: howToRebuild(hubOrigin, row.mission_id),
  };
}

/** `/proofs`, `/proofs/` and `/proofs/<64 lowercase hex>` (optionally with a trailing slash). */
export function isLedgerPagePath(path: string): boolean {
  return /^\/proofs\/?$/.test(path) || /^\/proofs\/[0-9a-f]{64}\/?$/.test(path);
}

export type FailureStage =
  | "patch"
  | "lint"
  | "compile"
  | "kernel"
  | "axioms"
  | "timeout"
  | "sandbox";

const VALID_FAILURE_STAGES = new Set<string>([
  "patch",
  "lint",
  "compile",
  "kernel",
  "axioms",
  "timeout",
  "sandbox",
]);

export const MAX_DIAGNOSTICS_CHARS = 2_000;

/** Validate and clip optional structured failure diagnostics from the verifier. */
export function sanitizeFailureDiagnostics(
  stage: unknown,
  diagnostics: unknown
): { stage?: FailureStage; diagnostics?: string } {
  const out: { stage?: FailureStage; diagnostics?: string } = {};
  if (typeof stage === "string" && VALID_FAILURE_STAGES.has(stage)) {
    out.stage = stage as FailureStage;
  }
  if (typeof diagnostics === "string") {
    const trimmed = diagnostics.trim();
    if (trimmed) {
      out.diagnostics = trimmed.slice(0, MAX_DIAGNOSTICS_CHARS);
    }
  }
  return out;
}

/**
 * Single-request view of a task's current target files and readable frozen specs
 * (`GET /api/missions/:id/tasks/:task/files`) so agents can inspect a theorem stub
 * before downloading the full `bundle.tar.gz`.
 */
export function buildTaskFilesView(opts: {
  mission: MissionManifest;
  specSha256: string;
  task: TaskState;
  unlocked: boolean;
  seedFiles: Record<string, string>;
  liveOverlay: Record<string, string>;
}) {
  const { mission, specSha256, task, unlocked, seedFiles, liveOverlay } = opts;
  const targetFiles: Record<string, string> = {};
  const frozenFiles: Record<string, string> = {};

  const allPaths = Array.from(
    new Set([...Object.keys(seedFiles), ...Object.keys(liveOverlay)])
  ).sort();

  for (const rel of allPaths) {
    const isFrozen = mission.frozen_paths.some((pat) => globMatches(pat, rel));
    if (isFrozen) {
      // Frozen files always come strictly from the trusted seed, never from mutable overlay.
      if (rel in seedFiles) {
        frozenFiles[rel] = seedFiles[rel];
      }
      continue;
    }
    if (task.def.target_files.some((pat) => globMatches(pat, rel))) {
      targetFiles[rel] = rel in liveOverlay ? liveOverlay[rel] : seedFiles[rel];
    }
  }

  return {
    mission_id: mission.id,
    task_id: task.def.id,
    title: task.def.title,
    status: task.status,
    unlocked,
    open_conjecture: isOpenConjectureTask(mission, task.def),
    spec_sha256: specSha256,
    upstream_url: task.def.upstream_url ?? null,
    depends_on: task.def.depends_on ?? [],
    target_files: targetFiles,
    frozen_files: frozenFiles,
  };
}

// ---------------------------------------------------------------------------
// v2 Theorem Decomposition & Kernel-Verified Refutations (docs/RFC-DECOMPOSE.md)

export const MIN_DECOMPOSE_SUBGOALS = 2;
export const MAX_DECOMPOSE_SUBGOALS = 6;
export const MAX_DECOMPOSE_DEPTH = 2;
export const MAX_ACTIVE_DECOMPOSITIONS_PER_TARGET = 1;
export const MAX_ACTIVE_DECOMPOSITIONS_PER_CONTRIBUTOR = 3;
export const MAX_SUBGOAL_STATEMENT_BYTES = 4096;
export const ARCHITECT_SHARE_RATIO = 0.2;
export const REFUTATION_BOUNTY_TIER1 = 75;
export const REFUTATION_BOUNTY_OTHER = 50;

export const DECOMP_ID_RE = /^[a-z0-9][a-z0-9_]{0,23}$/;
export const SUBGOAL_ID_RE = /^[a-z][a-z0-9_]{1,47}$/;
export const LEAN_QUALIFIED_IDENT_RE = /^[A-Za-z_][A-Za-z0-9_']*(?:\.[A-Za-z_][A-Za-z0-9_']*)*$/;
const RESERVED_DECOMP_FILE_RE = /^[^/]+\/(?:SunsteadStatements|DecompStatements_[A-Za-z0-9_]+)\.lean$/;

export type DecompositionStatus = "active" | "completed" | "refuted" | "bypassed" | "cancelled";

export interface IncomingSubgoalInput {
  id: string;
  title: string;
  statement: string;
}

export interface ParsedDecomposeRequest {
  decomp_id: string;
  subgoals: IncomingSubgoalInput[];
  reduction_file: string;
  reduction_module: string;
  reduction_theorem: string;
  patch: string;
}

export interface ParsedRefuteRequest {
  refute_file: string;
  refute_module: string;
  refute_theorem: string;
  patch: string;
}

export interface SubgoalSpec {
  id: string;
  title: string;
  statement: string;
  task_id: string;
  subgoal_module: string;
  subgoal_theorem: string;
  target_file: string;
  subgoal_spec_sha256: string;
}

/** Zero-inflation point split (RFC §5.2): architect gets floor(20%), each subgoal gets floor(80% / k). */
export function computeDecompPointSplit(
  parentPoints: number,
  subgoalCount: number
): {
  solver_points_per_subgoal: number;
  architect_points: number;
  max_total_points: number;
} {
  if (!Number.isFinite(parentPoints) || parentPoints <= 0 || subgoalCount < MIN_DECOMPOSE_SUBGOALS) {
    return { solver_points_per_subgoal: 0, architect_points: 0, max_total_points: 0 };
  }
  const base = Math.floor(parentPoints);
  const architect = Math.floor(base * ARCHITECT_SHARE_RATIO);
  const solverPool = base - architect;
  const perSubgoal = Math.floor(solverPool / subgoalCount);
  return {
    solver_points_per_subgoal: perSubgoal,
    architect_points: architect,
    max_total_points: architect + perSubgoal * subgoalCount,
  };
}

/** Bounty awarded for a kernel-verified refutation (`¬ L_i` or non-conjecture `¬ T`); 0 on demo missions. */
export function computeRefutationBounty(mission: Pick<MissionManifest, "tier" | "demo">): number {
  if (mission.demo) return 0;
  return mission.tier === 1 ? REFUTATION_BOUNTY_TIER1 : REFUTATION_BOUNTY_OTHER;
}

/** Full points awarded when a kernel-verified `¬ T` resolves an open conjecture (0 on demo missions). */
export function computeOpenConjectureRefutePoints(
  mission: MissionManifest,
  task: TaskState
): number {
  if (mission.demo) return 0;
  return computePoints(mission, task, null, 1.0);
}

export function buildSubgoalTaskId(parentTaskId: string, decompId: string, subgoalId: string): string {
  return `${parentTaskId}__${decompId}__${subgoalId}`;
}

export function leanPathToModule(relPath: string): string {
  const norm = normalizeRelPath(relPath);
  if (!norm.endsWith(".lean")) {
    throw new Error(`expected a .lean file path, got '${relPath}'`);
  }
  const mod = norm.slice(0, -5).replace(/\//g, ".");
  if (!LEAN_QUALIFIED_IDENT_RE.test(mod)) {
    throw new Error(`invalid Lean module path: '${relPath}'`);
  }
  return mod;
}

export function checkDecompositionEligibility(opts: {
  manifest: MissionManifest;
  task: TaskState;
  allTasks: TaskState[];
  contributor: string;
  isAllowlisted: boolean;
  activeDecompsOnTarget: number;
  activeDecompsByContributor: number;
}): { depth: number; max_depth: number } {
  const { manifest, task, allTasks, isAllowlisted, activeDecompsOnTarget, activeDecompsByContributor } = opts;
  if (manifest.mode !== "dag") {
    throw new Error("only DAG missions support theorem decomposition");
  }
  if (manifest.snapshot?.mode === "repo-snapshot") {
    throw new Error("repo-snapshot missions do not support Phase 1 decomposition yet");
  }
  const policy = manifest.decomposition;
  if (!policy || !policy.enabled) {
    throw new Error(`decomposition is not enabled on mission '${manifest.id}'`);
  }
  if (policy.require_allowlist !== false && !isAllowlisted) {
    throw new Error(
      `contributor '${opts.contributor}' is not on the Phase 1 decomposition allowlist for '${manifest.id}'`
    );
  }
  if (!isTaskUnlocked(task, allTasks)) {
    throw new Error(`task '${task.def.id}' is blocked on unverified dependencies`);
  }
  if (task.status === "verified") {
    throw new Error(`task '${task.def.id}' is already verified`);
  }
  if (task.status === "refuted") {
    throw new Error(`task '${task.def.id}' is already refuted`);
  }
  const disputeMsg = taskDisputeReason(task);
  if (disputeMsg) {
    throw new Error(`${disputeMsg} and cannot be decomposed`);
  }
  const parentDepth = task.def.decomp_depth ?? 0;
  const maxDepth = Math.min(MAX_DECOMPOSE_DEPTH, Math.max(1, policy.max_depth ?? MAX_DECOMPOSE_DEPTH));
  const nextDepth = parentDepth + 1;
  if (nextDepth > maxDepth) {
    throw new Error(
      `decomposition depth limit reached: max depth is ${maxDepth} (task '${task.def.id}' is already at depth ${parentDepth})`
    );
  }
  if (activeDecompsOnTarget >= MAX_ACTIVE_DECOMPOSITIONS_PER_TARGET) {
    throw new Error(
      `task '${task.def.id}' already has an active decomposition (max ${MAX_ACTIVE_DECOMPOSITIONS_PER_TARGET} active per target)`
    );
  }
  if (activeDecompsByContributor >= MAX_ACTIVE_DECOMPOSITIONS_PER_CONTRIBUTOR) {
    throw new Error(
      `active decomposition cap reached for '${opts.contributor}' (max ${MAX_ACTIVE_DECOMPOSITIONS_PER_CONTRIBUTOR} active decompositions per contributor)`
    );
  }
  return { depth: nextDepth, max_depth: maxDepth };
}

export function parseDecomposeRequest(
  rawBody: unknown,
  opts: {
    libRoot: string;
    frozenPaths: string[];
    defaultDecompId: string;
  }
): ParsedDecomposeRequest {
  if (!rawBody || typeof rawBody !== "object" || Array.isArray(rawBody)) {
    throw new Error("request body must be a JSON object");
  }
  const body = rawBody as Record<string, unknown>;
  const decompId =
    typeof body.decomp_id === "string" && body.decomp_id.trim()
      ? body.decomp_id.trim()
      : opts.defaultDecompId;
  if (!DECOMP_ID_RE.test(decompId)) {
    throw new Error(`invalid decomp_id '${decompId}': use lowercase letters, digits, or underscores (max 24 chars)`);
  }
  if (!Array.isArray(body.subgoals)) {
    throw new Error("subgoals must be a JSON array");
  }
  if (body.subgoals.length < MIN_DECOMPOSE_SUBGOALS || body.subgoals.length > MAX_DECOMPOSE_SUBGOALS) {
    throw new Error(
      `decomposition requires between ${MIN_DECOMPOSE_SUBGOALS} and ${MAX_DECOMPOSE_SUBGOALS} subgoals (got ${body.subgoals.length})`
    );
  }
  const enc = new TextEncoder();
  const seenIds = new Set<string>();
  const subgoals: IncomingSubgoalInput[] = [];
  for (const item of body.subgoals) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error("each subgoal must be an object with id, title, and statement");
    }
    const obj = item as Record<string, unknown>;
    const id = typeof obj.id === "string" ? obj.id.trim() : "";
    if (!SUBGOAL_ID_RE.test(id)) {
      throw new Error(`invalid subgoal id '${id}': use 2-48 lowercase letters, digits, or underscores starting with a-z`);
    }
    if (seenIds.has(id)) {
      throw new Error(`duplicate subgoal id '${id}'`);
    }
    seenIds.add(id);
    const title = typeof obj.title === "string" ? obj.title.trim().replace(/[\r\n\t]+/g, " ").slice(0, 140) : "";
    if (!title) {
      throw new Error(`subgoal '${id}' requires a non-empty title`);
    }
    const statement = typeof obj.statement === "string" ? obj.statement.trim() : "";
    if (!statement) {
      throw new Error(`subgoal '${id}' requires a non-empty Lean Prop statement`);
    }
    if (enc.encode(statement).byteLength > MAX_SUBGOAL_STATEMENT_BYTES) {
      throw new Error(`subgoal '${id}' statement exceeds ${MAX_SUBGOAL_STATEMENT_BYTES} bytes`);
    }
    subgoals.push({ id, title, statement });
  }

  const rawRedFile = typeof body.reduction_file === "string" ? body.reduction_file.trim() : "";
  if (!rawRedFile) {
    throw new Error("reduction_file is required");
  }
  const reductionFile = normalizeRelPath(rawRedFile);
  if (!reductionFile.startsWith(`${opts.libRoot}/`) || !reductionFile.endsWith(".lean")) {
    throw new Error(`reduction_file must live under '${opts.libRoot}/' and end with '.lean'`);
  }
  if (RESERVED_DECOMP_FILE_RE.test(reductionFile)) {
    throw new Error(`reduction_file '${reductionFile}' uses a reserved Sunstead statements module name`);
  }
  const reductionModule = leanPathToModule(reductionFile);

  const reductionTheorem =
    typeof body.reduction_theorem === "string" ? body.reduction_theorem.trim() : "";
  if (!LEAN_QUALIFIED_IDENT_RE.test(reductionTheorem)) {
    throw new Error("reduction_theorem must be a valid qualified Lean theorem name");
  }

  const patch = typeof body.patch === "string" ? body.patch : "";
  if (!patch.trim()) {
    throw new Error("patch is required");
  }
  validatePatch(patch, opts.frozenPaths, [reductionFile]);

  return {
    decomp_id: decompId,
    subgoals,
    reduction_file: reductionFile,
    reduction_module: reductionModule,
    reduction_theorem: reductionTheorem,
    patch,
  };
}

export function parseRefuteRequest(
  rawBody: unknown,
  opts: {
    libRoot: string | null;
    frozenPaths: string[];
  }
): ParsedRefuteRequest {
  if (!rawBody || typeof rawBody !== "object" || Array.isArray(rawBody)) {
    throw new Error("request body must be a JSON object");
  }
  const body = rawBody as Record<string, unknown>;
  const patch = typeof body.patch === "string" ? body.patch : "";
  if (!patch.trim()) {
    throw new Error("patch is required");
  }
  const touched = extractPatchPaths(patch);
  let refuteFile: string;
  if (typeof body.refute_file === "string" && body.refute_file.trim()) {
    refuteFile = normalizeRelPath(body.refute_file.trim());
  } else if (touched.length === 1) {
    refuteFile = touched[0];
  } else {
    throw new Error("refute_file is required when patch touches multiple files");
  }
  if (!refuteFile.endsWith(".lean")) {
    throw new Error("refute_file must end with '.lean'");
  }
  if (opts.libRoot && !refuteFile.startsWith(`${opts.libRoot}/`)) {
    throw new Error(`refute_file must live under '${opts.libRoot}/'`);
  }
  if (RESERVED_DECOMP_FILE_RE.test(refuteFile)) {
    throw new Error(`refute_file '${refuteFile}' uses a reserved Sunstead statements module name`);
  }
  validatePatch(patch, opts.frozenPaths, [refuteFile]);

  const refuteModule = leanPathToModule(refuteFile);
  const refuteTheorem =
    typeof body.refute_theorem === "string" ? body.refute_theorem.trim() : "";
  if (!LEAN_QUALIFIED_IDENT_RE.test(refuteTheorem)) {
    throw new Error("refute_theorem must be a valid qualified Lean theorem name");
  }
  return {
    refute_file: refuteFile,
    refute_module: refuteModule,
    refute_theorem: refuteTheorem,
    patch,
  };
}

/** Generate a clean sorry stub for a spawned decomposition subgoal task. */
export function buildSubgoalStubSource(opts: {
  libRoot: string;
  decompStatementsModule: string;
  decompStatementsNamespace: string;
  subgoalId: string;
  subgoalTitle: string;
  subgoalTheorem: string;
  statementPreamble?: string;
}): string {
  const { libRoot, decompStatementsModule, decompStatementsNamespace, subgoalId, subgoalTitle, subgoalTheorem } = opts;
  const parts = subgoalTheorem.split(".");
  const shortName = parts[parts.length - 1];
  const nsPrefix = parts.length > 1 ? parts.slice(0, -1).join(".") : "";
  const preamble = (opts.statementPreamble || "").trim();
  const lines = [
    `import ${libRoot}.Spec`,
    `import ${decompStatementsModule}`,
    "",
  ];
  if (preamble) {
    lines.push(preamble, "");
  }
  if (nsPrefix) {
    lines.push(`namespace ${nsPrefix}`, "");
  }
  lines.push(
    `/-- Spawned v2 decomposition subgoal: ${subgoalTitle.replace(/\*\//g, "* /").replace(/-\//g, "- /")} -/`,
    `theorem ${shortName} : ${decompStatementsNamespace}.${subgoalId} := by`,
    `  sorry`,
    ""
  );
  if (nsPrefix) {
    lines.push(`end ${nsPrefix}`, "");
  }
  return lines.join("\n");
}

/** Extract leading `import ...` lines from a Lean 4 file, returning deduplicated module names and remaining body. */
export function splitLeanImports(source: string): { imports: string[]; body: string } {
  const lines = source.replace(/\r\n/g, "\n").split("\n");
  const imports: string[] = [];
  const bodyLines: string[] = [];
  let inHeader = true;
  let blockDepth = 0;

  for (const line of lines) {
    if (!inHeader) {
      bodyLines.push(line);
      continue;
    }
    const trimmed = line.trim();
    if (blockDepth > 0) {
      bodyLines.push(line);
      for (let i = 0; i < line.length - 1; i++) {
        if (line[i] === "/" && line[i + 1] === "-") {
          blockDepth++;
          i++;
        } else if (line[i] === "-" && line[i + 1] === "/") {
          blockDepth = Math.max(0, blockDepth - 1);
          i++;
        }
      }
      continue;
    }
    if (trimmed === "" || trimmed.startsWith("--")) {
      bodyLines.push(line);
      continue;
    }
    if (trimmed.startsWith("/-")) {
      bodyLines.push(line);
      for (let i = 0; i < line.length - 1; i++) {
        if (line[i] === "/" && line[i + 1] === "-") {
          blockDepth++;
          i++;
        } else if (line[i] === "-" && line[i + 1] === "/") {
          blockDepth = Math.max(0, blockDepth - 1);
          i++;
        }
      }
      continue;
    }
    const impMatch = trimmed.match(/^import\s+([A-Za-z0-9_.'«»]+)(?:\s*--.*)?$/);
    if (impMatch) {
      imports.push(impMatch[1]);
      continue;
    }
    inHeader = false;
    bodyLines.push(line);
  }
  return { imports, body: bodyLines.join("\n").trim() };
}

/** Extract the Prop body from a frozen `def <name> : Prop := <expr>` statement. */
export function extractPropStatementExpr(statementDef: string): string {
  const trimmed = statementDef.trim();
  const m = trimmed.match(/^(?:noncomputable\s+)?def\s+[A-Za-z_][A-Za-z0-9_']*\s*:\s*Prop\s*:=\s*([\s\S]+)$/);
  return m ? m[1].trim() : trimmed;
}

export type AssembledProofNode =
  | {
      kind: "leaf";
      label: string;
      theorem: string;
      source: string;
    }
  | {
      kind: "decomp";
      decomp_id: string;
      decomp_statements_module: string;
      decomp_statements_source: string;
      reduction_theorem: string;
      reduction_source: string;
      children: AssembledProofNode[];
    };

/** Extract top-level `namespace Foo` names declared in Lean source text. */
function extractLeanNamespaces(source: string): string[] {
  const out: string[] = [];
  for (const line of source.replace(/\r\n/g, "\n").split("\n")) {
    const m = line.match(/^\s*namespace\s+([A-Za-z_][A-Za-z0-9_']*(?:\.[A-Za-z_][A-Za-z0-9_']*)*)\s*(?:--.*)?$/);
    if (m) out.push(m[1]);
  }
  return out;
}

/**
 * Assemble a complete, self-contained, sorry-free Lean 4 file proving `targetTheorem : targetTypeExpr`
 * from a verified decomposition tree (depth 1 or depth 2).
 *
 * The output has zero imports of reserved `DecompStatements_*` modules (unless explicitly listed in
 * `keepImports`, e.g. when assembling a depth-2 child into a depth-1 subgoal file) and compiles
 * cleanly under the original untouched `./verify <T>` and stock `lake build` + `leanchecker`.
 */
export function assembleDecomposedLeanFile(opts: {
  baseImports: string[];
  keepImports?: string[];
  knownRootNamespaces?: string[];
  statementPreamble?: string;
  targetTheorem: string;
  targetTypeExpr: string;
  root: AssembledProofNode;
}): string {
  const importOrder: string[] = [];
  const seenImports = new Set<string>();
  const keepSet = new Set(opts.keepImports || []);
  const inlineModules = new Set<string>();
  const knownRootNs = new Set<string>(opts.knownRootNamespaces || []);
  const thmPartsForRoot = opts.targetTheorem.split(".");
  if (thmPartsForRoot.length > 1) {
    knownRootNs.add(thmPartsForRoot.slice(0, -1).join("."));
    knownRootNs.add(thmPartsForRoot[0]);
  }

  const collectInlineMods = (node: AssembledProofNode) => {
    if (node.kind === "decomp") {
      inlineModules.add(node.decomp_statements_module);
      for (const ch of node.children) collectInlineMods(ch);
    }
  };
  collectInlineMods(opts.root);

  const addImport = (mod: string) => {
    if (!mod || seenImports.has(mod)) return;
    if (inlineModules.has(mod) && !keepSet.has(mod)) return;
    if (/\.DecompStatements_[A-Za-z0-9_]+$/.test(mod) && !keepSet.has(mod)) return;
    seenImports.add(mod);
    importOrder.push(mod);
  };

  for (const imp of opts.baseImports) addImport(imp);
  for (const imp of opts.keepImports || []) addImport(imp);

  const emittedDecompStmts = new Set<string>();
  const stmtBlocks: string[] = [];
  const proofBlocks: string[] = [];
  let nsCounter = 0;

  const wrapInIsolatedNamespace = (body: string): string => {
    const ns = `SunsteadAssembled_${++nsCounter}`;
    // When a contributor file writes `namespace Foo`, at top level it brings root
    // declarations in `Foo` into scope. Wrapping inside `SunsteadAssembled_k`
    // creates `SunsteadAssembled_k.Foo`, so pre-opening any known root namespace
    // `Foo` in an enclosing `section` preserves unqualified references while still
    // isolating all newly defined contributor symbols under `SunsteadAssembled_k`.
    const opens = Array.from(
      new Set(extractLeanNamespaces(body).filter((n) => knownRootNs.has(n)))
    );
    const openPrefix = opens.length > 0 ? `open ${opens.join(" ")}\n` : "";
    proofBlocks.push(`section\n${openPrefix}namespace ${ns}\n${body}\nend ${ns}\nend`);
    return ns;
  };

  const emitNode = (node: AssembledProofNode): string => {
    if (node.kind === "leaf") {
      const split = splitLeanImports(node.source);
      for (const imp of split.imports) addImport(imp);
      const ns = wrapInIsolatedNamespace(split.body);
      return `${ns}.${node.theorem}`;
    }
    // Emit this decomposition's frozen subgoal definitions once.
    if (!emittedDecompStmts.has(node.decomp_statements_module)) {
      emittedDecompStmts.add(node.decomp_statements_module);
      const stSplit = splitLeanImports(node.decomp_statements_source);
      for (const imp of stSplit.imports) addImport(imp);
      stmtBlocks.push(`section\n${stSplit.body}\nend`);
    }
    const childTerms = node.children.map((ch) => emitNode(ch));
    const redSplit = splitLeanImports(node.reduction_source);
    for (const imp of redSplit.imports) addImport(imp);
    const redNs = wrapInIsolatedNamespace(redSplit.body);
    return `(${redNs}.${node.reduction_theorem} ${childTerms.join(" ")})`;
  };

  const finalProofTerm = emitNode(opts.root);

  const thmParts = opts.targetTheorem.split(".");
  const shortThm = thmParts[thmParts.length - 1];
  const thmNs = thmParts.length > 1 ? thmParts.slice(0, -1).join(".") : "";
  const preamble = (opts.statementPreamble || "").trim();

  const sections: string[] = [];
  sections.push(importOrder.map((m) => `import ${m}`).join("\n"));
  if (stmtBlocks.length > 0) {
    sections.push(stmtBlocks.join("\n\n"));
  }
  if (proofBlocks.length > 0) {
    sections.push(proofBlocks.join("\n\n"));
  }
  const finalLines: string[] = ["section"];
  if (preamble) {
    finalLines.push(preamble);
  }
  if (thmNs) {
    finalLines.push(`namespace ${thmNs}`);
  }
  finalLines.push(
    `theorem ${shortThm} :`,
    `    (${opts.targetTypeExpr}) :=`,
    `  ${finalProofTerm}`
  );
  if (thmNs) {
    finalLines.push(`end ${thmNs}`);
  }
  finalLines.push("end");
  sections.push(finalLines.join("\n"));

  return sections.filter(Boolean).join("\n\n") + "\n";
}

/** Generate a standard unified git diff replacing `oldContent` (or creating a new file when null) with `newContent`. */
export function generateUnifiedDiff(
  relPath: string,
  oldContent: string | null,
  newContent: string
): string {
  const norm = normalizeRelPath(relPath);
  const splitLines = (text: string): { lines: string[]; hasTrailingNl: boolean } => {
    const clean = text.replace(/\r\n/g, "\n");
    if (clean === "") return { lines: [], hasTrailingNl: true };
    const hasTrailingNl = clean.endsWith("\n");
    const body = hasTrailingNl ? clean.slice(0, -1) : clean;
    return { lines: body.split("\n"), hasTrailingNl };
  };

  const dst = splitLines(newContent);
  const out: string[] = [`diff --git a/${norm} b/${norm}`];
  if (oldContent === null) {
    out.push("new file mode 100644", "--- /dev/null", `+++ b/${norm}`);
    out.push(`@@ -0,0 +1,${dst.lines.length} @@`);
    for (const l of dst.lines) out.push(`+${l}`);
    if (!dst.hasTrailingNl) out.push("\\ No newline at end of file");
    return out.join("\n") + "\n";
  }

  const src = splitLines(oldContent);
  out.push(`--- a/${norm}`, `+++ b/${norm}`);
  out.push(`@@ -1,${src.lines.length} +1,${dst.lines.length} @@`);
  for (const l of src.lines) out.push(`-${l}`);
  if (!src.hasTrailingNl && src.lines.length > 0) out.push("\\ No newline at end of file");
  for (const l of dst.lines) out.push(`+${l}`);
  if (!dst.hasTrailingNl && dst.lines.length > 0) out.push("\\ No newline at end of file");
  return out.join("\n") + "\n";
}
