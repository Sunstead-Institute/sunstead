#!/usr/bin/env python3
"""Helper for .github/workflows/upstream-verify.yml.

Default: print `ids=<json list>` of ledger proofs that have a `verify_command`
(they mirror one upstream `sorry`); with the ledger from before verify_command
existed, fall back to non-demo, non-retired `proof` entries with an upstream
task URL. `ONLY=<id>` narrows it to one id.

`--report DIR`: read the per-proof result.json files under DIR and print a
Markdown summary table.
"""
import glob
import json
import os
import re
import sys
import urllib.request

HUB = os.environ.get("SUNSTEAD_HUB", "https://sunstead.org")
UA = {"User-Agent": "sunstead-upstream-verify/0.1"}


def eligible(p: dict) -> bool:
    if "verify_command" in p:
        return bool(p["verify_command"])
    return (
        p.get("entry_kind", "proof") == "proof"
        and not p.get("mission_demo")
        and not p.get("mission_retired")
        and bool((p.get("upstream") or {}).get("task_url"))
    )


def list_ids(ledger: dict, only: str = "") -> list:
    ids = [p["proof_id"] for p in ledger.get("proofs", []) if eligible(p)]
    ids = [i for i in ids if re.fullmatch(r"[0-9a-f]{64}", i or "")]
    if only:
        return [only] if re.fullmatch(r"[0-9a-f]{64}", only) else []
    return ids


def report(results_dir: str) -> str:
    rows = []
    for path in sorted(glob.glob(os.path.join(results_dir, "**", "result.json"), recursive=True)):
        with open(path, encoding="utf-8") as f:
            r = json.load(f)
        code = r.get("exit_code")
        status = {0: "✅ verified", 3: "➖ not upstream-checkable", 1: "❌ failed", 2: "⚠️ environment"}.get(code, f"? {code}")
        where = f"{r.get('upstream_repo', '?')}@{(r.get('upstream_commit') or '')[:12]}"
        decl = r.get("upstream_declaration") or (r.get("stderr_tail") or [""])[-1][:120]
        axioms = ", ".join(r.get("axioms") or []) if code == 0 else ""
        rows.append(f"| `{r.get('proof_id', '')[:12]}` | {status} | {where} | `{decl}` | {axioms} |")
    ok = sum(1 for r in rows if "✅" in r)
    head = [
        f"## Upstream verification: {ok}/{len(rows)} verified",
        "",
        "| proof | result | upstream | declaration / reason | axioms |",
        "|---|---|---|---|---|",
    ]
    return "\n".join(head + rows) + "\n"


def main(argv) -> int:
    if len(argv) >= 2 and argv[0] == "--report":
        print(report(argv[1]))
        return 0
    req = urllib.request.Request(f"{HUB}/api/proofs?limit=200", headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        ledger = json.loads(r.read().decode("utf-8"))
    print("ids=" + json.dumps(list_ids(ledger, os.environ.get("ONLY", "").strip())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
