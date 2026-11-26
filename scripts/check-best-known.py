#!/usr/bin/env python3
"""Check missions/best-known.json against the mission manifests.

Design principle (docs/BEST-KNOWN.md): every non-demo hill-climb task carries a
sourced best_known value, and full points are paid only for beating it. This
check fails CI when a task has no entry, an entry is malformed, an entry names a
task that does not exist, or a best_known is worse than the task's own seed.
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MISSIONS = os.path.join(ROOT, "missions")
KINDS = {"literature", "collection", "heuristic", "derived", "proxy", "record"}
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def load_manifests() -> dict[str, dict]:
    out = {}
    for name in sorted(os.listdir(MISSIONS)):
        path = os.path.join(MISSIONS, name, "sunstead.json")
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as f:
                m = json.load(f)
            out[m["id"]] = m
    return out


def check(registry: dict, manifests: dict[str, dict]) -> list[str]:
    errors: list[str] = []
    entries = registry.get("missions")
    if not isinstance(entries, dict):
        return ["best-known.json: top-level 'missions' object is missing"]
    for mid, tasks in entries.items():
        m = manifests.get(mid)
        if m is None or m.get("mode") != "hillclimb" or m.get("demo"):
            errors.append(f"{mid}: listed in best-known.json but not a non-demo hill-climb mission")
            continue
        ids = {t["id"] for t in m["tasks"]}
        for tid in tasks:
            if tid not in ids:
                errors.append(f"{mid}/{tid}: no such task in sunstead.json")
    for mid, m in manifests.items():
        if m.get("mode") != "hillclimb" or m.get("demo"):
            continue
        direction = m.get("score_direction", "maximize")
        for t in m["tasks"]:
            where = f"{mid}/{t['id']}"
            bk = entries.get(mid, {}).get(t["id"])
            if bk is None:
                errors.append(f"{where}: no best_known entry (every hill-climb task needs a sourced best known value)")
                continue
            if not isinstance(bk.get("value"), (int, float)) or isinstance(bk.get("value"), bool):
                errors.append(f"{where}: value must be a number")
                continue
            if bk.get("kind") not in KINDS:
                errors.append(f"{where}: kind must be one of {sorted(KINDS)}")
            if not isinstance(bk.get("source"), str) or len(bk["source"].strip()) < 20:
                errors.append(f"{where}: source must cite where the value comes from")
            if not isinstance(bk.get("url"), str) or not bk["url"].startswith("https://"):
                errors.append(f"{where}: url must be an https link to the source")
            if not isinstance(bk.get("checked"), str) or not DATE.match(bk["checked"]):
                errors.append(f"{where}: checked must be a YYYY-MM-DD date")
            if "proven_optimal" in bk and not isinstance(bk["proven_optimal"], bool):
                errors.append(f"{where}: proven_optimal must be a boolean")
            seed = t.get("baseline_score")
            if isinstance(seed, (int, float)):
                worse = bk["value"] > seed if direction == "minimize" else bk["value"] < seed
                if worse:
                    errors.append(f"{where}: best_known {bk['value']} is worse than the seed {seed}")
    return errors


def main() -> int:
    with open(os.path.join(MISSIONS, "best-known.json"), encoding="utf-8") as f:
        registry = json.load(f)
    errors = check(registry, load_manifests())
    for e in errors:
        print(f"error: {e}", file=sys.stderr)
    if errors:
        return 1
    n = sum(len(v) for v in registry["missions"].values())
    print(f"best-known.json OK: {n} hill-climb tasks have a sourced best known value")
    return 0


if __name__ == "__main__":
    sys.exit(main())
