use anyhow::{anyhow, Context, Result};
use flate2::{write::GzEncoder, Compression};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::{Duration, Instant};
use sunstead_core::{glob_matches, validate_touched_paths, MissionManifest, Verdict};
use tempfile::TempDir;
use tokio::process::Command;
use tracing::{info, warn};
use walkdir::WalkDir;

/// Deterministically compute `sha256:<hex>` over all files matching `frozen_paths`.
pub fn compute_spec_sha256(repo_dir: &Path, frozen_paths: &[String]) -> Result<String> {
    let mut matched: BTreeMap<String, PathBuf> = BTreeMap::new();

    for entry in WalkDir::new(repo_dir)
        .into_iter()
        .filter_entry(|e| e.file_name() != ".git" && e.file_name() != "target" && e.file_name() != ".lake")
    {
        let entry = entry?;
        if !entry.file_type().is_file() {
            continue;
        }
        let rel = entry
            .path()
            .strip_prefix(repo_dir)?
            .to_string_lossy()
            .replace('\\', "/");
        if frozen_paths.iter().any(|pat| glob_matches(pat, &rel)) {
            matched.insert(rel, entry.path().to_path_buf());
        }
    }

    let mut hasher = Sha256::new();
    for (rel, abs) in matched {
        let bytes = std::fs::read(&abs)
            .with_context(|| format!("reading frozen file {}", abs.display()))?;
        hasher.update(rel.as_bytes());
        hasher.update(b"\0");
        hasher.update((bytes.len() as u64).to_le_bytes());
        hasher.update(b"\0");
        hasher.update(&bytes);
        hasher.update(b"\n");
    }

    Ok(format!("sha256:{}", hex::encode(hasher.finalize())))
}

/// Recursively copy a directory (skipping `.git`, `target`, `.lake` build caches).
pub fn copy_clean_tree(src: &Path, dst: &Path) -> Result<()> {
    for entry in WalkDir::new(src).into_iter().filter_entry(|e| {
        let name = e.file_name().to_string_lossy();
        name != ".git" && name != "target" && name != ".lake"
    }) {
        let entry = entry?;
        let rel = entry.path().strip_prefix(src)?;
        if rel.as_os_str().is_empty() {
            continue;
        }
        let target = dst.join(rel);
        if entry.file_type().is_dir() {
            std::fs::create_dir_all(&target)?;
        } else if entry.file_type().is_file() {
            if let Some(parent) = target.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::copy(entry.path(), &target)?;
            #[cfg(unix)]
            {
                let perms = std::fs::metadata(entry.path())?.permissions();
                std::fs::set_permissions(&target, perms)?;
            }
        }
    }
    Ok(())
}

/// Ensure a live mission git repo exists under `live_repo_dir` initialized from `seed_dir`.
pub async fn ensure_mission_repo(seed_dir: &Path, live_repo_dir: &Path) -> Result<()> {
    if live_repo_dir.join(".git").exists() {
        return Ok(());
    }
    std::fs::create_dir_all(live_repo_dir)?;
    copy_clean_tree(seed_dir, live_repo_dir)?;

    run_git(live_repo_dir, &["init", "-b", "main"]).await?;
    run_git(live_repo_dir, &["config", "user.name", "Sunstead Hub"]).await?;
    run_git(live_repo_dir, &["config", "user.email", "hub@sunstead.org"]).await?;
    run_git(live_repo_dir, &["add", "."]).await?;
    run_git(live_repo_dir, &["commit", "-m", "Initial mission seed"]).await?;
    Ok(())
}

/// Package the current live mission repo (including `.git` so contributors can run `git diff` immediately!)
/// into an in-memory `.tar.gz` archive.
pub fn build_mission_tarball(repo_dir: &Path) -> Result<Vec<u8>> {
    let mut enc = GzEncoder::new(Vec::new(), Compression::default());
    {
        let mut tar = tar::Builder::new(&mut enc);
        for entry in WalkDir::new(repo_dir).into_iter().filter_entry(|e| {
            let name = e.file_name().to_string_lossy();
            name != "target" && name != ".lake"
        }) {
            let entry = entry?;
            let rel = entry.path().strip_prefix(repo_dir)?;
            if rel.as_os_str().is_empty() {
                continue;
            }
            if entry.file_type().is_file() {
                tar.append_path_with_name(entry.path(), rel)?;
            } else if entry.file_type().is_dir() {
                tar.append_dir(rel, entry.path())?;
            }
        }
        tar.finish()?;
    }
    Ok(enc.finish()?)
}

/// Apply an accepted, verified patch directly into the live mission repo and commit it.
pub async fn merge_verified_patch(
    live_repo_dir: &Path,
    patch: &str,
    contributor: &str,
    task_id: &str,
    summary: &str,
) -> Result<()> {
    let patch_file = TempDir::new()?;
    let patch_path = patch_file.path().join("submission.patch");
    std::fs::write(&patch_path, patch)?;

    run_git(
        live_repo_dir,
        &["apply", "--whitespace=nowarn", patch_path.to_str().unwrap()],
    )
    .await
    .context("git apply on live mission repo failed")?;

    run_git(live_repo_dir, &["add", "-A"]).await?;
    let msg = format!("Verify {task_id} by {contributor}\n\n{summary}");
    let author = format!("{contributor} <{contributor}@donors.sunstead.org>");
    run_git(
        live_repo_dir,
        &["commit", "--allow-empty", "--author", &author, "-m", &msg],
    )
    .await?;
    Ok(())
}

/// Run a donor's unified diff inside an isolated, networkless Docker container using `docker create` + `docker cp`.
pub async fn run_hermetic_verification(
    live_repo_dir: &Path,
    manifest: &MissionManifest,
    task_id: &str,
    target_files: &[String],
    patch: &str,
    docker_runtime: Option<&str>,
) -> Result<(Verdict, u64)> {
    let started = Instant::now();
    let staging = TempDir::new()?;
    let stage_dir = staging.path();

    // 1. Copy clean live repo into staging and initialize git for exact diff checking.
    copy_clean_tree(live_repo_dir, stage_dir)?;
    run_git(stage_dir, &["init", "-q"]).await?;
    run_git(stage_dir, &["config", "user.name", "Verifier"]).await?;
    run_git(stage_dir, &["config", "user.email", "verify@sunstead.org"]).await?;
    run_git(stage_dir, &["add", "."]).await?;
    run_git(stage_dir, &["commit", "-q", "-m", "base"]).await?;

    // 2. Apply submitted patch in staging.
    let patch_path = stage_dir.join(".sunstead_incoming.patch");
    std::fs::write(&patch_path, patch)?;
    let apply_out = Command::new("git")
        .current_dir(stage_dir)
        .args(["apply", "--whitespace=nowarn", ".sunstead_incoming.patch"])
        .output()
        .await?;
    let _ = std::fs::remove_file(&patch_path);

    if !apply_out.status.success() {
        let stderr = String::from_utf8_lossy(&apply_out.stderr);
        return Ok((
            Verdict {
                ok: false,
                score: None,
                summary: format!("git apply failed: {}", stderr.trim()),
                spec_sha256: String::new(),
            },
            started.elapsed().as_millis() as u64,
        ));
    }

    // 3. Double-check actual git modified/untracked files against frozen_paths & target_files.
    let status_out = Command::new("git")
        .current_dir(stage_dir)
        .args(["status", "--porcelain"])
        .output()
        .await?;
    let touched: Vec<String> = String::from_utf8_lossy(&status_out.stdout)
        .lines()
        .filter_map(|l| l.get(3..).map(|s| s.trim().to_string()))
        .filter(|s| !s.is_empty())
        .collect();

    if let Err(e) = validate_touched_paths(&touched, &manifest.frozen_paths, target_files) {
        return Ok((
            Verdict {
                ok: false,
                score: None,
                summary: format!("post-apply policy violation: {e}"),
                spec_sha256: String::new(),
            },
            started.elapsed().as_millis() as u64,
        ));
    }

    // 4. Compute post-patch frozen spec hash directly on the Hub (never trusted from container).
    let post_spec_sha256 = compute_spec_sha256(stage_dir, &manifest.frozen_paths)?;

    // Strip `.git` before copying into container so the container has zero git history clutter.
    let _ = std::fs::remove_dir_all(stage_dir.join(".git"));

    // 5. Create hermetic, networkless container (`docker create` + `docker cp` + `docker start -a`).
    let mut create_args = vec![
        "create".to_string(),
        "--network=none".to_string(),
        "--cpus=2".to_string(),
        format!("--memory={}m", manifest.verifier.memory_mb.max(256)),
        "--pids-limit=512".to_string(),
        // `verify` starts as root with only SETUID/SETGID so it can run contributor
        // code as `sunstead-runner` and trusted checks as `sunstead-checker`
        // (see missions/verifier-common/sunstead_sandbox.py).
        "--user=0:0".to_string(),
        "--cap-drop=ALL".to_string(),
        "--cap-add=SETUID".to_string(),
        "--cap-add=SETGID".to_string(),
        "--security-opt=no-new-privileges".to_string(),
        "-w".to_string(),
        "/work".to_string(),
    ];
    if let Some(runtime) = docker_runtime {
        if !runtime.trim().is_empty() {
            create_args.push(format!("--runtime={}", runtime.trim()));
        }
    }
    create_args.push(manifest.verifier.image.clone());
    create_args.extend(manifest.verifier.command.clone());
    create_args.push(task_id.to_string());

    let create_out = Command::new("docker")
        .args(&create_args)
        .output()
        .await
        .context("failed to execute `docker create`")?;
    if !create_out.status.success() {
        let stderr = String::from_utf8_lossy(&create_out.stderr);
        return Err(anyhow!(
            "docker create failed for image '{}': {}",
            manifest.verifier.image,
            stderr.trim()
        ));
    }
    let cid = String::from_utf8_lossy(&create_out.stdout).trim().to_string();

    // Ensure the container is always destroyed even on error/timeout.
    let result = run_container_lifecycle(&cid, stage_dir, manifest.verifier.timeout_sec).await;
    let _ = Command::new("docker")
        .args(["rm", "-f", &cid])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await;

    let elapsed_ms = started.elapsed().as_millis() as u64;

    match result {
        Ok((stdout, stderr, success)) => {
            if let Some(mut verdict) = parse_verdict_from_stdout(&stdout) {
                verdict.spec_sha256 = post_spec_sha256;
                if !success {
                    verdict.ok = false;
                }
                Ok((verdict, elapsed_ms))
            } else {
                let tail = combined_tail(&stdout, &stderr, 400);
                Ok((
                    Verdict {
                        ok: false,
                        score: None,
                        summary: format!("verifier did not emit valid JSON verdict: {tail}"),
                        spec_sha256: post_spec_sha256,
                    },
                    elapsed_ms,
                ))
            }
        }
        Err(err) => Ok((
            Verdict {
                ok: false,
                score: None,
                summary: format!("verifier execution error: {err}"),
                spec_sha256: post_spec_sha256,
            },
            elapsed_ms,
        )),
    }
}

async fn run_container_lifecycle(
    cid: &str,
    stage_dir: &Path,
    timeout_sec: u64,
) -> Result<(String, String, bool)> {
    let src_spec = format!("{}/.", stage_dir.display());
    let dst_spec = format!("{cid}:/work");

    let cp_out = Command::new("docker")
        .args(["cp", &src_spec, &dst_spec])
        .output()
        .await
        .context("docker cp failed")?;
    if !cp_out.status.success() {
        return Err(anyhow!(
            "docker cp failed: {}",
            String::from_utf8_lossy(&cp_out.stderr).trim()
        ));
    }

    info!(container_id = %cid, timeout_sec, "starting hermetic verifier container");
    let start_fut = Command::new("docker")
        .args(["start", "-a", cid])
        .output();

    let out = match tokio::time::timeout(Duration::from_secs(timeout_sec.max(5)), start_fut).await {
        Ok(res) => res.context("docker start failed")?,
        Err(_) => {
            warn!(container_id = %cid, "verifier container timed out");
            return Err(anyhow!("verification timed out after {timeout_sec}s"));
        }
    };

    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    Ok((stdout, stderr, out.status.success()))
}

fn parse_verdict_from_stdout(stdout: &str) -> Option<Verdict> {
    for line in stdout.lines().rev() {
        let trimmed = line.trim();
        if trimmed.starts_with('{') && trimmed.ends_with('}') {
            if let Ok(v) = serde_json::from_str::<Verdict>(trimmed) {
                return Some(v);
            }
        }
    }
    None
}

fn combined_tail(stdout: &str, stderr: &str, max_chars: usize) -> String {
    let combined = format!("{}\n{}", stdout.trim(), stderr.trim());
    let cleaned = combined.trim();
    if cleaned.len() <= max_chars {
        cleaned.to_string()
    } else {
        cleaned[cleaned.len() - max_chars..].to_string()
    }
}

async fn run_git(dir: &Path, args: &[&str]) -> Result<()> {
    let out = Command::new("git")
        .current_dir(dir)
        .args(args)
        .output()
        .await
        .with_context(|| format!("failed to run git {:?}", args))?;
    if !out.status.success() {
        return Err(anyhow!(
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(())
}

pub async fn check_docker_available() -> bool {
    Command::new("docker")
        .args(["version", "--format", "{{.Server.Version}}"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .map(|s| s.success())
        .unwrap_or(false)
}
