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
"""
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


def _extract_mission_config(mission_dir):
    """Capture the exact kwargs `verify` passes to `sunstead_sandbox.lean_verify`."""
    verify_path = os.path.join(mission_dir, "verify")
    if not os.path.isfile(verify_path):
        raise RuntimeError(f"missing verify script in {mission_dir}")

    captured = {}

    def _capture(task_id, *, lib_root, frozen_files, tasks,
                 uses_mathlib=False, statement_preamble="", timeout_sec=110):
        captured.update(
            lib_root=lib_root,
            frozen_files=list(frozen_files),
            tasks=dict(tasks),
            uses_mathlib=bool(uses_mathlib),
            statement_preamble=statement_preamble,
        )

    orig_verify = sb.lean_verify
    orig_argv = list(sys.argv)
    try:
        sb.lean_verify = _capture
        sys.argv = [verify_path, "__prebuild__"]
        runpy.run_path(verify_path, run_name="__main__")
    finally:
        sb.lean_verify = orig_verify
        sys.argv = orig_argv

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


def prebuild_mission(mission_dir, cache_base):
    started = time.monotonic()
    mission_name = os.path.basename(os.path.normpath(mission_dir))
    cfg = _extract_mission_config(mission_dir)
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

    cache_root = os.path.join(cache_base, cache_key)
    spec_dir = os.path.join(cache_root, "spec")
    trusted_dir = os.path.join(cache_root, "trusted")
    if os.path.exists(cache_root):
        shutil.rmtree(cache_root)
    os.makedirs(spec_dir, exist_ok=True)
    os.makedirs(trusted_dir, exist_ok=True)

    extra_lib_paths = sb._mathlib_lib_paths() if uses_mathlib else []

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
            # Hardlink each frozen `.olean` into `trusted/` so `trusted/` is a
            # complete single-root package directory for Lean's `LEAN_PATH` lookup
            # while `spec/` exposes only frozen spec modules (never statements).
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
        "frozen_modules": spec_order,
        "statements_module": f"{lib_root}.SunsteadStatements",
        "build_ms": elapsed_ms,
    }
    with open(os.path.join(cache_root, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    print(
        f"[prebuild-cache] {mission_name} ({lib_root}, mathlib={uses_mathlib}) "
        f"key={cache_key[:12]}... ({elapsed_ms} ms)",
        flush=True,
    )


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: prebuild_cache.py <mission_dir> [<mission_dir>...]\n")
        sys.exit(2)
    cache_base = sb.MISSION_CACHE_DIR
    os.makedirs(cache_base, exist_ok=True)
    built = 0
    for d in sys.argv[1:]:
        if not os.path.isdir(d) or not os.path.isfile(os.path.join(d, "verify")):
            continue
        prebuild_mission(d, cache_base)
        built += 1
    if built == 0:
        sys.stderr.write("prebuild_cache.py: no mission directories with a `verify` script found\n")
        sys.exit(1)
    print(f"[prebuild-cache] prebuilt {built} mission(s) into {cache_base}", flush=True)


if __name__ == "__main__":
    main()
