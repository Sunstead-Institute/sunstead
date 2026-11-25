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
import ast
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {"User-Agent": "sunstead-export-upstream/0.1"}
STANDARD_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
PROOF_ID_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SIMPLE_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z_0-9']*$")
SCOPED_PREFIX_RE = re.compile(r"^(?:set_option|open|attribute|local|scoped)\b.*\bin\s*$")

_spec = importlib.util.spec_from_file_location("scout_upstream", os.path.join(ROOT, "scripts", "scout-upstream.py"))
scout = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scout)


class ExportError(Exception):
    pass


# ---------------------------------------------------------------- inputs

def load_proof(args) -> dict:
    if args.proof_json:
        with open(args.proof_json, encoding="utf-8") as f:
            return json.load(f)
    pid = args.proof_id.lower().removeprefix("sha256:")
    if not PROOF_ID_RE.match(pid):
        raise ExportError("--proof-id must be 64 hex characters")
    url = f"{args.hub.rstrip('/')}/api/proofs/{pid}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def verify_theorems(verify_src: str) -> dict:
    """task id -> fully qualified theorem name, from a mission's `verify` TASKS table."""
    try:
        tree = ast.parse(verify_src)
        for node in tree.body:
            if isinstance(node, ast.Assign):
                for target in node.targets:
                    if isinstance(target, ast.Name) and target.id == "TASKS":
                        tasks = ast.literal_eval(node.value)
                        if isinstance(tasks, dict):
                            return {
                                k: v["theorem"]
                                for k, v in tasks.items()
                                if isinstance(k, str) and isinstance(v, dict) and isinstance(v.get("theorem"), str)
                            }
    except (SyntaxError, ValueError):
        pass
    pat = re.compile(r'"(?P<task>[\w.-]+)"\s*:\s*\{\s*"module"\s*:\s*"[^"]+"\s*,\s*"theorem"\s*:\s*"(?P<thm>[^"]+)"')
    return {m.group("task"): m.group("thm") for m in pat.finditer(verify_src)}


def parse_upstream_url(url: str):
    """github.com/<owner>/<repo>/blob/<commit>/<path>#L<a>[-L<b>] -> (repo, commit, path, a, b)."""
    m = re.match(
        r"^https://github\.com/(?P<repo>[^/]+/[^/]+)/blob/(?P<commit>[0-9a-f]{40})/(?P<path>[^#]+\.lean)#L(?P<a>\d+)(?:-L(?P<b>\d+))?$",
        url or "",
    )
    if not m:
        raise ExportError(f"task upstream_url is not a pinned GitHub line link: {url!r}")
    a = int(m.group("a"))
    return m.group("repo"), m.group("commit"), m.group("path"), a, int(m.group("b") or a)


def load_mission(missions_root: str, proof: dict) -> dict:
    mid = proof.get("mission_id", "")
    if not re.match(r"^[\w.-]+$", mid):
        raise ExportError(f"bad mission id {mid!r}")
    mdir = os.path.join(missions_root, mid)
    if not os.path.isfile(os.path.join(mdir, "sunstead.json")):
        raise ExportError(f"mission {mid} not found under {missions_root} (retired missions cannot be exported)")
    manifest = json.loads(read(os.path.join(mdir, "sunstead.json")))
    if manifest.get("demo"):
        raise ExportError(f"{mid} is a demo mission; nothing to send upstream")
    upstream = json.loads(read(os.path.join(mdir, "UPSTREAM.json")))
    for k in ("repo", "commit", "license"):
        if not upstream.get(k):
            raise ExportError(f"UPSTREAM.json missing {k}")
    if not REPO_RE.match(upstream["repo"]) or not COMMIT_RE.match(upstream["commit"]):
        raise ExportError("UPSTREAM.json repo/commit malformed (need owner/name and a 40-hex commit)")
    task = next((t for t in manifest["tasks"] if t["id"] == proof.get("task_id")), None)
    if task is None:
        raise ExportError(f"task {proof.get('task_id')!r} not in {mid}/sunstead.json")
    if len(task.get("target_files", [])) != 1:
        raise ExportError("export supports tasks with exactly one target file")
    repo, commit, path, line_a, line_b = parse_upstream_url(task.get("upstream_url", ""))
    if repo != upstream["repo"] or commit != upstream["commit"]:
        raise ExportError(f"task upstream_url points at {repo}@{commit}, mission pins {upstream['repo']}@{upstream['commit']}")
    theorems = verify_theorems(read(os.path.join(mdir, "verify")))
    if task["id"] not in theorems:
        raise ExportError(f"no theorem for task {task['id']} in {mid}/verify")
    is_repo_snapshot = (manifest.get("snapshot") or {}).get("mode") == "repo-snapshot"
    return {
        "id": mid, "dir": mdir, "manifest": manifest, "upstream": upstream, "task": task,
        "target_file": task["target_files"][0], "theorem": theorems[task["id"]],
        "upstream_path": path, "upstream_lines": (line_a, line_b),
        "is_repo_snapshot": is_repo_snapshot,
    }


# ---------------------------------------------------------------- git helpers

def run(cmd, cwd, check=True, timeout=None, log=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    if log is not None:
        log.append(f"$ {' '.join(cmd)}  (exit {p.returncode})\n{p.stdout}{p.stderr}")
    if check and p.returncode != 0:
        raise ExportError(f"{' '.join(cmd[:3])}… failed ({p.returncode}): {(p.stderr or p.stdout)[-1500:]}")
    return p


# Every git call: no hooks from any repo config, fixed identity, no signing.
GIT = ["git", "-c", "core.hooksPath=/dev/null", "-c", "user.name=sunstead-export",
       "-c", "user.email=export@localhost", "-c", "commit.gpgsign=false"]


def proved_file(mission: dict, patch: str, scratch: str):
    """Seed target file and the same file with the accepted patch applied."""
    work = os.path.join(scratch, "mission")
    shutil.copytree(mission["dir"], work)
    run([*GIT, "init", "-q"], work)
    run([*GIT, "add", "-A"], work)
    run([*GIT, "commit", "-q", "-m", "seed"], work)
    patch_path = os.path.join(scratch, "accepted.patch")
    with open(patch_path, "w", encoding="utf-8") as f:
        f.write(patch if patch.endswith("\n") else patch + "\n")
    run([*GIT, "apply", "--whitespace=nowarn", patch_path], work)
    changed = run([*GIT, "diff", "--name-only"], work).stdout.split()
    untracked = run([*GIT, "ls-files", "--others", "--exclude-standard"], work).stdout.split()
    if set(changed + untracked) - {mission["target_file"]}:
        raise ExportError(f"patch touches files other than {mission['target_file']}: {sorted(set(changed + untracked))}")
    if os.path.islink(os.path.join(work, mission["target_file"])):
        raise ExportError(f"patch turns {mission['target_file']} into a symlink")
    for line in run([*GIT, "diff", "--raw"], work).stdout.splitlines():
        old_mode, new_mode = line.split()[:2]
        if old_mode.lstrip(":") != new_mode or new_mode != "100644":
            raise ExportError(f"patch changes file mode ({line.strip()})")
    seed = read(os.path.join(mission["dir"], mission["target_file"]))
    proved = read(os.path.join(work, mission["target_file"]))
    return seed, proved


def fetch_upstream(repo_url: str, commit: str, dest: str, log: list):
    os.makedirs(dest)
    run([*GIT, "init", "-q"], dest)
    run([*GIT, "remote", "add", "origin", repo_url], dest)
    run([*GIT, "fetch", "-q", "--depth", "1", "origin", commit], dest, timeout=1800, log=log)
    run([*GIT, "-c", "advice.detachedHead=false", "checkout", "-q", "FETCH_HEAD"], dest)
    head = run([*GIT, "rev-parse", "HEAD"], dest).stdout.strip()
    if head != commit:
        raise ExportError(f"fetched {head}, expected pinned {commit}")


# ---------------------------------------------------------------- Lean surgery

def read(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def norm(s: str) -> str:
    return " ".join(scout.mask_comments_and_strings(s).split())


def norm_statement(s: str) -> str:
    """Statement for comparison: comments, whitespace and leading attributes ignored
    (Sunstead copies keep the statement verbatim but may drop `@[simp]` and the like)."""
    return re.sub(r"^(?:@\[[^\]]*\]\s*)+", "", norm(s))


def short(name: str) -> str:
    return name.rsplit(".", 1)[-1]


def find_decl(decls, theorem: str):
    exact = [d for d in decls if d.name == theorem]
    if exact:
        return exact[0]
    by_short = [d for d in decls if short(d.name) == short(theorem)]
    if len(by_short) == 1:
        return by_short[0]
    raise ExportError(f"declaration {theorem} not found (or ambiguous) in proved file")


def leading_block_start(lines, masked_lines, idx: int) -> int:
    """First line of doc comments, attributes, or scoped `... in` modifiers directly above line idx (0-based)."""
    j = idx
    while j > 0:
        raw, masked = lines[j - 1], masked_lines[j - 1]
        if not raw.strip():
            break
        m = masked.strip()
        if m == "" or m.startswith("@[") or SCOPED_PREFIX_RE.match(m):
            j -= 1
            continue
        break
    return j


def decl_text_with_header(src: str, d) -> str:
    lines, masked = src.split("\n"), scout.mask_comments_and_strings(src).split("\n")
    start = leading_block_start(lines, masked, d.start_line - 1)
    return "\n".join(lines[start:d.end_line])


def split_statement(d):
    cut = scout.statement_end(d.code)
    if cut < 0:
        raise ExportError(f"cannot find `:=` in {d.name}")
    return d.raw[:cut], d.raw[cut:]


def extract_contribution(seed: str, proved: str, theorem: str) -> dict:
    seed_decls, proved_decls = scout.split_declarations(seed), scout.split_declarations(proved)
    seed_target, proved_target = find_decl(seed_decls, theorem), find_decl(proved_decls, theorem)
    seed_stmt, _ = split_statement(seed_target)
    proved_stmt, proof = split_statement(proved_target)
    if norm_statement(seed_stmt) != norm_statement(proved_stmt):
        raise ExportError("the accepted file changed the frozen statement; refusing to export")
    if scout.SORRY_RE.search(scout.mask_comments_and_strings(proof)):
        raise ExportError("accepted proof still contains `sorry`")
    seed_names = {d.name for d in seed_decls}
    helpers = [d for d in proved_decls if d.name not in seed_names and d.start_line < proved_target.start_line]
    for h in helpers:
        if h.sorry_lines:
            raise ExportError(f"helper {h.name} contains `sorry`")
    late = [d.name for d in proved_decls if d.name not in seed_names and d.start_line > proved_target.start_line]
    seed_imports = set(re.findall(r"^import\s+(\S+)", seed, re.M))
    new_imports = [m for m in re.findall(r"^import\s+(\S+)", proved, re.M) if m not in seed_imports]
    seed_opens = set(re.findall(r"^open\b.*$", seed, re.M))
    new_opens = [o for o in re.findall(r"^open\b.*$", proved, re.M) if o not in seed_opens]
    return {
        "statement": seed_stmt,
        "proof": proof.rstrip(),
        "helpers": [decl_text_with_header(proved, d) for d in helpers],
        "helper_names": [d.name for d in helpers],
        "after_target": late,
        "new_imports": new_imports,
        "new_opens": new_opens,
    }


def transplant(upstream_src: str, mission: dict, contrib: dict) -> tuple:
    """Upstream file text with the proof (and helpers, imports) put in place, the
    upstream declaration, and the 1-based (first, last) lines of the new helpers
    plus declaration."""
    decls = scout.split_declarations(upstream_src)
    a, b = mission["upstream_lines"]
    hits = [d for d in decls if d.start_line <= b and d.end_line >= a and d.sorry_lines]
    if len(hits) != 1:
        raise ExportError(f"expected one sorry declaration at {mission['upstream_path']}:{a}-{b}, found {len(hits)}")
    d = hits[0]
    up_stmt, up_proof = split_statement(d)
    if short(d.name) != short(mission["theorem"]):
        raise ExportError(
            f"the upstream sorry at {mission['upstream_path']}:{a} sits inside `{d.name}`, which the mission "
            f"extracted as the separate theorem `{short(mission['theorem'])}`. Automatic export only swaps the "
            "proof of a matching upstream declaration; this one needs a hand-written upstream lemma."
        )
    if norm_statement(up_stmt) != norm_statement(contrib["statement"]):
        raise ExportError(
            "upstream statement differs from the mission's frozen statement at the pinned commit:\n"
            f"  upstream: {norm_statement(up_stmt)[:300]}\n  mission:  {norm_statement(contrib['statement'])[:300]}"
        )
    if not scout.SORRY_RE.search(scout.mask_comments_and_strings(up_proof)):
        raise ExportError(f"{d.name} at the pinned commit has no `sorry` to replace")
    lines = upstream_src.split("\n")
    masked = scout.mask_comments_and_strings(upstream_src).split("\n")
    new_decl = up_stmt + contrib["proof"]
    header_start = leading_block_start(lines, masked, d.start_line - 1)
    helper_lines = "\n\n".join(contrib["helpers"]).split("\n") + [""] if contrib["helpers"] else []
    before = lines[:header_start] + helper_lines + lines[header_start:d.start_line - 1]
    decl_lines = new_decl.split("\n")
    text = "\n".join(before + decl_lines + lines[d.end_line:])
    existing = set(re.findall(r"^import\s+(\S+)", upstream_src, re.M))
    added_imports = [m for m in contrib["new_imports"] if m not in existing]
    shift = len(added_imports)
    first = (header_start + 1 if helper_lines else len(before) + 1) + shift
    span = (first, len(before) + len(decl_lines) + shift)
    if added_imports:
        imp = [m.end() for m in re.finditer(r"^import\s+\S+[^\n]*\n", text, re.M)]
        at = imp[-1] if imp else 0
        text = text[:at] + "".join(f"import {m}\n" for m in added_imports) + text[at:]
    return text, d, span


# ---------------------------------------------------------------- build & checks

def lean_module(path: str) -> str:
    parts = path[: -len(".lean")].split("/")
    return ".".join(p if SIMPLE_IDENT_RE.match(p) else f"«{p}»" for p in parts)


# Standalone checker run with `lake env lean --run`. It imports only `Lean`, loads
# the built module's environment with `importModules ... (loadExts := false)` (no
# elaborators, commands, `initialize` hooks or `#print` run), requires the
# declaration to be a theorem, and lists its axioms with `collectAxioms`, so
# nothing in the upstream or contributed source can rewrite the report (cf.
# redteam.py's lean-spoof-axiom-report).
AXIOM_CHECKER = """import Lean
open Lean

def stripGuillemets (raw : String) : String :=
  match raw.toList with
  | '«' :: rest =>
    match rest.reverse with
    | '»' :: innerRev => String.ofList innerRev.reverse
    | _ => raw
  | _ => raw

def parseLeanName (s : String) : Name :=
  (s.splitOn ".").foldl (fun acc part => Name.str acc (stripGuillemets part)) Name.anonymous

def main (args : List String) : IO UInt32 := do
  match args with
  | [modStr, declStr] =>
    let mod := parseLeanName modStr
    let decl := parseLeanName declStr
    initSearchPath (← findSysroot)
    let env ← importModules #[{ module := mod }] {} 0 (loadExts := false)
    match env.find? decl with
    | some (.thmInfo _) => pure ()
    | some _ =>
      IO.println s!"NOT_A_THEOREM {decl}"
      return 3
    | none =>
      IO.println s!"MISSING {decl}"
      return 4
    let ctx : Core.Context := { fileName := "<sunstead-export>", fileMap := default }
    let (axs, _) ← (collectAxioms decl : CoreM (Array Name)).toIO ctx { env := env }
    for a in axs do
      IO.println s!"AXIOM {a}"
    IO.println "SUNSTEAD_AXIOMS_DONE"
    return 0
  | _ =>
    IO.eprintln "usage: lean --run check.lean <module> <declaration>"
    return 2
"""


def tail(p, n=60) -> str:
    lines = (p.stdout + p.stderr).rstrip().splitlines()
    return "\n".join("    " + l for l in lines[-n:])


def read_axioms(output: str, decl_name: str) -> list:
    if f"NOT_A_THEOREM {decl_name}" in output:
        raise ExportError(f"{decl_name} is not a theorem after the build")
    if f"MISSING {decl_name}" in output:
        raise ExportError(f"{decl_name} not found in the built module")
    if "SUNSTEAD_AXIOMS_DONE" not in output:
        raise ExportError("axiom checker did not finish")
    return [l[len("AXIOM "):].strip() for l in output.splitlines() if l.startswith("AXIOM ")]


def build_and_check(updir: str, mission: dict, decl_name: str, lint_cmds, log: list, scratch: str) -> dict:
    checks = {}
    run(["lake", "exe", "cache", "get"], updir, check=False, timeout=3600, log=log)
    module = lean_module(mission["upstream_path"])
    p = run(["lake", "build", module], updir, check=False, timeout=6 * 3600, log=log)
    checks["lake_build"] = p.returncode == 0
    if p.returncode != 0:
        raise ExportError(f"lake build {module} failed:\n{tail(p)}")
    out = p.stdout + p.stderr
    # Lean prints `<file>:l:c: warning: declaration uses 'sorry'`; lake prints
    # `warning: ./<file>:l:c: declaration uses 'sorry'`. Accept both.
    sorry_warn = re.findall(
        rf"(?:\./)*{re.escape(mission['upstream_path'])}:(\d+):\d+:(?: warning:)? declaration uses 'sorry'", out
    )
    checks["sorry_warnings_in_file"] = [int(x) for x in sorry_warn]
    checker = os.path.join(scratch, "sunstead_axiom_check.lean")  # outside the upstream checkout
    with open(checker, "w", encoding="utf-8") as f:
        f.write(AXIOM_CHECKER)
    p = run(["lake", "env", "lean", "--run", checker, module, decl_name], updir, check=False, timeout=3600, log=log)
    if p.returncode not in (0, 3, 4):
        raise ExportError(f"axiom checker failed for {decl_name}:\n{tail(p)}")
    axioms = read_axioms(p.stdout, decl_name)
    checks["axioms"] = axioms
    bad = sorted(set(axioms) - STANDARD_AXIOMS)
    if bad:
        raise ExportError(f"{decl_name} depends on non-standard axioms: {bad}")
    checks["lint"] = []
    for cmd in lint_cmds:
        p = run(["bash", "-c", cmd], updir, check=False, timeout=3600, log=log)
        checks["lint"].append({"cmd": cmd, "ok": p.returncode == 0})
    return checks


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
