import { clearGithubVerification, startGithubVerification, confirmGithubVerification } from "./github_verification";
import { DurableObject } from "cloudflare:workers";
import {
  applyClaim,
  applyVerdict,
  computeFrontier,
  computePoints,
  isTaskUnlocked,
  validatePatch,
  type Lease,
  type MissionManifest,
  type TaskState,
  type TaskStatus,
  filesStateSha256,
  renderMbox,
  type AcceptedPatch,
  buildProofView,
  type AcceptedProofRow,
  sseHello,
  buildLedgerEntry,
  buildLedgerProof,
  parseLedgerQuery,
  PROOF_HASH_RE,
  type LedgerMissionInfo,
  type LedgerRow,
  verifiedGithubHandle,
  buildTaskFilesView,
  sanitizeFailureDiagnostics,
  type FailureStage,
  normalizeGithubHandle,
  normalizeXHandle,
  normalizeLinkedinHandle,
  parseProfilePatch,
  gatePublicSocialHandles,
  buildSocialLinksFromHandles,
  publicVerifierImage,
  buildMissionLocalSetup,
  renderRepoSnapshotBootstrapScript,
} from "./core";
import { SEED_MISSIONS, type SeedMission } from "./generated/missions";
import { renderJoinTxt } from "./join_txt";
import type { Lean4Verifier, Lean4V435Verifier, Lean4V431Verifier } from "./containers";

export interface HubEnv {
  HUB: DurableObjectNamespace<SunsteadHub>;
  LEAN4_VERIFIER: DurableObjectNamespace<Lean4Verifier>;
  LEAN4_V435_VERIFIER: DurableObjectNamespace<Lean4V435Verifier>;
  LEAN4_V431_VERIFIER: DurableObjectNamespace<Lean4V431Verifier>;
}

function parseVerifierKind(kind: string): SeedMission["verifier_kind"] {
  if (kind === "lean4-v4.35.0") return "lean4-v4.35.0";
  if (kind === "lean4-v4.31.0") return "lean4-v4.31.0";
  return "lean4";
}

interface HubEvent {
  kind: string;
  mission_id: string;
  task_id: string | null;
  contributor: string | null;
  accepted: boolean | null;
  score: number | null;
  summary: string;
  timestamp: number;
}

interface SubmissionRecord {
  id: string;
  mission_id: string;
  task_id: string;
  contributor: string;
  accepted: boolean;
  score: number | null;
  points: number;
  summary: string;
  patch_sha256: string;
  verify_ms: number;
  created_at: number;
  is_demo: boolean;
}

type ContributorRecord = {
  handle: string;
  display_name: string;
  github: string | null;
  github_verified_handle: string | null;
  github_verified_at: number | null;
  x_handle: string | null;
  linkedin_handle: string | null;
  created_at: number;
};

interface ContainerVerifyResponse {
  ok: boolean;
  score?: number | null;
  summary: string;
  stage?: FailureStage;
  diagnostics?: string;
  spec_sha256: string;
  updated_files?: Record<string, string>;
  normalized_patch?: string;
  verify_ms: number;
}

const MAX_BODY_BYTES = 512 * 1024;
const MAX_SSE_CLIENTS = 200;
const SSE_KEEPALIVE_MS = 25_000;

const MAX_ACTIVE_LEASES_PER_IDENTITY = 2;
const MAX_ACTIVE_LEASES_PER_IP = 3;
const RATE_LIMITS = {
  register_ip: { limit: 5, windowSec: 3600 },
  claim_id: { limit: 10, windowSec: 3600 },
  claim_ip: { limit: 15, windowSec: 3600 },
  submit_id: { limit: 20, windowSec: 3600 },
  submit_ip: { limit: 30, windowSec: 3600 },
  profile_id: { limit: 30, windowSec: 3600 },
} as const;

function sanitizeHandle(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]/g, "")
    .slice(0, 36);
}

function sanitizeOptionalText(raw: unknown, maxLen: number): string {
  if (typeof raw !== "string") return "";
  return raw.trim().replace(/[\r\n\t]+/g, " ").slice(0, maxLen);
}

async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `sha256:${hex}`;
}

function generateApiKey(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  const hex = Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `ss_live_${hex}`;
}

function clientIp(request: Request): string {
  return (
    request.headers.get("CF-Connecting-IP") ||
    request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ||
    "unknown"
  );
}

function extractBearerToken(request: Request): string | null {
  const auth = request.headers.get("Authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : null;
}

function jsonResp(data: unknown, status = 200, extraHeaders?: Record<string, string>): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      ...(extraHeaders || {}),
    },
  });
}

export class SunsteadHub extends DurableObject<HubEnv> {
  private sseClients = new Set<WritableStreamDefaultWriter<Uint8Array>>();
  private encoder = new TextEncoder();
  private stateLocks = new Map<string, Promise<void>>();
  private verifyLocks = new Map<string, Promise<void>>();

  constructor(ctx: DurableObjectState, env: HubEnv) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.initSchema();
      this.seedMissions();
    });
  }

  private initSchema(): void {
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS missions (
        id TEXT PRIMARY KEY,
        manifest_json TEXT NOT NULL,
        spec_sha256 TEXT NOT NULL,
        verifier_kind TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS tasks (
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

      CREATE TABLE IF NOT EXISTS contributors (
        handle TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        github TEXT,
        token_sha256 TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS submissions (
        id TEXT PRIMARY KEY,
        mission_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        contributor TEXT NOT NULL,
        accepted INTEGER NOT NULL,
        score REAL,
        points INTEGER NOT NULL DEFAULT 0,
        summary TEXT NOT NULL,
        patch_sha256 TEXT NOT NULL,
        verify_ms INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        is_demo INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS rate_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bucket TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS mission_files (
        mission_id TEXT NOT NULL,
        rel_path TEXT NOT NULL,
        content TEXT NOT NULL,
        PRIMARY KEY (mission_id, rel_path)
      );

      CREATE TABLE IF NOT EXISTS bundle_cache (
        mission_id TEXT PRIMARY KEY,
        tarball BLOB NOT NULL,
        updated_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS claims_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mission_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        contributor TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );

      -- Every accepted patch, in order, so mission history can be published
      -- as git commits (GET /api/missions/:id/history.mbox).
      CREATE TABLE IF NOT EXISTS accepted_patches (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        mission_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        submission_id TEXT NOT NULL,
        contributor TEXT NOT NULL,
        summary TEXT NOT NULL,
        patch TEXT NOT NULL,
        spec_sha256 TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_demo INTEGER NOT NULL DEFAULT 0
      );

      CREATE INDEX IF NOT EXISTS idx_accepted_patches_mission
        ON accepted_patches(mission_id, seq);
      CREATE INDEX IF NOT EXISTS idx_submissions_created
        ON submissions(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_rate_events_bucket_time
        ON rate_events(bucket, created_at);
    `);

    // Safe additive schema migrations for existing Durable Object SQLite instances.
    this.ensureColumn("tasks", "lease_ip", "TEXT");
    this.ensureColumn("submissions", "points", "INTEGER NOT NULL DEFAULT 0");
    this.ensureColumn("contributors", "x_handle", "TEXT");
    this.ensureColumn("contributors", "linkedin_handle", "TEXT");
    this.ensureColumn("contributors", "github_verified_handle", "TEXT");
    this.ensureColumn("contributors", "github_verified_at", "INTEGER");
    this.ensureColumn("contributors", "github_challenge", "TEXT");
    this.ensureColumn("contributors", "github_challenge_expires", "INTEGER");
    this.ctx.storage.sql.exec(clearGithubVerification);
    // Ledger permalink key: SHA-256 of the stored (possibly normalized) patch.
    // Rows from before this column are filled in by backfillPatchHashes().
    this.ensureColumn("accepted_patches", "patch_sha256", "TEXT");
    this.ctx.storage.sql.exec(
      "CREATE INDEX IF NOT EXISTS idx_accepted_patches_sha ON accepted_patches(patch_sha256)"
    );

    // Persist demo flag on historical submissions and accepted proofs so retired
    // demo missions (such as `onboarding-sandbox`) stay flagged as 0-pt demo rows
    // in /proofs and never count toward research verified_tasks or social-link unlock.
    this.ensureColumn("submissions", "is_demo", "INTEGER NOT NULL DEFAULT 0");
    this.ensureColumn("accepted_patches", "is_demo", "INTEGER NOT NULL DEFAULT 0");
    const knownDemoIds = new Set<string>(["onboarding-sandbox"]);
    for (const s of SEED_MISSIONS) {
      if (s.manifest.demo) knownDemoIds.add(s.manifest.id);
    }
    for (const row of this.ctx.storage.sql
      .exec<{ id: string; manifest_json: string }>("SELECT id, manifest_json FROM missions")
      .toArray()) {
      try {
        const parsed = JSON.parse(row.manifest_json) as { demo?: boolean };
        if (parsed.demo) knownDemoIds.add(row.id);
      } catch {
        // Ignore legacy rows with unreadable manifest JSON.
      }
    }
    for (const demoId of knownDemoIds) {
      this.ctx.storage.sql.exec(
        "UPDATE submissions SET is_demo = 1 WHERE mission_id = ? AND is_demo = 0",
        demoId
      );
      this.ctx.storage.sql.exec(
        "UPDATE accepted_patches SET is_demo = 1 WHERE mission_id = ? AND is_demo = 0",
        demoId
      );
    }
  }

  private ensureColumn(table: string, col: string, colDef: string): void {
    const cols = this.ctx.storage.sql
      .exec<{ name: string }>(`PRAGMA table_info(${table})`)
      .toArray();
    if (!cols.some((c) => c.name === col)) {
      this.ctx.storage.sql.exec(`ALTER TABLE ${table} ADD COLUMN ${col} ${colDef}`);
    }
  }

  private seedMissions(): void {
    const now = Math.floor(Date.now() / 1000);
    const seedMissionIds = new Set(SEED_MISSIONS.map((s) => s.manifest.id));

    // Prune retired missions from active tables while preserving historical
    // submissions, contributors, claims_log, and accepted_patches.
    const existingMissions = this.ctx.storage.sql
      .exec<{ id: string }>("SELECT id FROM missions")
      .toArray();
    for (const row of existingMissions) {
      if (!seedMissionIds.has(row.id)) {
        this.ctx.storage.sql.exec("DELETE FROM tasks WHERE mission_id = ?", row.id);
        this.ctx.storage.sql.exec("DELETE FROM mission_files WHERE mission_id = ?", row.id);
        this.ctx.storage.sql.exec(
          "DELETE FROM bundle_cache WHERE mission_id IN (?, ?)",
          row.id,
          `${row.id}#seed`
        );
        this.ctx.storage.sql.exec("DELETE FROM missions WHERE id = ?", row.id);
      }
    }

    for (const seed of SEED_MISSIONS) {
      const existing = this.ctx.storage.sql
        .exec<{ spec_sha256: string }>(
          "SELECT spec_sha256 FROM missions WHERE id = ?",
          seed.manifest.id
        )
        .toArray();
      const specChanged = existing.length > 0 && existing[0].spec_sha256 !== seed.spec_sha256;

      this.ctx.storage.sql.exec(
        `INSERT INTO missions (id, manifest_json, spec_sha256, verifier_kind, created_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           manifest_json = excluded.manifest_json,
           spec_sha256 = excluded.spec_sha256,
           verifier_kind = excluded.verifier_kind`,
        seed.manifest.id,
        JSON.stringify(seed.manifest),
        seed.spec_sha256,
        seed.verifier_kind,
        now
      );

      if (specChanged) {
        this.ctx.storage.sql.exec(
          "DELETE FROM bundle_cache WHERE mission_id IN (?, ?)",
          seed.manifest.id,
          `${seed.manifest.id}#seed`
        );
      }

      const seedTaskIds = new Set(seed.manifest.tasks.map((t) => t.id));
      const existingTasks = this.ctx.storage.sql
        .exec<{ task_id: string }>(
          "SELECT task_id FROM tasks WHERE mission_id = ?",
          seed.manifest.id
        )
        .toArray();
      for (const t of existingTasks) {
        if (!seedTaskIds.has(t.task_id)) {
          this.ctx.storage.sql.exec(
            "DELETE FROM tasks WHERE mission_id = ? AND task_id = ?",
            seed.manifest.id,
            t.task_id
          );
        }
      }

      for (const task of seed.manifest.tasks) {
        this.ctx.storage.sql.exec(
          `INSERT INTO tasks (mission_id, task_id, def_json, status, best_score, attempts)
           VALUES (?, ?, ?, 'open', ?, 0)
           ON CONFLICT(mission_id, task_id) DO UPDATE SET
             def_json = excluded.def_json`,
          seed.manifest.id,
          task.id,
          JSON.stringify(task),
          task.baseline_score ?? null
        );
      }
    }
  }

  private checkRateLimit(
    bucket: string,
    limit: number,
    windowSec: number,
    now: number
  ): { allowed: boolean; retryAfterSec: number } {
    const cutoff = now - windowSec;
    this.ctx.storage.sql.exec("DELETE FROM rate_events WHERE created_at < ?", now - 7200);
    const rows = this.ctx.storage.sql
      .exec<{ created_at: number }>(
        "SELECT created_at FROM rate_events WHERE bucket = ? AND created_at >= ? ORDER BY created_at ASC",
        bucket,
        cutoff
      )
      .toArray();
    if (rows.length >= limit) {
      const retryAfterSec = Math.max(1, rows[0].created_at + windowSec - now);
      return { allowed: false, retryAfterSec };
    }
    return { allowed: true, retryAfterSec: 0 };
  }

  private recordRateEvent(bucket: string, now: number): void {
    this.ctx.storage.sql.exec(
      "INSERT INTO rate_events (bucket, created_at) VALUES (?, ?)",
      bucket,
      now
    );
  }

  private async resolveContributor(
    request: Request,
    bodyHandle?: string
  ): Promise<{ ok: true; handle: string; authenticated: boolean } | { ok: false; status: number; error: string }> {
    const token = extractBearerToken(request);
    if (token) {
      const hash = await sha256Hex(token);
      const rows = this.ctx.storage.sql
        .exec<{ handle: string }>(
          "SELECT handle FROM contributors WHERE token_sha256 = ?",
          hash
        )
        .toArray();
      if (rows.length === 0) {
        return { ok: false, status: 401, error: "invalid Bearer API key" };
      }
      return { ok: true, handle: rows[0].handle, authenticated: true };
    }

    // Require registered identity for claims & submissions so leaderboard attribution
    // and per-identity lease rate limits cannot be spoofed or bypassed.
    const requested = sanitizeHandle(bodyHandle || "");
    if (requested) {
      const exists = this.ctx.storage.sql
        .exec<{ handle: string }>(
          "SELECT handle FROM contributors WHERE handle = ?",
          requested
        )
        .toArray();
      if (exists.length > 0) {
        return {
          ok: false,
          status: 401,
          error: `handle '${requested}' is registered; send Authorization: Bearer <SUNSTEAD_API_KEY>`,
        };
      }
    }
    return {
      ok: false,
      status: 401,
      error:
        "authentication required: register once via POST /api/contributors/register and send Authorization: Bearer <api_key>",
    };
  }

  private countActiveLeases(contributor: string, ip: string, now: number): { byId: number; byIp: number } {
    const byId = this.ctx.storage.sql
      .exec<{ c: number }>(
        "SELECT COUNT(*) AS c FROM tasks WHERE lease_contributor = ? AND lease_expires_at > ?",
        contributor,
        now
      )
      .one().c;
    const byIp =
      ip === "unknown"
        ? 0
        : this.ctx.storage.sql
            .exec<{ c: number }>(
              "SELECT COUNT(*) AS c FROM tasks WHERE lease_ip = ? AND lease_expires_at > ?",
              ip,
              now
            )
            .one().c;
    return { byId, byIp };
  }

  private listMissionsRows(): SeedMission[] {
    const rows = this.ctx.storage.sql
      .exec<{ manifest_json: string; spec_sha256: string; verifier_kind: string }>(
        "SELECT manifest_json, spec_sha256, verifier_kind FROM missions"
      )
      .toArray();

    const parsed: SeedMission[] = rows.map((r) => ({
      manifest: JSON.parse(r.manifest_json) as MissionManifest,
      spec_sha256: r.spec_sha256,
      verifier_kind: parseVerifierKind(r.verifier_kind),
    }));

    parsed.sort((a, b) =>
      b.manifest.tier !== a.manifest.tier
        ? b.manifest.tier - a.manifest.tier
        : a.manifest.id.localeCompare(b.manifest.id)
    );
    return parsed;
  }

  private getMissionRow(missionId: string): SeedMission | null {
    const rows = this.ctx.storage.sql
      .exec<{ manifest_json: string; spec_sha256: string; verifier_kind: string }>(
        "SELECT manifest_json, spec_sha256, verifier_kind FROM missions WHERE id = ?",
        missionId
      )
      .toArray();
    if (rows.length === 0) return null;
    return {
      manifest: JSON.parse(rows[0].manifest_json) as MissionManifest,
      spec_sha256: rows[0].spec_sha256,
      verifier_kind: parseVerifierKind(rows[0].verifier_kind),
    };
  }

  private getTasks(missionId: string): TaskState[] {
    const now = Math.floor(Date.now() / 1000);
    const rows = this.ctx.storage.sql
      .exec<{
        def_json: string;
        status: string;
        best_score: number | null;
        verified_by: string | null;
        lease_contributor: string | null;
        lease_token: string | null;
        lease_expires_at: number | null;
        attempts: number;
      }>(
        `SELECT def_json, status, best_score, verified_by,
                lease_contributor, lease_token, lease_expires_at, attempts
         FROM tasks WHERE mission_id = ? ORDER BY rowid ASC`,
        missionId
      )
      .toArray();

    return rows.map((r) => {
      const def = JSON.parse(r.def_json);
      let active_lease: Lease | null = null;
      if (
        r.lease_contributor &&
        r.lease_token &&
        r.lease_expires_at !== null &&
        r.lease_expires_at > now
      ) {
        active_lease = {
          task_id: def.id,
          contributor: r.lease_contributor,
          lease_token: r.lease_token,
          expires_at_unix: r.lease_expires_at,
        };
      }
      let status: TaskStatus =
        r.status === "verified" ? "verified" : r.status === "leased" ? "leased" : "open";
      if (status === "leased" && !active_lease) {
        status = "open";
      }
      return {
        def,
        status,
        best_score: r.best_score,
        verified_by: r.verified_by,
        active_lease,
        attempts: r.attempts,
      };
    });
  }

  private getMissionFiles(missionId: string): Record<string, string> {
    const rows = this.ctx.storage.sql
      .exec<{ rel_path: string; content: string }>(
        "SELECT rel_path, content FROM mission_files WHERE mission_id = ?",
        missionId
      )
      .toArray();
    const out: Record<string, string> = {};
    for (const r of rows) out[r.rel_path] = r.content;
    return out;
  }

  private getRecentSubmissions(missionId: string | null, limit: number): SubmissionRecord[] {
    const rows = missionId
      ? this.ctx.storage.sql
          .exec<{
            id: string;
            mission_id: string;
            task_id: string;
            contributor: string;
            accepted: number;
            score: number | null;
            points: number;
            summary: string;
            patch_sha256: string;
            verify_ms: number;
            created_at: number;
            is_demo: number;
          }>(
            `SELECT id, mission_id, task_id, contributor, accepted, score, points, summary,
                    patch_sha256, verify_ms, created_at, is_demo
             FROM submissions WHERE mission_id = ? ORDER BY created_at DESC LIMIT ?`,
            missionId,
            limit
          )
          .toArray()
      : this.ctx.storage.sql
          .exec<{
            id: string;
            mission_id: string;
            task_id: string;
            contributor: string;
            accepted: number;
            score: number | null;
            points: number;
            summary: string;
            patch_sha256: string;
            verify_ms: number;
            created_at: number;
            is_demo: number;
          }>(
            `SELECT id, mission_id, task_id, contributor, accepted, score, points, summary,
                    patch_sha256, verify_ms, created_at, is_demo
             FROM submissions ORDER BY created_at DESC LIMIT ?`,
            limit
          )
          .toArray();

    return rows.map((r) => ({ ...r, accepted: r.accepted !== 0, is_demo: r.is_demo !== 0 }));
  }

  private insertSubmission(rec: SubmissionRecord): void {
    this.ctx.storage.sql.exec(
      `INSERT INTO submissions
       (id, mission_id, task_id, contributor, accepted, score, points, summary, patch_sha256, verify_ms, created_at, is_demo)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      rec.id,
      rec.mission_id,
      rec.task_id,
      rec.contributor,
      rec.accepted ? 1 : 0,
      rec.score,
      rec.points,
      rec.summary,
      rec.patch_sha256,
      rec.verify_ms,
      rec.created_at,
      rec.is_demo ? 1 : 0
    );
  }

  private emit(ev: HubEvent): void {
    const frame = this.encoder.encode(
      `event: ${ev.kind}\ndata: ${JSON.stringify(ev)}\n\n`
    );
    for (const writer of Array.from(this.sseClients)) {
      writer.write(frame).catch(() => {
        this.sseClients.delete(writer);
        writer.close().catch(() => {});
      });
    }
  }

  private async withLock<T>(
    locks: Map<string, Promise<void>>,
    key: string,
    fn: () => Promise<T>
  ): Promise<T> {
    const prev = locks.get(key) ?? Promise.resolve();
    let release!: () => void;
    const gate = new Promise<void>((r) => {
      release = r;
    });
    const chained = prev.then(() => gate);
    locks.set(key, chained);
    await prev;
    try {
      return await fn();
    } finally {
      release();
      if (locks.get(key) === chained) {
        locks.delete(key);
      }
    }
  }

  private getVerifierStub(mission: SeedMission) {
    // Route each mission to its pinned Lean toolchain container, keying by image
    // tag so bumping the verifier image always routes to a fresh container DO.
    const key = `${mission.verifier_kind}:${mission.manifest.verifier.image}:${mission.manifest.id}`;
    if (mission.verifier_kind === "lean4-v4.35.0") {
      return this.env.LEAN4_V435_VERIFIER.getByName(key);
    }
    if (mission.verifier_kind === "lean4-v4.31.0") {
      return this.env.LEAN4_V431_VERIFIER.getByName(key);
    }
    return this.env.LEAN4_VERIFIER.getByName(key);
  }

  private getDemoMissionIds(): Set<string> {
    const demo = new Set<string>();
    for (const m of this.listMissionsRows()) {
      if (m.manifest.demo) demo.add(m.manifest.id);
    }
    for (const s of SEED_MISSIONS) {
      if (s.manifest.demo) demo.add(s.manifest.id);
    }
    return demo;
  }

  /** Map of contributor handle -> count of accepted proofs on non-demo missions. */
  private getNonDemoProofCounts(): Map<string, number> {
    const demoIds = this.getDemoMissionIds();
    const rows = this.ctx.storage.sql
      .exec<{ contributor: string; mission_id: string; c: number }>(
        `SELECT contributor, mission_id, COUNT(*) AS c
         FROM submissions
         WHERE accepted = 1 AND is_demo = 0
         GROUP BY contributor, mission_id`
      )
      .toArray();
    const counts = new Map<string, number>();
    for (const r of rows) {
      if (demoIds.has(r.mission_id)) continue;
      counts.set(r.contributor, (counts.get(r.contributor) ?? 0) + r.c);
    }
    return counts;
  }

  private getContributorNonDemoProofCount(handle: string): number {
    const demoIds = this.getDemoMissionIds();
    const rows = this.ctx.storage.sql
      .exec<{ mission_id: string; c: number }>(
        `SELECT mission_id, COUNT(*) AS c
         FROM submissions
         WHERE contributor = ? AND accepted = 1 AND is_demo = 0
         GROUP BY mission_id`,
        handle
      )
      .toArray();
    let total = 0;
    for (const r of rows) {
      if (!demoIds.has(r.mission_id)) total += r.c;
    }
    return total;
  }

  private computeLeaderboard(limit = 30) {
    // Count active hill-climb crowns (+150 bonus per active non-demo hillclimb record held)
    const hillclimbCrowns = new Map<string, number>();
    for (const m of this.listMissionsRows()) {
      if (m.manifest.mode !== "hillclimb" || m.manifest.demo) continue;
      for (const t of this.getTasks(m.manifest.id)) {
        if (t.status === "verified" && t.verified_by) {
          hillclimbCrowns.set(t.verified_by, (hillclimbCrowns.get(t.verified_by) ?? 0) + 1);
        }
      }
    }

    const nonDemoCounts = this.getNonDemoProofCounts();
    const rows = this.ctx.storage.sql
      .exec<{
        contributor: string;
        display_name: string | null;
        github: string | null;
        github_verified_handle: string | null;
        x_handle: string | null;
        linkedin_handle: string | null;
        verified_tasks: number;
        accepted_submissions: number;
        total_submissions: number;
        base_points: number;
      }>(
        `SELECT
           s.contributor AS contributor,
           c.display_name AS display_name,
           c.github AS github, c.github_verified_handle AS github_verified_handle,
           c.x_handle AS x_handle,
           c.linkedin_handle AS linkedin_handle,
           COUNT(DISTINCT CASE WHEN s.accepted = 1 AND s.is_demo = 0 THEN s.mission_id || ':' || s.task_id END) AS verified_tasks,
           SUM(CASE WHEN s.accepted = 1 AND s.is_demo = 0 THEN 1 ELSE 0 END) AS accepted_submissions,
           SUM(CASE WHEN s.is_demo = 0 THEN 1 ELSE 0 END) AS total_submissions,
           SUM(CASE WHEN s.accepted = 1 AND s.is_demo = 0 THEN s.points ELSE 0 END) AS base_points
         FROM submissions s
         LEFT JOIN contributors c ON c.handle = s.contributor
         WHERE s.is_demo = 0
         GROUP BY s.contributor`
      )
      .toArray();

    const enriched = rows.map((r) => {
      const active_records = hillclimbCrowns.get(r.contributor) ?? 0;
      const points = r.base_points + active_records * 150;
      const nonDemoVerified = nonDemoCounts.get(r.contributor) ?? 0;
      const social = gatePublicSocialHandles(
        { github: r.github, x: r.x_handle, linkedin: r.linkedin_handle },
        nonDemoVerified
      );
      return {
        contributor: r.contributor,
        display_name: r.display_name || r.contributor,
        github: social.github,
        github_verified_handle: verifiedGithubHandle(social.github, r.github_verified_handle),
        x: social.x,
        linkedin: social.linkedin,
        social_links: buildSocialLinksFromHandles(social),
        verified_identity: r.display_name !== null,
        points,
        active_records,
        verified_tasks: r.verified_tasks,
        accepted_submissions: r.accepted_submissions,
        total_submissions: r.total_submissions,
      };
    });

    enriched.sort(
      (a, b) =>
        b.points - a.points ||
        b.verified_tasks - a.verified_tasks ||
        a.contributor.localeCompare(b.contributor)
    );
    return enriched.slice(0, limit);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    if (method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    if (method === "GET" && path === "/join.txt") {
      const missions = this.listMissionsRows().map((m) => ({
        manifest: m.manifest,
        tasks: this.getTasks(m.manifest.id),
      }));
      const base = `${url.protocol}//${url.host}`;
      return new Response(renderJoinTxt(base, missions), {
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    if (method === "GET" && path === "/api/health") {
      const registeredCount = this.ctx.storage.sql
        .exec<{ c: number }>("SELECT COUNT(*) AS c FROM contributors")
        .one().c;
      return jsonResp({
        ok: true,
        service: "sunstead-cloudflare",
        docker_verifier_ready: true,
        verifier_label: "Sandbox Ready · Cloudflare",
        verifier_backend: "cloudflare-containers",
        registered_contributors: registeredCount,
        timestamp: Math.floor(Date.now() / 1000),
      });
    }

    if (method === "POST" && (path === "/api/contributors/register" || path === "/api/register")) {
      return this.handleRegisterContributor(request);
    }

    if (method === "GET" && path === "/api/me") {
      return this.handleGetMe(request);
    }

    if (method === "PATCH" && path === "/api/me") {
      return this.handlePatchMe(request);
    }

    if (method === "POST" && (path === "/api/me/verify/github/start" || path === "/api/me/verify/github/confirm")) {
      const auth = await this.resolveContributor(request);
      if (!auth.ok) return jsonResp({ error: auth.error }, auth.status);
      const now = Math.floor(Date.now() / 1000);
      const key = `github-verification:${auth.handle}`;
      const limit = this.checkRateLimit(key, 12, 3600, now);
      if (!limit.allowed) return jsonResp({ error: "Verification rate limit reached" }, 429, {
        "Retry-After": String(limit.retryAfterSec),
      });
      this.recordRateEvent(key, now);
      const sql = this.ctx.storage.sql;
      const result = path.endsWith("/start")
        ? startGithubVerification(sql, auth.handle, now)
        : await confirmGithubVerification(sql, auth.handle,
            (await request.json<{gist_id?: unknown}>().catch(() => null))?.gist_id);
      return jsonResp(result.body, result.status, { "Cache-Control": "no-store" });
    }

    const contribMatch = path.match(/^\/api\/contributors\/([^/]+)$/);
    if (method === "GET" && contribMatch) {
      const handle = sanitizeHandle(decodeURIComponent(contribMatch[1]));
      return this.handleGetContributor(handle);
    }

    if (method === "GET" && path === "/api/missions") {
      const summaries = this.listMissionsRows().map((m) => {
        const tasks = this.getTasks(m.manifest.id);
        return {
          id: m.manifest.id,
          title: m.manifest.title,
          description: m.manifest.description ?? "",
          tier: m.manifest.tier,
          mode: m.manifest.mode,
          demo: Boolean(m.manifest.demo),
          upstream: m.manifest.upstream ?? null,
          score_direction: m.manifest.score_direction ?? "maximize",
          spec_sha256: m.spec_sha256,
          verifier_image: m.manifest.verifier.image,
          verifier_public_image: publicVerifierImage(m.manifest.verifier.image),
          verifier_toolchain: m.manifest.verifier.toolchain ?? "leanprover/lean4:v4.36.0",
          snapshot: m.manifest.snapshot ?? null,
          frozen_paths: m.manifest.frozen_paths,
          total_tasks: tasks.length,
          verified_tasks: tasks.filter((t) => t.status === "verified").length,
          leased_tasks: tasks.filter((t) => t.active_lease !== null).length,
          frontier_task_ids: computeFrontier(m.manifest.mode, tasks),
        };
      });
      return jsonResp({ missions: summaries });
    }

    if (method === "GET" && path === "/api/submissions") {
      const missionId = url.searchParams.get("mission_id");
      const limit = Math.max(1, Math.min(Number(url.searchParams.get("limit") || 40), 200));
      return jsonResp({ submissions: this.getRecentSubmissions(missionId, limit) });
    }

    if (method === "GET" && path === "/api/leaderboard") {
      return jsonResp({ leaderboard: this.computeLeaderboard(30) });
    }

    if (method === "GET" && path === "/api/events") {
      if (this.sseClients.size >= MAX_SSE_CLIENTS) {
        return jsonResp(
          { error: "too many concurrent event stream listeners" },
          503,
          { "Retry-After": "15" }
        );
      }
      const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
      const writer = writable.getWriter();
      let closed = false;
      let pingTimer: ReturnType<typeof setInterval> | null = null;
      const cleanup = () => {
        if (closed) return;
        closed = true;
        if (pingTimer !== null) {
          clearInterval(pingTimer);
          pingTimer = null;
        }
        this.sseClients.delete(writer);
        writer.close().catch(() => {});
      };
      this.sseClients.add(writer);
      request.signal.addEventListener("abort", cleanup, { once: true });
      writer.closed.then(cleanup, cleanup);
      writer.write(this.encoder.encode(sseHello())).catch(cleanup);
      pingTimer = setInterval(() => {
        if (closed) return;
        writer.write(this.encoder.encode(": ping\n\n")).catch(cleanup);
      }, SSE_KEEPALIVE_MS);
      return new Response(readable, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    const bundleMatch = path.match(/^\/api\/missions\/([^/]+)\/bundle\.tar\.gz$/);
    if (method === "GET" && bundleMatch) {
      return this.handleBundle(
        decodeURIComponent(bundleMatch[1]),
        url.searchParams.get("base") === "seed"
      );
    }

    const historyMatch = path.match(/^\/api\/missions\/([^/]+)\/history(\.mbox)?$/);
    if (method === "GET" && historyMatch) {
      return this.handleHistory(decodeURIComponent(historyMatch[1]), historyMatch[2] === ".mbox");
    }

    const proofMatch = path.match(/^\/api\/missions\/([^/]+)\/tasks\/([^/]+)\/proof$/);
    if (method === "GET" && proofMatch) {
      return this.handleProof(
        decodeURIComponent(proofMatch[1]),
        decodeURIComponent(proofMatch[2]),
        url.origin
      );
    }

    if (method === "GET" && path === "/api/proofs") {
      return this.handleLedgerList(url.searchParams, url.origin);
    }

    const ledgerMatch = path.match(/^\/api\/proofs\/([^/]+)$/);
    if (method === "GET" && ledgerMatch) {
      return this.handleLedgerProof(decodeURIComponent(ledgerMatch[1]), url.origin);
    }

    const taskFilesMatch = path.match(/^\/api\/missions\/([^/]+)\/tasks\/([^/]+)\/files$/);
    if (method === "GET" && taskFilesMatch) {
      return this.handleTaskFiles(
        decodeURIComponent(taskFilesMatch[1]),
        decodeURIComponent(taskFilesMatch[2])
      );
    }

    if (method === "GET" && path === "/api/stats") {
      return jsonResp(this.computeStats());
    }

    const bootstrapMatch = path.match(/^\/api\/missions\/([^/]+)\/bootstrap\.sh$/);
    if (method === "GET" && bootstrapMatch) {
      const missionId = decodeURIComponent(bootstrapMatch[1]);
      const mission = this.getMissionRow(missionId);
      if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);
      if (mission.manifest.snapshot?.mode !== "repo-snapshot") {
        return jsonResp(
          { error: `mission '${missionId}' is not a repo-snapshot mission; use bundle.tar.gz directly` },
          400
        );
      }
      const script = renderRepoSnapshotBootstrapScript(mission.manifest, url.origin);
      return new Response(script, {
        headers: {
          "Content-Type": "text/x-shellscript; charset=utf-8",
          "Content-Disposition": `inline; filename="${missionId}-bootstrap.sh"`,
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    const missionMatch = path.match(/^\/api\/missions\/([^/]+)$/);
    if (method === "GET" && missionMatch) {
      const missionId = decodeURIComponent(missionMatch[1]);
      const mission = this.getMissionRow(missionId);
      if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);
      const tasks = this.getTasks(missionId);
      const frontier = computeFrontier(mission.manifest.mode, tasks);
      return jsonResp({
        mission: {
          manifest: mission.manifest,
          spec_sha256: mission.spec_sha256,
          repo_dir: `cloudflare://missions/${missionId}`,
        },
        local_setup: buildMissionLocalSetup(mission.manifest, url.origin),
        frontier,
        tasks: tasks.map((t) => ({ ...t, unlocked: isTaskUnlocked(t, tasks) })),
        recent_submissions: this.getRecentSubmissions(missionId, 25),
      });
    }

    const claimMatch = path.match(/^\/api\/missions\/([^/]+)\/tasks\/([^/]+)\/claim$/);
    if (method === "POST" && claimMatch) {
      return this.handleClaim(
        decodeURIComponent(claimMatch[1]),
        decodeURIComponent(claimMatch[2]),
        request
      );
    }

    const releaseMatch = path.match(/^\/api\/missions\/([^/]+)\/tasks\/([^/]+)\/release$/);
    if (method === "POST" && releaseMatch) {
      return this.handleRelease(
        decodeURIComponent(releaseMatch[1]),
        decodeURIComponent(releaseMatch[2]),
        request
      );
    }

    const submitMatch = path.match(/^\/api\/missions\/([^/]+)\/tasks\/([^/]+)\/submit$/);
    if (method === "POST" && submitMatch) {
      return this.handleSubmit(
        decodeURIComponent(submitMatch[1]),
        decodeURIComponent(submitMatch[2]),
        request
      );
    }

    return jsonResp({ error: "not found" }, 404);
  }

  private async handleRegisterContributor(request: Request): Promise<Response> {
    const ip = clientIp(request);
    const now = Math.floor(Date.now() / 1000);

    let body: { handle?: string; display_name?: string; github?: unknown; x?: unknown; linkedin?: unknown };
    try {
      body = (await request.json()) as {
        handle?: string;
        display_name?: string;
        github?: unknown;
        x?: unknown;
        linkedin?: unknown;
      };
    } catch {
      return jsonResp({ error: "invalid JSON body" }, 400);
    }

    const handle = sanitizeHandle(body.handle || "");
    if (handle.length < 3) {
      return jsonResp(
        { error: "handle must be at least 3 characters (a-z, 0-9, ., _, -)" },
        400
      );
    }

    let github: string | null;
    let xHandle: string | null;
    let linkedinHandle: string | null;
    try {
      github = normalizeGithubHandle(body.github);
      xHandle = normalizeXHandle(body.x);
      linkedinHandle = normalizeLinkedinHandle(body.linkedin);
    } catch (e) {
      return jsonResp({ error: e instanceof Error ? e.message : String(e) }, 400);
    }

    const existing = this.ctx.storage.sql
      .exec<{ handle: string }>("SELECT handle FROM contributors WHERE handle = ?", handle)
      .toArray();
    if (existing.length > 0) {
      return jsonResp({ error: `handle '${handle}' is already claimed` }, 409);
    }

    if (ip !== "unknown") {
      const rl = this.checkRateLimit(
        `reg:ip:${ip}`,
        RATE_LIMITS.register_ip.limit,
        RATE_LIMITS.register_ip.windowSec,
        now
      );
      if (!rl.allowed) {
        return jsonResp(
          { error: `registration rate limit reached; retry in ${rl.retryAfterSec}s` },
          429,
          { "Retry-After": String(rl.retryAfterSec) }
        );
      }
      this.recordRateEvent(`reg:ip:${ip}`, now);
    }

    const displayName = sanitizeOptionalText(body.display_name, 64) || handle;
    const apiKey = generateApiKey();
    const tokenHash = await sha256Hex(apiKey);

    this.ctx.storage.sql.exec(
      `INSERT INTO contributors (handle, display_name, github, x_handle, linkedin_handle, token_sha256, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      handle,
      displayName,
      github,
      xHandle,
      linkedinHandle,
      tokenHash,
      now
    );

    return jsonResp(
      {
        registered: true,
        handle,
        display_name: displayName,
        github,
        x: xHandle,
        linkedin: linkedinHandle,
        social_links: buildSocialLinksFromHandles({ github, x: xHandle, linkedin: linkedinHandle }),
        links_public: false,
        api_key: apiKey,
        note: "Save this api_key now—Sunstead stores only its SHA-256 hash and cannot recover it. Share it across all agents you run to aggregate credit under one identity. Profile links appear publicly once you have at least 1 accepted non-demo proof.",
      },
      201
    );
  }

  private getOwnProfileResponse(handle: string): Response {
    const rows = this.ctx.storage.sql
      .exec<ContributorRecord>(
        "SELECT handle, display_name, github, github_verified_handle, github_verified_at, x_handle, linkedin_handle, created_at FROM contributors WHERE handle = ?",
        handle
      )
      .toArray();
    if (rows.length === 0) {
      return jsonResp({ error: `unknown contributor: ${handle}` }, 404);
    }
    const row = rows[0];
    const nonDemoVerified = this.getContributorNonDemoProofCount(handle);
    const handles = {
      github: row.github,
      x: row.x_handle,
      linkedin: row.linkedin_handle,
    };
    return jsonResp({
      handle: row.handle,
      display_name: row.display_name || row.handle,
      github: row.github,
      x: row.x_handle,
      linkedin: row.linkedin_handle,
      social_links: buildSocialLinksFromHandles(handles),
      github_verified_handle: row.github_verified_handle,
      github_verified_at: row.github_verified_at,
      links_public: nonDemoVerified >= 1,
      non_demo_verified_proofs: nonDemoVerified,
      created_at: row.created_at,
    });
  }

  private async handleGetMe(request: Request): Promise<Response> {
    const auth = await this.resolveContributor(request);
    if (!auth.ok) return jsonResp({ error: auth.error }, auth.status);
    return this.getOwnProfileResponse(auth.handle);
  }

  private async handlePatchMe(request: Request): Promise<Response> {
    const auth = await this.resolveContributor(request);
    if (!auth.ok) return jsonResp({ error: auth.error }, auth.status);
    const handle = auth.handle;

    let rawBody: unknown;
    try {
      rawBody = await request.json();
    } catch {
      return jsonResp({ error: "invalid JSON body" }, 400);
    }
    if (!rawBody || typeof rawBody !== "object" || Array.isArray(rawBody)) {
      return jsonResp({ error: "request body must be a JSON object" }, 400);
    }

    let parsed: ReturnType<typeof parseProfilePatch>;
    try {
      parsed = parseProfilePatch(rawBody as Record<string, unknown>);
    } catch (e) {
      return jsonResp({ error: e instanceof Error ? e.message : String(e) }, 400);
    }
    if (!parsed.hasUpdates) {
      return jsonResp(
        { error: "specify at least one field to update: display_name, github, x, or linkedin" },
        400
      );
    }

    const now = Math.floor(Date.now() / 1000);
    const rl = this.checkRateLimit(
      `profile:id:${handle}`,
      RATE_LIMITS.profile_id.limit,
      RATE_LIMITS.profile_id.windowSec,
      now
    );
    if (!rl.allowed) {
      return jsonResp(
        { error: `profile update rate limit reached; retry in ${rl.retryAfterSec}s` },
        429,
        { "Retry-After": String(rl.retryAfterSec) }
      );
    }
    this.recordRateEvent(`profile:id:${handle}`, now);

    const sets: string[] = [];
    const params: (string | null)[] = [];
    if ("display_name" in parsed) {
      sets.push("display_name = ?");
      params.push(parsed.display_name || handle);
    }
    if ("github" in parsed) {
      sets.push("github = ?");
      params.push(parsed.github ?? null);
    }
    if ("x" in parsed) {
      sets.push("x_handle = ?");
      params.push(parsed.x ?? null);
    }
    if ("linkedin" in parsed) {
      sets.push("linkedin_handle = ?");
      params.push(parsed.linkedin ?? null);
    }

    this.ctx.storage.sql.exec(
      `UPDATE contributors SET ${sets.join(", ")} WHERE handle = ?`,
      ...params,
      handle
    );
    return this.getOwnProfileResponse(handle);
  }

  private handleGetContributor(handle: string): Response {
    const profileRows = this.ctx.storage.sql
      .exec<ContributorRecord>(
        "SELECT handle, display_name, github, github_verified_handle, github_verified_at, x_handle, linkedin_handle, created_at FROM contributors WHERE handle = ?",
        handle
      )
      .toArray();
    const board = this.computeLeaderboard(500);
    const rankIdx = board.findIndex((e) => e.contributor === handle);
    if (profileRows.length === 0 && rankIdx === -1) {
      return jsonResp({ error: `unknown contributor: ${handle}` }, 404);
    }
    const recent = this.ctx.storage.sql
      .exec<{
        id: string;
        mission_id: string;
        task_id: string;
        accepted: number;
        score: number | null;
        points: number;
        summary: string;
        patch_sha256: string;
        verify_ms: number;
        created_at: number;
      }>(
        `SELECT id, mission_id, task_id, accepted, score, points, summary,
                patch_sha256, verify_ms, created_at
         FROM submissions WHERE contributor = ? ORDER BY created_at DESC LIMIT 30`,
        handle
      )
      .toArray()
      .map((r) => ({ ...r, accepted: r.accepted !== 0 }));

    const row = profileRows[0];
    const nonDemoVerified = this.getContributorNonDemoProofCount(handle);
    const social = gatePublicSocialHandles(
      row
        ? { github: row.github, x: row.x_handle, linkedin: row.linkedin_handle }
        : { github: null, x: null, linkedin: null },
      nonDemoVerified
    );

    return jsonResp({
      contributor: {
        handle: row?.handle ?? handle,
        display_name: row?.display_name || handle,
        github: social.github,
        github_verified_handle: verifiedGithubHandle(social.github, row?.github_verified_handle),
        x: social.x,
        linkedin: social.linkedin,
        social_links: buildSocialLinksFromHandles(social),
        links_public: nonDemoVerified >= 1,
        created_at: row?.created_at ?? null,
      },
      rank: rankIdx >= 0 ? rankIdx + 1 : null,
      stats: rankIdx >= 0 ? board[rankIdx] : { points: 0, verified_tasks: 0, active_records: 0 },
      recent_submissions: recent,
    });
  }

  private async handleBundle(missionId: string, seed = false): Promise<Response> {
    const mission = this.getMissionRow(missionId);
    if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);
    // `?base=seed` returns the mission as shipped, before any accepted patch,
    // so `git am history.mbox` on top of it rebuilds the live state.
    const cacheKey = seed ? `${missionId}#seed` : missionId;

    const cached = this.ctx.storage.sql
      .exec<{ tarball: ArrayBuffer }>(
        "SELECT tarball FROM bundle_cache WHERE mission_id = ?",
        cacheKey
      )
      .toArray();
    if (cached.length > 0) {
      return new Response(cached[0].tarball, {
        headers: {
          "Content-Type": "application/gzip",
          "Content-Disposition": 'attachment; filename="mission-bundle.tar.gz"',
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    const filesBefore = seed ? {} : this.getMissionFiles(missionId);
    const stateShaBefore = await filesStateSha256(filesBefore);
    const specBefore = mission.spec_sha256;

    const resp = await this.callVerifier(
      mission,
      "/bundle",
      filesBefore,
      {
        mission_id: missionId,
        frozen_paths: mission.manifest.frozen_paths,
        cache_state: !seed,
      },
      stateShaBefore
    );
    if (!resp.ok) {
      const errText = await resp.text();
      return jsonResp({ error: `bundle build failed: ${errText}` }, 502);
    }

    const bytes = await resp.arrayBuffer();
    const latestMission = this.getMissionRow(missionId);
    const stateUnchanged =
      latestMission !== null &&
      latestMission.spec_sha256 === specBefore &&
      (seed || (await filesStateSha256(this.getMissionFiles(missionId))) === stateShaBefore);

    if (stateUnchanged) {
      this.ctx.storage.sql.exec(
        `INSERT INTO bundle_cache (mission_id, tarball, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(mission_id) DO UPDATE SET tarball = excluded.tarball, updated_at = excluded.updated_at`,
        cacheKey,
        new Uint8Array(bytes),
        Math.floor(Date.now() / 1000)
      );
    }

    return new Response(bytes, {
      headers: {
        "Content-Type": "application/gzip",
        "Content-Disposition": 'attachment; filename="mission-bundle.tar.gz"',
        "Access-Control-Allow-Origin": "*",
      },
    });
  }

  /**
   * Ask the mission's verifier container to act on the current accepted state.
   * The first attempt sends only the state hash; a warm container that already
   * holds that state uses it, otherwise it answers 409 {need_files} and we
   * resend with the files.
   */
  private async callVerifier(
    mission: SeedMission,
    path: "/verify" | "/bundle",
    files: Record<string, string>,
    body: Record<string, unknown>,
    precomputedSha?: string
  ): Promise<Response> {
    const stub = this.getVerifierStub(mission);
    const stateSha = precomputedSha ?? (await filesStateSha256(files));
    const send = (withFiles: boolean) =>
      stub.fetch(
        new Request(`http://verifier${path}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            ...body,
            current_files_sha256: stateSha,
            ...(withFiles ? { current_files: files } : {}),
          }),
        })
      );
    if (body.cache_state === false) {
      return send(true);
    }
    const first = await send(false);
    if (first.status !== 409) return first;
    const info = (await first.json().catch(() => ({}))) as { need_files?: boolean };
    if (!info.need_files) {
      return new Response(JSON.stringify(info), { status: 409, headers: { "Content-Type": "application/json" } });
    }
    return send(true);
  }

  private handleHistory(missionId: string, mbox: boolean): Response {
    const mission = this.getMissionRow(missionId);
    if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);
    const rows = this.ctx.storage.sql
      .exec<{
        seq: number;
        mission_id: string;
        task_id: string;
        contributor: string;
        display_name: string;
        summary: string;
        patch: string;
        spec_sha256: string;
        created_at: number;
      }>(
        `SELECT a.seq, a.mission_id, a.task_id, a.contributor,
                COALESCE(c.display_name, a.contributor) AS display_name,
                a.summary, a.patch, a.spec_sha256, a.created_at
         FROM accepted_patches a LEFT JOIN contributors c ON c.handle = a.contributor
         WHERE a.mission_id = ? ORDER BY a.seq ASC`,
        missionId
      )
      .toArray();
    if (mbox) {
      return new Response(renderMbox(rows as AcceptedPatch[]), {
        headers: {
          "Content-Type": "application/mbox; charset=utf-8",
          "Content-Disposition": `attachment; filename="${missionId}-history.mbox"`,
          "Access-Control-Allow-Origin": "*",
        },
      });
    }
    return jsonResp({
      mission_id: missionId,
      how_to_rebuild:
        `curl -sL <hub>/api/missions/${missionId}/bundle.tar.gz?base=seed | tar xz && ` +
        `curl -sL <hub>/api/missions/${missionId}/history.mbox | git am`,
      commits: rows.map((r) => ({
        seq: r.seq,
        task_id: r.task_id,
        contributor: r.contributor,
        display_name: r.display_name,
        summary: r.summary,
        spec_sha256: r.spec_sha256,
        created_at: r.created_at,
      })),
    });
  }

  /** Latest accepted proof for one task, for the inspector's "View verified proof" panel. */
  private async handleProof(missionId: string, taskId: string, hubOrigin: string): Promise<Response> {
    const mission = this.getMissionRow(missionId);
    if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);
    const rows = this.ctx.storage.sql
      .exec<AcceptedProofRow>(
        `SELECT a.seq, a.mission_id, a.task_id, a.submission_id, a.contributor,
                COALESCE(c.display_name, a.contributor) AS display_name,
                c.github AS github, c.github_verified_handle AS github_verified_handle, c.x_handle AS x, c.linkedin_handle AS linkedin,
                a.summary, a.patch, a.spec_sha256, a.created_at, s.verify_ms AS verify_ms, a.is_demo AS is_demo
         FROM accepted_patches a
         LEFT JOIN contributors c ON c.handle = a.contributor
         LEFT JOIN submissions s ON s.id = a.submission_id
         WHERE a.mission_id = ? AND a.task_id = ?
         ORDER BY a.seq DESC LIMIT 1`,
        missionId,
        taskId
      )
      .toArray();
    if (rows.length === 0) {
      return jsonResp({ error: `no accepted proof for ${missionId}/${taskId}` }, 404);
    }
    const row = rows[0];
    const nonDemoVerifiedCount = this.getContributorNonDemoProofCount(row.contributor);
    return jsonResp(
      buildProofView(row, {
        hubOrigin,
        currentSpecSha256: mission.spec_sha256,
        patchSha256: await sha256Hex(row.patch),
        nonDemoVerifiedCount,
      })
    );
  }

  /** Fill accepted_patches.patch_sha256 for rows accepted before the column existed. */
  private async backfillPatchHashes(): Promise<void> {
    const missing = this.ctx.storage.sql
      .exec<{ seq: number; patch: string }>(
        "SELECT seq, patch FROM accepted_patches WHERE patch_sha256 IS NULL"
      )
      .toArray();
    if (missing.length === 0) return;
    const hashes = await Promise.all(missing.map((r) => sha256Hex(r.patch)));
    missing.forEach((r, i) => {
      this.ctx.storage.sql.exec(
        "UPDATE accepted_patches SET patch_sha256 = ? WHERE seq = ? AND patch_sha256 IS NULL",
        hashes[i],
        r.seq
      );
    });
  }

  private static readonly LEDGER_SELECT = `
    SELECT a.seq, a.mission_id, a.task_id, a.submission_id, a.contributor,
           COALESCE(c.display_name, a.contributor) AS display_name,
           c.github AS github, c.github_verified_handle AS github_verified_handle, c.x_handle AS x, c.linkedin_handle AS linkedin,
           a.summary, a.patch, a.patch_sha256, a.spec_sha256, a.created_at, s.verify_ms AS verify_ms, a.is_demo AS is_demo
    FROM accepted_patches a
    LEFT JOIN contributors c ON c.handle = a.contributor
    LEFT JOIN submissions s ON s.id = a.submission_id`;

  private ledgerMissionInfo(): (missionId: string) => LedgerMissionInfo {
    const cache = new Map<string, LedgerMissionInfo>();
    return (missionId) => {
      if (!cache.has(missionId)) cache.set(missionId, this.getMissionRow(missionId));
      return cache.get(missionId) ?? null;
    };
  }

  /** GET /api/proofs: every accepted proof, newest first, paged by ?before=<seq>. */
  private async handleLedgerList(params: URLSearchParams, hubOrigin: string): Promise<Response> {
    await this.backfillPatchHashes();
    const { limit, before, missionId } = parseLedgerQuery(params);
    const where: string[] = [];
    const args: (string | number)[] = [];
    if (before !== null) {
      where.push("a.seq < ?");
      args.push(before);
    }
    if (missionId !== null) {
      where.push("a.mission_id = ?");
      args.push(missionId);
    }
    const rows = this.ctx.storage.sql
      .exec<LedgerRow>(
        `${SunsteadHub.LEDGER_SELECT}
         ${where.length ? `WHERE ${where.join(" AND ")}` : ""}
         ORDER BY a.seq DESC LIMIT ?`,
        ...args,
        limit + 1
      )
      .toArray();
    const page = rows.slice(0, limit);
    const missionInfo = this.ledgerMissionInfo();
    const nonDemoCounts = this.getNonDemoProofCounts();
    const total = this.ctx.storage.sql
      .exec<{ c: number }>(
        missionId === null
          ? "SELECT COUNT(*) AS c FROM accepted_patches"
          : "SELECT COUNT(*) AS c FROM accepted_patches WHERE mission_id = ?",
        ...(missionId === null ? [] : [missionId])
      )
      .one().c;
    return jsonResp({
      total,
      proofs: page.map((r) =>
        buildLedgerEntry(r, missionInfo(r.mission_id), hubOrigin, nonDemoCounts.get(r.contributor) ?? 0)
      ),
      next_before: rows.length > limit ? page[page.length - 1].seq : null,
    });
  }

  /** GET /api/proofs/:proof_id: one proof's permanent record (id = bare hex of patch_sha256). */
  private async handleLedgerProof(hash: string, hubOrigin: string): Promise<Response> {
    const key = hash.toLowerCase().replace(/^sha256:/, "");
    if (!PROOF_HASH_RE.test(key)) {
      return jsonResp({ error: "proof id must be a 64-character hex SHA-256" }, 400);
    }
    await this.backfillPatchHashes();
    const rows = this.ctx.storage.sql
      .exec<LedgerRow>(
        `${SunsteadHub.LEDGER_SELECT} WHERE a.patch_sha256 = ? ORDER BY a.seq ASC`,
        `sha256:${key}`
      )
      .toArray();
    if (rows.length === 0) return jsonResp({ error: `no accepted proof with patch sha256:${key}` }, 404);
    const missionInfo = this.ledgerMissionInfo();
    const [first, ...rest] = rows;
    const nonDemoCount = this.getContributorNonDemoProofCount(first.contributor);
    return jsonResp({
      ...buildLedgerProof(first, missionInfo(first.mission_id), hubOrigin, nonDemoCount),
      // The same patch text accepted again (another task or mission) shares this hash.
      also_accepted_as: rest.map((r) => ({
        seq: r.seq,
        mission_id: r.mission_id,
        task_id: r.task_id,
        contributor: r.contributor,
        accepted_at: r.created_at,
      })),
    });
  }

  /** Single-request inspection of a task's current target files + frozen specs (no container wake-up). */
  private handleTaskFiles(missionId: string, taskId: string): Response {
    const mission = this.getMissionRow(missionId);
    if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);
    const tasks = this.getTasks(missionId);
    const task = tasks.find((t) => t.def.id === taskId);
    if (!task) return jsonResp({ error: `unknown task: ${taskId}` }, 404);
    const seed = SEED_MISSIONS.find((s) => s.manifest.id === missionId);
    return jsonResp(
      buildTaskFilesView({
        mission: mission.manifest,
        specSha256: mission.spec_sha256,
        task,
        unlocked: isTaskUnlocked(task, tasks),
        seedFiles: seed?.seed_files ?? {},
        liveOverlay: this.getMissionFiles(missionId),
      })
    );
  }

  /** Contributor funnel: registered -> claimed -> submitted -> verified. */
  private computeStats() {
    const count = (sql: string, ...args: (string | number)[]) =>
      this.ctx.storage.sql.exec<{ c: number }>(sql, ...args).one().c;
    const now = Math.floor(Date.now() / 1000);
    const funnel = (since: number) => ({
      registered: count("SELECT COUNT(*) AS c FROM contributors WHERE created_at >= ?", since),
      claimed: count("SELECT COUNT(DISTINCT contributor) AS c FROM claims_log WHERE created_at >= ?", since),
      submitted: count("SELECT COUNT(DISTINCT contributor) AS c FROM submissions WHERE created_at >= ?", since),
      verified: count(
        "SELECT COUNT(DISTINCT contributor) AS c FROM submissions WHERE accepted = 1 AND created_at >= ?",
        since
      ),
      submissions: count("SELECT COUNT(*) AS c FROM submissions WHERE created_at >= ?", since),
      accepted_submissions: count(
        "SELECT COUNT(*) AS c FROM submissions WHERE accepted = 1 AND created_at >= ?",
        since
      ),
    });
    return {
      note: "Counts of distinct contributors at each step; claims are logged from Nov 2026 on.",
      all_time: funnel(0),
      last_7_days: funnel(now - 7 * 86400),
      last_24_hours: funnel(now - 86400),
      timestamp: now,
    };
  }

  private async handleClaim(
    missionId: string,
    taskId: string,
    request: Request
  ): Promise<Response> {
    let body: { contributor?: string; lease_seconds?: number } = {};
    try {
      const text = await request.text();
      if (text.trim()) body = JSON.parse(text);
    } catch {
      return jsonResp({ error: "invalid JSON body" }, 400);
    }

    const auth = await this.resolveContributor(request, body.contributor);
    if (!auth.ok) return jsonResp({ error: auth.error }, auth.status);
    const contributor = auth.handle;

    const ip = clientIp(request);
    const now = Math.floor(Date.now() / 1000);

    return this.withLock(this.stateLocks, missionId, async () => {
      const mission = this.getMissionRow(missionId);
      if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);

      const tasks = this.getTasks(missionId);
      const targetTask = tasks.find((t) => t.def.id === taskId);
      if (!targetTask) return jsonResp({ error: `unknown task: ${taskId}` }, 404);

      const token = crypto.randomUUID();
      const duration = Number.isFinite(body.lease_seconds) ? Number(body.lease_seconds) : 1800;

      // Validate task state (unlocked, not already verified, not leased by someone else)
      // BEFORE recording rate-limit events or checking active lease caps.
      let outcome: ReturnType<typeof applyClaim>;
      try {
        outcome = applyClaim(
          mission.manifest.mode,
          tasks,
          taskId,
          contributor,
          token,
          now,
          duration
        );
      } catch (e) {
        return jsonResp({ error: e instanceof Error ? e.message : String(e) }, 409);
      }

      const isRenewal = targetTask.active_lease?.contributor === contributor;
      if (!isRenewal) {
        const active = this.countActiveLeases(contributor, ip, now);
        if (active.byId >= MAX_ACTIVE_LEASES_PER_IDENTITY) {
          return jsonResp(
            {
              error: `active lease cap reached: '${contributor}' already holds ${active.byId}/${MAX_ACTIVE_LEASES_PER_IDENTITY} active leases. Finish or POST .../release one first.`,
            },
            429
          );
        }
        if (active.byIp >= MAX_ACTIVE_LEASES_PER_IP) {
          return jsonResp(
            {
              error: `active lease cap reached for this IP (${active.byIp}/${MAX_ACTIVE_LEASES_PER_IP}).`,
            },
            429
          );
        }
      }

      // Rate-limit claims per identity & IP (exempting unknown IPs to match countActiveLeases).
      const rlId = this.checkRateLimit(
        `claim:id:${contributor}`,
        RATE_LIMITS.claim_id.limit,
        RATE_LIMITS.claim_id.windowSec,
        now
      );
      if (!rlId.allowed) {
        return jsonResp(
          { error: `claim rate limit reached for '${contributor}' (max 10/hr); retry in ${rlId.retryAfterSec}s` },
          429,
          { "Retry-After": String(rlId.retryAfterSec) }
        );
      }
      if (ip !== "unknown") {
        const rlIp = this.checkRateLimit(
          `claim:ip:${ip}`,
          RATE_LIMITS.claim_ip.limit,
          RATE_LIMITS.claim_ip.windowSec,
          now
        );
        if (!rlIp.allowed) {
          return jsonResp(
            { error: `claim rate limit reached for this IP; retry in ${rlIp.retryAfterSec}s` },
            429,
            { "Retry-After": String(rlIp.retryAfterSec) }
          );
        }
      }

      this.recordRateEvent(`claim:id:${contributor}`, now);
      if (ip !== "unknown") {
        this.recordRateEvent(`claim:ip:${ip}`, now);
      }

      this.ctx.storage.sql.exec(
        `UPDATE tasks
         SET status = ?, lease_contributor = ?, lease_token = ?, lease_expires_at = ?, lease_ip = ?
         WHERE mission_id = ? AND task_id = ?`,
        outcome.updated_status,
        outcome.lease.contributor,
        outcome.lease.lease_token,
        outcome.lease.expires_at_unix,
        ip,
        missionId,
        taskId
      );
      this.ctx.storage.sql.exec(
        "INSERT INTO claims_log (mission_id, task_id, contributor, created_at) VALUES (?, ?, ?, ?)",
        missionId,
        taskId,
        contributor,
        now
      );
      this.emit({
        kind: "lease_claimed",
        mission_id: missionId,
        task_id: taskId,
        contributor,
        accepted: null,
        score: null,
        summary: `${contributor} claimed ${taskId}`,
        timestamp: now,
      });
      return jsonResp({
        claimed: true,
        lease: outcome.lease,
        bundle_url: `/api/missions/${missionId}/bundle.tar.gz`,
      });
    });
  }

  private async handleRelease(
    missionId: string,
    taskId: string,
    request: Request
  ): Promise<Response> {
    const auth = await this.resolveContributor(request);
    if (!auth.ok) return jsonResp({ error: auth.error }, auth.status);
    const contributor = auth.handle;

    const mission = this.getMissionRow(missionId);
    if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);

    return this.withLock(this.stateLocks, missionId, async () => {
      const tasks = this.getTasks(missionId);
      const task = tasks.find((t) => t.def.id === taskId);
      if (!task) return jsonResp({ error: `unknown task: ${taskId}` }, 404);
      if (!task.active_lease || task.active_lease.contributor !== contributor) {
        return jsonResp({ error: `you do not hold an active lease on '${taskId}'` }, 409);
      }

      const now = Math.floor(Date.now() / 1000);
      const nextStatus: TaskStatus = task.status === "verified" ? "verified" : "open";
      this.ctx.storage.sql.exec(
        `UPDATE tasks
         SET status = ?, lease_contributor = NULL, lease_token = NULL, lease_expires_at = NULL, lease_ip = NULL
         WHERE mission_id = ? AND task_id = ?`,
        nextStatus,
        missionId,
        taskId
      );
      this.emit({
        kind: "lease_released",
        mission_id: missionId,
        task_id: taskId,
        contributor,
        accepted: null,
        score: null,
        summary: `${contributor} released ${taskId}`,
        timestamp: now,
      });
      return jsonResp({ released: true, mission_id: missionId, task_id: taskId });
    });
  }

  private async handleSubmit(
    missionId: string,
    taskId: string,
    request: Request
  ): Promise<Response> {
    const rawText = await request.text();
    if (new TextEncoder().encode(rawText).byteLength > MAX_BODY_BYTES) {
      return jsonResp({ error: "payload exceeds 512 KB limit" }, 413);
    }

    let body: { contributor?: string; patch?: string };
    try {
      body = JSON.parse(rawText) as { contributor?: string; patch?: string };
    } catch {
      return jsonResp({ error: "invalid JSON body" }, 400);
    }

    const auth = await this.resolveContributor(request, body.contributor);
    if (!auth.ok) return jsonResp({ error: auth.error }, auth.status);
    const contributor = auth.handle;

    const patch = typeof body.patch === "string" ? body.patch : "";
    const mission = this.getMissionRow(missionId);
    if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);

    const tasksPre = this.getTasks(missionId);
    const task = tasksPre.find((t) => t.def.id === taskId);
    if (!task) return jsonResp({ error: `unknown task: ${taskId}` }, 404);

    // Check task readiness BEFORE recording rate limits or waking any verifier container.
    if (!isTaskUnlocked(task, tasksPre)) {
      return jsonResp({ error: `task '${taskId}' is blocked on unverified dependencies` }, 409);
    }
    if (mission.manifest.mode === "dag" && task.status === "verified") {
      return jsonResp({ error: `task '${taskId}' is already verified` }, 409);
    }

    const ip = clientIp(request);
    const now = Math.floor(Date.now() / 1000);

    const rlId = this.checkRateLimit(
      `submit:id:${contributor}`,
      RATE_LIMITS.submit_id.limit,
      RATE_LIMITS.submit_id.windowSec,
      now
    );
    if (!rlId.allowed) {
      return jsonResp(
        { error: `submission rate limit reached for '${contributor}' (max 20/hr); retry in ${rlId.retryAfterSec}s` },
        429,
        { "Retry-After": String(rlId.retryAfterSec) }
      );
    }
    if (ip !== "unknown") {
      const rlIp = this.checkRateLimit(
        `submit:ip:${ip}`,
        RATE_LIMITS.submit_ip.limit,
        RATE_LIMITS.submit_ip.windowSec,
        now
      );
      if (!rlIp.allowed) {
        return jsonResp(
          { error: `submission rate limit reached for this IP; retry in ${rlIp.retryAfterSec}s` },
          429,
          { "Retry-After": String(rlIp.retryAfterSec) }
        );
      }
    }
    this.recordRateEvent(`submit:id:${contributor}`, now);
    if (ip !== "unknown") {
      this.recordRateEvent(`submit:ip:${ip}`, now);
    }

    const patchSha = await sha256Hex(patch);

    // Fast policy pre-check BEFORE waking any Cloudflare Container!
    try {
      validatePatch(patch, mission.manifest.frozen_paths, task.def.target_files);
    } catch (e) {
      const detail = e instanceof Error ? e.message : String(e);
      const summary = `policy rejected: ${detail}`;
      this.ctx.storage.sql.exec(
        "UPDATE tasks SET attempts = attempts + 1 WHERE mission_id = ? AND task_id = ?",
        missionId,
        taskId
      );
      this.insertSubmission({
        id: crypto.randomUUID(),
        mission_id: missionId,
        task_id: taskId,
        contributor,
        accepted: false,
        score: null,
        points: 0,
        summary,
        patch_sha256: patchSha,
        verify_ms: 0,
        created_at: now,
        is_demo: Boolean(mission.manifest.demo),
      });
      this.emit({
        kind: "submission_rejected",
        mission_id: missionId,
        task_id: taskId,
        contributor,
        accepted: false,
        score: null,
        summary,
        timestamp: now,
      });
      const diag = sanitizeFailureDiagnostics("patch", detail);
      return jsonResp({ error: summary, ...diag }, 422);
    }

    this.emit({
      kind: "verification_started",
      mission_id: missionId,
      task_id: taskId,
      contributor,
      accepted: null,
      score: null,
      summary: `Verifying patch from ${contributor} in internet-less Firecracker Container…`,
      timestamp: now,
    });

    // Serialize slow container invocations per mission on `verifyLocks` so
    // fast claims & releases on `stateLocks` never block behind a 120s verify.
    return this.withLock(this.verifyLocks, missionId, async () => {
      const preVerifyTasks = this.getTasks(missionId);
      const preVerifyTask = preVerifyTasks.find((t) => t.def.id === taskId);
      if (!preVerifyTask) return jsonResp({ error: `unknown task: ${taskId}` }, 404);
      if (!isTaskUnlocked(preVerifyTask, preVerifyTasks)) {
        return jsonResp({ error: `task '${taskId}' is blocked on unverified dependencies` }, 409);
      }
      if (mission.manifest.mode === "dag" && preVerifyTask.status === "verified") {
        return jsonResp({ error: `task '${taskId}' is already verified` }, 409);
      }

      let cRes: ContainerVerifyResponse;
      try {
        const resp = await this.callVerifier(mission, "/verify", this.getMissionFiles(missionId), {
          mission_id: missionId,
          task_id: taskId,
          patch,
          frozen_paths: mission.manifest.frozen_paths,
          target_files: task.def.target_files,
          timeout_sec: mission.manifest.verifier.timeout_sec ?? 90,
        });
        if (!resp.ok) {
          const errText = await resp.text().catch(() => "");
          return jsonResp(
            {
              error: `verifier container returned HTTP ${resp.status}${errText ? `: ${errText.slice(0, 300)}` : ""}`,
            },
            502
          );
        }
        const parsed = (await resp.json()) as Partial<ContainerVerifyResponse>;
        if (!parsed || typeof parsed !== "object" || typeof parsed.ok !== "boolean") {
          return jsonResp({ error: "verifier container returned malformed verdict JSON" }, 502);
        }
        cRes = parsed as ContainerVerifyResponse;
      } catch (e) {
        return jsonResp(
          { error: `verifier container invocation failed: ${e instanceof Error ? e.message : String(e)}` },
          502
        );
      }

      // Hash outside the state lock so nothing awaits between its reads and writes.
      const storedPatch =
        cRes.normalized_patch && cRes.normalized_patch.trim() ? cRes.normalized_patch : patch;
      const storedPatchSha = await sha256Hex(storedPatch);

      return this.withLock(this.stateLocks, missionId, async () => {
        const latestTasks = this.getTasks(missionId);
        const latestTask = latestTasks.find((t) => t.def.id === taskId) || task;
        const finishedAt = Math.floor(Date.now() / 1000);
        const verifyMs = cRes.verify_ms ?? 0;

        try {
          const outcome = applyVerdict(
            mission.manifest.mode,
            mission.manifest.score_direction ?? "maximize",
            mission.manifest.frozen_paths,
            mission.spec_sha256,
            latestTasks,
            taskId,
            patch,
            {
              ok: cRes.ok,
              score: cRes.score ?? null,
              summary: cRes.summary,
              spec_sha256: cRes.spec_sha256,
            }
          );

          const awardedPoints = computePoints(
            mission.manifest,
            latestTask,
            latestTask.best_score,
            outcome.new_best_score
          );

          for (const [relPath, content] of Object.entries(cRes.updated_files || {})) {
            this.ctx.storage.sql.exec(
              `INSERT INTO mission_files (mission_id, rel_path, content)
               VALUES (?, ?, ?)
               ON CONFLICT(mission_id, rel_path) DO UPDATE SET content = excluded.content`,
              missionId,
              relPath,
              content
            );
          }
          this.ctx.storage.sql.exec("DELETE FROM bundle_cache WHERE mission_id = ?", missionId);

          this.ctx.storage.sql.exec(
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
            contributor,
            missionId,
            taskId
          );

          const subId = crypto.randomUUID();
          const isDemo = Boolean(mission.manifest.demo);
          this.insertSubmission({
            id: subId,
            mission_id: missionId,
            task_id: taskId,
            contributor,
            accepted: true,
            score: outcome.new_best_score,
            points: awardedPoints,
            summary: cRes.summary,
            patch_sha256: patchSha,
            verify_ms: verifyMs,
            created_at: finishedAt,
            is_demo: isDemo,
          });
          this.ctx.storage.sql.exec(
            `INSERT INTO accepted_patches
             (mission_id, task_id, submission_id, contributor, summary, patch, spec_sha256, created_at, patch_sha256, is_demo)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            missionId,
            taskId,
            subId,
            contributor,
            cRes.summary,
            storedPatch,
            mission.spec_sha256,
            finishedAt,
            storedPatchSha,
            isDemo ? 1 : 0
          );

          this.emit({
            kind: "submission_accepted",
            mission_id: missionId,
            task_id: taskId,
            contributor,
            accepted: true,
            score: outcome.new_best_score,
            summary: `${cRes.summary} (+${awardedPoints} pts)`,
            timestamp: finishedAt,
          });

          return jsonResp({
            accepted: true,
            submission_id: subId,
            task_id: taskId,
            contributor,
            points_awarded: awardedPoints,
            score: outcome.new_best_score,
            unlocked_dependents: outcome.unlocked_dependents,
            verify_ms: verifyMs,
            summary: cRes.summary,
          });
        } catch (e) {
          const reason = e instanceof Error ? e.message : String(e);
          const subId = crypto.randomUUID();
          this.ctx.storage.sql.exec(
            "UPDATE tasks SET attempts = attempts + 1 WHERE mission_id = ? AND task_id = ?",
            missionId,
            taskId
          );
          this.insertSubmission({
            id: subId,
            mission_id: missionId,
            task_id: taskId,
            contributor,
            accepted: false,
            score: cRes.score ?? null,
            points: 0,
            summary: reason,
            patch_sha256: patchSha,
            verify_ms: verifyMs,
            created_at: finishedAt,
            is_demo: Boolean(mission.manifest.demo),
          });
          this.emit({
            kind: "submission_rejected",
            mission_id: missionId,
            task_id: taskId,
            contributor,
            accepted: false,
            score: cRes.score ?? null,
            summary: reason,
            timestamp: finishedAt,
          });
          const diag = sanitizeFailureDiagnostics(cRes.stage, cRes.diagnostics);
          return jsonResp(
            {
              accepted: false,
              submission_id: subId,
              error: reason,
              verify_ms: verifyMs,
              ...diag,
            },
            422
          );
        }
      });
    });
  }
}
