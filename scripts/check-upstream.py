#!/usr/bin/env python3
"""
Verify upstream provenance for every non-demo Sunstead mission.

For every `missions/*/sunstead.json`:
- Non-demo missions MUST have an `UPSTREAM.json` and `upstream` metadata pinning
  `repo`, full 40-char `commit` SHA, and `license`.
- Every check in `UPSTREAM.json` fetches the pinned upstream file at
  `https://raw.githubusercontent.com/<repo>/<commit>/<upstream_file>` and checks
  that each frozen definition/statement snippet appears verbatim in both the
  upstream commit and the local mission file (and that upstream anchors exist).
"""
import argparse
import glob
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {"User-Agent": "sunstead-check-upstream/0.2"}
_CACHE = {}


def fetch_upstream(repo: str, commit: str, path: str) -> str:
    key = (repo, commit, path)
    if key not in _CACHE:
        url = f"https://raw.githubusercontent.com/{repo}/{commit}/{path}"
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            _CACHE[key] = r.read().decode("utf-8")
    return _CACHE[key]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mission", action="append", help="Check only specific mission id(s)")
    args = ap.parse_args()

    manifests = sorted(glob.glob(os.path.join(ROOT, "missions", "*", "sunstead.json")))
    failures = 0
    checked_missions = 0

    for mpath in manifests:
        mdir = os.path.dirname(mpath)
        mid = os.path.basename(mdir)
        if args.mission and mid not in args.mission:
            continue
        manifest = json.loads(open(mpath, encoding="utf-8").read())
        if manifest.get("demo"):
            print(f"[SKIP] {mid} (demo/sandbox mission, 0 leaderboard points)")
            continue

        checked_missions += 1
        problems = []
        up_meta = manifest.get("upstream")
        up_json_path = os.path.join(mdir, "UPSTREAM.json")
        if not up_meta:
            problems.append("non-demo mission missing `upstream` metadata in sunstead.json")
        if not os.path.isfile(up_json_path):
            problems.append("non-demo mission missing UPSTREAM.json")
        else:
            up = json.loads(open(up_json_path, encoding="utf-8").read())
            repo = up.get("repo", "")
            commit = up.get("commit", "")
            lic = up.get("license", "")
            if not re.fullmatch(r"[0-9a-f]{40}", commit):
                problems.append(f"UPSTREAM.json commit must be a 40-char hex SHA, got {commit!r}")
            if not lic:
                problems.append("UPSTREAM.json missing license")
            if up_meta and (
                up_meta.get("repo") != repo
                or up_meta.get("commit") != commit
                or up_meta.get("license") != lic
            ):
                problems.append("sunstead.json `upstream` does not match UPSTREAM.json")
            if "UPSTREAM.json" not in manifest.get("frozen_paths", []):
                problems.append("UPSTREAM.json must be listed in frozen_paths")

            checks = up.get("checks", [])
            if not checks:
                problems.append("UPSTREAM.json has no verbatim checks")
            for idx, chk in enumerate(checks):
                local_rel = chk["local_file"]
                up_rel = chk["upstream_file"]
                local_path = os.path.join(mdir, local_rel)
                if not os.path.isfile(local_path):
                    problems.append(f"check #{idx}: missing local file {local_rel}")
                    continue
                local_txt = open(local_path, encoding="utf-8").read()
                try:
                    up_txt = fetch_upstream(repo, commit, up_rel)
                except Exception as e:
                    problems.append(f"check #{idx}: failed to fetch {repo}@{commit[:7]}/{up_rel}: {e}")
                    continue
                snippet = chk.get("verbatim_snippet")
                if snippet:
                    if snippet not in up_txt:
                        problems.append(
                            f"check #{idx}: verbatim_snippet not found in upstream {up_rel}:\n"
                            f"  {snippet.splitlines()[0]!r}"
                        )
                    if snippet not in local_txt:
                        problems.append(
                            f"check #{idx}: verbatim_snippet not found in local {local_rel}:\n"
                            f"  {snippet.splitlines()[0]!r}"
                        )
                anchor = chk.get("upstream_anchor")
                if anchor and anchor not in up_txt:
                    problems.append(f"check #{idx}: upstream_anchor not found in {up_rel}: {anchor!r}")

        status = "OK" if not problems else "FAIL"
        print(f"[{status}] {mid} ({up_meta.get('repo') if up_meta else '?'}@{(up_meta or {}).get('commit', '')[:7]})")
        for p in problems:
            print(f"    {p}")
        if problems:
            failures += 1

    if checked_missions == 0:
        print("FAIL: no non-demo upstream missions found")
        sys.exit(1)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
