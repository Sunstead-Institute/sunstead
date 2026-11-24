use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MissionMode {
    /// Binary completion DAG: tasks transition Open/Leased -> Verified once.
    Dag,
    /// Scalar hill-climbing: verified submissions compete to strictly beat `best_score`.
    Hillclimb,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ScoreDirection {
    Maximize,
    Minimize,
}

impl Default for ScoreDirection {
    fn default() -> Self {
        Self::Maximize
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TaskStatus {
    Open,
    Leased,
    Verified,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VerifierConfig {
    pub image: String,
    pub command: Vec<String>,
    #[serde(default = "default_timeout_sec")]
    pub timeout_sec: u64,
    #[serde(default = "default_memory_mb")]
    pub memory_mb: u64,
}

fn default_timeout_sec() -> u64 {
    120
}

fn default_memory_mb() -> u64 {
    2048
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TaskDefinition {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub description: String,
    pub target_files: Vec<String>,
    #[serde(default)]
    pub depends_on: Vec<String>,
    #[serde(default)]
    pub baseline_score: Option<f64>,
}

/// The lean `sunstead.json` manifest placed at the root of any mission Git repo.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MissionManifest {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub description: String,
    pub tier: u8,
    pub mode: MissionMode,
    #[serde(default)]
    pub repo: String,
    pub frozen_paths: Vec<String>,
    pub verifier: VerifierConfig,
    #[serde(default)]
    pub score_direction: ScoreDirection,
    pub tasks: Vec<TaskDefinition>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Lease {
    pub task_id: String,
    pub contributor: String,
    pub lease_token: String,
    pub expires_at_unix: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TaskState {
    pub def: TaskDefinition,
    pub status: TaskStatus,
    pub best_score: Option<f64>,
    pub verified_by: Option<String>,
    pub active_lease: Option<Lease>,
    pub attempts: u64,
}

impl TaskState {
    pub fn from_def(def: TaskDefinition) -> Self {
        let baseline = def.baseline_score;
        Self {
            def,
            status: TaskStatus::Open,
            best_score: baseline,
            verified_by: None,
            active_lease: None,
            attempts: 0,
        }
    }
}

/// Strict output contract emitted by `./verify <task_id>` and bound to `spec_sha256` by the Hub.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Verdict {
    pub ok: bool,
    #[serde(default)]
    pub score: Option<f64>,
    #[serde(default)]
    pub summary: String,
    /// Computed by the Hub over all `frozen_paths` before & after verification.
    #[serde(default)]
    pub spec_sha256: String,
}
