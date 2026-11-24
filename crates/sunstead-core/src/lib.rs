#![forbid(unsafe_code)]

//! `sunstead-core` is the pure, I/O-free Trusted Core of Sunstead.
//!
//! It owns all security-critical invariants:
//! - Patch safety and `frozen_paths` / `target_files` enforcement (`policy`)
//! - DAG validation, acyclicity, and dependency unlocking (`dag`)
//! - State transitions for claims and verified submissions (`transition`)

pub mod dag;
pub mod model;
pub mod policy;
pub mod transition;

pub use dag::{compute_frontier, is_task_unlocked, validate_dag, DagError};
pub use model::{
    Lease, MissionManifest, MissionMode, ScoreDirection, TaskDefinition, TaskState, TaskStatus,
    Verdict, VerifierConfig,
};
pub use policy::{
    extract_patch_paths, glob_matches, validate_patch, validate_touched_paths, PolicyError,
};
pub use transition::{
    apply_claim, apply_verdict, ClaimOutcome, TransitionError, VerdictOutcome,
};
