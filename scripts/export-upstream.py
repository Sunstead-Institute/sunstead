#!/usr/bin/env python3
"""Prepare a reviewable upstream PR bundle for one verified Sunstead proof.

Maintainer tool. It never pushes, never opens a pull request and never writes
inside this repository: everything happens in a temporary directory, and the
result is a bundle directory a maintainer reads before deciding to send anything.

What it does, for one accepted proof (by ledger id, or a saved ledger JSON):

1. Loads the mission's `sunstead.json`, `UPSTREAM.json` and `verify` (for the
   task's theorem name) and checks the task's `upstream_url` points into the
   pinned upstream commit.
2. Applies the accepted patch to a scratch copy of the mission's seed files and
   pulls out of the proved target file: the theorem's proof, any helper
   declarations the contributor added, and any new `import` lines.
3. Fetches the *full* upstream repository at the pinned 40-character commit into
   a scratch directory, finds the upstream declaration at the `sorry` the task
   mirrors, checks its statement matches the mission's frozen statement, and
   replaces its proof with the Sunstead one (helpers go just above it).
4. Unless `--no-build`: runs `lake exe cache get` and `lake build <module>` on the
   full upstream checkout, fails if that declaration still uses `sorry`, checks
   its axioms (read by a standalone `collectAxioms` checker, not `#print axioms`)
   are only propext, Classical.choice and Quot.sound, and runs
   each `--lint-cmd` given.
5. Writes `<out>/upstream.patch` (git diff against the pinned commit),
   `PR_BODY.md` (attribution, Sunstead permalink, checks run), `metadata.json`
   and `build.log`.

Usage:
    python3 scripts/export-upstream.py --proof-id <64 hex> --out /tmp/export-bundle
    python3 scripts/export-upstream.py --proof-json proof.json --out /tmp/b --no-build

`--hub` (default https://sunstead.org) is only read with GET /api/proofs/<id>.
"""
import argparse
import json
import os
import re
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
# The statement matching, proof splicing, build and axiom checks are shared with
# the public verifier (served as https://sunstead.org/verify.py) so the two can
# never disagree about what "this proof closes that upstream sorry" means.
import sunstead_verify as sv  # noqa: E402
from sunstead_verify import (  # noqa: E402,F401  (re-exported for tests)
    AXIOM_CHECKER, GIT, build_and_check, extract_contribution, fetch_upstream,
    lean_module, load_mission, parse_upstream_url, proved_file, read, run, short, transplant,
    verify_theorems,
)

ExportError = sv.VerifyError


# ---------------------------------------------------------------- inputs

def load_proof(args) -> dict:
    if args.proof_json:
        with open(args.proof_json, encoding="utf-8") as f:
            return json.load(f)
    return sv.load_public_proof(args.hub, args.proof_id)  # also checks sha256(patch) == id


# ---------------------------------------------------------------- bundle

def inside_repo(path: str) -> bool:
    real = os.path.realpath(path)
    return real == ROOT or real.startswith(ROOT + os.sep)


def pr_body(proof: dict, mission: dict, decl_name: str, contrib: dict, checks: dict, built: bool) -> str:
    up = mission["upstream"]
    who = proof.get("display_name") or proof.get("contributor")
    gh = f" (@{proof['github']})" if proof.get("github") else ""
    lines = [
        f"Proof of `{decl_name}` (`{mission['upstream_path']}`), closing the `sorry` at",
        f"{mission['task'].get('upstream_url')}.",
        "",
        f"Contributed by {who}{gh} through Sunstead and checked there by the Lean kernel",
        f"against a verbatim copy of this statement at `{up['commit']}`:",
        f"{proof.get('permalink', '')}",
        "",
        "## Checks run on the full repository at the pinned commit",
    ]
    if built:
        lines += [
            f"- `lake build {lean_module(mission['upstream_path'])}`: ok",
            f"- Axioms of `{decl_name}` (collectAxioms on the built module): {', '.join(checks.get('axioms') or []) or 'none'}",
        ]
        for l in checks.get("lint", []):
            lines.append(f"- `{l['cmd']}`: {'ok' if l['ok'] else 'FAILED'}")
    else:
        lines.append("- Not built (`--no-build`). Build before sending.")
    if contrib["helper_names"]:
        lines += ["", "Helper lemmas added above it: " + ", ".join(f"`{short(n)}`" for n in contrib["helper_names"])]
    if contrib["new_imports"]:
        lines += ["", "New imports: " + ", ".join(f"`{m}`" for m in contrib["new_imports"])]
    lines += ["", f"Rebased against the pinned commit `{up['commit']}`; rebase onto current `main` before opening."]
    return "\n".join(lines) + "\n"


def export(args) -> dict:
    out = os.path.abspath(args.out)
    if inside_repo(out):
        raise ExportError(f"--out {out} is inside the Sunstead repo; bundles contain solutions, write them elsewhere")
    if os.path.exists(out) and os.listdir(out):
        raise ExportError(f"--out {out} exists and is not empty")
    proof = load_proof(args)
    mission = load_mission(args.missions_root, proof)
    if proof.get("spec_is_current") is False and not args.allow_stale_spec:
        raise ExportError("proof was accepted under an earlier frozen spec; pass --allow-stale-spec after checking it")
    if not proof.get("patch"):
        raise ExportError("proof JSON has no patch")
    warnings = []
    log: list = []
    try:
        with tempfile.TemporaryDirectory(prefix="sunstead-export-") as scratch:
            seed, proved = proved_file(mission, proof["patch"], scratch)
            contrib = extract_contribution(seed, proved, mission["theorem"])
            if not mission["is_repo_snapshot"]:
                lib_root = mission["theorem"].split(".")[0]
                transplanted = "\n".join(contrib["helpers"] + [contrib["proof"]])
                if re.search(rf"(?<![\w.]){re.escape(lib_root)}\.", transplanted):
                    warnings.append(f"proof text refers to the mission namespace `{lib_root}.`; rename to upstream names before sending")
                if any(m.split(".")[0] == lib_root for m in contrib["new_imports"]):
                    raise ExportError("proof imports another mission module; export its dependency first")
            if contrib["after_target"]:
                warnings.append(f"declarations added after the theorem are not exported: {contrib['after_target']}")
            try:
                sv.check_no_metaprogramming(contrib)
            except ExportError as e:
                warnings.append(str(e).split(". Read the patch")[0] + "; review it before sending")
            if contrib["new_opens"]:
                warnings.append(f"the proved file adds `open` lines; add what the proof needs upstream by hand: {contrib['new_opens']}")
            updir = os.path.join(scratch, "upstream")
            repo_url = args.upstream_url or f"https://github.com/{mission['upstream']['repo']}.git"
            fetch_upstream(repo_url, mission["upstream"]["commit"], updir, log)
            target = os.path.join(updir, mission["upstream_path"])
            if not os.path.isfile(target):
                raise ExportError(f"{mission['upstream_path']} not in upstream at the pinned commit")
            src = read(target)
            new_src, decl, span = transplant(src, mission, contrib)
            with open(target, "w", encoding="utf-8") as f:
                f.write(new_src)
            checks = {}
            if not args.no_build:
                checks = build_and_check(updir, mission, decl.name, args.lint_cmd or [], log, scratch)
                if any(span[0] <= ln <= span[1] for ln in checks["sorry_warnings_in_file"]):
                    raise ExportError(f"{decl.name} (or a helper) still reports `sorry` after the build")
            diff = run([*GIT, "diff", "--no-color"], updir).stdout
            os.makedirs(out, exist_ok=True)
            with open(os.path.join(out, "upstream.patch"), "w", encoding="utf-8") as f:
                f.write(diff)
            with open(os.path.join(out, "build.log"), "w", encoding="utf-8") as f:
                f.write("\n".join(log))
            with open(os.path.join(out, "PR_BODY.md"), "w", encoding="utf-8") as f:
                f.write(pr_body(proof, mission, decl.name, contrib, checks, not args.no_build))
            meta = {
                "proof_id": proof.get("proof_id"),
                "permalink": proof.get("permalink"),
                "mission_id": mission["id"],
                "task_id": mission["task"]["id"],
                "upstream_repo": mission["upstream"]["repo"],
                "upstream_commit": mission["upstream"]["commit"],
                "upstream_file": mission["upstream_path"],
                "upstream_declaration": decl.name,
                "upstream_lines": list(span),
                "helpers": contrib["helper_names"],
                "new_imports": contrib["new_imports"],
                "built": not args.no_build,
                "checks": checks,
                "warnings": warnings,
            }
            with open(os.path.join(out, "metadata.json"), "w", encoding="utf-8") as f:
                json.dump(meta, f, indent=2)
    except ExportError as e:
        # Keep the command output for the maintainer even though no bundle is written.
        if log:
            os.makedirs(out, exist_ok=True)
            with open(os.path.join(out, "build.log"), "w", encoding="utf-8") as f:
                f.write("\n".join(log))
            raise ExportError(f"{e}\n  Full command log: {os.path.join(out, 'build.log')} (no bundle written)") from e
        raise
    return meta


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--proof-id", help="ledger id (64 hex) of an accepted proof")
    src.add_argument("--proof-json", help="saved GET /api/proofs/<id> response")
    ap.add_argument("--hub", default="https://sunstead.org", help="hub to read the proof from (GET only)")
    ap.add_argument("--out", required=True, help="empty directory outside this repo for the bundle")
    ap.add_argument("--missions-root", default=os.path.join(ROOT, "missions"))
    ap.add_argument("--upstream-url", help="override the git URL to fetch the pinned commit from")
    ap.add_argument("--no-build", action="store_true", help="skip lake build / axioms / lint (bundle is marked unbuilt)")
    ap.add_argument("--lint-cmd", action="append", help="extra check to run in the upstream checkout (repeatable)")
    ap.add_argument("--allow-stale-spec", action="store_true")
    args = ap.parse_args(argv)
    try:
        meta = export(args)
    except ExportError as e:
        print(f"export-upstream: {e}", file=sys.stderr)
        return 1
    print(f"Bundle written to {os.path.abspath(args.out)}")
    print(f"  {meta['upstream_repo']}@{meta['upstream_commit'][:12]} {meta['upstream_file']}: {meta['upstream_declaration']}")
    for w in meta["warnings"]:
        print(f"  WARNING: {w}")
    if not meta["built"]:
        print("  NOT BUILT (--no-build): run again without it before sending anything upstream.")
    print("Nothing was pushed or opened. Review upstream.patch and PR_BODY.md before sending anything.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
