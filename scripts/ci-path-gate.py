#!/usr/bin/env python3
"""Fail-closed GitHub Actions path gate for Sunstead CI and GHCR verifier publishing.

Maps changed repo paths (from `git diff --name-only <base>...<head>` or explicit
`--files`) to per-toolchain verifier/publish boolean outputs so unrelated Hub,
UI, docs, or single-toolchain mission PRs do not rebuild all three Lean 4
toolchains while preserving 100% mandatory proof checks for every verifier,
toolchain, script, or mission change.

Fail-closed guarantees:
- `workflow_dispatch` and `schedule` always enable all toolchains.
- If `git diff` fails, base SHA is missing/zero, or a changed path under
  `missions/` or `cloudflare/containers/` cannot be mapped cleanly to one known
  toolchain (e.g. a deleted mission or unknown verifier image), all three
  toolchains are enabled.
- Any change to `missions/verifier-common/**`, shared verification/red-team/
  scripts, `cloudflare/containers/verifier_server.py`, or workflow files
  enables all affected toolchains.
"""
import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MISSIONS_DIR = os.path.join(ROOT, "missions")

IMAGE_TO_TOOLCHAIN = {
    "sunstead/verifier-lean4:v0.2": "v436",
    "sunstead/verifier-lean4-v4.35.0:v0.1": "v435",
    "sunstead/verifier-lean4-v4.31.0:v0.1": "v431",
}

ALL_VERIFIER_SHARED_PREFIXES = (
    "missions/verifier-common/",
)
ALL_VERIFIER_SHARED_FILES = {
    "cloudflare/containers/verifier_server.py",
    "scripts/redteam.py",
    "scripts/check-statements.py",
    "scripts/build-verifiers.sh",
    "scripts/ci-path-gate.py",
    "scripts/test_ci_path_gate.py",
    ".github/workflows/ci.yml",
}
EXPORT_FILES = {
    "scripts/export-upstream.py",
    "scripts/test_export_upstream.py",
    # Shared engine of export-upstream.py, served publicly as /verify.py, and the
    # scout parser it must stay identical to.
    "scripts/sunstead_verify.py",
    "scripts/test_sunstead_verify.py",
    "scripts/scout-upstream.py",
    ".github/workflows/ci.yml",
}

# Hub-only metadata under missions/ that no verifier image or Lean build reads.
HUB_ONLY_MISSION_FILES = {
    "missions/best-known.json",
}

TOOLCHAIN_VERIFIER_DIRS = {
    "missions/verifier-lean4/": ("v436", True),
    "missions/verifier-lean4-v4.35.0/": ("v435", True),
    "missions/verifier-lean4-v4.31.0/": ("v431", True),
    "cloudflare/containers/lean4/": ("v436", False),
    "cloudflare/containers/lean4-v4.35.0/": ("v435", False),
    "cloudflare/containers/lean4-v4.31.0/": ("v431", False),
}


def load_mission_toolchains(missions_dir=MISSIONS_DIR):
    """Map `<mission-dir-name>` -> `'v436' | 'v435' | 'v431'` from `sunstead.json`."""
    mapping = {}
    if not os.path.isdir(missions_dir):
        return mapping
    for name in sorted(os.listdir(missions_dir)):
        manifest_path = os.path.join(missions_dir, name, "sunstead.json")
        if not os.path.isfile(manifest_path):
            continue
        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                manifest = json.load(f)
            image = (manifest.get("verifier") or {}).get("image")
            tc = IMAGE_TO_TOOLCHAIN.get(image)
            if tc:
                mapping[name] = tc
        except (OSError, ValueError):
            # Leave unmapped so edits to a broken manifest fail closed to all toolchains.
            continue
    return mapping


def all_enabled(reason):
    return {
        "run_v436": True,
        "run_v435": True,
        "run_v431": True,
        "run_export": True,
        "pub_v436": True,
        "pub_v435": True,
        "pub_v431": True,
        "reason": reason,
    }


def classify_paths(changed_files, *, event_name="pull_request", missions_dir=MISSIONS_DIR):
    """Return boolean gate outputs for the given list of changed repo-relative paths."""
    if event_name in ("schedule", "workflow_dispatch"):
        return all_enabled(f"event={event_name}")
    if changed_files is None:
        return all_enabled("diff unavailable (fail-closed)")

    out = {
        "run_v436": False,
        "run_v435": False,
        "run_v431": False,
        "run_export": False,
        "pub_v436": False,
        "pub_v435": False,
        "pub_v431": False,
    }
    mission_tc = load_mission_toolchains(missions_dir)
    reasons = []

    def enable_all_verifiers(tag, *, publish=False):
        out["run_v436"] = out["run_v435"] = out["run_v431"] = True
        if publish:
            out["pub_v436"] = out["pub_v435"] = out["pub_v431"] = True
        reasons.append(tag)

    for raw in changed_files:
        p = raw.strip().replace("\\", "/")
        if not p:
            continue
        if p in EXPORT_FILES:
            out["run_export"] = True
            reasons.append(f"export:{p}")
        if p == ".github/workflows/publish-verifiers.yml":
            out["pub_v436"] = out["pub_v435"] = out["pub_v431"] = True
            reasons.append("publish-workflow")
            continue
        if any(p.startswith(pref) for pref in ALL_VERIFIER_SHARED_PREFIXES):
            enable_all_verifiers(f"shared:{p}", publish=True)
            continue
        if p in ALL_VERIFIER_SHARED_FILES:
            enable_all_verifiers(f"shared:{p}", publish=False)
            continue

        matched_dir = False
        for pref, (tc, is_pub) in TOOLCHAIN_VERIFIER_DIRS.items():
            if p.startswith(pref):
                out[f"run_{tc}"] = True
                if is_pub:
                    out[f"pub_{tc}"] = True
                reasons.append(f"{tc}:{p}")
                matched_dir = True
                break
        if matched_dir:
            continue

        if p.startswith("cloudflare/containers/"):
            # Unrecognized file under cloudflare/containers/: fail closed for verifier checks.
            enable_all_verifiers(f"unknown-container:{p}", publish=False)
            continue

        if p in HUB_ONLY_MISSION_FILES:
            reasons.append(f"hub-only:{p}")
            continue

        if p.startswith("missions/"):
            parts = p.split("/")
            if len(parts) < 3:
                enable_all_verifiers(f"missions-root:{p}", publish=True)
                continue
            mdir = parts[1]
            tc = mission_tc.get(mdir)
            if tc is None:
                # Deleted mission, new unmapped image, or unreadable manifest -> fail closed.
                enable_all_verifiers(f"unmapped-mission:{mdir}", publish=True)
            else:
                out[f"run_{tc}"] = True
                out[f"pub_{tc}"] = True
                reasons.append(f"mission-{tc}:{mdir}")
            if p.endswith(("/verify", "/sunstead.json", "/lean-toolchain")):
                out["run_export"] = True
            continue

    out["reason"] = ", ".join(dict.fromkeys(reasons))[:240] if reasons else "non-verifier paths only"
    return out


def git_changed_files(base_ref, head_ref="HEAD", *, repo_root=ROOT, three_dot=True):
    """Compute changed repo-relative paths via `git diff --name-only`, or None on error."""
    if not base_ref or set(base_ref) == {"0"}:
        return None
    spec = f"{base_ref}...{head_ref}" if three_dot else f"{base_ref}..{head_ref}"
    p = subprocess.run(
        ["git", "diff", "--name-only", spec],
        cwd=repo_root,
        capture_output=True,
        text=True,
    )
    if p.returncode != 0:
        return None
    return [line.strip() for line in p.stdout.splitlines() if line.strip()]


def main():
    ap = argparse.ArgumentParser(description="Classify changed paths for Sunstead CI / GHCR publish")
    ap.add_argument("--event", default=os.environ.get("GITHUB_EVENT_NAME", "pull_request"))
    ap.add_argument("--base", default=None, help="Base commit/ref for git diff")
    ap.add_argument("--head", default="HEAD", help="Head commit/ref for git diff")
    ap.add_argument("--two-dot", action="store_true", help="Use two-dot diff (push events)")
    ap.add_argument("--files", nargs="*", default=None, help="Explicit changed paths (for testing)")
    ap.add_argument("--github-output", default=os.environ.get("GITHUB_OUTPUT"))
    ap.add_argument("--json", action="store_true", help="Print JSON summary to stdout")
    args = ap.parse_args()

    if args.files is not None:
        changed = list(args.files)
    elif args.event in ("schedule", "workflow_dispatch"):
        changed = []
    else:
        changed = git_changed_files(args.base, args.head, three_dot=not args.two_dot)

    result = classify_paths(changed, event_name=args.event)
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as f:
            for k, v in result.items():
                val = "true" if v is True else ("false" if v is False else str(v).replace("\n", " "))
                f.write(f"{k}={val}\n")

    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        for k in ("run_v436", "run_v435", "run_v431", "run_export", "pub_v436", "pub_v435", "pub_v431", "reason"):
            v = result[k]
            val = "true" if v is True else ("false" if v is False else v)
            print(f"{k}={val}")


if __name__ == "__main__":
    main()
