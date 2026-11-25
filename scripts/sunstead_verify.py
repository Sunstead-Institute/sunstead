#!/usr/bin/env python3
"""Check a Sunstead proof against its upstream repository, without trusting Sunstead.

    curl -fsSLO https://sunstead.org/verify.py
    python3 verify.py <proof_id>

Sunstead's own verifier checks proofs against frozen copies of open `sorry`s
taken from real Lean projects. This script takes Sunstead out of the trust
path. For one accepted proof it:

1. Downloads the proof from the public ledger (GET /api/proofs/<id>) and checks
   that the patch hashes to the id you asked for.
2. Downloads the mission's public seed bundle, applies the accepted patch to it
   and extracts the proof, plus any helper lemmas and imports it added. Nothing
   in the bundle is executed.
3. Clones the upstream repository from GitHub at the pinned 40-character
   commit, finds the declaration whose `sorry` the task mirrors, requires its
   statement to match the one the proof was checked against, and replaces
   that `sorry` with the Sunstead proof.
4. Builds the module with the upstream project's own toolchain (`lake exe cache
   get`, `lake build`), requires the declaration to be sorry-free, and lists its
   axioms with a standalone `collectAxioms` checker that loads the compiled
   environment without running any elaborator. Only propext, Classical.choice
   and Quot.sound are accepted.

What you trust when it passes: the upstream repository at that commit (the
statement and everything it depends on), GitHub for serving it, and the Lean
toolchain elan installs for it. You do not trust Sunstead's verifier, its hub
or its source code. The hub only supplies the candidate proof.

Building Lean code runs it: tactics and macros execute at compile time, and so
does the upstream project's lakefile. The script refuses proofs that add
metaprogramming (`elab`, `macro`, `#eval`, `initialize` and similar) unless you
pass --allow-metaprogramming, but run it in a disposable VM or container if
you would not run `lake build` on the upstream repository itself.

Needs Python 3.9+, git, and elan (https://github.com/leanprover/elan) for
`lake`. Building against Mathlib downloads several GB of cache.

Exit status: 0 verified, 1 check failed, 2 usage or environment problem,
3 not checkable against upstream automatically (the upstream `sorry` sits
inside a larger declaration that the mission split out as its own theorem).
"""
import argparse
import ast
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from dataclasses import dataclass, field

VERSION = "0.1"
DEFAULT_HUB = "https://sunstead.org"
UA = {"User-Agent": f"sunstead-verify/{VERSION}"}
STANDARD_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
PROOF_ID_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
MISSION_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_.-]{0,119}$")
SIMPLE_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z_0-9']*$")
SCOPED_PREFIX_RE = re.compile(r"^(?:set_option|open|attribute|local|scoped)\b.*\bin\s*$")
MAX_DOWNLOAD = 64 * 1024 * 1024
# Commands in contributed code that run arbitrary code at build time, or swap a
# definition's runtime implementation. A proof of a theorem has no use for them.
METAPROGRAMMING_RE = re.compile(
    r"(?m)(?:^|\s)(?:#eval|#exit|run_cmd|run_elab|run_meta|run_tac|elab_rules|elab|macro_rules|macro|syntax|"
    r"initialize|builtin_initialize|declare_syntax_cat|notation|infixl?|infixr|prefix|postfix)\b"
    r"|@\[\s*(?:extern|implemented_by|export|init|command_elab|term_elab|tactic|macro)\b"
)


class VerifyError(Exception):
    pass


class NotUpstreamCheckable(VerifyError):
    """The upstream `sorry` is not a declaration this tool can swap a proof into."""


# ---------------------------------------------------------------- Lean declarations
# Kept identical to scripts/scout-upstream.py in the Sunstead repository
# (test_sunstead_verify.py checks it), so this file stays self-contained.

DECL_KINDS = (
    "theorem", "lemma", "def", "instance", "structure", "class", "abbrev",
    "example", "opaque", "inductive", "axiom",
)
PROOF_KINDS = {"theorem", "lemma"}
MODIFIERS = ("private", "protected", "noncomputable", "nonrec", "partial", "unsafe", "scoped", "local")
DECL_RE = re.compile(
    r"^(?:@\[[^\n]*?\]\s*)?(?:(?:" + "|".join(MODIFIERS) + r")\s+)*"
    r"(?P<kind>" + "|".join(DECL_KINDS) + r")\b\s*(?P<name>[^\s:({\[⦃]*)"
)
SORRY_RE = re.compile(r"(?<![\w.'])sorry(?![\w'])")


# ---------------------------------------------------------------- Lean lexing

def mask_comments_and_strings(src: str) -> str:
    """Replace comment and string contents with spaces (newlines kept), so code
    positions line up with the original text. Handles nested block comments,
    line comments, string literals with escapes, and char literals."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif src.startswith("/-", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/-", j):
                    depth, j = depth + 1, j + 2
                elif src.startswith("-/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            for k in range(i, j):
                if src[k] != "\n":
                    out[k] = " "
            i = j
        elif c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            for k in range(i + 1, min(j, n)):
                if src[k] != "\n":
                    out[k] = " "
            i = j + 1
        elif c == "'" and i + 2 < n and (src[i + 2] == "'" or (src[i + 1] == "\\" and i + 3 < n and src[i + 3] == "'")):
            # char literal 'a' or '\n' (identifiers like h' are not touched: a quote after a word char)
            if i > 0 and (src[i - 1].isalnum() or src[i - 1] in "_'"):
                i += 1
                continue
            j = i + (3 if src[i + 1] != "\\" else 4)
            for k in range(i + 1, j - 1):
                out[k] = " "
            i = j
        else:
            i += 1
    return "".join(out)


@dataclass
class Decl:
    kind: str
    name: str
    start_line: int  # 1-based, line of the keyword
    end_line: int
    attr_text: str  # attributes / doc comment lines just above the keyword (raw)
    raw: str  # raw source of the declaration (with comments)
    code: str  # masked source of the declaration
    sorry_lines: list = field(default_factory=list)


def split_declarations(src: str):
    """Split a Lean file into top-level declarations. A declaration starts at a
    column-0 line matching DECL_RE (attributes allowed on the same line) and
    ends where the next column-0 declaration, `namespace`, `section`, `end`,
    `open`, `variable` or attribute line starts."""
    masked = mask_comments_and_strings(src)
    raw_lines = src.split("\n")
    lines = masked.split("\n")
    starts = []
    ns_stack = []
    boundary = re.compile(r"^(namespace|section|end|open|variable|universe|set_option|@\[|#|noncomputable section|mutual)\b")
    ns_at = {}
    for idx, line in enumerate(lines):
        m = re.match(r"^namespace\s+([\w'.]+)", line)
        if m:
            ns_stack.append(m.group(1))
        elif re.match(r"^end\s+([\w'.]+)\s*$", line):
            name = re.match(r"^end\s+([\w'.]+)", line).group(1)
            if ns_stack and ns_stack[-1] == name:
                ns_stack.pop()
        ns_at[idx] = ".".join(ns_stack)
        dm = DECL_RE.match(line)
        if dm and not line.startswith(" "):
            starts.append((idx, dm.group("kind"), dm.group("name")))
    ends = []
    for k, (idx, kind, name) in enumerate(starts):
        nxt = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
        end = nxt
        for j in range(idx + 1, nxt):
            if lines[j] and not lines[j][0].isspace() and boundary.match(lines[j]):
                end = j
                break
        while end > idx + 1 and not lines[end - 1].strip():
            end -= 1  # trailing blank / comment-only lines belong to the next declaration
        ends.append(end)
    decls = []
    for k, (idx, kind, name) in enumerate(starts):
        end = ends[k]
        # Attributes and doc comment between the previous declaration and this one.
        a = max(ends[k - 1] if k else 0, idx - 60)
        full_name = f"{ns_at[idx]}.{name}" if ns_at.get(idx) and name and not name.startswith("_root_.") else name.replace("_root_.", "")
        code = "\n".join(lines[idx:end])
        decl = Decl(kind, full_name, idx + 1, end, "\n".join(raw_lines[a:idx + 1]), "\n".join(raw_lines[idx:end]), code)
        for off, cl in enumerate(lines[idx:end]):
            if SORRY_RE.search(cl):
                decl.sorry_lines.append(idx + 1 + off)
        decls.append(decl)
    return decls


def statement_end(code: str) -> int:
    """Offset of the top-level `:=` (or ` where`/`|` for pattern-matching
    definitions) ending a declaration's signature; -1 if absent."""
    depth = 0
    for i, ch in enumerate(code):
        if ch in "([{⦃⟨":
            depth += 1
        elif ch in ")]}⦄⟩":
            depth = max(0, depth - 1)
        elif depth == 0 and code.startswith(":=", i):
            return i
        elif depth == 0 and ch == "\n" and i + 1 < len(code) and code[i + 1] == "|":
            return i
    return -1

# ---------------------------------------------------------------- mission, git, Lean surgery, build

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
        raise VerifyError(f"task upstream_url is not a pinned GitHub line link: {url!r}")
    a = int(m.group("a"))
    return m.group("repo"), m.group("commit"), m.group("path"), a, int(m.group("b") or a)


def load_mission(missions_root: str, proof: dict) -> dict:
    mid = proof.get("mission_id", "")
    if not re.match(r"^[\w.-]+$", mid):
        raise VerifyError(f"bad mission id {mid!r}")
    mdir = os.path.join(missions_root, mid)
    if not os.path.isfile(os.path.join(mdir, "sunstead.json")):
        raise VerifyError(f"mission {mid} not found under {missions_root} (retired missions are not available)")
    manifest = json.loads(read(os.path.join(mdir, "sunstead.json")))
    if manifest.get("demo"):
        raise VerifyError(f"{mid} is a demo mission; it has no upstream")
    upstream = json.loads(read(os.path.join(mdir, "UPSTREAM.json")))
    for k in ("repo", "commit", "license"):
        if not upstream.get(k):
            raise VerifyError(f"UPSTREAM.json missing {k}")
    if not REPO_RE.match(upstream["repo"]) or not COMMIT_RE.match(upstream["commit"]):
        raise VerifyError("UPSTREAM.json repo/commit malformed (need owner/name and a 40-hex commit)")
    task = next((t for t in manifest["tasks"] if t["id"] == proof.get("task_id")), None)
    if task is None:
        raise VerifyError(f"task {proof.get('task_id')!r} not in {mid}/sunstead.json")
    if len(task.get("target_files", [])) != 1:
        raise VerifyError("only tasks with exactly one target file are supported")
    repo, commit, path, line_a, line_b = parse_upstream_url(task.get("upstream_url", ""))
    if repo != upstream["repo"] or commit != upstream["commit"]:
        raise VerifyError(f"task upstream_url points at {repo}@{commit}, mission pins {upstream['repo']}@{upstream['commit']}")
    theorems = verify_theorems(read(os.path.join(mdir, "verify")))
    if task["id"] not in theorems:
        raise VerifyError(f"no theorem for task {task['id']} in {mid}/verify")
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
        raise VerifyError(f"{' '.join(cmd[:3])}… failed ({p.returncode}): {(p.stderr or p.stdout)[-1500:]}")
    return p


# Every git call: no hooks from any repo config, fixed identity, no signing.
GIT = ["git", "-c", "core.hooksPath=/dev/null", "-c", "user.name=sunstead-verify",
       "-c", "user.email=verify@localhost", "-c", "commit.gpgsign=false"]


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
        raise VerifyError(f"patch touches files other than {mission['target_file']}: {sorted(set(changed + untracked))}")
    if os.path.islink(os.path.join(work, mission["target_file"])):
        raise VerifyError(f"patch turns {mission['target_file']} into a symlink")
    for line in run([*GIT, "diff", "--raw"], work).stdout.splitlines():
        old_mode, new_mode = line.split()[:2]
        if old_mode.lstrip(":") != new_mode or new_mode != "100644":
            raise VerifyError(f"patch changes file mode ({line.strip()})")
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
        raise VerifyError(f"fetched {head}, expected pinned {commit}")


# ---------------------------------------------------------------- Lean surgery

def read(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def norm(s: str) -> str:
    return " ".join(mask_comments_and_strings(s).split())


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
    raise VerifyError(f"declaration {theorem} not found (or ambiguous) in proved file")


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
    lines, masked = src.split("\n"), mask_comments_and_strings(src).split("\n")
    start = leading_block_start(lines, masked, d.start_line - 1)
    return "\n".join(lines[start:d.end_line])


def split_statement(d):
    cut = statement_end(d.code)
    if cut < 0:
        raise VerifyError(f"cannot find `:=` in {d.name}")
    return d.raw[:cut], d.raw[cut:]


def extract_contribution(seed: str, proved: str, theorem: str, allow_restated: bool = False) -> dict:
    """The proof, helpers and imports a patch adds. With `allow_restated`, a proved
    file whose statement text differs from the seed's is accepted: only its proof
    is used, under the upstream statement, and the build's reference check decides."""
    seed_decls, proved_decls = split_declarations(seed), split_declarations(proved)
    seed_target, proved_target = find_decl(seed_decls, theorem), find_decl(proved_decls, theorem)
    seed_stmt, _ = split_statement(seed_target)
    proved_stmt, proof = split_statement(proved_target)
    restated = norm_statement(seed_stmt) != norm_statement(proved_stmt)
    if restated and not allow_restated:
        raise VerifyError(
            "the accepted file changed the frozen statement text:\n"
            f"  frozen:   {norm_statement(seed_stmt)[:300]}\n  accepted: {norm_statement(proved_stmt)[:300]}"
        )
    if SORRY_RE.search(mask_comments_and_strings(proof)):
        raise VerifyError("accepted proof still contains `sorry`")
    seed_names = {d.name for d in seed_decls}
    helpers = [d for d in proved_decls if d.name not in seed_names and d.start_line < proved_target.start_line]
    for h in helpers:
        if h.sorry_lines:
            raise VerifyError(f"helper {h.name} contains `sorry`")
    late = [d.name for d in proved_decls if d.name not in seed_names and d.start_line > proved_target.start_line]
    seed_imports = set(re.findall(r"^import\s+(\S+)", seed, re.M))
    new_imports = [m for m in re.findall(r"^import\s+(\S+)", proved, re.M) if m not in seed_imports]
    seed_opens = set(re.findall(r"^open\b.*$", seed, re.M))
    new_opens = [o for o in re.findall(r"^open\b.*$", proved, re.M) if o not in seed_opens]
    return {
        "statement": seed_stmt,
        "statement_restated": restated,
        "proof": proof.rstrip(),
        "helpers": [decl_text_with_header(proved, d) for d in helpers],
        "helper_names": [d.name for d in helpers],
        "after_target": late,
        "new_imports": new_imports,
        "new_opens": new_opens,
    }


def transplant(upstream_src: str, mission: dict, contrib: dict) -> tuple:
    """Upstream file text with the proof (and helpers, imports) put in place, the
    upstream declaration, the 1-based (first, last) lines of the new helpers plus
    declaration, and the reference statement to build alongside (see
    `reference_statement`; not part of the text, add it with `with_reference`)."""
    decls = split_declarations(upstream_src)
    a, b = mission["upstream_lines"]
    hits = [d for d in decls if d.start_line <= b and d.end_line >= a and d.sorry_lines]
    if len(hits) != 1:
        raise VerifyError(f"expected one sorry declaration at {mission['upstream_path']}:{a}-{b}, found {len(hits)}")
    d = hits[0]
    up_stmt, up_proof = split_statement(d)
    if short(d.name) != short(mission["theorem"]):
        raise NotUpstreamCheckable(
            f"the upstream sorry at {mission['upstream_path']}:{a} sits inside `{d.name}`, which the mission "
            f"extracted as the separate theorem `{short(mission['theorem'])}`. Only the proof of a matching "
            "upstream declaration can be swapped in automatically; this one needs a hand-written upstream lemma."
        )
    if norm_statement(up_stmt) != norm_statement(contrib["statement"]):
        raise VerifyError(
            "upstream statement differs from the mission's frozen statement at the pinned commit:\n"
            f"  upstream: {norm_statement(up_stmt)[:300]}\n  mission:  {norm_statement(contrib['statement'])[:300]}"
        )
    if not SORRY_RE.search(mask_comments_and_strings(up_proof)):
        raise VerifyError(f"{d.name} at the pinned commit has no `sorry` to replace")
    lines = upstream_src.split("\n")
    masked = mask_comments_and_strings(upstream_src).split("\n")
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
    ref = reference_statement(d, up_stmt, lines, masked, header_start)
    ref["at"] = header_start + shift  # 0-based line index in `text`, above helpers and header
    return text, d, span, ref


REF_SUFFIX = "sunsteadRefStatement"
REF_DECL_RE = re.compile(
    r"^(?:@\[[^\n]*?\]\s*)*(?P<mods>(?:(?:" + "|".join(MODIFIERS) + r")\s+)*)"
    r"(?P<kind>theorem|lemma)\b\s*(?P<name>[^\s:({\[⦃]+)"
)


def reference_statement(d, up_stmt: str, lines, masked, header_start: int) -> dict:
    """A sorry'd copy of the pristine upstream statement under a fresh name, placed
    above the contributed helpers. The checker requires the spliced theorem's
    type to be identical to it, so a helper (an `instance`, or a `def` that
    shadows a name) cannot change what the upstream statement means."""
    m = REF_DECL_RE.match(up_stmt)
    if not m or m.group("name").endswith("."):
        raise VerifyError(f"cannot restate `{d.name}` for the statement check (only `theorem`/`lemma` are supported)")
    src_name = m.group("name")
    prefix = src_name.rsplit(".", 1)[0] + "." if "." in src_name else ""
    full_prefix = d.name.rsplit(".", 1)[0] + "." if "." in d.name else ""
    body = f"{m.group('mods')}theorem {prefix}{REF_SUFFIX}" + up_stmt[m.end():]
    # Keep `set_option ... in` / `open ... in` prefixes: they change how the statement elaborates.
    scoped = [
        lines[i] for i in range(header_start, d.start_line - 1)
        if SCOPED_PREFIX_RE.match(masked[i].strip())
    ]
    ref_lines = scoped + (body.rstrip() + " := sorry").split("\n") + [""]
    return {"name": full_prefix + REF_SUFFIX, "lines": ref_lines}


def with_reference(text: str, ref: dict) -> str:
    lines = text.split("\n")
    return "\n".join(lines[: ref["at"]] + ref["lines"] + lines[ref["at"]:])


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
  | modStr :: declStr :: refStrs =>
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
    -- The spliced theorem must state exactly what the pristine upstream
    -- statement (elaborated before any contributed helper) states.
    for refStr in refStrs do
      let ref := parseLeanName refStr
      match env.find? decl, env.find? ref with
      | some d, some r =>
        if d.type != r.type || d.levelParams != r.levelParams then
          IO.println s!"STATEMENT_MISMATCH {ref}"
          return 5
      | _, _ =>
        IO.println s!"MISSING {ref}"
        return 4
    let ctx : Core.Context := { fileName := "<sunstead-verify>", fileMap := default }
    let (axs, _) ← (collectAxioms decl : CoreM (Array Name)).toIO ctx { env := env }
    for a in axs do
      IO.println s!"AXIOM {a}"
    IO.println "SUNSTEAD_AXIOMS_DONE"
    return 0
  | _ =>
    IO.eprintln "usage: lean --run check.lean <module> <declaration> [<reference declaration>...]"
    return 2
"""


def tail(p, n=60) -> str:
    lines = (p.stdout + p.stderr).rstrip().splitlines()
    return "\n".join("    " + l for l in lines[-n:])


def read_axioms(output: str, decl_name: str) -> list:
    if f"NOT_A_THEOREM {decl_name}" in output:
        raise VerifyError(f"{decl_name} is not a theorem after the build")
    if f"MISSING {decl_name}" in output:
        raise VerifyError(f"{decl_name} not found in the built module")
    if "STATEMENT_MISMATCH " in output:
        raise VerifyError(
            f"{decl_name} no longer states what the upstream statement states: with the contributed helpers "
            "in scope it elaborates to a different type than the pristine copy built above them"
        )
    for line in output.splitlines():
        if line.startswith("MISSING "):
            raise VerifyError(f"{line[len('MISSING '):]} not found in the built module")
    if "SUNSTEAD_AXIOMS_DONE" not in output:
        raise VerifyError("axiom checker did not finish")
    return [l[len("AXIOM "):].strip() for l in output.splitlines() if l.startswith("AXIOM ")]


def build_and_check(updir: str, mission: dict, decl_name: str, log: list, scratch: str,
                    ref_name: str = None) -> dict:
    """Build the module and check the declaration. `ref_name` is the reference
    statement written into the file by `with_reference`; without it the type
    check against the pristine statement is skipped."""
    checks = {}
    run(["lake", "exe", "cache", "get"], updir, check=False, timeout=3600, log=log)
    module = lean_module(mission["upstream_path"])
    p = run(["lake", "build", module], updir, check=False, timeout=6 * 3600, log=log)
    checks["lake_build"] = p.returncode == 0
    if p.returncode != 0:
        raise VerifyError(f"lake build {module} failed:\n{tail(p)}")
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
    argv = ["lake", "env", "lean", "--run", checker, module, decl_name] + ([ref_name] if ref_name else [])
    p = run(argv, updir, check=False, timeout=3600, log=log)
    checks["statement_matches_upstream"] = bool(ref_name) and p.returncode == 0
    if p.returncode not in (0, 3, 4, 5):
        raise VerifyError(f"axiom checker failed for {decl_name}:\n{tail(p)}")
    axioms = read_axioms(p.stdout, decl_name)
    checks["axioms"] = axioms
    bad = sorted(set(axioms) - STANDARD_AXIOMS)
    if bad:
        raise VerifyError(f"{decl_name} depends on non-standard axioms: {bad}")
    return checks


def run_lints(updir: str, lint_cmds, log: list) -> list:
    """Extra maintainer checks, run on the checkout as it will be proposed."""
    results = []
    for cmd in lint_cmds:
        p = run(["bash", "-c", cmd], updir, check=False, timeout=3600, log=log)
        results.append({"cmd": cmd, "ok": p.returncode == 0})
    return results

# ---------------------------------------------------------------- public verification

def fetch(url: str, limit: int = MAX_DOWNLOAD) -> bytes:
    if not url.startswith(("https://", "http://127.0.0.1", "http://localhost")):
        raise VerifyError(f"refusing non-https URL {url}")
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        data = r.read(limit + 1)
    if len(data) > limit:
        raise VerifyError(f"{url} is larger than {limit} bytes")
    return data


def load_public_proof(hub: str, proof_id: str) -> dict:
    pid = proof_id.lower().removeprefix("sha256:")
    if not PROOF_ID_RE.match(pid):
        raise VerifyError("proof id must be 64 hex characters (the id in /proofs/<id>)")
    proof = json.loads(fetch(f"{hub.rstrip('/')}/api/proofs/{pid}").decode("utf-8"))
    check_patch_hash(proof, pid)
    return proof


def check_patch_hash(proof: dict, pid: str) -> None:
    patch = proof.get("patch")
    if not isinstance(patch, str) or not patch:
        raise VerifyError("the ledger entry has no patch")
    got = hashlib.sha256(patch.encode("utf-8")).hexdigest()
    if got != pid:
        raise VerifyError(f"patch hashes to {got}, not the requested id {pid}")


def safe_extract(tar_bytes: bytes, dest: str) -> None:
    """Extract regular files and directories only: no links, devices, absolute or
    `..` paths, and nothing under `.git` (a bundled git config could run commands)."""
    os.makedirs(dest, exist_ok=True)
    total = 0
    with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:*") as tf:
        for m in tf.getmembers():
            name = m.name
            while name.startswith("./"):
                name = name[2:]
            if not name or name == ".":
                continue
            parts = name.split("/")
            if name.startswith("/") or ".." in parts or "\\" in name:
                raise VerifyError(f"unsafe path in bundle: {m.name!r}")
            if parts[0] == ".git":
                continue
            target = os.path.join(dest, *parts)
            if m.isdir():
                os.makedirs(target, exist_ok=True)
                continue
            if not m.isreg():
                raise VerifyError(f"bundle entry {m.name!r} is not a regular file")
            total += m.size
            if total > 4 * MAX_DOWNLOAD:
                raise VerifyError("bundle expands to more than 256 MB")
            os.makedirs(os.path.dirname(target), exist_ok=True)
            src = tf.extractfile(m)
            with open(target, "wb") as f:
                shutil.copyfileobj(src, f)


def check_no_metaprogramming(contrib: dict) -> None:
    code = "\n".join(contrib["helpers"] + [contrib["proof"]])
    hit = METAPROGRAMMING_RE.search(mask_comments_and_strings(code))
    if hit:
        raise VerifyError(
            f"the contributed code uses `{hit.group(0).strip()}`, which runs code at build time. "
            "Read the patch, and pass --allow-metaprogramming (ideally inside a disposable VM) to build it anyway."
        )


def verify(args) -> dict:
    if args.proof_json:
        with open(args.proof_json, encoding="utf-8") as f:
            proof = json.load(f)
        if proof.get("proof_id"):
            check_patch_hash(proof, proof["proof_id"])
    else:
        proof = load_public_proof(args.hub, args.proof_id)
    mid = proof.get("mission_id", "")
    if not isinstance(mid, str) or not MISSION_ID_RE.match(mid):
        raise VerifyError(f"bad mission id {mid!r}")
    if proof.get("mission_demo"):
        raise VerifyError(f"{mid} is a demo mission; it has no upstream to check against")
    for tool in ["git"] + ([] if args.no_build else ["lake"]):
        if not shutil.which(tool):
            hint = " (install elan: https://github.com/leanprover/elan)" if tool == "lake" else ""
            raise VerifyError(f"`{tool}` not found on PATH{hint}")
    log: list = []
    with tempfile.TemporaryDirectory(prefix="sunstead-verify-") as scratch:
        if args.seed_bundle:
            with open(args.seed_bundle, "rb") as f:
                bundle = f.read()
        else:
            bundle = fetch(f"{args.hub.rstrip('/')}/api/missions/{mid}/bundle.tar.gz?base=seed")
        missions_root = os.path.join(scratch, "missions")
        safe_extract(bundle, os.path.join(missions_root, mid))
        mission = load_mission(missions_root, proof)
        up = proof.get("upstream") or {}
        if up.get("repo") and (up.get("repo"), up.get("commit")) != (mission["upstream"]["repo"], mission["upstream"]["commit"]):
            raise VerifyError("ledger upstream and the seed bundle's UPSTREAM.json disagree")
        seed, proved = proved_file(mission, proof["patch"], scratch)
        # The accepted file may restate the theorem (say, a shorter name inside a
        # namespace); only its proof is used, under the upstream statement, and with
        # a build the reference check confirms the type is unchanged.
        contrib = extract_contribution(seed, proved, mission["theorem"], allow_restated=True)
        if not args.allow_metaprogramming:
            check_no_metaprogramming(contrib)
        updir = os.path.join(scratch, "upstream")
        repo_url = args.upstream_url or f"https://github.com/{mission['upstream']['repo']}.git"
        print(f"Fetching {mission['upstream']['repo']}@{mission['upstream']['commit'][:12]} ...", file=sys.stderr)
        fetch_upstream(repo_url, mission["upstream"]["commit"], updir, log)
        target = os.path.join(updir, mission["upstream_path"])
        if not os.path.isfile(target):
            raise VerifyError(f"{mission['upstream_path']} not in upstream at the pinned commit")
        new_src, decl, span, ref = transplant(read(target), mission, contrib)
        checks = {}
        if args.no_build:
            with open(target, "w", encoding="utf-8") as f:
                f.write(new_src)
        else:
            with open(target, "w", encoding="utf-8") as f:
                f.write(with_reference(new_src, ref))
            print(f"Building {lean_module(mission['upstream_path'])} (can take a while) ...", file=sys.stderr)
            checks = build_and_check(updir, mission, decl.name, log, scratch, ref_name=ref["name"])
            shift = len(ref["lines"])
            if any(span[0] + shift <= ln <= span[1] + shift for ln in checks["sorry_warnings_in_file"]):
                raise VerifyError(f"{decl.name} (or a helper) still reports `sorry` after the build")
            with open(target, "w", encoding="utf-8") as f:
                f.write(new_src)  # --keep gets the checkout without the reference statement
        if args.keep:
            kept = os.path.abspath(args.keep)
            shutil.copytree(updir, kept, symlinks=True)
    return {
        "verified": not args.no_build,
        "proof_id": proof.get("proof_id"),
        "mission_id": mission["id"],
        "task_id": mission["task"]["id"],
        "upstream_repo": mission["upstream"]["repo"],
        "upstream_commit": mission["upstream"]["commit"],
        "upstream_file": mission["upstream_path"],
        "upstream_declaration": decl.name,
        "upstream_lines": list(span),
        "helpers": contrib["helper_names"],
        "new_imports": contrib["new_imports"],
        "statement_restated": contrib["statement_restated"],
        "axioms": checks.get("axioms"),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Check a Sunstead proof against its upstream repository, without trusting Sunstead.",
        epilog="See the top of this file for what is and is not trusted.",
    )
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("proof_id", nargs="?", help="64-hex id from https://sunstead.org/proofs/<id>")
    src.add_argument("--proof-json", help="a saved GET /api/proofs/<id> response instead of fetching it")
    ap.add_argument("--hub", default=DEFAULT_HUB, help="where to read the proof and seed bundle (GET only)")
    ap.add_argument("--seed-bundle", help="a saved bundle.tar.gz?base=seed instead of fetching it")
    ap.add_argument("--upstream-url", help="git URL to fetch the pinned commit from (default: GitHub)")
    ap.add_argument("--no-build", action="store_true", help="only check the statement and splice; do not build")
    ap.add_argument("--allow-metaprogramming", action="store_true", help="build proofs that add elab/macro/#eval code")
    ap.add_argument("--keep", metavar="DIR", help="copy the patched upstream checkout to DIR (must not exist)")
    ap.add_argument("--json", action="store_true", help="print the result as JSON")
    args = ap.parse_args(argv)
    if args.keep and os.path.exists(args.keep):
        print(f"verify: --keep {args.keep} already exists", file=sys.stderr)
        return 2
    try:
        result = verify(args)
    except NotUpstreamCheckable as e:
        print(f"NOT CHECKABLE AGAINST UPSTREAM: {e}", file=sys.stderr)
        return 3
    except VerifyError as e:
        print(f"FAILED: {e}", file=sys.stderr)
        return 1
    except (OSError, ValueError) as e:  # network, JSON, tar
        print(f"verify: {e}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(result, indent=2))
        return 0
    where = f"{result['upstream_repo']}@{result['upstream_commit'][:12]} {result['upstream_file']}:{result['upstream_lines'][0]}"
    if result["verified"]:
        print(f"VERIFIED against upstream: {result['upstream_declaration']} ({where})")
        print(f"  axioms: {', '.join(result['axioms']) or 'none'}")
    else:
        print(f"STATEMENT MATCHES upstream, proof spliced in, NOT BUILT (--no-build): {result['upstream_declaration']} ({where})")
    if result["helpers"]:
        print(f"  helper lemmas added: {', '.join(result['helpers'])}")
    if result["statement_restated"]:
        print("  note: the accepted file restates the theorem in different words; its proof was checked under the upstream statement")
    return 0


if __name__ == "__main__":
    sys.exit(main())
