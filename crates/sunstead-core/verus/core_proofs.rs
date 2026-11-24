//! Mission #0 — Formal Verus specification & proofs for `sunstead-core` invariants.
//!
//! Run with: `verus crates/sunstead-core/verus/core_proofs.rs`
//!
//! Proves the core safety properties of Sunstead's Trusted Core:
//! 1. Frozen-path safety: any submission touching a frozen file is rejected.
//! 2. Spec-immutability: a verdict with mismatched `spec_sha256` can never verify a task.
//! 3. Dependency soundness: a task with unmet dependencies can never transition to `Verified`.
//! 4. Hillclimb monotonicity: accepted hillclimb scores strictly improve the best score.

#[cfg(verus)]
use vstd::prelude::*;

#[cfg(verus)]
verus! {

#[derive(PartialEq, Eq, Copy, Clone)]
pub enum Mode {
    Dag,
    Hillclimb,
}

#[derive(PartialEq, Eq, Copy, Clone)]
pub enum Direction {
    Maximize,
    Minimize,
}

#[derive(PartialEq, Eq, Copy, Clone)]
pub enum Status {
    Open,
    Leased,
    Verified,
}

pub struct CoreTask {
    pub status: Status,
    pub deps_verified: bool,
    pub has_best: bool,
    pub best_score: i64,
}

pub struct CoreVerdict {
    pub ok: bool,
    pub touches_frozen: bool,
    pub outside_targets: bool,
    pub spec_hash_matches: bool,
    pub has_score: bool,
    pub score: i64,
}

pub open spec fn strictly_improves(dir: Direction, submitted: i64, current_best: i64) -> bool {
    match dir {
        Direction::Maximize => submitted > current_best,
        Direction::Minimize => submitted < current_best,
    }
}

pub fn accept_verdict(
    mode: Mode,
    dir: Direction,
    task: CoreTask,
    verdict: CoreVerdict,
) -> (res: Option<CoreTask>)
    ensures
        // Invariant 1: Frozen or out-of-scope paths can NEVER be accepted.
        (verdict.touches_frozen || verdict.outside_targets) ==> res.is_none(),
        // Invariant 2: Spec hash mismatch or failing verdict can NEVER be accepted.
        (!verdict.spec_hash_matches || !verdict.ok) ==> res.is_none(),
        // Invariant 3: Blocked tasks can NEVER transition to Verified.
        (!task.deps_verified) ==> res.is_none(),
        // Invariant 4: Dag tasks cannot be verified twice.
        (mode == Mode::Dag && task.status == Status::Verified) ==> res.is_none(),
        // Invariant 5: Accepted hillclimb verdicts strictly improve best_score.
        match res {
            Some(next) =>
                next.status == Status::Verified
                && (mode == Mode::Hillclimb ==> (
                    next.has_best
                    && (!task.has_best || strictly_improves(dir, next.best_score, task.best_score))
                )),
            None => true,
        }
{
    if !task.deps_verified {
        return None;
    }
    if mode == Mode::Dag && task.status == Status::Verified {
        return None;
    }
    if verdict.touches_frozen || verdict.outside_targets {
        return None;
    }
    if !verdict.spec_hash_matches || !verdict.ok {
        return None;
    }

    match mode {
        Mode::Dag => Some(CoreTask {
            status: Status::Verified,
            deps_verified: task.deps_verified,
            has_best: task.has_best,
            best_score: task.best_score,
        }),
        Mode::Hillclimb => {
            if !verdict.has_score {
                return None;
            }
            if task.has_best {
                let improved = match dir {
                    Direction::Maximize => verdict.score > task.best_score,
                    Direction::Minimize => verdict.score < task.best_score,
                };
                if !improved {
                    return None;
                }
            }
            Some(CoreTask {
                status: Status::Verified,
                deps_verified: task.deps_verified,
                has_best: true,
                best_score: verdict.score,
            })
        }
    }
}

} // verus!
