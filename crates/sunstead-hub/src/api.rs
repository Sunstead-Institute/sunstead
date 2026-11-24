use crate::db::{Database, StoredMission, SubmissionRecord};
use crate::join_txt::render_join_txt;
use crate::verifier::{
    build_mission_tarball, check_docker_available, merge_verified_patch, run_hermetic_verification,
};
use axum::{
    extract::{DefaultBodyLimit, Path as AxumPath, Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{
        sse::{Event, KeepAlive, Sse},
        IntoResponse, Response,
    },
    routing::{get, post},
    Json, Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::convert::Infallible;
use std::path::PathBuf;
use std::sync::Arc;
use sunstead_core::{
    apply_claim, apply_verdict, compute_frontier, is_task_unlocked, validate_patch, MissionMode,
    TaskState, TaskStatus,
};
use tokio::sync::{broadcast, Mutex, Semaphore};
use tokio_stream::{wrappers::BroadcastStream, StreamExt};
use tower_http::cors::CorsLayer;
use tower_http::services::ServeDir;
use tracing::{error, info};
use uuid::Uuid;

const MAX_BODY_BYTES: usize = 512 * 1024; // 512 KB max request payload

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HubEvent {
    pub kind: String,
    pub mission_id: String,
    pub task_id: Option<String>,
    pub contributor: Option<String>,
    pub accepted: Option<bool>,
    pub score: Option<f64>,
    pub summary: String,
    pub timestamp: i64,
}

pub struct AppState {
    pub db: Database,
    pub public_base_url: Option<String>,
    pub docker_runtime: Option<String>,
    pub verifier_slots: Arc<Semaphore>,
    pub events_tx: broadcast::Sender<HubEvent>,
    pub mission_locks: Mutex<HashMap<String, Arc<Mutex<()>>>>,
}

impl AppState {
    async fn mission_lock(&self, mission_id: &str) -> Arc<Mutex<()>> {
        let mut guard = self.mission_locks.lock().await;
        guard
            .entry(mission_id.to_string())
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    }

    fn emit(&self, event: HubEvent) {
        let _ = self.events_tx.send(event);
    }
}

pub fn router(state: Arc<AppState>, web_dir: PathBuf) -> Router {
    Router::new()
        .route("/join.txt", get(get_join_txt))
        .route("/api/health", get(get_health))
        .route("/api/missions", get(list_missions))
        .route("/api/missions/:mission_id", get(get_mission_detail))
        .route(
            "/api/missions/:mission_id/bundle.tar.gz",
            get(get_mission_bundle),
        )
        .route(
            "/api/missions/:mission_id/tasks/:task_id/claim",
            post(claim_task),
        )
        .route(
            "/api/missions/:mission_id/tasks/:task_id/submit",
            post(submit_patch),
        )
        .route("/api/submissions", get(list_submissions))
        .route("/api/leaderboard", get(get_leaderboard))
        .route("/api/events", get(sse_events))
        .fallback_service(ServeDir::new(web_dir))
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .layer(CorsLayer::permissive())
        .with_state(state)
}

#[derive(Serialize)]
struct ErrorBody {
    error: String,
}

fn json_err(status: StatusCode, msg: impl Into<String>) -> Response {
    (status, Json(ErrorBody { error: msg.into() })).into_response()
}

fn infer_base_url(state: &AppState, headers: &HeaderMap) -> String {
    if let Some(ref configured) = state.public_base_url {
        return configured.trim_end_matches('/').to_string();
    }
    let host = headers
        .get(header::HOST)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("localhost:8080");
    let proto = headers
        .get("x-forwarded-proto")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("http");
    format!("{proto}://{host}")
}

async fn get_join_txt(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let missions = match state.db.list_missions() {
        Ok(m) => m,
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };
    let mut pairs = Vec::new();
    for m in missions {
        let tasks = state.db.get_tasks(&m.manifest.id).unwrap_or_default();
        pairs.push((m, tasks));
    }
    let base = infer_base_url(&state, &headers);
    let body = render_join_txt(&base, &pairs);
    (
        [(header::CONTENT_TYPE, "text/plain; charset=utf-8")],
        body,
    )
        .into_response()
}

async fn get_health() -> impl IntoResponse {
    let docker_ok = check_docker_available().await;
    Json(serde_json::json!({
        "ok": true,
        "service": "sunstead-hub",
        "docker_verifier_ready": docker_ok,
        "timestamp": Utc::now().timestamp()
    }))
}

#[derive(Serialize)]
struct MissionSummary {
    id: String,
    title: String,
    description: String,
    tier: u8,
    mode: MissionMode,
    score_direction: sunstead_core::ScoreDirection,
    spec_sha256: String,
    verifier_image: String,
    frozen_paths: Vec<String>,
    total_tasks: usize,
    verified_tasks: usize,
    leased_tasks: usize,
    frontier_task_ids: Vec<String>,
}

async fn list_missions(State(state): State<Arc<AppState>>) -> Response {
    let missions = match state.db.list_missions() {
        Ok(m) => m,
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };

    let mut summaries = Vec::new();
    for m in missions {
        let tasks = state.db.get_tasks(&m.manifest.id).unwrap_or_default();
        let verified_tasks = tasks
            .iter()
            .filter(|t| t.status == TaskStatus::Verified)
            .count();
        let leased_tasks = tasks
            .iter()
            .filter(|t| t.active_lease.is_some())
            .count();
        let frontier_task_ids = compute_frontier(m.manifest.mode, &tasks);

        summaries.push(MissionSummary {
            id: m.manifest.id,
            title: m.manifest.title,
            description: m.manifest.description,
            tier: m.manifest.tier,
            mode: m.manifest.mode,
            score_direction: m.manifest.score_direction,
            spec_sha256: m.spec_sha256,
            verifier_image: m.manifest.verifier.image,
            frozen_paths: m.manifest.frozen_paths,
            total_tasks: tasks.len(),
            verified_tasks,
            leased_tasks,
            frontier_task_ids,
        });
    }

    Json(serde_json::json!({ "missions": summaries })).into_response()
}

#[derive(Serialize)]
struct TaskView {
    #[serde(flatten)]
    state: TaskState,
    unlocked: bool,
}

#[derive(Serialize)]
struct MissionDetailResponse {
    mission: StoredMission,
    frontier: Vec<String>,
    tasks: Vec<TaskView>,
    recent_submissions: Vec<SubmissionRecord>,
}

async fn get_mission_detail(
    State(state): State<Arc<AppState>>,
    AxumPath(mission_id): AxumPath<String>,
) -> Response {
    let mission = match state.db.get_mission(&mission_id) {
        Ok(Some(m)) => m,
        Ok(None) => return json_err(StatusCode::NOT_FOUND, format!("unknown mission: {mission_id}")),
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };
    let tasks = match state.db.get_tasks(&mission_id) {
        Ok(t) => t,
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };
    let frontier = compute_frontier(mission.manifest.mode, &tasks);
    let task_views: Vec<TaskView> = tasks
        .iter()
        .map(|t| TaskView {
            unlocked: is_task_unlocked(t, &tasks),
            state: t.clone(),
        })
        .collect();
    let recent_submissions = state
        .db
        .recent_submissions(Some(&mission_id), 25)
        .unwrap_or_default();

    Json(MissionDetailResponse {
        mission,
        frontier,
        tasks: task_views,
        recent_submissions,
    })
    .into_response()
}

async fn get_mission_bundle(
    State(state): State<Arc<AppState>>,
    AxumPath(mission_id): AxumPath<String>,
) -> Response {
    let mission = match state.db.get_mission(&mission_id) {
        Ok(Some(m)) => m,
        Ok(None) => return json_err(StatusCode::NOT_FOUND, format!("unknown mission: {mission_id}")),
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };
    let lock = state.mission_lock(&mission_id).await;
    let _guard = lock.lock().await;

    let repo_dir = PathBuf::from(&mission.repo_dir);
    match build_mission_tarball(&repo_dir) {
        Ok(bytes) => (
            [
                (header::CONTENT_TYPE, "application/gzip"),
                (
                    header::CONTENT_DISPOSITION,
                    "attachment; filename=\"mission-bundle.tar.gz\"",
                ),
            ],
            bytes,
        )
            .into_response(),
        Err(e) => json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

#[derive(Deserialize)]
struct ClaimRequest {
    contributor: String,
    #[serde(default = "default_lease_sec")]
    lease_seconds: i64,
}

fn default_lease_sec() -> i64 {
    1800
}

async fn claim_task(
    State(state): State<Arc<AppState>>,
    AxumPath((mission_id, task_id)): AxumPath<(String, String)>,
    Json(req): Json<ClaimRequest>,
) -> Response {
    let contributor = sanitize_contributor(&req.contributor);
    if contributor.is_empty() {
        return json_err(StatusCode::BAD_REQUEST, "contributor handle is required");
    }

    let mission = match state.db.get_mission(&mission_id) {
        Ok(Some(m)) => m,
        Ok(None) => return json_err(StatusCode::NOT_FOUND, format!("unknown mission: {mission_id}")),
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };

    let lock = state.mission_lock(&mission_id).await;
    let _guard = lock.lock().await;

    let tasks = match state.db.get_tasks(&mission_id) {
        Ok(t) => t,
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };

    let now = Utc::now().timestamp();
    let token = Uuid::new_v4().to_string();
    let duration = req.lease_seconds.clamp(60, 3600);

    match apply_claim(
        mission.manifest.mode,
        &tasks,
        &task_id,
        &contributor,
        &token,
        now,
        duration,
    ) {
        Ok(outcome) => {
            if let Err(e) =
                state
                    .db
                    .save_lease(&mission_id, &task_id, &outcome.lease, outcome.updated_status)
            {
                return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
            }
            state.emit(HubEvent {
                kind: "lease_claimed".into(),
                mission_id: mission_id.clone(),
                task_id: Some(task_id.clone()),
                contributor: Some(contributor.clone()),
                accepted: None,
                score: None,
                summary: format!("{contributor} claimed {task_id}"),
                timestamp: now,
            });
            Json(serde_json::json!({
                "claimed": true,
                "lease": outcome.lease,
                "bundle_url": format!("/api/missions/{mission_id}/bundle.tar.gz")
            }))
            .into_response()
        }
        Err(e) => json_err(StatusCode::CONFLICT, e.to_string()),
    }
}

#[derive(Deserialize)]
struct SubmitRequest {
    contributor: String,
    patch: String,
}

async fn submit_patch(
    State(state): State<Arc<AppState>>,
    AxumPath((mission_id, task_id)): AxumPath<(String, String)>,
    Json(req): Json<SubmitRequest>,
) -> Response {
    let contributor = sanitize_contributor(&req.contributor);
    if contributor.is_empty() {
        return json_err(StatusCode::BAD_REQUEST, "contributor handle is required");
    }

    let mission = match state.db.get_mission(&mission_id) {
        Ok(Some(m)) => m,
        Ok(None) => return json_err(StatusCode::NOT_FOUND, format!("unknown mission: {mission_id}")),
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };

    let tasks = match state.db.get_tasks(&mission_id) {
        Ok(t) => t,
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };
    let task = match tasks.iter().find(|t| t.def.id == task_id) {
        Some(t) => t.clone(),
        None => return json_err(StatusCode::NOT_FOUND, format!("unknown task: {task_id}")),
    };

    let patch_sha256 = format!(
        "sha256:{}",
        hex::encode(Sha256::digest(req.patch.as_bytes()))
    );
    let now = Utc::now().timestamp();

    // Fast policy pre-check BEFORE touching Docker!
    if let Err(policy_err) = validate_patch(
        &req.patch,
        &mission.manifest.frozen_paths,
        &task.def.target_files,
    ) {
        let summary = format!("policy rejected: {policy_err}");
        let rec = SubmissionRecord {
            id: Uuid::new_v4().to_string(),
            mission_id: mission_id.clone(),
            task_id: task_id.clone(),
            contributor: contributor.clone(),
            accepted: false,
            score: None,
            summary: summary.clone(),
            patch_sha256,
            verify_ms: 0,
            created_at: now,
        };
        let _ = state.db.increment_attempts(&mission_id, &task_id);
        let _ = state.db.insert_submission(&rec);
        state.emit(HubEvent {
            kind: "submission_rejected".into(),
            mission_id,
            task_id: Some(task_id),
            contributor: Some(contributor),
            accepted: Some(false),
            score: None,
            summary: summary.clone(),
            timestamp: now,
        });
        return json_err(StatusCode::UNPROCESSABLE_ENTITY, summary);
    }

    state.emit(HubEvent {
        kind: "verification_started".into(),
        mission_id: mission_id.clone(),
        task_id: Some(task_id.clone()),
        contributor: Some(contributor.clone()),
        accepted: None,
        score: None,
        summary: format!("Verifying patch from {contributor} in networkless sandbox..."),
        timestamp: now,
    });

    // Acquire a global verifier concurrency slot so bursty submissions cannot OOM the host.
    let _slot = match state.verifier_slots.clone().acquire_owned().await {
        Ok(permit) => permit,
        Err(_) => {
            return json_err(
                StatusCode::SERVICE_UNAVAILABLE,
                "verifier pool is shutting down",
            )
        }
    };

    // Serialize verification + merge per mission so concurrent patches apply cleanly against HEAD.
    let lock = state.mission_lock(&mission_id).await;
    let _guard = lock.lock().await;

    let live_repo = PathBuf::from(&mission.repo_dir);
    let (verdict, verify_ms) = match run_hermetic_verification(
        &live_repo,
        &mission.manifest,
        &task_id,
        &task.def.target_files,
        &req.patch,
        state.docker_runtime.as_deref(),
    )
    .await
    {
        Ok(res) => res,
        Err(e) => {
            error!(error = %e, "hermetic verifier runner error");
            return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
        }
    };

    let latest_tasks = match state.db.get_tasks(&mission_id) {
        Ok(t) => t,
        Err(e) => return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };

    let finished_at = Utc::now().timestamp();
    match apply_verdict(
        mission.manifest.mode,
        mission.manifest.score_direction,
        &mission.manifest.frozen_paths,
        &mission.spec_sha256,
        &latest_tasks,
        &task_id,
        &req.patch,
        &verdict,
    ) {
        Ok(outcome) => {
            if let Err(e) = merge_verified_patch(
                &live_repo,
                &req.patch,
                &contributor,
                &task_id,
                &verdict.summary,
            )
            .await
            {
                return json_err(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("verified patch failed to merge: {e}"),
                );
            }

            if let Err(e) = state.db.mark_verified(
                &mission_id,
                &task_id,
                &contributor,
                outcome.new_best_score,
            ) {
                return json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string());
            }

            let rec = SubmissionRecord {
                id: Uuid::new_v4().to_string(),
                mission_id: mission_id.clone(),
                task_id: task_id.clone(),
                contributor: contributor.clone(),
                accepted: true,
                score: outcome.new_best_score,
                summary: verdict.summary.clone(),
                patch_sha256,
                verify_ms,
                created_at: finished_at,
            };
            let _ = state.db.insert_submission(&rec);

            info!(
                mission = %mission_id,
                task = %task_id,
                contributor = %contributor,
                score = ?outcome.new_best_score,
                verify_ms,
                "submission accepted and merged"
            );

            state.emit(HubEvent {
                kind: "submission_accepted".into(),
                mission_id: mission_id.clone(),
                task_id: Some(task_id.clone()),
                contributor: Some(contributor.clone()),
                accepted: Some(true),
                score: outcome.new_best_score,
                summary: verdict.summary.clone(),
                timestamp: finished_at,
            });

            Json(serde_json::json!({
                "accepted": true,
                "submission_id": rec.id,
                "task_id": task_id,
                "score": outcome.new_best_score,
                "unlocked_dependents": outcome.unlocked_dependents,
                "verify_ms": verify_ms,
                "summary": verdict.summary
            }))
            .into_response()
        }
        Err(err) => {
            let reason = err.to_string();
            let rec = SubmissionRecord {
                id: Uuid::new_v4().to_string(),
                mission_id: mission_id.clone(),
                task_id: task_id.clone(),
                contributor: contributor.clone(),
                accepted: false,
                score: verdict.score,
                summary: reason.clone(),
                patch_sha256,
                verify_ms,
                created_at: finished_at,
            };
            let _ = state.db.increment_attempts(&mission_id, &task_id);
            let _ = state.db.insert_submission(&rec);

            state.emit(HubEvent {
                kind: "submission_rejected".into(),
                mission_id,
                task_id: Some(task_id),
                contributor: Some(contributor),
                accepted: Some(false),
                score: verdict.score,
                summary: reason.clone(),
                timestamp: finished_at,
            });

            (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(serde_json::json!({
                    "accepted": false,
                    "submission_id": rec.id,
                    "error": reason,
                    "verify_ms": verify_ms
                })),
            )
                .into_response()
        }
    }
}

#[derive(Deserialize)]
struct SubmissionsQuery {
    mission_id: Option<String>,
    limit: Option<usize>,
}

async fn list_submissions(
    State(state): State<Arc<AppState>>,
    Query(q): Query<SubmissionsQuery>,
) -> Response {
    let limit = q.limit.unwrap_or(40).clamp(1, 200);
    match state.db.recent_submissions(q.mission_id.as_deref(), limit) {
        Ok(items) => Json(serde_json::json!({ "submissions": items })).into_response(),
        Err(e) => json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

async fn get_leaderboard(State(state): State<Arc<AppState>>) -> Response {
    match state.db.leaderboard(30) {
        Ok(entries) => Json(serde_json::json!({ "leaderboard": entries })).into_response(),
        Err(e) => json_err(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

async fn sse_events(
    State(state): State<Arc<AppState>>,
) -> Sse<impl tokio_stream::Stream<Item = Result<Event, Infallible>>> {
    let rx = state.events_tx.subscribe();
    let stream = BroadcastStream::new(rx).filter_map(|msg| match msg {
        Ok(ev) => serde_json::to_string(&ev)
            .ok()
            .map(|data| Ok(Event::default().event(ev.kind).data(data))),
        Err(_) => None,
    });
    Sse::new(stream).keep_alive(KeepAlive::default())
}

fn sanitize_contributor(raw: &str) -> String {
    raw.trim()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_' || *c == '.')
        .take(48)
        .collect()
}
