#!/usr/bin/env python3
"""
Check that every mission's frozen task statements match its seed theorems.

The verifier enforces the `statement` strings in each mission's `verify`
TASKS: the kernel must accept `theorem _ : <statement> := <target theorem>`.
Nothing else ties those strings to the theorems contributors see in the seed
files. This script builds each mission's unmodified seed inside the verifier
image and runs the same kernel comparison for every task, accepting `sorry`
and `sorryAx` because seeds are unsolved.

    ./scripts/build-verifiers.sh
    python3 scripts/check-statements.py            # every mission, every task
    python3 scripts/check-statements.py --mission arklib-near-capacity-primes

Each mission runs all of its task checks inside a single batched verifier
container (one `docker create` + one `docker cp` per mission instead of one per
task), executing each task inside an isolated child Python process with its own
per-task timeout and fail-closed verdict parsing.

The sorry-accepting path (`check_seed_statement` in the harness) is only
reachable from this script: it swaps it in for `lean_verify` inside its own
container process. Mission `verify` entrypoints and the verifier server take
no option that reaches it.
"""
import argparse
import concurrent.futures
import glob
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MISSIONS = os.path.join(ROOT, "missions")
BATCH_RESULT_PREFIX = "SUNSTEAD_BATCH_RESULT "
JOB_TMP_DIR = "/tmp"


def _cleanup_job_tmp(tmp_dir=None):
    """Best-effort removal of leftover `/tmp/sunstead-job-*` scratch entries."""
    base = JOB_TMP_DIR if tmp_dir is None else tmp_dir
    for path in glob.glob(os.path.join(base, "sunstead-job-*")):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path, ignore_errors=True)
        else:
            try:
                os.unlink(path)
            except OSError:
                pass


def parse_verdict(stdout, stderr="", returncode=0):
    """Extract the last JSON verdict line from child output, failing closed."""
    out = stdout or ""
    err = stderr or ""
    for line in reversed(out.splitlines()):
        stripped = line.strip()
        if stripped.startswith("{"):
            try:
                obj = json.loads(stripped)
            except ValueError:
                continue
            if isinstance(obj, dict) and isinstance(obj.get("ok"), bool):
                if obj["ok"] and returncode != 0:
                    return {
                        "ok": False,
                        "summary": f"child exited {returncode} despite ok verdict: {obj.get('summary', '')}",
                    }
                return obj
    tail = (out + err)[-400:]
    return {"ok": False, "summary": f"no verdict (exit {returncode}): {tail}"}


def _cleanup_after_timeout():
    """Best-effort cleanup inside the container after a per-task child times out."""
    try:
        if "/opt/sunstead" not in sys.path:
            sys.path.insert(0, "/opt/sunstead")
        import sunstead_sandbox
        for user in (
            getattr(sunstead_sandbox, "RUNNER_USER", None),
            getattr(sunstead_sandbox, "CHECKER_USER", None),
        ):
            if user:
                try:
                    sunstead_sandbox.ensure_no_processes(user)
                except Exception:
                    pass
    except Exception:
        pass
    _cleanup_job_tmp()


def _maybe_warm_mission_cache(task_timeout):
    """Best-effort prebuild of frozen `.olean` cache inside the ephemeral batch container.

    On a multi-task classic mission whose cache was not yet baked into the image,
    this compiles `<Lib>.Spec` + `<Lib>.SunsteadStatements` once instead of once
    per task. Failures are ignored so every task still runs its own fail-closed
    `--inside <task_id>` verification.
    """
    prebuild = "/opt/sunstead/prebuild_cache.py"
    if not os.path.isfile(prebuild):
        return
    manifest_path = "/work/sunstead.json"
    if os.path.isfile(manifest_path):
        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                manifest = json.load(f)
            if (manifest.get("snapshot") or {}).get("mode") == "repo-snapshot":
                return
        except (OSError, ValueError):
            return
    try:
        subprocess.run(
            [sys.executable, "-I", prebuild, "/work"],
            cwd="/work",
            capture_output=True,
            text=True,
            timeout=task_timeout,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def inside(task_id):
    """Container side: run the mission's own `verify` with the CI-only check."""
    sys.path.insert(0, "/opt/sunstead")
    import runpy
    import sunstead_sandbox

    sunstead_sandbox.lean_verify = sunstead_sandbox.check_seed_statement
    sunstead_sandbox.lean_repo_snapshot_verify = sunstead_sandbox.check_seed_repo_snapshot
    sys.argv = ["./verify", task_id]
    runpy.run_path("/work/verify", run_name="__main__")
    sunstead_sandbox.emit(False, "verify exited without a verdict")


def inside_batch(task_ids, task_timeout, *, workdir="/work", script_path=None):
    """Container side: verify a batch of tasks inside isolated child processes."""
    script = script_path or os.path.abspath(__file__)
    if len(task_ids) > 1 and workdir == "/work":
        _maybe_warm_mission_cache(task_timeout)
    for task_id in task_ids:
        try:
            p = subprocess.run(
                [sys.executable, "-I", script, "--inside", task_id],
                cwd=workdir,
                capture_output=True,
                text=True,
                timeout=task_timeout,
            )
            verdict = parse_verdict(p.stdout, p.stderr, returncode=p.returncode)
            if not verdict.get("ok"):
                _cleanup_job_tmp()
        except subprocess.TimeoutExpired:
            _cleanup_after_timeout()
            verdict = {"ok": False, "summary": f"timed out after {task_timeout}s"}
        record = {"task_id": task_id, "verdict": verdict}
        print(BATCH_RESULT_PREFIX + json.dumps(record, sort_keys=True), flush=True)


def _as_text(val):
    if val is None:
        return ""
    if isinstance(val, bytes):
        return val.decode("utf-8", errors="replace")
    return str(val)


def parse_batch_output(stdout, stderr, task_ids, returncode=0, timeout_summary=None):
    """Parse structured per-task verdicts from a batched container run, failing closed."""
    expected = set(task_ids)
    parsed = {}
    duplicates = set()
    for line in (stdout or "").splitlines():
        if not line.startswith(BATCH_RESULT_PREFIX):
            continue
        raw = line[len(BATCH_RESULT_PREFIX):].strip()
        try:
            rec = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(rec, dict):
            continue
        tid = rec.get("task_id")
        verdict = rec.get("verdict")
        if (not isinstance(tid, str) or tid not in expected
                or not isinstance(verdict, dict)
                or not isinstance(verdict.get("ok"), bool)):
            continue
        if tid in parsed:
            duplicates.add(tid)
        else:
            parsed[tid] = verdict

    tail = ((stdout or "") + (stderr or ""))[-400:]
    out = []
    for tid in task_ids:
        if tid in duplicates:
            out.append((tid, {"ok": False, "summary": f"duplicate batch verdict for {tid}"}))
        elif tid in parsed:
            out.append((tid, parsed[tid]))
        elif timeout_summary:
            out.append((tid, {"ok": False, "summary": timeout_summary}))
        else:
            out.append((tid, {"ok": False, "summary": f"missing batch verdict (exit {returncode}): {tail}"}))
    return out


def _run_batch_chunk(mission_dir, image, chunk, timeout):
    create = [
        "docker", "create", "--network=none", "--cpus=2", "--memory=6144m",
        "--pids-limit=512", "--user=0:0", "--cap-drop=ALL",
        "--cap-add=SETUID", "--cap-add=SETGID",
        "--security-opt=no-new-privileges", "--workdir=/work", image,
        "python3", "-I", "/tmp/check-statements.py", "--inside-batch", str(timeout), *chunk,
    ]
    cid = subprocess.run(create, capture_output=True, text=True, check=True).stdout.strip()
    outer_timeout = max(timeout, timeout * len(chunk)) + 60
    try:
        subprocess.run(["docker", "cp", f"{mission_dir}/.", f"{cid}:/work"],
                       check=True, capture_output=True)
        subprocess.run(["docker", "cp", os.path.abspath(__file__), f"{cid}:/tmp/check-statements.py"],
                       check=True, capture_output=True)
        try:
            p = subprocess.run(["docker", "start", "-a", cid], capture_output=True, text=True,
                               timeout=outer_timeout)
            return parse_batch_output(p.stdout, p.stderr, chunk, returncode=p.returncode)
        except subprocess.TimeoutExpired as exc:
            return parse_batch_output(
                _as_text(exc.stdout),
                _as_text(exc.stderr),
                chunk,
                returncode=-1,
                timeout_summary=f"batch container timed out after {outer_timeout}s",
            )
    finally:
        subprocess.run(["docker", "rm", "-f", cid], capture_output=True)


def build_work_chunks(work, batch_size=0):
    """Expand mission work items into container chunks ordered largest-first.

    Each input item is `(mission_name, mission_dir, image, task_ids)`.
    Returns `(mission_name, mission_dir, image, chunk_idx, chunk_task_ids)` sorted
    by `(-len(chunk), mission_name, chunk_idx)` for parallel work-stealing across
    large multi-task arenas.
    """
    chunks = []
    for name, mission_dir, image, task_ids in work:
        ids = list(task_ids)
        if not ids:
            continue
        step = batch_size if batch_size and batch_size > 0 else len(ids)
        for chunk_idx, i in enumerate(range(0, len(ids), step)):
            chunks.append((name, mission_dir, image, chunk_idx, ids[i:i + step]))
    chunks.sort(key=lambda item: (-len(item[4]), item[0], item[3]))
    return chunks


def run_mission_batch(mission_dir, image, task_ids, timeout, batch_size=0):
    """Verify all `task_ids` of one mission in a single container (or chunks of `batch_size`)."""
    ids = list(task_ids)
    if not ids:
        return []
    step = batch_size if batch_size and batch_size > 0 else len(ids)
    results = []
    for i in range(0, len(ids), step):
        results.extend(_run_batch_chunk(mission_dir, image, ids[i:i + step], timeout))
    return results


def run_task(mission_dir, image, task_id, timeout):
    """Single-task compatibility wrapper backed by `run_mission_batch`."""
    return run_mission_batch(mission_dir, image, [task_id], timeout)[0][1]


def main(argv=None):
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    if len(raw_argv) == 2 and raw_argv[0] == "--inside":
        inside(raw_argv[1])
        return
    if len(raw_argv) >= 2 and raw_argv[0] == "--inside-batch":
        task_timeout = int(raw_argv[1])
        inside_batch(raw_argv[2:], task_timeout)
        return

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mission", action="append", help="only these missions (repeatable)")
    ap.add_argument("--exclude-mission", action="append", help="skip these missions (repeatable)")
    ap.add_argument("--image", action="append", help="only missions targeting these verifier image(s) (repeatable)")
    ap.add_argument("--timeout", type=int, default=900, help="seconds per task")
    ap.add_argument("--batch-size", type=int, default=0,
                    help="max tasks per container (0 = all tasks of a mission in one container)")
    ap.add_argument("--jobs", type=int, default=1,
                    help="parallel verifier containers across missions/chunks (default: 1)")
    args = ap.parse_args(raw_argv)
    if args.timeout <= 0:
        ap.error("--timeout must be positive")
    if args.batch_size < 0:
        ap.error("--batch-size must be >= 0")
    if args.jobs <= 0:
        ap.error("--jobs must be positive")

    work = []
    for name in sorted(os.listdir(MISSIONS)):
        mission_dir = os.path.join(MISSIONS, name)
        manifest_path = os.path.join(mission_dir, "sunstead.json")
        if (not os.path.isfile(manifest_path)
                or (args.mission and name not in args.mission)
                or (args.exclude_mission and name in args.exclude_mission)):
            continue
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        image = manifest["verifier"]["image"]
        if args.image and image not in args.image:
            continue
        task_ids = [task["id"] for task in manifest["tasks"]]
        if not task_ids:
            continue
        work.append((name, mission_dir, image, task_ids))

    if not work:
        print("no tasks checked")
        sys.exit(1)

    failures = 0
    checked = 0

    def _emit_mission(name, results):
        nonlocal checked, failures
        for task_id, res in results:
            checked += 1
            mark = "OK" if res.get("ok") else "FAIL"
            failures += 0 if res.get("ok") else 1
            print(f"[{mark}] {name}/{task_id}: {res.get('summary', '')}", flush=True)

    if args.batch_size > 0:
        chunks = build_work_chunks(work, args.batch_size)
        workers = min(args.jobs, len(chunks))
        if workers <= 1:
            for name, mission_dir, image, _chunk_idx, chunk in chunks:
                _emit_mission(name, _run_batch_chunk(mission_dir, image, chunk, args.timeout))
        else:
            with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
                futs = {
                    pool.submit(
                        _run_batch_chunk,
                        mission_dir,
                        image,
                        chunk,
                        args.timeout,
                    ): name
                    for name, mission_dir, image, _chunk_idx, chunk in chunks
                }
                for fut in concurrent.futures.as_completed(futs):
                    _emit_mission(futs[fut], fut.result())
    else:
        workers = min(args.jobs, len(work))
        if workers <= 1:
            for name, mission_dir, image, task_ids in work:
                _emit_mission(
                    name,
                    run_mission_batch(
                        mission_dir, image, task_ids, args.timeout, batch_size=0
                    ),
                )
        else:
            # Longest-processing-time-first (most tasks first) minimizes tail latency.
            ordered = sorted(work, key=lambda item: (-len(item[3]), item[0]))
            with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
                futs = {
                    pool.submit(
                        run_mission_batch,
                        mission_dir,
                        image,
                        task_ids,
                        args.timeout,
                        batch_size=0,
                    ): name
                    for name, mission_dir, image, task_ids in ordered
                }
                for fut in concurrent.futures.as_completed(futs):
                    _emit_mission(futs[fut], fut.result())

    if checked == 0:
        print("no tasks checked")
        sys.exit(1)
    print(f"\n{checked} task(s) checked, {failures} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
