use std::collections::BTreeSet;
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum PolicyError {
    #[error("patch is empty or modifies no files")]
    EmptyPatch,
    #[error("binary patches are forbidden")]
    BinaryPatchForbidden,
    #[error("symlink mode changes (120000) are forbidden")]
    SymlinkForbidden,
    #[error("unsafe or non-normalized path in patch: {0}")]
    UnsafePath(String),
    #[error("patch modifies frozen path '{path}' (matched '{pattern}')")]
    FrozenPathViolation { path: String, pattern: String },
    #[error("patch modifies '{path}', which is outside allowed target_files")]
    OutsideTargetFiles { path: String },
}

/// Normalize and validate a repository-relative POSIX path.
pub fn normalize_rel_path(raw: &str) -> Result<String, PolicyError> {
    let trimmed = raw.trim().trim_matches('"');
    if trimmed.is_empty()
        || trimmed.starts_with('/')
        || trimmed.contains('\0')
        || trimmed.contains('\\')
    {
        return Err(PolicyError::UnsafePath(raw.to_string()));
    }

    let stripped = trimmed
        .strip_prefix("a/")
        .or_else(|| trimmed.strip_prefix("b/"))
        .unwrap_or(trimmed);

    let mut parts = Vec::new();
    for seg in stripped.split('/') {
        if seg.is_empty() || seg == "." {
            continue;
        }
        if seg == ".." {
            return Err(PolicyError::UnsafePath(raw.to_string()));
        }
        parts.push(seg);
    }
    if parts.is_empty() {
        return Err(PolicyError::UnsafePath(raw.to_string()));
    }
    Ok(parts.join("/"))
}

/// Extract all touched paths from a unified git diff and reject binary/symlink tricks.
pub fn extract_patch_paths(patch: &str) -> Result<Vec<String>, PolicyError> {
    let mut paths = BTreeSet::new();

    for line in patch.lines() {
        if line.starts_with("GIT binary patch") || line.starts_with("Binary files ") {
            return Err(PolicyError::BinaryPatchForbidden);
        }
        if line.starts_with("new file mode 120")
            || line.starts_with("old mode 120")
            || line.starts_with("new mode 120")
        {
            return Err(PolicyError::SymlinkForbidden);
        }

        if let Some(rest) = line.strip_prefix("diff --git ") {
            let mut tokens = rest.split_whitespace();
            if let (Some(a), Some(b)) = (tokens.next(), tokens.next()) {
                paths.insert(normalize_rel_path(a)?);
                paths.insert(normalize_rel_path(b)?);
            }
        } else if let Some(rest) = line.strip_prefix("rename from ") {
            paths.insert(normalize_rel_path(rest)?);
        } else if let Some(rest) = line.strip_prefix("rename to ") {
            paths.insert(normalize_rel_path(rest)?);
        } else if let Some(rest) = line.strip_prefix("copy from ") {
            paths.insert(normalize_rel_path(rest)?);
        } else if let Some(rest) = line.strip_prefix("copy to ") {
            paths.insert(normalize_rel_path(rest)?);
        } else if let Some(rest) = line.strip_prefix("--- ") {
            let p = rest.split('\t').next().unwrap_or(rest).trim();
            if p != "/dev/null" {
                paths.insert(normalize_rel_path(p)?);
            }
        } else if let Some(rest) = line.strip_prefix("+++ ") {
            let p = rest.split('\t').next().unwrap_or(rest).trim();
            if p != "/dev/null" {
                paths.insert(normalize_rel_path(p)?);
            }
        }
    }

    if paths.is_empty() {
        return Err(PolicyError::EmptyPatch);
    }

    Ok(paths.into_iter().collect())
}

/// Deterministic glob matcher supporting exact matches, `*` (within segment), and `**` (any depth).
pub fn glob_matches(pattern: &str, path: &str) -> bool {
    let pat_segs: Vec<&str> = pattern.split('/').filter(|s| !s.is_empty()).collect();
    let path_segs: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
    match_segments(&pat_segs, &path_segs)
}

fn match_segments(pat: &[&str], path: &[&str]) -> bool {
    match (pat.first(), path.first()) {
        (None, None) => true,
        (Some(&"**"), _) => {
            match_segments(&pat[1..], path)
                || (!path.is_empty() && match_segments(pat, &path[1..]))
        }
        (Some(p), Some(s)) => {
            segment_matches(p, s) && match_segments(&pat[1..], &path[1..])
        }
        _ => false,
    }
}

fn segment_matches(pat: &str, seg: &str) -> bool {
    let p: Vec<char> = pat.chars().collect();
    let s: Vec<char> = seg.chars().collect();
    let mut dp = vec![vec![false; s.len() + 1]; p.len() + 1];
    dp[0][0] = true;
    for i in 1..=p.len() {
        if p[i - 1] == '*' {
            dp[i][0] = dp[i - 1][0];
        }
    }
    for i in 1..=p.len() {
        for j in 1..=s.len() {
            if p[i - 1] == '*' {
                dp[i][j] = dp[i - 1][j] || dp[i][j - 1];
            } else if p[i - 1] == '?' || p[i - 1] == s[j - 1] {
                dp[i][j] = dp[i - 1][j - 1];
            }
        }
    }
    dp[p.len()][s.len()]
}

/// Validate a unified diff patch against `frozen_paths` and a task's allowed `target_files`.
pub fn validate_patch(
    patch: &str,
    frozen_paths: &[String],
    target_files: &[String],
) -> Result<Vec<String>, PolicyError> {
    let touched = extract_patch_paths(patch)?;
    validate_touched_paths(&touched, frozen_paths, target_files)?;
    Ok(touched)
}

/// Validate an explicit list of repository-relative modified paths (e.g., from `git diff --name-only`).
pub fn validate_touched_paths(
    touched: &[String],
    frozen_paths: &[String],
    target_files: &[String],
) -> Result<(), PolicyError> {
    if touched.is_empty() {
        return Err(PolicyError::EmptyPatch);
    }
    for raw_path in touched {
        let path = normalize_rel_path(raw_path)?;
        for frozen in frozen_paths {
            if glob_matches(frozen, &path) {
                return Err(PolicyError::FrozenPathViolation {
                    path,
                    pattern: frozen.clone(),
                });
            }
        }
        if !target_files.is_empty() && !target_files.iter().any(|t| glob_matches(t, &path)) {
            return Err(PolicyError::OutsideTargetFiles { path });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_frozen_path_modification() {
        let patch = "\
diff --git a/src/spec/Spec.lean b/src/spec/Spec.lean
--- a/src/spec/Spec.lean
+++ b/src/spec/Spec.lean
@@ -1 +1 @@
-theorem foo : False := sorry
+theorem foo : True := trivial
";
        let frozen = vec!["src/spec/**".to_string(), "verify".to_string()];
        let targets = vec!["src/proofs/Foo.lean".to_string()];
        let err = validate_patch(patch, &frozen, &targets).unwrap_err();
        assert!(matches!(err, PolicyError::FrozenPathViolation { .. }));
    }

    #[test]
    fn rejects_symlink_and_traversal() {
        let sym_patch = "\
diff --git a/src/proofs/Foo.lean b/src/proofs/Foo.lean
new file mode 120000
--- /dev/null
+++ b/src/proofs/Foo.lean
@@ -0,0 +1 @@
+/etc/passwd
";
        assert_eq!(
            extract_patch_paths(sym_patch),
            Err(PolicyError::SymlinkForbidden)
        );

        let trav_patch = "\
--- a/../verify
+++ b/../verify
@@ -1 +1 @@
-exit 1
+exit 0
";
        assert!(matches!(
            extract_patch_paths(trav_patch),
            Err(PolicyError::UnsafePath(_))
        ));
    }

    #[test]
    fn accepts_clean_target_patch() {
        let patch = "\
diff --git a/src/proofs/Foo.lean b/src/proofs/Foo.lean
--- a/src/proofs/Foo.lean
+++ b/src/proofs/Foo.lean
@@ -1 +1 @@
-sorry
+rfl
";
        let frozen = vec!["src/spec/**".to_string(), "verify".to_string()];
        let targets = vec!["src/proofs/Foo.lean".to_string()];
        let touched = validate_patch(patch, &frozen, &targets).unwrap();
        assert_eq!(touched, vec!["src/proofs/Foo.lean".to_string()]);
    }
}
