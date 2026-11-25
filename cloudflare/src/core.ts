/**
 * Sunstead core rules (frozen-path policy, DAG readiness, task transitions,
 * points) for the Cloudflare hub. Unit tests: cloudflare/test/core.test.ts.
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

export interface UpstreamProvenance {
  repo: string;
  commit: string;
  license: string;
  issue_url?: string;
}

export interface TaskDefinition {
  id: string;
  title: string;
  description?: string;
  target_files: string[];
  depends_on?: string[];
  baseline_score?: number | null;
  upstream_url?: string;
}

export interface MissionManifest {
  id: string;
  title: string;
  description?: string;
  tier: number;
  mode: MissionMode;
  repo?: string;
  upstream?: UpstreamProvenance;
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

/**
 * Points for an accepted submission.
 *
 * Demo missions (`mission.demo === true`) earn 0 leaderboard points.
 * DAG tasks pay a flat amount by tier and depth. Hill-climb records pay
 * floor(250 * |ln(new / previous)|): the log ratio is additive, so splitting one
 * improvement into many tiny records never earns more than making it at once
 * (and flooring makes it earn less). The first record on a task with no
 * baseline pays 100.
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
    if (previousBest === null || newScore === null) return 100;
    if (previousBest > 0 && newScore > 0) {
      return Math.max(0, Math.floor(250 * Math.abs(Math.log(newScore / previousBest))));
    }
    // Non-positive scores: fall back to relative change against |previous|.
    const rel = Math.abs(newScore - previousBest) / Math.max(Math.abs(previousBest), 1);
    return Math.max(0, Math.floor(250 * rel));
  }
  if (mission.tier === 1) {
    return hasDeps ? 250 : 150;
  }
  return hasDeps ? 150 : 100;
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
        `${body}\n\nSunstead-Submission: ${p.seq}\n---\n` +
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
  summary: string;
  patch: string;
  spec_sha256: string;
  created_at: number;
  verify_ms: number | null;
};

/** Shell-safe single-quoted argument. */
function shellQuote(s: string): string {
  return `'${s.replace(/'/g, `'\\''`)}'`;
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
 * Public view of a task's accepted proof (GET /api/missions/:id/tasks/:task/proof).
 * `currentSpecSha256` is the mission's spec hash now; a proof accepted under an
 * older spec is still shown, but flagged.
 */
export function buildProofView(
  row: AcceptedProofRow,
  opts: { hubOrigin: string; currentSpecSha256: string; patchSha256: string }
) {
  return {
    mission_id: row.mission_id,
    task_id: row.task_id,
    seq: row.seq,
    submission_id: row.submission_id,
    contributor: row.contributor,
    display_name: row.display_name || row.contributor,
    github: row.github || null,
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

/**
 * One ledger entry. Mission and task titles and upstream provenance come from the
 * live manifest; a proof from a retired mission keeps its record but has none.
 */
export function buildLedgerEntry(row: LedgerRow, mission: LedgerMissionInfo, hubOrigin: string) {
  const manifest = mission?.manifest ?? null;
  const taskDef = manifest?.tasks.find((t) => t.id === row.task_id) ?? null;
  const upstream = manifest?.upstream ?? null;
  return {
    proof_id: proofIdFromPatchSha(row.patch_sha256),
    patch_sha256: row.patch_sha256,
    permalink: `${hubOrigin}/proofs/${proofIdFromPatchSha(row.patch_sha256)}`,
    seq: row.seq,
    mission_id: row.mission_id,
    mission_title: manifest?.title ?? null,
    mission_retired: manifest === null,
    mission_demo: Boolean(manifest?.demo),
    task_id: row.task_id,
    task_title: taskDef?.title ?? null,
    upstream: upstream
      ? {
          repo: upstream.repo,
          commit: upstream.commit,
          license: upstream.license,
          task_url: taskDef?.upstream_url ?? null,
        }
      : null,
    contributor: row.contributor,
    display_name: row.display_name || row.contributor,
    github: row.github || null,
    accepted_at: row.created_at,
    verify_ms: row.verify_ms,
    spec_sha256: row.spec_sha256,
    spec_is_current: mission !== null && row.spec_sha256 === mission.spec_sha256,
    files: extractPatchPaths(row.patch),
    // Reserved for an independent re-check (e.g. a leanchecker audit workflow).
    // null means no audit has run; nothing on the hub fills it in yet.
    audit: null,
  };
}

/** Full permalink view: ledger entry plus the patch and how to reproduce it. */
export function buildLedgerProof(row: LedgerRow, mission: LedgerMissionInfo, hubOrigin: string) {
  return {
    ...buildLedgerEntry(row, mission, hubOrigin),
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

