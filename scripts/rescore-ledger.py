#!/usr/bin/env python3
"""Replay accepted hill-climb awards from public data; never write to the hub."""

import argparse
import hashlib
import json
import math
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen

ORIGIN = "https://sunstead.org"
SUBMISSION_LIMIT = 200
RETIRED_DAG = {"onboarding-sandbox"}
RULE = "sunstead-scoring-v2"


def load_public(path):
    # No credentials and no write methods.
    request = Request(ORIGIN + "/api/" + path, headers={"User-Agent": "sunstead-rescore/1.0"})
    with urlopen(request, timeout=20) as response:
        return json.load(response)


def utc(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def accepted(submissions):
    # The endpoint has no cursor; do not present a truncated feed as all history.
    if len(submissions) >= SUBMISSION_LIMIT:
        raise ValueError("public submission feed is capped at 200; use a complete ledger export")
    return [row for row in submissions if row["accepted"]]


def collect():
    submissions = load_public(f"submissions?limit={SUBMISSION_LIMIT}")["submissions"]
    records = accepted(submissions)
    modes = {m["id"]: m["mode"] for m in load_public("missions")["missions"]}
    details = {}
    for mid in sorted({row["mission_id"] for row in records}):
        if modes.get(mid) == "hillclimb":
            details[mid] = load_public("missions/" + quote(mid, safe=""))
    return {
        "retrieved_at_utc": utc(datetime.now(timezone.utc).timestamp()),
        "submissions": submissions,
        "mission_modes": modes,
        "hillclimb_missions": details,
    }


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def better(direction, candidate, reference):
    return candidate < reference if direction == "minimize" else candidate > reference


def points(direction, previous, score, known):
    reference = previous if previous is not None and better(direction, previous, known) else known
    if better(direction, score, reference):
        if reference > 0 and score > 0:
            return math.floor(5000 * abs(math.log(score / reference)))
        return math.floor(5000 * (abs(score - reference) / max(abs(reference), 1)))
    if score == known:
        return 25
    return 10 if abs(score - known) / max(abs(known), 1) <= 0.05 else 0


def replay(snapshot):
    tasks = {}
    records = []
    submissions = accepted(snapshot["submissions"])
    ids = set()
    for row in submissions:
        if row["id"] in ids:
            raise ValueError(f"duplicate submission ID: {row['id']}")
        ids.add(row["id"])
        mid = row["mission_id"]
        mode = snapshot["mission_modes"].get(mid)
        if mode == "dag" or (mode is None and mid in RETIRED_DAG):
            continue
        if mode != "hillclimb":
            raise ValueError(f"unknown mission mode for accepted submission {mid}")
        if mid not in tasks:
            detail = snapshot["hillclimb_missions"][mid]
            manifest = detail["mission"]["manifest"]
            direction = manifest.get("score_direction", "maximize")
            if direction not in ("maximize", "minimize"):
                raise ValueError(f"unknown score direction for {mid}: {direction}")
            tasks[mid] = (direction, {task["def"]["id"]: task["def"] for task in detail["tasks"]})
        if row.get("completed_at") is None:
            raise ValueError(f"missing completion time for {row['id']}")
        records.append(row)

    # Replay in scoring (completion) order; same-second records on one task
    # must progress from weakest to strongest in that task's direction.
    def order(row):
        mid, tid = row["mission_id"], row["task_id"]
        score = row.get("score")
        if not finite(score):
            raise ValueError(f"expected a finite verified score for {row['id']}")
        return row["completed_at"], mid, tid, score if tasks[mid][0] == "maximize" else -score

    previous = {}
    result = []
    for row in sorted(records, key=order):
        mid, tid = row["mission_id"], row["task_id"]
        direction, defs = tasks[mid]
        task = defs[tid]
        demo = bool(row.get("is_demo") or snapshot["hillclimb_missions"][mid]["mission"]["manifest"].get("demo"))
        key = (mid, tid)
        baseline = task.get("baseline_score")
        prior = previous.get(key, baseline)
        score = row["score"]
        known = (task.get("best_known") or {}).get("value")
        if prior is not None and (not finite(prior) or not better(direction, score, prior)):
            raise ValueError(f"cannot replay {row['id']}: {key} score {score} does not improve on {prior}")
        if not demo and not finite(known):
            raise ValueError(f"no finite public best_known: {mid}/{tid}")
        award = 0 if demo else points(direction, prior, score, known)
        result.append({**row, "previous": prior, "best_known": known, "replayed": award})
        previous[key] = score
    return result


def snapshot_bytes(snapshot):
    return (json.dumps(snapshot, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")


def render(snapshot, records):
    digest = hashlib.sha256(snapshot_bytes(snapshot)).hexdigest()
    out = [
        "# Hill-climb scoring replay", "",
        f"Public snapshot captured {snapshot['retrieved_at_utc']} UTC (canonical JSON SHA-256: `{digest}`).",
        f"`/api/submissions?limit=200` returned {len(snapshot['submissions'])} rows; "
        f"{len(records)} were accepted hill-climb records.",
        f"Replayed with `{RULE}`, using current public task definitions and completion order. "
        "Only per-record awards are compared; no DAG or active-record crown points are included. "
        "This is a counterfactual, not a reconstruction of the scoring build used historically.", "",
        "| Completed (UTC) | Mission/task | Submission ID | Contributor | Previous | Best known | Score | Paid | Replayed | Δ |",
        "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    totals = defaultdict(lambda: [0, 0, 0])

    def cell(value):
        return "—" if value is None else str(value).replace("|", "\\|").replace("\n", " ")

    for row in records:
        delta = row["replayed"] - row["points"]
        out.append("| " + " | ".join(map(cell, (
            utc(row["completed_at"]), row["mission_id"] + "/" + row["task_id"],
            row["id"], row["contributor"], row["previous"], row["best_known"], row["score"],
            row["points"], row["replayed"], delta,
        ))) + " |")
        totals[row["contributor"]][0] += 1
        totals[row["contributor"]][1] += row["points"]
        totals[row["contributor"]][2] += row["replayed"]
    out.extend(["", "| Contributor | Records | Paid | Replayed | Δ |", "| --- | ---: | ---: | ---: | ---: |"])
    for name, (count, paid, replayed) in sorted(totals.items()):
        out.append(f"| {cell(name)} | {count} | {paid} | {replayed} | {replayed - paid} |")
    paid = sum(row["points"] for row in records)
    replayed = sum(row["replayed"] for row in records)
    out.append(f"| **Total** | **{len(records)}** | **{paid}** | **{replayed}** | **{replayed - paid}** |")
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group()
    inputs.add_argument("--snapshot", type=Path, help="replay previously saved JSON without network access")
    inputs.add_argument("--save-snapshot", type=Path, help="save the public input snapshot for offline replay")
    args = parser.parse_args()
    try:
        snapshot = json.loads(args.snapshot.read_text(encoding="utf-8")) if args.snapshot else collect()
        records = replay(snapshot)
        if args.save_snapshot:
            args.save_snapshot.write_bytes(snapshot_bytes(snapshot))
        print(render(snapshot, records))
    except (ValueError, KeyError, TypeError, OSError) as exc:
        parser.exit(1, f"Could not generate complete replay: {exc}\n")


if __name__ == "__main__":
    main()
