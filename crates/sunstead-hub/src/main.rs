mod api;
mod db;
mod join_txt;
mod verifier;

use anyhow::{Context, Result};
use api::{router, AppState};
use db::Database;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use sunstead_core::{validate_dag, MissionManifest};
use tokio::sync::{broadcast, Mutex, Semaphore};
use tracing::info;
use verifier::{compute_spec_sha256, ensure_mission_repo};

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "sunstead_hub=info,tower_http=info".into()),
        )
        .init();

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8080);
    let missions_dir = PathBuf::from(
        std::env::var("SUNSTEAD_MISSIONS_DIR").unwrap_or_else(|_| "./missions".into()),
    );
    let data_dir = PathBuf::from(
        std::env::var("SUNSTEAD_DATA_DIR").unwrap_or_else(|_| "./data".into()),
    );
    let web_dir = PathBuf::from(
        std::env::var("SUNSTEAD_WEB_DIR").unwrap_or_else(|_| "./web".into()),
    );
    let public_base_url = std::env::var("SUNSTEAD_PUBLIC_URL")
        .ok()
        .filter(|s| !s.trim().is_empty());
    let docker_runtime = std::env::var("SUNSTEAD_DOCKER_RUNTIME")
        .ok()
        .filter(|s| !s.trim().is_empty());
    let max_concurrent_verifiers: usize = std::env::var("SUNSTEAD_MAX_CONCURRENT_VERIFIERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(4)
        .clamp(1, 32);

    std::fs::create_dir_all(&data_dir)?;
    let db = Database::open(&data_dir.join("sunstead.sqlite"))?;

    bootstrap_missions(&missions_dir, &data_dir.join("repos"), &db).await?;

    let (events_tx, _) = broadcast::channel(256);
    let state = Arc::new(AppState {
        db,
        public_base_url,
        docker_runtime: docker_runtime.clone(),
        verifier_slots: Arc::new(Semaphore::new(max_concurrent_verifiers)),
        events_tx,
        mission_locks: Mutex::new(HashMap::new()),
    });

    let app = router(state, web_dir);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!(
        %addr,
        max_concurrent_verifiers,
        docker_runtime = ?docker_runtime,
        "Sunstead Hub listening — agents can onboard at /join.txt"
    );

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    info!("Sunstead Hub shut down cleanly");
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };

    #[cfg(unix)]
    let terminate = async {
        if let Ok(mut sig) =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            sig.recv().await;
        }
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}

async fn bootstrap_missions(
    missions_dir: &Path,
    repos_root: &Path,
    db: &Database,
) -> Result<()> {
    if !missions_dir.exists() {
        return Ok(());
    }
    std::fs::create_dir_all(repos_root)?;

    let mut entries: Vec<PathBuf> = std::fs::read_dir(missions_dir)?
        .filter_map(|e| e.ok().map(|d| d.path()))
        .filter(|p| p.is_dir() && p.join("sunstead.json").exists())
        .collect();
    entries.sort();

    for seed_dir in entries {
        let manifest_path = seed_dir.join("sunstead.json");
        let raw = std::fs::read_to_string(&manifest_path)
            .with_context(|| format!("reading {}", manifest_path.display()))?;
        let manifest: MissionManifest = serde_json::from_str(&raw)
            .with_context(|| format!("parsing {}", manifest_path.display()))?;

        validate_dag(&manifest.tasks)
            .with_context(|| format!("invalid DAG in mission '{}'", manifest.id))?;

        let live_repo_dir = repos_root.join(&manifest.id);
        ensure_mission_repo(&seed_dir, &live_repo_dir).await?;

        let spec_sha256 = compute_spec_sha256(&live_repo_dir, &manifest.frozen_paths)?;
        db.upsert_mission(
            &manifest,
            &spec_sha256,
            live_repo_dir.to_str().context("non-utf8 repo path")?,
        )?;
        info!(
            mission_id = %manifest.id,
            tier = manifest.tier,
            tasks = manifest.tasks.len(),
            spec_sha256 = %spec_sha256,
            "loaded mission"
        );
    }

    Ok(())
}
