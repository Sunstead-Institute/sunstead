#!/usr/bin/env python3
"""Build-time precompiler for Sunstead repo-snapshot missions.

Invoked inside verifier Dockerfiles to fetch the exact pinned 40-char upstream
commit SHA from `UPSTREAM.json`, verify verbatim byte-for-byte agreement with
the mission's local target files and `lean-toolchain`, build the minimal
transitive upstream dependency `.olean` graph into read-only
`/opt/sunstead/snapshots/<snapshot_id>/deps/`, and build the unmodified pinned
upstream target `.olean`(s) into a separate read-only directory
`/opt/sunstead/snapshots/<snapshot_id>/frozen-targets/`.

Separating `deps/` from `frozen-targets/` guarantees `sunstead-runner` can
never import the `sorry`-bearing pinned target `.olean`, while
`sunstead-checker` reads `frozen-targets/<TargetMod>.olean` directly via
`Lean.readModuleData` to enforce exact kernel type equality without manual
statement transcription.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sunstead_sandbox as sb  # noqa: E402


def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _extract_snapshot_config(mission_dir):
    """Capture kwargs `verify` passes to `sunstead_sandbox.lean_repo_snapshot_verify`."""
    verify_path = os.path.join(mission_dir, "verify")
    if not os.path.isfile(verify_path):
        raise RuntimeError(f"missing verify script in {mission_dir}")

    captured = {}

    def _capture(task_id, *, snapshot_id, frozen_files, tasks,
                 allowed_import_prefixes, uses_mathlib=False,
                 lean_options=None, snapshot_source_dir=None, timeout_sec=170):
        captured.update(
            snapshot_id=snapshot_id,
            frozen_files=list(frozen_files),
            tasks=dict(tasks),
            allowed_import_prefixes=list(allowed_import_prefixes),
            uses_mathlib=bool(uses_mathlib),
            lean_options=list(lean_options or []),
            snapshot_source_dir=snapshot_source_dir,
        )

    orig_verify = sb.lean_repo_snapshot_verify
    orig_argv = list(sys.argv)
    try:
        sb.lean_repo_snapshot_verify = _capture
        sys.argv = [verify_path, "__prebuild__"]
        runpy.run_path(verify_path, run_name="__main__")
    finally:
        sb.lean_repo_snapshot_verify = orig_verify
        sys.argv = orig_argv

    return captured or None


def _clone_pinned_upstream(repo, commit, dst_dir):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RuntimeError(f"upstream commit must be a 40-char hex SHA, got {commit!r}")
    url = f"https://github.com/{repo}.git"
    os.makedirs(dst_dir, exist_ok=True)
    for cmd in (
        ["git", "init", "-q"],
        ["git", "remote", "add", "origin", url],
        ["git", "fetch", "--quiet", "--depth=1", "origin", commit],
        ["git", "checkout", "--quiet", "FETCH_HEAD"],
    ):
        subprocess.run(cmd, cwd=dst_dir, check=True)
    actual = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=dst_dir, text=True
    ).strip()
    if actual != commit:
        raise RuntimeError(f"pinned checkout mismatch: expected {commit}, got {actual}")


def _trace_dependency_graph(upstream_dir, target_modules):
    """Return `{mod: [local_dep_mod, ...]}` for all local modules reachable from `target_modules`."""
    deps = {}
    state = {}  # 1 = visiting, 2 = done

    def dfs(mod):
        st = state.get(mod, 0)
        if st == 2:
            return True
        if st == 1:
            raise RuntimeError(f"cyclic Lean import involving `{mod}`")
        segs = sb._validate_mod_name(mod)
        src_path = os.path.join(upstream_dir, *segs) + ".lean"
        if not os.path.isfile(src_path):
            return False
        state[mod] = 1
        with open(src_path, "r", encoding="utf-8") as f:
            code = sb._strip_lean_comments(f.read())
        local_deps = []
        for imp in sb._extract_imports(code):
            try:
                imp_segs = sb._validate_mod_name(imp)
            except SystemExit:
                continue
            imp_path = os.path.join(upstream_dir, *imp_segs) + ".lean"
            if os.path.isfile(imp_path):
                if imp not in local_deps:
                    local_deps.append(imp)
                dfs(imp)
        deps[mod] = local_deps
        state[mod] = 2
        return True

    for m in target_modules:
        if not dfs(m):
            raise RuntimeError(f"target module `{m}` not found in upstream checkout")
    return deps


def _compile_module(upstream_dir, mod, out_dir, lean_path, lean_options):
    segs = sb._validate_mod_name(mod)
    rel_src = os.path.join(*segs) + ".lean"
    out_olean = os.path.join(out_dir, *segs) + ".olean"
    os.makedirs(os.path.dirname(out_olean), exist_ok=True)
    cmd = ["lean", f"--root={upstream_dir}"]
    for opt in lean_options:
        cmd.extend(["-D", opt])
    cmd.extend(["-o", out_olean, rel_src])
    env = os.environ.copy()
    env["LEAN_PATH"] = lean_path
    proc = subprocess.run(cmd, cwd=upstream_dir, env=env, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"failed to compile {mod} ({rel_src}):\n{proc.stdout}\n{proc.stderr}"
        )
    if not os.path.isfile(out_olean):
        raise RuntimeError(f"expected .olean not written: {out_olean}")
    if os.path.exists(out_olean + ".private"):
        raise RuntimeError(f"unsupported `.olean.private` produced for {mod}")
    return out_olean


def prebuild_snapshot_mission(mission_dir, snapshot_base, upstream_dir=None, jobs=None):
    started = time.monotonic()
    mission_name = os.path.basename(os.path.normpath(mission_dir))
    manifest_path = os.path.join(mission_dir, "sunstead.json")
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    snap_meta = manifest.get("snapshot") or {}
    if snap_meta.get("mode") != "repo-snapshot":
        return False

    cfg = _extract_snapshot_config(mission_dir)
    if not cfg:
        raise RuntimeError(f"{mission_name}: verify did not invoke lean_repo_snapshot_verify")

    up_path = os.path.join(mission_dir, "UPSTREAM.json")
    with open(up_path, "r", encoding="utf-8") as f:
        up = json.load(f)
    repo = up["repo"]
    commit = up["commit"]
    snapshot_id = cfg["snapshot_id"]
    lean_options = cfg["lean_options"]
    uses_mathlib = cfg["uses_mathlib"]
    tasks = cfg["tasks"]

    target_modules = list(dict.fromkeys(t["module"] for t in tasks.values()))
    target_rels = set()
    for t in tasks.values():
        tfiles = t.get("target_files") or ["/".join(sb._validate_mod_name(t["module"])) + ".lean"]
        for rel in tfiles:
            target_rels.add(rel.replace("\\", "/"))

    extra_lib_paths = sb._mathlib_lib_paths() if uses_mathlib else []
    snap_root = os.path.join(snapshot_base, snapshot_id)
    deps_dir = os.path.join(snap_root, "deps")
    frozen_targets_dir = os.path.join(snap_root, "frozen-targets")
    if os.path.exists(snap_root):
        shutil.rmtree(snap_root)
    os.makedirs(deps_dir, exist_ok=True)
    os.makedirs(frozen_targets_dir, exist_ok=True)

    tmp_ctx = tempfile.TemporaryDirectory(prefix=f"sunstead-snap-{snapshot_id}-")
    try:
        if upstream_dir:
            src_root = os.path.abspath(upstream_dir)
        else:
            src_root = os.path.join(tmp_ctx.name, "upstream")
            print(f"[prebuild-snapshot] fetching {repo}@{commit[:12]}...", flush=True)
            _clone_pinned_upstream(repo, commit, src_root)

        # Verify lean-toolchain and every local target file match pinned upstream byte-for-byte.
        for rel in sorted({"lean-toolchain"} | target_rels):
            local_f = os.path.join(mission_dir, rel)
            up_f = os.path.join(src_root, rel)
            if not os.path.isfile(local_f):
                raise RuntimeError(f"{mission_name}: missing local file {rel}")
            if not os.path.isfile(up_f):
                raise RuntimeError(f"{mission_name}: missing upstream file {rel} at {commit[:12]}")
            if open(local_f, "rb").read() != open(up_f, "rb").read():
                raise RuntimeError(
                    f"{mission_name}: {rel} does not match pinned {repo}@{commit[:12]} byte-for-byte"
                )

        # Trace minimal transitive dependency graph for the target module(s).
        graph = _trace_dependency_graph(src_root, target_modules)
        target_mod_set = set(target_modules)
        dep_graph = {m: [d for d in ds if d not in target_mod_set]
                     for m, ds in graph.items() if m not in target_mod_set}

        # Verify no dependency module contains a live `sorry`.
        dep_source_hashes = {}
        for mod in sorted(dep_graph.keys()):
            segs = sb._validate_mod_name(mod)
            rel = "/".join(segs) + ".lean"
            abs_p = os.path.join(src_root, *segs) + ".lean"
            dep_source_hashes[rel] = _sha256_file(abs_p)
            stripped = sb._strip_lean_comments(open(abs_p, encoding="utf-8").read())
            if re.search(r"(?<![\w.])sorry\b", stripped):
                raise RuntimeError(
                    f"{mission_name}: upstream dependency `{mod}` ({rel}) contains `sorry`"
                )

        workers = jobs or max(1, min(os.cpu_count() or 2, 8))
        deps_lean_path = ":".join([deps_dir] + extra_lib_paths)
        print(
            f"[prebuild-snapshot] building {len(dep_graph)} dependency module(s) for "
            f"{mission_name} ({workers} workers)...",
            flush=True,
        )

        built = set()
        dep_olean_hashes = {}
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
            while len(built) < len(dep_graph):
                wave = sorted(
                    m for m, ds in dep_graph.items()
                    if m not in built and all(d in built for d in ds)
                )
                if not wave:
                    remaining = sorted(set(dep_graph) - built)
                    raise RuntimeError(f"dependency cycle among: {remaining[:5]}")
                futs = {
                    ex.submit(_compile_module, src_root, m, deps_dir, deps_lean_path, lean_options): m
                    for m in wave
                }
                for fut in concurrent.futures.as_completed(futs):
                    mod = futs[fut]
                    out_olean = fut.result()
                    built.add(mod)
                    dep_olean_hashes[mod] = _sha256_file(out_olean)

        # Build unmodified pinned upstream target module(s) into `frozen-targets/`
        # (kept strictly outside `deps/` so sunstead-runner never imports them).
        frozen_target_hashes = {}
        for mod in target_modules:
            out_olean = _compile_module(
                src_root, mod, frozen_targets_dir, deps_lean_path, lean_options
            )
            frozen_target_hashes[mod] = _sha256_file(out_olean)

        elapsed_ms = int((time.monotonic() - started) * 1000)
        meta = {
            "mission": mission_name,
            "snapshot_id": snapshot_id,
            "repo": repo,
            "commit": commit,
            "toolchain": open(os.path.join(mission_dir, "lean-toolchain"), encoding="utf-8").read().strip(),
            "uses_mathlib": uses_mathlib,
            "lean_options": lean_options,
            "target_modules": target_modules,
            "target_files": sorted(target_rels),
            "dep_modules_count": len(dep_graph),
            "frozen_file_hashes": dep_source_hashes,
            "dep_olean_hashes": dep_olean_hashes,
            "frozen_target_olean_hashes": frozen_target_hashes,
            "build_ms": elapsed_ms,
        }
        with open(os.path.join(snap_root, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
            f.write("\n")
        print(
            f"[prebuild-snapshot] {mission_name} ({repo}@{commit[:12]}): "
            f"{len(dep_graph)} deps + {len(target_modules)} frozen target(s) built in {elapsed_ms} ms",
            flush=True,
        )
        return True
    finally:
        tmp_ctx.cleanup()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("mission_dirs", nargs="+", help="Mission directories to inspect/prebuild")
    ap.add_argument("--upstream-dir", help="Use an existing local upstream checkout instead of cloning")
    ap.add_argument("--jobs", type=int, default=None, help="Parallel Lean compile workers")
    args = ap.parse_args()

    snapshot_base = sb.SNAPSHOT_CACHE_DIR
    os.makedirs(snapshot_base, exist_ok=True)
    built = 0
    for d in args.mission_dirs:
        if not os.path.isdir(d) or not os.path.isfile(os.path.join(d, "sunstead.json")):
            continue
        if prebuild_snapshot_mission(d, snapshot_base, upstream_dir=args.upstream_dir, jobs=args.jobs):
            built += 1
    if built == 0:
        sys.stderr.write("prebuild_snapshot.py: no repo-snapshot missions found\n")
        sys.exit(1)
    print(f"[prebuild-snapshot] prebuilt {built} repo-snapshot mission(s) into {snapshot_base}", flush=True)


if __name__ == "__main__":
    main()
