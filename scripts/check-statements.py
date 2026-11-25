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
    python3 scripts/check-statements.py --mission onboarding-sandbox

The sorry-accepting path (`check_seed_statement` in the harness) is only
reachable from this script: it swaps it in for `lean_verify` inside its own
container process. Mission `verify` entrypoints and the verifier server take
no option that reaches it.
"""
import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MISSIONS = os.path.join(ROOT, "missions")


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


def run_task(mission_dir, image, task_id, timeout):
    create = ["docker", "create", "--network=none", "--cpus=2", "--memory=6144m",
              "--pids-limit=512", "--user=0:0", "--cap-drop=ALL",
              "--cap-add=SETUID", "--cap-add=SETGID",
              "--security-opt=no-new-privileges", "--workdir=/work", image,
              "python3", "-I", "/tmp/check-statements.py", "--inside", task_id]
    cid = subprocess.run(create, capture_output=True, text=True, check=True).stdout.strip()
    try:
        subprocess.run(["docker", "cp", f"{mission_dir}/.", f"{cid}:/work"],
                       check=True, capture_output=True)
        subprocess.run(["docker", "cp", os.path.abspath(__file__), f"{cid}:/tmp/check-statements.py"],
                       check=True, capture_output=True)
        p = subprocess.run(["docker", "start", "-a", cid], capture_output=True, text=True,
                           timeout=timeout)
    finally:
        subprocess.run(["docker", "rm", "-f", cid], capture_output=True)
    for line in reversed(p.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except ValueError:
                pass
    return {"ok": False, "summary": f"no verdict: {(p.stdout + p.stderr)[-400:]}"}


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--inside":
        inside(sys.argv[2])
        return
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mission", action="append", help="only these missions (repeatable)")
    ap.add_argument("--exclude-mission", action="append", help="skip these missions (repeatable)")
    ap.add_argument("--timeout", type=int, default=900, help="seconds per task")
    args = ap.parse_args()

    failures = 0
    checked = 0
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
        for task in manifest["tasks"]:
            res = run_task(mission_dir, image, task["id"], args.timeout)
            checked += 1
            mark = "OK" if res.get("ok") else "FAIL"
            failures += 0 if res.get("ok") else 1
            print(f"[{mark}] {name}/{task['id']}: {res.get('summary', '')}", flush=True)
    if checked == 0:
        print("no tasks checked")
        sys.exit(1)
    print(f"\n{checked} task(s) checked, {failures} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
