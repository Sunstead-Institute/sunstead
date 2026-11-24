/**
 * 1:1 TypeScript port of `crates/sunstead-core` invariants (policy, DAG, transitions).
 * Mirrors the Verus-verified state machine rules for Cloudflare Workers/Durable Objects.
 */

export type MissionMode = "dag" | "hillclimb";
export type ScoreDirection = "maximize" | "minimize";
export type TaskStatus = "open" | "leased" | "verified";

export interface VerifierConfig {
  image: string;
  command: string[];
  timeout_sec?: number;
  memory_mb?: number;
}

export interface TaskDefinition {
  id: string;
  title: string;
  description?: string;
  target_files: string[];
  depends_on?: string[];
  baseline_score?: number | null;
}

export interface MissionManifest {
  id: string;
  title: string;
  description?: string;
  tier: number;
  mode: MissionMode;
  repo?: string;
  frozen_paths: string[];
  verifier: VerifierConfig;
  score_direction?: ScoreDirection;
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

export function extractPatchPaths(patch: string): string[] {
  const paths = new Set<string>();
  for (const line of patch.split(/\r?\n/)) {
    if (line.startsWith("GIT binary patch") || line.startsWith("Binary files ")) {
      throw new Error("binary patches are forbidden");
    }
    if (
      line.startsWith("new file mode 120") ||
      line.startsWith("old mode 120") ||
      line.startsWith("new mode 120")
    ) {
      throw new Error("symlink mode changes (120000) are forbidden");
    }

    if (line.startsWith("diff --git ")) {
      const tokens = line.slice("diff --git ".length).trim().split(/\s+/);
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

export function isTaskUnlocked(task: TaskState, allTasks: TaskState[]): boolean {
  const deps = task.def.depends_on || [];
  return deps.every((depId) => {
    const found = allTasks.find((other) => other.def.id === depId);
    return found?.status === "verified";
  });
}

export function computeFrontier(mode: MissionMode, tasks: TaskState[]): string[] {
  return tasks
    .filter((t) => {
      const unlocked = isTaskUnlocked(t, tasks);
      return mode === "dag" ? unlocked && t.status !== "verified" : unlocked;
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
  if (!isTaskUnlocked(task, allTasks)) {
    throw new Error(`task '${taskId}' is blocked on unverified dependencies`);
  }
  if (mode === "dag" && task.status === "verified") {
    throw new Error(`task '${taskId}' is already verified`);
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

  validatePatch(patch, frozenPaths, task.def.target_files);

  if (verdict.spec_sha256 !== expectedSpecSha256) {
    throw new Error(
      `spec hash mismatch: expected '${expectedSpecSha256}', got '${verdict.spec_sha256}'`
    );
  }
  if (!verdict.ok) {
    throw new Error(`verification failed: ${verdict.summary}`);
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
  const unlockedDependents = simulated
    .filter(
      (c) =>
        (c.def.depends_on || []).includes(taskId) &&
        isTaskUnlocked(c, simulated) &&
        c.status !== "verified"
    )
    .map((t) => t.def.id);

  return {
    updated_status: "verified",
    new_best_score: newBestScore,
    unlocked_dependents: unlockedDependents,
  };
}
