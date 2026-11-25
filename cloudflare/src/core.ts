/**
 * Sunstead core rules (frozen-path policy, DAG readiness, task transitions,
 * points) for the Cloudflare hub. Unit tests: cloudflare/test/core.test.ts.
 */

export type MissionMode = "dag" | "hillclimb";
export type ScoreDirection = "maximize" | "minimize";
export type TaskStatus = "open" | "leased" | "verified";
export type VerifierKind = "lean4" | "lean4-v4.35.0";

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
}

export const SUPPORTED_VERIFIER_TOOLCHAINS: Record<
  VerifierKind,
  { toolchain: string; container_app: string; default_image: string }
> = {
  lean4: {
    toolchain: "leanprover/lean4:v4.36.0",
    container_app: "sunstead-verifier-lean4",
    default_image: "sunstead/verifier-lean4:v0.2",
  },
  "lean4-v4.35.0": {
    toolchain: "leanprover/lean4:v4.35.0",
    container_app: "sunstead-verifier-lean4-v435",
    default_image: "sunstead/verifier-lean4-v4.35.0:v0.1",
  },
};

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
    throw new Error(`unsupported verifier toolchain: ${tc}`);
  }
  if (img.includes("lean4-v4.35.0")) return "lean4-v4.35.0";
  if (img.includes("lean4")) return "lean4";
  throw new Error(`unsupported verifier image: ${img}`);
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
  snapshot?: RepoSnapshotConfig;
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
  github_verified_handle?: string | null;
  x?: string | null;
  linkedin?: string | null;
  summary: string;
  patch: string;
  spec_sha256: string;
  created_at: number;
  verify_ms: number | null;
};

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
  return {
    mission_id: row.mission_id,
    task_id: row.task_id,
    seq: row.seq,
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
export function buildLedgerEntry(
  row: LedgerRow,
  mission: LedgerMissionInfo,
  hubOrigin: string,
  nonDemoVerifiedCount?: number
) {
  const manifest = mission?.manifest ?? null;
  const taskDef = manifest?.tasks.find((t) => t.id === row.task_id) ?? null;
  const upstream = manifest?.upstream ?? null;
  const effectiveNonDemo = nonDemoVerifiedCount ?? (manifest?.demo ? 0 : 1);
  const social = gatePublicSocialHandles(
    { github: row.github, x: row.x ?? null, linkedin: row.linkedin ?? null },
    effectiveNonDemo
  );
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
    // Reserved for an independent re-check (e.g. a leanchecker audit workflow).
    // null means no audit has run; nothing on the hub fills it in yet.
    audit: null,
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
    spec_sha256: specSha256,
    upstream_url: task.def.upstream_url ?? null,
    depends_on: task.def.depends_on ?? [],
    target_files: targetFiles,
    frozen_files: frozenFiles,
  };
}
