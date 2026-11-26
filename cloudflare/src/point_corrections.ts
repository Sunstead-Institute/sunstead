/** Committed point batches are applied on Hub startup, never through an API write. */
export interface PointCorrectionEntry {
  submission_id: string;
  contributor: string;
  original_points: number;
  replayed_points: number;
  delta: number;
  reason: string;
}

export interface PointCorrectionBatch {
  batch_id: string;
  approved_by: string;
  approved_at: string;
  references: Record<string, string>;
  scoring_rule_version: string;
  input_snapshot_sha256: string;
  reverses_batch_id?: string;
  entries: PointCorrectionEntry[];
}

export type CorrectionStatus =
  | { batch_id: string; status: "applied" }
  | { batch_id: string; status: "error"; error: string };

export function initPointCorrections(sql: SqlStorage): void {
  sql.exec(`
    CREATE TABLE IF NOT EXISTS point_correction_batches (
      batch_id TEXT PRIMARY KEY,
      metadata_json TEXT NOT NULL,
      reverses_batch_id TEXT UNIQUE REFERENCES point_correction_batches(batch_id),
      applied_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS point_corrections (
      batch_id TEXT NOT NULL REFERENCES point_correction_batches(batch_id),
      submission_id TEXT NOT NULL REFERENCES submissions(id),
      contributor TEXT NOT NULL,
      original_points INTEGER NOT NULL,
      replayed_points INTEGER NOT NULL,
      delta INTEGER NOT NULL,
      reason TEXT NOT NULL,
      UNIQUE(batch_id, submission_id)
    );
    CREATE INDEX IF NOT EXISTS idx_point_corrections_submission
      ON point_corrections(submission_id);
    CREATE VIEW IF NOT EXISTS scored_submissions AS
      SELECT c.*, c.points AS original_points, c.points + c.points_delta AS effective_points
      FROM (
        SELECT submissions.*, COALESCE((
          SELECT SUM(delta) FROM point_corrections WHERE submission_id = submissions.id
        ), 0) AS points_delta
        FROM submissions
      ) c;
  `);
}

function listEntries(sql: SqlStorage, batchId: string): PointCorrectionEntry[] {
  return sql.exec<PointCorrectionEntry & Record<string, SqlStorageValue>>(
    `SELECT submission_id, contributor, original_points, replayed_points, delta, reason
     FROM point_corrections WHERE batch_id = ? ORDER BY submission_id`, batchId
  ).toArray();
}

export function listPointCorrections(sql: SqlStorage) {
  return sql.exec<{ batch_id: string; metadata_json: string; applied_at: number }>(
    "SELECT batch_id, metadata_json, applied_at FROM point_correction_batches ORDER BY applied_at, batch_id"
  ).toArray().map(({ batch_id, metadata_json, applied_at }) => ({
    ...JSON.parse(metadata_json) as Omit<PointCorrectionBatch, "entries">,
    applied_at,
    entries: listEntries(sql, batch_id),
  }));
}

export function applyPointCorrections(
  storage: DurableObjectStorage,
  batches: readonly PointCorrectionBatch[],
): CorrectionStatus[] {
  const sql = storage.sql;
  return batches.map((batch) => {
    const { entries, ...meta } = batch;
    try {
      storage.transactionSync(() => {
        const metadataJson = JSON.stringify(meta);
        const existing = sql.exec<{ metadata_json: string }>(
          "SELECT metadata_json FROM point_correction_batches WHERE batch_id = ?", meta.batch_id
        ).toArray()[0];
        if (existing) {
          const saved = listEntries(sql, meta.batch_id);
          const byId = new Map(entries.map((entry) => [entry.submission_id, entry]));
          if (existing.metadata_json !== metadataJson || saved.length !== entries.length ||
              byId.size !== entries.length || saved.some((row) => {
                const entry = byId.get(row.submission_id);
                return !entry || Object.keys(row).some((key) =>
                  row[key as keyof PointCorrectionEntry] !== entry[key as keyof PointCorrectionEntry]);
              })) {
            throw new Error("batch ID already applied with different contents");
          }
          return;
        }

        if (!meta.batch_id || !meta.approved_by || !Number.isFinite(Date.parse(meta.approved_at)) ||
            !meta.scoring_rule_version || !/^[a-f0-9]{64}$/.test(meta.input_snapshot_sha256) ||
            !meta.references || Object.keys(meta.references).length === 0 || entries.length === 0) {
          throw new Error("invalid correction batch metadata or empty batch");
        }
        const reversalId = meta.reverses_batch_id;
        const reversed = new Map<string, PointCorrectionEntry>();
        if (reversalId !== undefined) {
          const target = sql.exec<{ reverses_batch_id: string | null }>(
            "SELECT reverses_batch_id FROM point_correction_batches WHERE batch_id = ?", reversalId
          ).toArray()[0];
          if (!target || target.reverses_batch_id !== null) {
            throw new Error("compensation must reference an applied original batch");
          }
          if (sql.exec("SELECT batch_id FROM point_correction_batches WHERE reverses_batch_id = ?", reversalId).toArray().length) {
            throw new Error("original batch already has a compensation");
          }
          for (const row of listEntries(sql, reversalId)) reversed.set(row.submission_id, row);
          if (reversed.size !== entries.length) throw new Error("compensation must cover the original batch");
        }

        const seen = new Set<string>();
        for (const entry of entries) {
          const { submission_id, contributor, original_points, replayed_points, delta, reason } = entry;
          if (!submission_id || seen.has(submission_id) || !contributor || !reason?.trim() ||
              ![original_points, replayed_points, delta].every(Number.isSafeInteger) ||
              original_points < 0 || replayed_points < 0) {
            throw new Error(`invalid or duplicate correction entry: ${submission_id}`);
          }
          seen.add(submission_id);
          const row = sql.exec<{
            accepted: number; status: string; contributor: string;
            original_points: number; effective_points: number;
          }>(
            `SELECT accepted, status, contributor, original_points, effective_points
             FROM scored_submissions WHERE id = ?`, submission_id
          ).toArray()[0];
          if (!row) throw new Error(`submission not found: ${submission_id}`);
          if (row.accepted !== 1 || row.status !== "accepted") throw new Error(`submission not accepted: ${submission_id}`);
          if (row.contributor !== contributor) throw new Error(`contributor mismatch: ${submission_id}`);
          if (row.original_points !== original_points) throw new Error(`original points mismatch: ${submission_id}`);

          if (reversalId !== undefined) {
            const prior = reversed.get(submission_id);
            if (!prior || delta !== -prior.delta || replayed_points !== original_points) {
              throw new Error(`compensation not the inverse of original entry: ${submission_id}`);
            }
          } else if (original_points + delta !== replayed_points) {
            throw new Error(`replayed points and delta disagree: ${submission_id}`);
          }
          if (row.effective_points + delta !== replayed_points) {
            throw new Error(`effective points conflict with prior corrections: ${submission_id}`);
          }
        }

        sql.exec(
          "INSERT INTO point_correction_batches (batch_id, metadata_json, reverses_batch_id, applied_at) VALUES (?, ?, ?, ?)",
          meta.batch_id, metadataJson, reversalId ?? null, Math.floor(Date.now() / 1000)
        );
        for (const e of entries) {
          sql.exec(
            `INSERT INTO point_corrections
               (batch_id, submission_id, contributor, original_points, replayed_points, delta, reason)
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
            meta.batch_id, e.submission_id, e.contributor, e.original_points, e.replayed_points, e.delta, e.reason,
          );
        }
      });
      return { batch_id: meta.batch_id, status: "applied" };
    } catch (err) {
      return { batch_id: meta.batch_id, status: "error", error: err instanceof Error ? err.message : String(err) };
    }
  });
}
