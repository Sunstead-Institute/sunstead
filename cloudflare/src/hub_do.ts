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
} from "./core";
import { SEED_MISSIONS, type SeedMission } from "./generated/missions";
import { renderJoinTxt } from "./join_txt";
import type { Lean4Verifier, RustVerifier } from "./containers";

export interface HubEnv {
  HUB: DurableObjectNamespace<SunsteadHub>;
  LEAN4_VERIFIER: DurableObjectNamespace<Lean4Verifier>;
  RUST_VERIFIER: DurableObjectNamespace<RustVerifier>;
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
}

type ContributorRecord = {
  handle: string;
  display_name: string;
  github: string | null;
  created_at: number;
};

interface ContainerVerifyResponse {
  ok: boolean;
  score?: number | null;
  summary: string;
  spec_sha256: string;
  updated_files?: Record<string, string>;
  verify_ms: number;
}

const MAX_BODY_BYTES = 512 * 1024;
const MAX_ACTIVE_LEASES_PER_IDENTITY = 2;
const MAX_ACTIVE_LEASES_PER_IP = 3;
const RATE_LIMITS = {
  register_ip: { limit: 5, windowSec: 3600 },
  claim_id: { limit: 10, windowSec: 3600 },
  claim_ip: { limit: 15, windowSec: 3600 },
  submit_id: { limit: 20, windowSec: 3600 },
  submit_ip: { limit: 30, windowSec: 3600 },
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

function sanitizeGithub(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const cleaned = raw.trim().replace(/^@/, "").replace(/[^A-Za-z0-9-]/g, "").slice(0, 39);
  return cleaned || null;
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
  private missionLocks = new Map<string, Promise<void>>();

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
        created_at INTEGER NOT NULL
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

      CREATE INDEX IF NOT EXISTS idx_submissions_created
        ON submissions(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_rate_events_bucket_time
        ON rate_events(bucket, created_at);
    `);

    // Safe additive schema migrations for existing Durable Object SQLite instances.
    this.ensureColumn("tasks", "lease_ip", "TEXT");
    this.ensureColumn("submissions", "points", "INTEGER NOT NULL DEFAULT 0");
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
        this.ctx.storage.sql.exec("DELETE FROM bundle_cache WHERE mission_id = ?", seed.manifest.id);
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

  private checkAndRecordRateLimit(
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
    this.ctx.storage.sql.exec(
      "INSERT INTO rate_events (bucket, created_at) VALUES (?, ?)",
      bucket,
      now
    );
    return { allowed: true, retryAfterSec: 0 };
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
      verifier_kind: r.verifier_kind === "rust" ? "rust" : "lean4",
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
      verifier_kind: rows[0].verifier_kind === "rust" ? "rust" : "lean4",
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
          }>(
            `SELECT id, mission_id, task_id, contributor, accepted, score, points, summary,
                    patch_sha256, verify_ms, created_at
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
          }>(
            `SELECT id, mission_id, task_id, contributor, accepted, score, points, summary,
                    patch_sha256, verify_ms, created_at
             FROM submissions ORDER BY created_at DESC LIMIT ?`,
            limit
          )
          .toArray();

    return rows.map((r) => ({ ...r, accepted: r.accepted !== 0 }));
  }

  private insertSubmission(rec: SubmissionRecord): void {
    this.ctx.storage.sql.exec(
      `INSERT INTO submissions
       (id, mission_id, task_id, contributor, accepted, score, points, summary, patch_sha256, verify_ms, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
      rec.created_at
    );
  }

  private emit(ev: HubEvent): void {
    const frame = this.encoder.encode(
      `event: ${ev.kind}\ndata: ${JSON.stringify(ev)}\n\n`
    );
    for (const writer of Array.from(this.sseClients)) {
      writer.write(frame).catch(() => {
        this.sseClients.delete(writer);
      });
    }
  }

  private async withMissionLock<T>(missionId: string, fn: () => Promise<T>): Promise<T> {
    const prev = this.missionLocks.get(missionId) ?? Promise.resolve();
    let release!: () => void;
    const gate = new Promise<void>((r) => {
      release = r;
    });
    const chained = prev.then(() => gate);
    this.missionLocks.set(missionId, chained);
    await prev;
    try {
      return await fn();
    } finally {
      release();
      if (this.missionLocks.get(missionId) === chained) {
        this.missionLocks.delete(missionId);
      }
    }
  }

  private getVerifierStub(mission: SeedMission) {
    if (mission.verifier_kind === "rust") {
      return this.env.RUST_VERIFIER.getByName(`rust:${mission.manifest.id}`);
    }
    return this.env.LEAN4_VERIFIER.getByName(`lean4:${mission.manifest.id}`);
  }

  private computeLeaderboard(limit = 30) {
    // Count active hill-climb crowns (+150 bonus per active hillclimb record held)
    const hillclimbCrowns = new Map<string, number>();
    for (const m of this.listMissionsRows()) {
      if (m.manifest.mode !== "hillclimb") continue;
      for (const t of this.getTasks(m.manifest.id)) {
        if (t.status === "verified" && t.verified_by) {
          hillclimbCrowns.set(t.verified_by, (hillclimbCrowns.get(t.verified_by) ?? 0) + 1);
        }
      }
    }

    const rows = this.ctx.storage.sql
      .exec<{
        contributor: string;
        display_name: string | null;
        github: string | null;
        verified_tasks: number;
        accepted_submissions: number;
        total_submissions: number;
        base_points: number;
      }>(
        `SELECT
           s.contributor AS contributor,
           c.display_name AS display_name,
           c.github AS github,
           COUNT(DISTINCT CASE WHEN s.accepted = 1 THEN s.mission_id || ':' || s.task_id END) AS verified_tasks,
           SUM(CASE WHEN s.accepted = 1 THEN 1 ELSE 0 END) AS accepted_submissions,
           COUNT(*) AS total_submissions,
           SUM(CASE WHEN s.accepted = 1 THEN s.points ELSE 0 END) AS base_points
         FROM submissions s
         LEFT JOIN contributors c ON c.handle = s.contributor
         GROUP BY s.contributor`
      )
      .toArray();

    const enriched = rows.map((r) => {
      const active_records = hillclimbCrowns.get(r.contributor) ?? 0;
      const points = r.base_points + active_records * 150;
      return {
        contributor: r.contributor,
        display_name: r.display_name || r.contributor,
        github: r.github,
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
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
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

    if (method === "POST" && path === "/api/contributors/register") {
      return this.handleRegisterContributor(request);
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
          score_direction: m.manifest.score_direction ?? "maximize",
          spec_sha256: m.spec_sha256,
          verifier_image: m.manifest.verifier.image,
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
      const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
      const writer = writable.getWriter();
      this.sseClients.add(writer);
      writer.write(this.encoder.encode(": connected\n\n")).catch(() => {
        this.sseClients.delete(writer);
      });
      return new Response(readable, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    const bundleMatch = path.match(/^\/api\/missions\/([^/]+)\/bundle\.tar\.gz$/);
    if (method === "GET" && bundleMatch) {
      return this.handleBundle(decodeURIComponent(bundleMatch[1]));
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

    let body: { handle?: string; display_name?: string; github?: string };
    try {
      body = (await request.json()) as { handle?: string; display_name?: string; github?: string };
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

    const existing = this.ctx.storage.sql
      .exec<{ handle: string }>("SELECT handle FROM contributors WHERE handle = ?", handle)
      .toArray();
    if (existing.length > 0) {
      return jsonResp({ error: `handle '${handle}' is already claimed` }, 409);
    }

    const rl = this.checkAndRecordRateLimit(
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

    const displayName = sanitizeOptionalText(body.display_name, 64) || handle;
    const github = sanitizeGithub(body.github);
    const apiKey = generateApiKey();
    const tokenHash = await sha256Hex(apiKey);

    this.ctx.storage.sql.exec(
      `INSERT INTO contributors (handle, display_name, github, token_sha256, created_at)
       VALUES (?, ?, ?, ?, ?)`,
      handle,
      displayName,
      github,
      tokenHash,
      now
    );

    return jsonResp(
      {
        registered: true,
        handle,
        display_name: displayName,
        github,
        api_key: apiKey,
        note: "Save this api_key now—Sunstead stores only its SHA-256 hash and cannot recover it. Share it across all agents you run to aggregate credit under one identity.",
      },
      201
    );
  }

  private handleGetContributor(handle: string): Response {
    const profileRows = this.ctx.storage.sql
      .exec<ContributorRecord>(
        "SELECT handle, display_name, github, created_at FROM contributors WHERE handle = ?",
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

    return jsonResp({
      contributor: profileRows[0] ?? {
        handle,
        display_name: handle,
        github: null,
        created_at: null,
      },
      rank: rankIdx >= 0 ? rankIdx + 1 : null,
      stats: rankIdx >= 0 ? board[rankIdx] : { points: 0, verified_tasks: 0, active_records: 0 },
      recent_submissions: recent,
    });
  }

  private async handleBundle(missionId: string): Promise<Response> {
    const mission = this.getMissionRow(missionId);
    if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);

    const cached = this.ctx.storage.sql
      .exec<{ tarball: ArrayBuffer }>(
        "SELECT tarball FROM bundle_cache WHERE mission_id = ?",
        missionId
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

    const currentFiles = this.getMissionFiles(missionId);
    const stub = this.getVerifierStub(mission);
    const resp = await stub.fetch(
      new Request("http://verifier/bundle", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mission_id: missionId,
          frozen_paths: mission.manifest.frozen_paths,
          current_files: currentFiles,
        }),
      })
    );
    if (!resp.ok) {
      const errText = await resp.text();
      return jsonResp({ error: `bundle build failed: ${errText}` }, 502);
    }

    const bytes = await resp.arrayBuffer();
    this.ctx.storage.sql.exec(
      `INSERT INTO bundle_cache (mission_id, tarball, updated_at)
       VALUES (?, ?, ?)
       ON CONFLICT(mission_id) DO UPDATE SET tarball = excluded.tarball, updated_at = excluded.updated_at`,
      missionId,
      new Uint8Array(bytes),
      Math.floor(Date.now() / 1000)
    );

    return new Response(bytes, {
      headers: {
        "Content-Type": "application/gzip",
        "Content-Disposition": 'attachment; filename="mission-bundle.tar.gz"',
        "Access-Control-Allow-Origin": "*",
      },
    });
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

    const mission = this.getMissionRow(missionId);
    if (!mission) return jsonResp({ error: `unknown mission: ${missionId}` }, 404);

    const ip = clientIp(request);
    const now = Math.floor(Date.now() / 1000);

    // Rate-limit claims per identity & IP
    const rlId = this.checkAndRecordRateLimit(
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
    const rlIp = this.checkAndRecordRateLimit(
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

    return this.withMissionLock(missionId, async () => {
      const tasks = this.getTasks(missionId);
      const targetTask = tasks.find((t) => t.def.id === taskId);
      const isRenewal = targetTask?.active_lease?.contributor === contributor;

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

      const token = crypto.randomUUID();
      const duration = Number.isFinite(body.lease_seconds) ? Number(body.lease_seconds) : 1800;

      try {
        const outcome = applyClaim(
          mission.manifest.mode,
          tasks,
          taskId,
          contributor,
          token,
          now,
          duration
        );
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
      } catch (e) {
        return jsonResp({ error: e instanceof Error ? e.message : String(e) }, 409);
      }
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

    return this.withMissionLock(missionId, async () => {
      const tasks = this.getTasks(missionId);
      const task = tasks.find((t) => t.def.id === taskId);
      if (!task) return jsonResp({ error: `unknown task: ${taskId}` }, 404);
      if (!task.active_lease || task.active_lease.contributor !== contributor) {
        return jsonResp({ error: `you do not hold an active lease on '${taskId}'` }, 409);
      }

      const nextStatus: TaskStatus = task.status === "verified" ? "verified" : "open";
      this.ctx.storage.sql.exec(
        `UPDATE tasks
         SET status = ?, lease_contributor = NULL, lease_token = NULL, lease_expires_at = NULL, lease_ip = NULL
         WHERE mission_id = ? AND task_id = ?`,
        nextStatus,
        missionId,
        taskId
      );
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

    const ip = clientIp(request);
    const now = Math.floor(Date.now() / 1000);

    const rlId = this.checkAndRecordRateLimit(
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
    const rlIp = this.checkAndRecordRateLimit(
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

    const patchSha = await sha256Hex(patch);

    // Fast policy pre-check BEFORE waking any Cloudflare Container!
    try {
      validatePatch(patch, mission.manifest.frozen_paths, task.def.target_files);
    } catch (e) {
      const summary = `policy rejected: ${e instanceof Error ? e.message : String(e)}`;
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
      return jsonResp({ error: summary }, 422);
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

    return this.withMissionLock(missionId, async () => {
      const currentFiles = this.getMissionFiles(missionId);
      const stub = this.getVerifierStub(mission);
      let cRes: ContainerVerifyResponse;
      try {
        const resp = await stub.fetch(
          new Request("http://verifier/verify", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              mission_id: missionId,
              task_id: taskId,
              patch,
              frozen_paths: mission.manifest.frozen_paths,
              target_files: task.def.target_files,
              current_files: currentFiles,
              timeout_sec: mission.manifest.verifier.timeout_sec ?? 90,
            }),
          })
        );
        cRes = (await resp.json()) as ContainerVerifyResponse;
      } catch (e) {
        return jsonResp(
          { error: `verifier container invocation failed: ${e instanceof Error ? e.message : String(e)}` },
          502
        );
      }

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
        });

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
        return jsonResp(
          {
            accepted: false,
            submission_id: subId,
            error: reason,
            verify_ms: verifyMs,
          },
          422
        );
      }
    });
  }
}
