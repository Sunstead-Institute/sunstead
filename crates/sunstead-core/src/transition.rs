use crate::dag::is_task_unlocked;
use crate::model::{Lease, MissionMode, ScoreDirection, TaskState, TaskStatus, Verdict};
use crate::policy::{validate_patch, PolicyError};
use thiserror::Error;

#[derive(Debug, Error, PartialEq)]
pub enum TransitionError {
    #[error("task not found: {0}")]
    TaskNotFound(String),
    #[error("task '{0}' is blocked on unverified dependencies")]
    DependenciesUnmet(String),
    #[error("task '{0}' is already verified")]
    AlreadyVerified(String),
    #[error("task '{task}' is actively leased by '{holder}' until {expires_at}")]
    ActivelyLeased {
        task: String,
        holder: String,
        expires_at: i64,
    },
    #[error("spec hash mismatch: expected '{expected}', got '{actual}'")]
    SpecHashMismatch { expected: String, actual: String },
    #[error("verification failed: {0}")]
    VerificationFailed(String),
    #[error("hillclimb verdict missing numeric score")]
    MissingScore,
    #[error("hillclimb score {submitted} does not strictly improve on best {best}")]
    ScoreNotImproved { submitted: f64, best: f64 },
    #[error("patch policy rejected: {0}")]
    Policy(#[from] PolicyError),
}

#[derive(Debug, Clone, PartialEq)]
pub struct ClaimOutcome {
    pub lease: Lease,
    pub updated_status: TaskStatus,
}

#[derive(Debug, Clone, PartialEq)]
pub struct VerdictOutcome {
    pub updated_status: TaskStatus,
    pub new_best_score: Option<f64>,
    pub unlocked_dependents: Vec<String>,
}

/// Pure soft-lease transition.
/// Leases are advisory and time-bounded; expired leases can always be taken over.
pub fn apply_claim(
    mode: MissionMode,
    all_tasks: &[TaskState],
    task_id: &str,
    contributor: &str,
    lease_token: &str,
    now_unix: i64,
    lease_duration_sec: i64,
) -> Result<ClaimOutcome, TransitionError> {
    let task = all_tasks
        .iter()
        .find(|t| t.def.id == task_id)
        .ok_or_else(|| TransitionError::TaskNotFound(task_id.to_string()))?;

    if !is_task_unlocked(task, all_tasks) {
        return Err(TransitionError::DependenciesUnmet(task_id.to_string()));
    }

    if mode == MissionMode::Dag && task.status == TaskStatus::Verified {
        return Err(TransitionError::AlreadyVerified(task_id.to_string()));
    }

    if let Some(existing) = &task.active_lease {
        if existing.expires_at_unix > now_unix && existing.contributor != contributor {
            return Err(TransitionError::ActivelyLeased {
                task: task_id.to_string(),
                holder: existing.contributor.clone(),
                expires_at: existing.expires_at_unix,
            });
        }
    }

    let lease = Lease {
        task_id: task_id.to_string(),
        contributor: contributor.to_string(),
        lease_token: lease_token.to_string(),
        expires_at_unix: now_unix.saturating_add(lease_duration_sec.max(60)),
    };

    let updated_status = if task.status == TaskStatus::Verified {
        TaskStatus::Verified
    } else {
        TaskStatus::Leased
    };

    Ok(ClaimOutcome {
        lease,
        updated_status,
    })
}

/// Pure verdict acceptance transition.
/// Note: soft leases NEVER block a valid verified submission—whoever submits a valid proof first wins.
pub fn apply_verdict(
    mode: MissionMode,
    score_direction: ScoreDirection,
    frozen_paths: &[String],
    expected_spec_sha256: &str,
    all_tasks: &[TaskState],
    task_id: &str,
    patch: &str,
    verdict: &Verdict,
) -> Result<VerdictOutcome, TransitionError> {
    let task = all_tasks
        .iter()
        .find(|t| t.def.id == task_id)
        .ok_or_else(|| TransitionError::TaskNotFound(task_id.to_string()))?;

    if !is_task_unlocked(task, all_tasks) {
        return Err(TransitionError::DependenciesUnmet(task_id.to_string()));
    }

    if mode == MissionMode::Dag && task.status == TaskStatus::Verified {
        return Err(TransitionError::AlreadyVerified(task_id.to_string()));
    }

    validate_patch(patch, frozen_paths, &task.def.target_files)?;

    if verdict.spec_sha256 != expected_spec_sha256 {
        return Err(TransitionError::SpecHashMismatch {
            expected: expected_spec_sha256.to_string(),
            actual: verdict.spec_sha256.clone(),
        });
    }

    if !verdict.ok {
        return Err(TransitionError::VerificationFailed(verdict.summary.clone()));
    }

    let new_best_score = match mode {
        MissionMode::Dag => verdict.score.or(task.best_score),
        MissionMode::Hillclimb => {
            let submitted = verdict.score.ok_or(TransitionError::MissingScore)?;
            if !submitted.is_finite() {
                return Err(TransitionError::MissingScore);
            }
            if let Some(best) = task.best_score {
                let improved = match score_direction {
                    ScoreDirection::Maximize => submitted > best,
                    ScoreDirection::Minimize => submitted < best,
                };
                if !improved {
                    return Err(TransitionError::ScoreNotImproved { submitted, best });
                }
            }
            Some(submitted)
        }
    };

    let mut simulated = all_tasks.to_vec();
    if let Some(t) = simulated.iter_mut().find(|t| t.def.id == task_id) {
        t.status = TaskStatus::Verified;
    }

    let unlocked_dependents = simulated
        .iter()
        .filter(|candidate| {
            candidate.def.depends_on.iter().any(|d| d == task_id)
                && is_task_unlocked(candidate, &simulated)
                && candidate.status != TaskStatus::Verified
        })
        .map(|t| t.def.id.clone())
        .collect();

    Ok(VerdictOutcome {
        updated_status: TaskStatus::Verified,
        new_best_score,
        unlocked_dependents,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TaskDefinition;

    fn sample_tasks() -> Vec<TaskState> {
        vec![
            TaskState::from_def(TaskDefinition {
                id: "t1".into(),
                title: "Base lemma".into(),
                description: String::new(),
                target_files: vec!["Proofs/T1.lean".into()],
                depends_on: vec![],
                baseline_score: None,
            }),
            TaskState::from_def(TaskDefinition {
                id: "t2".into(),
                title: "Dependent lemma".into(),
                description: String::new(),
                target_files: vec!["Proofs/T2.lean".into()],
                depends_on: vec!["t1".into()],
                baseline_score: None,
            }),
        ]
    }

    fn good_patch() -> &'static str {
        "\
diff --git a/Proofs/T1.lean b/Proofs/T1.lean
--- a/Proofs/T1.lean
+++ b/Proofs/T1.lean
@@ -1 +1 @@
-sorry
+trivial
"
    }

    #[test]
    fn enforces_spec_hash_and_unlocks_dependents() {
        let tasks = sample_tasks();
        let frozen = vec!["Spec/**".into()];
        let bad_verdict = Verdict {
            ok: true,
            score: None,
            summary: "ok".into(),
            spec_sha256: "wrong".into(),
        };
        assert!(matches!(
            apply_verdict(
                MissionMode::Dag,
                ScoreDirection::Maximize,
                &frozen,
                "sha256:abc",
                &tasks,
                "t1",
                good_patch(),
                &bad_verdict
            ),
            Err(TransitionError::SpecHashMismatch { .. })
        ));

        let good_verdict = Verdict {
            ok: true,
            score: None,
            summary: "ok".into(),
            spec_sha256: "sha256:abc".into(),
        };
        let out = apply_verdict(
            MissionMode::Dag,
            ScoreDirection::Maximize,
            &frozen,
            "sha256:abc",
            &tasks,
            "t1",
            good_patch(),
            &good_verdict,
        )
        .unwrap();
        assert_eq!(out.updated_status, TaskStatus::Verified);
        assert_eq!(out.unlocked_dependents, vec!["t2".to_string()]);
    }

    #[test]
    fn hillclimb_enforces_strict_improvement() {
        let mut tasks = sample_tasks();
        tasks[0].best_score = Some(100.0);
        let frozen = vec!["Spec/**".into()];

        let worse = Verdict {
            ok: true,
            score: Some(120.0),
            summary: "worse".into(),
            spec_sha256: "sha256:abc".into(),
        };
        assert!(matches!(
            apply_verdict(
                MissionMode::Hillclimb,
                ScoreDirection::Minimize,
                &frozen,
                "sha256:abc",
                &tasks,
                "t1",
                good_patch(),
                &worse
            ),
            Err(TransitionError::ScoreNotImproved { .. })
        ));

        let better = Verdict {
            ok: true,
            score: Some(16.0),
            summary: "tighter bound!".into(),
            spec_sha256: "sha256:abc".into(),
        };
        let out = apply_verdict(
            MissionMode::Hillclimb,
            ScoreDirection::Minimize,
            &frozen,
            "sha256:abc",
            &tasks,
            "t1",
            good_patch(),
            &better,
        )
        .unwrap();
        assert_eq!(out.new_best_score, Some(16.0));
    }
}
