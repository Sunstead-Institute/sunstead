use crate::model::{MissionMode, TaskDefinition, TaskState, TaskStatus};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum DagError {
    #[error("duplicate task id: {0}")]
    DuplicateTaskId(String),
    #[error("task '{task}' depends on unknown task '{missing}'")]
    UnknownDependency { task: String, missing: String },
    #[error("task dependency graph contains a cycle")]
    CycleDetected,
}

/// Validate that task IDs are unique, all dependencies exist, and the graph is acyclic (Kahn's algorithm).
pub fn validate_dag(tasks: &[TaskDefinition]) -> Result<Vec<String>, DagError> {
    let mut ids = BTreeSet::new();
    for t in tasks {
        if !ids.insert(t.id.clone()) {
            return Err(DagError::DuplicateTaskId(t.id.clone()));
        }
    }

    let mut in_degree: BTreeMap<String, usize> = BTreeMap::new();
    let mut dependents: BTreeMap<String, Vec<String>> = BTreeMap::new();

    for t in tasks {
        in_degree.insert(t.id.clone(), t.depends_on.len());
        for dep in &t.depends_on {
            if !ids.contains(dep) {
                return Err(DagError::UnknownDependency {
                    task: t.id.clone(),
                    missing: dep.clone(),
                });
            }
            dependents.entry(dep.clone()).or_default().push(t.id.clone());
        }
    }

    let mut queue: VecDeque<String> = in_degree
        .iter()
        .filter(|(_, &deg)| deg == 0)
        .map(|(id, _)| id.clone())
        .collect();

    let mut topo = Vec::with_capacity(tasks.len());
    while let Some(curr) = queue.pop_front() {
        topo.push(curr.clone());
        if let Some(children) = dependents.get(&curr) {
            for child in children {
                if let Some(deg) = in_degree.get_mut(child) {
                    *deg -= 1;
                    if *deg == 0 {
                        queue.push_back(child.clone());
                    }
                }
            }
        }
    }

    if topo.len() != tasks.len() {
        return Err(DagError::CycleDetected);
    }
    Ok(topo)
}

/// True iff every dependency of `task` is currently `TaskStatus::Verified`.
pub fn is_task_unlocked(task: &TaskState, all_tasks: &[TaskState]) -> bool {
    task.def.depends_on.iter().all(|dep_id| {
        all_tasks
            .iter()
            .find(|other| other.def.id == *dep_id)
            .map(|other| other.status == TaskStatus::Verified)
            .unwrap_or(false)
    })
}

/// Return IDs of tasks currently eligible for work.
/// - In `Dag` mode: unlocked tasks that are not yet `Verified`.
/// - In `Hillclimb` mode: all unlocked tasks (already-verified tasks remain open for strictly better scores).
pub fn compute_frontier(mode: MissionMode, tasks: &[TaskState]) -> Vec<String> {
    tasks
        .iter()
        .filter(|t| {
            let unlocked = is_task_unlocked(t, tasks);
            match mode {
                MissionMode::Dag => unlocked && t.status != TaskStatus::Verified,
                MissionMode::Hillclimb => unlocked,
            }
        })
        .map(|t| t.def.id.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mk_task(id: &str, deps: &[&str]) -> TaskDefinition {
        TaskDefinition {
            id: id.into(),
            title: id.into(),
            description: String::new(),
            target_files: vec![format!("{id}.lean")],
            depends_on: deps.iter().map(|s| s.to_string()).collect(),
            baseline_score: None,
        }
    }

    #[test]
    fn detects_cycles() {
        let tasks = vec![mk_task("a", &["b"]), mk_task("b", &["a"])];
        assert_eq!(validate_dag(&tasks), Err(DagError::CycleDetected));
    }

    #[test]
    fn unlocks_downstream_only_when_deps_verified() {
        let mut states = vec![
            TaskState::from_def(mk_task("a", &[])),
            TaskState::from_def(mk_task("b", &["a"])),
        ];
        assert_eq!(compute_frontier(MissionMode::Dag, &states), vec!["a"]);
        states[0].status = TaskStatus::Verified;
        assert_eq!(compute_frontier(MissionMode::Dag, &states), vec!["b"]);
    }
}
