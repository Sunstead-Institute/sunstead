#!/usr/bin/env python3
"""Build-time precompiler for Sunstead frozen mission `.olean` caches.

Invoked inside the verifier Dockerfiles to prebuild read-only `<Lib>.Spec.olean`
(and any other frozen `<Lib>.*.lean` modules) plus `<Lib>.SunsteadStatements.olean`
under `/opt/sunstead/mission-cache/<sha256>/`.

Each cache directory is keyed by `sunstead_sandbox.trusted_cache_key(...)`, a
SHA-256 over the exact `lib_root`, `uses_mathlib`, every frozen file's contents,
and the generated `SunsteadStatements.lean` source. At verify time,
`sunstead_sandbox.py` only reuses a cache entry when the live `/work` tree
produces the exact same SHA-256, falling back seamlessly to live trusted
compilation for modified or synthetic trees.

Scaling features for 50+ missions / 1,000+ tasks:
- Cleanly skips repo-snapshot missions (which are built by `prebuild_snapshot.py`)
  so directory-wide invocations (`prebuild_cache.py /missions` or `/missions/*`)
  work without per-mission Dockerfile boilerplate.
- Optional `--toolchain <tc>` filter selects only missions targeting that Lean
  toolchain (defaulting to `leanprover/lean4:v4.36.0` when omitted in manifest).
- Parallel mission compilation via `--jobs N`, cache-key deduplication, and
  atomic temp-dir publishing so identical frozen specs never build twice or race.
"""
import argparse
import concurrent.futures
import json
import os
import runpy
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sunstead_sandbox as sb  # noqa: E402

DEFAULT_TOOLCHAIN = "leanprover/lean4:v4.36.0"


def _mission_manifest(mission_dir):
    manifest_path = os.path.join(mission_dir, "sunstead.json")
    if not os.path.isfile(manifest_path):
        return None
    with open(manifest_path, "r", encoding="utf-8") as f:
        return json.load(f)


def _mission_toolchain(manifest):
    if not isinstance(manifest, dict):
        return DEFAULT_TOOLCHAIN
    ver = manifest.get("verifier") or {}
    tc = (ver.get("toolchain") or "").strip()
    if tc:
        return tc
    img = (ver.get("image") or "").strip()
    if "lean4-v4.35.0" in img:
        return "leanprover/lean4:v4.35.0"
    if "lean4-v4.31.0" in img:
        return "leanprover/lean4:v4.31.0"
    return DEFAULT_TOOLCHAIN


def _is_repo_snapshot_mission(manifest):
    if not isinstance(manifest, dict):
        return False
    return (manifest.get("snapshot") or {}).get("mode") == "repo-snapshot"


def discover_mission_dirs(paths, toolchain=None):
    """Expand explicit mission dirs or parent directories (e.g. `/missions`) into
    sorted classic (non-repo-snapshot) mission directories matching `toolchain`."""
    candidates = []
    for raw in paths:
        if not os.path.isdir(raw):
            continue
        if os.path.isfile(os.path.join(raw, "verify")):
            candidates.append(raw)
            continue
        # Parent directory scan (e.g. `/missions`): inspect direct children.
        for name in sorted(os.listdir(raw)):
            child = os.path.join(raw, name)
            if os.path.isdir(child) and os.path.isfile(os.path.join(child, "verify")):
                candidates.append(child)

    selected = []
    seen = set()
    want_tc = toolchain.strip() if toolchain else None
    for d in candidates:
        norm = os.path.abspath(d)
        if norm in seen:
            continue
        seen.add(norm)
        manifest = _mission_manifest(d)
        if _is_repo_snapshot_mission(manifest):
            continue
        if want_tc and _mission_toolchain(manifest) != want_tc:
            continue
        selected.append(d)
    return selected


def _extract_mission_config(mission_dir):
    """Capture the exact kwargs `verify` passes to `sunstead_sandbox.lean_verify`.

    Returns `None` if `verify` invokes `lean_repo_snapshot_verify` instead.
    Must be called on the main thread (temporarily hooks `sys.argv` / `sb.lean_verify`).
    """
    verify_path = os.path.join(mission_dir, "verify")
    if not os.path.isfile(verify_path):
        raise RuntimeError(f"missing verify script in {mission_dir}")

    captured = {}
    is_snapshot = [False]

    def _capture(task_id, *, lib_root, frozen_files, tasks,
                 uses_mathlib=False, statement_preamble="", timeout_sec=110):
        captured.update(
            lib_root=lib_root,
            frozen_files=list(frozen_files),
            tasks=dict(tasks),
            uses_mathlib=bool(uses_mathlib),
            statement_preamble=statement_preamble,
        )

    def _capture_snapshot(*args, **kwargs):
        is_snapshot[0] = True

    orig_verify = sb.lean_verify
    orig_snap = getattr(sb, "lean_repo_snapshot_verify", None)
    orig_argv = list(sys.argv)
    try:
        sb.lean_verify = _capture
        if orig_snap is not None:
            sb.lean_repo_snapshot_verify = _capture_snapshot
        sys.argv = [verify_path, "__prebuild__"]
        runpy.run_path(verify_path, run_name="__main__")
    finally:
        sb.lean_verify = orig_verify
        if orig_snap is not None:
            sb.lean_repo_snapshot_verify = orig_snap
        sys.argv = orig_argv

    if is_snapshot[0]:
        return None
    if not captured:
        raise RuntimeError(f"{verify_path} did not invoke lean_verify")
    return captured


def _compile_module(project_dir, mod, out_dir, lean_path):
    segs = sb._validate_mod_name(mod)
    rel_src = os.path.join(*segs) + ".lean"
    out_olean = os.path.join(out_dir, *segs) + ".olean"
    os.makedirs(os.path.dirname(out_olean), exist_ok=True)
    env = os.environ.copy()
    env["LEAN_PATH"] = lean_path
    proc = subprocess.run(
        ["lean", f"--root={project_dir}", "-o", out_olean, rel_src],
        cwd=project_dir,
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"failed to prebuild {mod} in {project_dir}:\n{proc.stdout}\n{proc.stderr}"
        )
    if not os.path.isfile(out_olean):
        raise RuntimeError(f"expected .olean not written: {out_olean}")
    return out_olean


def _cache_entry_complete(cache_root, lib_root, frozen_mods):
    """True when `cache_root` already contains all expected prebuilt `.olean`s and manifest."""
    if not os.path.isfile(os.path.join(cache_root, "manifest.json")):
        return False
    spec_dir = os.path.join(cache_root, "spec")
    trusted_dir = os.path.join(cache_root, "trusted")
    for mod in frozen_mods:
        segs = sb._validate_mod_name(mod)
        if not os.path.isfile(os.path.join(spec_dir, *segs) + ".olean"):
            return False
        if not os.path.isfile(os.path.join(trusted_dir, *segs) + ".olean"):
            return False
    stmts_segs = sb._validate_mod_name(f"{lib_root}.SunsteadStatements")
    return os.path.isfile(os.path.join(trusted_dir, *stmts_segs) + ".olean")


def prepare_mission_plan(mission_dir):
    """Extract config and compute deterministic `cache_key` for one classic mission.
    Returns `None` for repo-snapshot missions."""
    mission_name = os.path.basename(os.path.normpath(mission_dir))
    manifest = _mission_manifest(mission_dir)
    if _is_repo_snapshot_mission(manifest):
        return None
    cfg = _extract_mission_config(mission_dir)
    if cfg is None:
        return None
    lib_root = cfg["lib_root"]
    frozen_files = cfg["frozen_files"]
    tasks = cfg["tasks"]
    uses_mathlib = cfg["uses_mathlib"]
    statement_preamble = cfg["statement_preamble"]

    frozen_contents = {}
    for rel in frozen_files:
        src = os.path.join(mission_dir, rel)
        if not os.path.isfile(src):
            continue
        with open(src, "r", encoding="utf-8") as f:
            frozen_contents[rel] = f.read()

    stmts = {tid: t["statement"] for tid, t in tasks.items()}
    statements_src = sb._statements_module_source(
        lib_root, stmts, preamble=statement_preamble
    )
    cache_key = sb.trusted_cache_key(
        lib_root, uses_mathlib, frozen_contents, statements_src
    )
    frozen_mods = sb._frozen_lean_modules(lib_root, frozen_contents.keys())
    if not frozen_mods:
        raise RuntimeError(f"{mission_name}: no frozen Lean modules found under {lib_root}/")
    return {
        "mission_name": mission_name,
        "mission_dir": mission_dir,
        "lib_root": lib_root,
        "uses_mathlib": uses_mathlib,
        "frozen_contents": frozen_contents,
        "statements_src": statements_src,
        "frozen_mods": frozen_mods,
        "cache_key": cache_key,
        "task_count": len(tasks),
    }


def build_mission_plan(plan, cache_base, *, force=False):
    """Compile a prepared mission plan into `cache_base/<cache_key>/` atomically."""
    started = time.monotonic()
    mission_name = plan["mission_name"]
    lib_root = plan["lib_root"]
    uses_mathlib = plan["uses_mathlib"]
    frozen_contents = plan["frozen_contents"]
    statements_src = plan["statements_src"]
    frozen_mods = plan["frozen_mods"]
    cache_key = plan["cache_key"]
    cache_root = os.path.join(cache_base, cache_key)

    if not force and _cache_entry_complete(cache_root, lib_root, frozen_mods):
        print(
            f"[prebuild-cache] {mission_name} ({lib_root}, {plan['task_count']} tasks) "
            f"key={cache_key[:12]}... (cached)",
            flush=True,
        )
        return "cached"

    extra_lib_paths = sb._mathlib_lib_paths() if uses_mathlib else []
    stage_root = tempfile.mkdtemp(prefix=f".stage-{cache_key[:12]}-", dir=cache_base)
    spec_dir = os.path.join(stage_root, "spec")
    trusted_dir = os.path.join(stage_root, "trusted")
    os.makedirs(spec_dir, exist_ok=True)
    os.makedirs(trusted_dir, exist_ok=True)

    try:
        with tempfile.TemporaryDirectory(prefix="sunstead-prebuild-") as tmp:
            for rel, content in frozen_contents.items():
                dst = os.path.join(tmp, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(dst, "w", encoding="utf-8") as f:
                    f.write(content)
            stmts_path = os.path.join(tmp, lib_root, "SunsteadStatements.lean")
            os.makedirs(os.path.dirname(stmts_path), exist_ok=True)
            with open(stmts_path, "w", encoding="utf-8") as f:
                f.write(statements_src)

            # Build frozen spec modules in dependency order into `spec/`.
            spec_order = sb._resolve_local_build_order(tmp, lib_root, frozen_mods)
            spec_lean_path = ":".join([spec_dir] + extra_lib_paths)
            for mod in spec_order:
                out_olean = _compile_module(tmp, mod, spec_dir, spec_lean_path)
                rel_olean = os.path.relpath(out_olean, spec_dir)
                trusted_olean = os.path.join(trusted_dir, rel_olean)
                os.makedirs(os.path.dirname(trusted_olean), exist_ok=True)
                os.link(out_olean, trusted_olean)

            # Build SunsteadStatements inside `trusted/` (which already contains Spec.olean).
            stmts_mod = f"{lib_root}.SunsteadStatements"
            trusted_lean_path = ":".join([trusted_dir] + extra_lib_paths)
            _compile_module(tmp, stmts_mod, trusted_dir, trusted_lean_path)

        elapsed_ms = int((time.monotonic() - started) * 1000)
        meta = {
            "mission": mission_name,
            "cache_key": cache_key,
            "lib_root": lib_root,
            "uses_mathlib": uses_mathlib,
            "task_count": plan["task_count"],
            "frozen_modules": spec_order,
            "statements_module": f"{lib_root}.SunsteadStatements",
            "build_ms": elapsed_ms,
        }
        with open(os.path.join(stage_root, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
            f.write("\n")

        if os.path.exists(cache_root):
            shutil.rmtree(cache_root)
        os.replace(stage_root, cache_root)
    except Exception:
        shutil.rmtree(stage_root, ignore_errors=True)
        raise

    print(
        f"[prebuild-cache] {mission_name} ({lib_root}, {plan['task_count']} tasks, mathlib={uses_mathlib}) "
        f"key={cache_key[:12]}... ({elapsed_ms} ms)",
        flush=True,
    )
    return "built"


def prebuild_mission(mission_dir, cache_base, *, force=False):
    plan = prepare_mission_plan(mission_dir)
    if plan is None:
        return None
    return build_mission_plan(plan, cache_base, force=force)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("mission_dirs", nargs="+", help="Mission directories (or parent missions root)")
    ap.add_argument("--toolchain", default=None, help="Only prebuild classic missions targeting this toolchain")
    ap.add_argument(
        "--jobs", type=int, default=max(1, min(os.cpu_count() or 2, 4)),
        help="Parallel Lean compile workers across missions (default: min(cpus, 4))",
    )
    ap.add_argument("--force", action="store_true", help="Rebuild even if cache entry already exists")
    args = ap.parse_args(argv)

    cache_base = sb.MISSION_CACHE_DIR
    os.makedirs(cache_base, exist_ok=True)
    selected = discover_mission_dirs(args.mission_dirs, toolchain=args.toolchain)

    # Extract all configs sequentially on the main thread (safe around sys.argv/monkeypatching)
    # and deduplicate identical cache keys before compiling in parallel.
    plans_by_key = {}
    for d in selected:
        plan = prepare_mission_plan(d)
        if plan is None:
            continue
        plans_by_key.setdefault(plan["cache_key"], plan)

    plans = list(plans_by_key.values())
    if not plans:
        sys.stderr.write("prebuild_cache.py: no classic mission directories with a `verify` script found\n")
        sys.exit(1)

    workers = max(1, min(int(args.jobs), len(plans)))
    built = 0
    cached = 0
    if workers == 1:
        for plan in plans:
            status = build_mission_plan(plan, cache_base, force=args.force)
            built += 1 if status == "built" else 0
            cached += 1 if status == "cached" else 0
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
            futs = [ex.submit(build_mission_plan, plan, cache_base, force=args.force) for plan in plans]
            for fut in concurrent.futures.as_completed(futs):
                status = fut.result()
                built += 1 if status == "built" else 0
                cached += 1 if status == "cached" else 0

    print(
        f"[prebuild-cache] ready: {built} built, {cached} cached ({len(plans)} unique cache key(s), {workers} worker(s)) in {cache_base}",
        flush=True,
    )


if __name__ == "__main__":
    main()
