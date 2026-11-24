use anyhow::{Context, Result};
use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Mutex;
use sunstead_core::{Lease, MissionManifest, TaskState, TaskStatus};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredMission {
    pub manifest: MissionManifest,
    pub spec_sha256: String,
    pub repo_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubmissionRecord {
    pub id: String,
    pub mission_id: String,
    pub task_id: String,
    pub contributor: String,
    pub accepted: bool,
    pub score: Option<f64>,
    pub summary: String,
    pub patch_sha256: String,
    pub verify_ms: u64,
    pub created_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LeaderboardEntry {
    pub contributor: String,
    pub verified_tasks: u64,
    pub accepted_submissions: u64,
    pub total_submissions: u64,
}

pub struct Database {
    conn: Mutex<Connection>,
}

impl Database {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let conn = Connection::open(path).context("failed to open sqlite db")?;
        conn.execute_batch(
            "
            PRAGMA journal_mode = WAL;
            PRAGMA foreign_keys = ON;

            CREATE TABLE IF NOT EXISTS missions (
                id TEXT PRIMARY KEY,
                manifest_json TEXT NOT NULL,
                spec_sha256 TEXT NOT NULL,
                repo_dir TEXT NOT NULL,
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
                attempts INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (mission_id, task_id),
                FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS submissions (
                id TEXT PRIMARY KEY,
                mission_id TEXT NOT NULL,
                task_id TEXT NOT NULL,
                contributor TEXT NOT NULL,
                accepted INTEGER NOT NULL,
                score REAL,
                summary TEXT NOT NULL,
                patch_sha256 TEXT NOT NULL,
                verify_ms INTEGER NOT NULL,
                created_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_submissions_created
                ON submissions(created_at DESC);
            ",
        )?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    pub fn upsert_mission(
        &self,
        manifest: &MissionManifest,
        spec_sha256: &str,
        repo_dir: &str,
    ) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().timestamp();
        let manifest_json = serde_json::to_string(manifest)?;

        conn.execute(
            "INSERT INTO missions (id, manifest_json, spec_sha256, repo_dir, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(id) DO UPDATE SET
               manifest_json = excluded.manifest_json,
               spec_sha256 = excluded.spec_sha256,
               repo_dir = excluded.repo_dir",
            params![manifest.id, manifest_json, spec_sha256, repo_dir, now],
        )?;

        for task in &manifest.tasks {
            let def_json = serde_json::to_string(task)?;
            conn.execute(
                "INSERT INTO tasks (mission_id, task_id, def_json, status, best_score, attempts)
                 VALUES (?1, ?2, ?3, 'open', ?4, 0)
                 ON CONFLICT(mission_id, task_id) DO UPDATE SET
                   def_json = excluded.def_json",
                params![manifest.id, task.id, def_json, task.baseline_score],
            )?;
        }
        Ok(())
    }

    pub fn list_missions(&self) -> Result<Vec<StoredMission>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT manifest_json, spec_sha256, repo_dir FROM missions ORDER BY id ASC",
        )?;
        let rows = stmt.query_map([], |row| {
            let manifest_json: String = row.get(0)?;
            let spec_sha256: String = row.get(1)?;
            let repo_dir: String = row.get(2)?;
            Ok((manifest_json, spec_sha256, repo_dir))
        })?;

        let mut out = Vec::new();
        for item in rows {
            let (manifest_json, spec_sha256, repo_dir) = item?;
            let manifest: MissionManifest = serde_json::from_str(&manifest_json)?;
            out.push(StoredMission {
                manifest,
                spec_sha256,
                repo_dir,
            });
        }
        // Sort nicely by tier descending (Tier 3 daily wins, Tier 2 bounds, Tier 1 moonshot) then id.
        out.sort_by(|a, b| {
            b.manifest
                .tier
                .cmp(&a.manifest.tier)
                .then(a.manifest.id.cmp(&b.manifest.id))
        });
        Ok(out)
    }

    pub fn get_mission(&self, mission_id: &str) -> Result<Option<StoredMission>> {
        let conn = self.conn.lock().unwrap();
        let row: Option<(String, String, String)> = conn
            .query_row(
                "SELECT manifest_json, spec_sha256, repo_dir FROM missions WHERE id = ?1",
                params![mission_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?;

        match row {
            Some((manifest_json, spec_sha256, repo_dir)) => Ok(Some(StoredMission {
                manifest: serde_json::from_str(&manifest_json)?,
                spec_sha256,
                repo_dir,
            })),
            None => Ok(None),
        }
    }

    pub fn get_tasks(&self, mission_id: &str) -> Result<Vec<TaskState>> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now().timestamp();
        let mut stmt = conn.prepare(
            "SELECT def_json, status, best_score, verified_by,
                    lease_contributor, lease_token, lease_expires_at, attempts
             FROM tasks
             WHERE mission_id = ?1
             ORDER BY rowid ASC",
        )?;

        let rows = stmt.query_map(params![mission_id], |row| {
            let def_json: String = row.get(0)?;
            let status_str: String = row.get(1)?;
            let best_score: Option<f64> = row.get(2)?;
            let verified_by: Option<String> = row.get(3)?;
            let lease_contributor: Option<String> = row.get(4)?;
            let lease_token: Option<String> = row.get(5)?;
            let lease_expires_at: Option<i64> = row.get(6)?;
            let attempts: u64 = row.get::<_, i64>(7)? as u64;
            Ok((
                def_json,
                status_str,
                best_score,
                verified_by,
                lease_contributor,
                lease_token,
                lease_expires_at,
                attempts,
            ))
        })?;

        let mut tasks = Vec::new();
        for item in rows {
            let (
                def_json,
                status_str,
                best_score,
                verified_by,
                lease_contributor,
                lease_token,
                lease_expires_at,
                attempts,
            ) = item?;
            let def = serde_json::from_str(&def_json)?;

            let active_lease = match (lease_contributor, lease_token, lease_expires_at) {
                (Some(contributor), Some(lease_token), Some(expires_at_unix))
                    if expires_at_unix > now =>
                {
                    Some(Lease {
                        task_id: String::new(), // populated below
                        contributor,
                        lease_token,
                        expires_at_unix,
                    })
                }
                _ => None,
            };

            let mut status = match status_str.as_str() {
                "verified" => TaskStatus::Verified,
                "leased" => TaskStatus::Leased,
                _ => TaskStatus::Open,
            };
            // Expired lease automatically reverts Leased -> Open.
            if status == TaskStatus::Leased && active_lease.is_none() {
                status = TaskStatus::Open;
            }

            let mut state = TaskState {
                def,
                status,
                best_score,
                verified_by,
                active_lease,
                attempts,
            };
            if let Some(ref mut l) = state.active_lease {
                l.task_id = state.def.id.clone();
            }
            tasks.push(state);
        }
        Ok(tasks)
    }

    pub fn save_lease(
        &self,
        mission_id: &str,
        task_id: &str,
        lease: &Lease,
        status: TaskStatus,
    ) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let status_str = status_to_str(status);
        conn.execute(
            "UPDATE tasks
             SET status = ?1, lease_contributor = ?2, lease_token = ?3, lease_expires_at = ?4
             WHERE mission_id = ?5 AND task_id = ?6",
            params![
                status_str,
                lease.contributor,
                lease.lease_token,
                lease.expires_at_unix,
                mission_id,
                task_id
            ],
        )?;
        Ok(())
    }

    pub fn mark_verified(
        &self,
        mission_id: &str,
        task_id: &str,
        contributor: &str,
        new_best_score: Option<f64>,
    ) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE tasks
             SET status = 'verified',
                 best_score = ?1,
                 verified_by = ?2,
                 lease_contributor = NULL,
                 lease_token = NULL,
                 lease_expires_at = NULL,
                 attempts = attempts + 1
             WHERE mission_id = ?3 AND task_id = ?4",
            params![new_best_score, contributor, mission_id, task_id],
        )?;
        Ok(())
    }

    pub fn increment_attempts(&self, mission_id: &str, task_id: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE tasks SET attempts = attempts + 1 WHERE mission_id = ?1 AND task_id = ?2",
            params![mission_id, task_id],
        )?;
        Ok(())
    }

    pub fn insert_submission(&self, rec: &SubmissionRecord) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO submissions
             (id, mission_id, task_id, contributor, accepted, score, summary, patch_sha256, verify_ms, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                rec.id,
                rec.mission_id,
                rec.task_id,
                rec.contributor,
                if rec.accepted { 1 } else { 0 },
                rec.score,
                rec.summary,
                rec.patch_sha256,
                rec.verify_ms as i64,
                rec.created_at
            ],
        )?;
        Ok(())
    }

    pub fn recent_submissions(
        &self,
        mission_id: Option<&str>,
        limit: usize,
    ) -> Result<Vec<SubmissionRecord>> {
        let conn = self.conn.lock().unwrap();
        let mut out = Vec::new();
        if let Some(mid) = mission_id {
            let mut stmt = conn.prepare(
                "SELECT id, mission_id, task_id, contributor, accepted, score, summary, patch_sha256, verify_ms, created_at
                 FROM submissions
                 WHERE mission_id = ?1
                 ORDER BY created_at DESC
                 LIMIT ?2",
            )?;
            let rows = stmt.query_map(params![mid, limit as i64], map_submission_row)?;
            for r in rows {
                out.push(r?);
            }
        } else {
            let mut stmt = conn.prepare(
                "SELECT id, mission_id, task_id, contributor, accepted, score, summary, patch_sha256, verify_ms, created_at
                 FROM submissions
                 ORDER BY created_at DESC
                 LIMIT ?1",
            )?;
            let rows = stmt.query_map(params![limit as i64], map_submission_row)?;
            for r in rows {
                out.push(r?);
            }
        }
        Ok(out)
    }

    pub fn leaderboard(&self, limit: usize) -> Result<Vec<LeaderboardEntry>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT
                contributor,
                COUNT(DISTINCT CASE WHEN accepted = 1 THEN mission_id || ':' || task_id END) AS verified_tasks,
                SUM(CASE WHEN accepted = 1 THEN 1 ELSE 0 END) AS accepted_submissions,
                COUNT(*) AS total_submissions
             FROM submissions
             GROUP BY contributor
             ORDER BY verified_tasks DESC, accepted_submissions DESC, contributor ASC
             LIMIT ?1",
        )?;
        let rows = stmt.query_map(params![limit as i64], |r| {
            Ok(LeaderboardEntry {
                contributor: r.get(0)?,
                verified_tasks: r.get::<_, i64>(1)? as u64,
                accepted_submissions: r.get::<_, i64>(2)? as u64,
                total_submissions: r.get::<_, i64>(3)? as u64,
            })
        })?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r?);
        }
        Ok(out)
    }
}

fn map_submission_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<SubmissionRecord> {
    Ok(SubmissionRecord {
        id: r.get(0)?,
        mission_id: r.get(1)?,
        task_id: r.get(2)?,
        contributor: r.get(3)?,
        accepted: r.get::<_, i64>(4)? != 0,
        score: r.get(5)?,
        summary: r.get(6)?,
        patch_sha256: r.get(7)?,
        verify_ms: r.get::<_, i64>(8)? as u64,
        created_at: r.get(9)?,
    })
}

fn status_to_str(s: TaskStatus) -> &'static str {
    match s {
        TaskStatus::Open => "open",
        TaskStatus::Leased => "leased",
        TaskStatus::Verified => "verified",
    }
}
