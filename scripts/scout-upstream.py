#!/usr/bin/env python3
"""
Scout curated upstream Lean 4 repositories for open `sorry`s that could become
Sunstead tasks, applying the intake criteria in docs/DESIGN.md Section 4.

For each watched repository it reports:
- a pinned 40-char commit (HEAD, or with --toolchain the newest commit whose
  `lean-toolchain` matches), its `lean-toolchain`, Mathlib rev, and license SPDX id;
- every `sorry` found, classified. Only a `sorry` inside the proof of a
  `theorem`/`lemma` (after its top-level `:=`) is a candidate. Definition,
  instance, structure, statement-level and `example` sorries are excluded, as
  are those whose file, declaration or comments are marked upstreamed / WIP /
  do-not-touch / deprecated, and files under test/example/scratch paths;
- audit hints per candidate: blueprint backing (`@[blueprint ...]` or a
  `\\lean{...}` entry in blueprint/*.tex), whether its statement mentions a
  declaration that itself contains a `sorry` (possible vacuity), and whether
  it is already a live Sunstead task;
- dependency edges between candidates (a proof that names another open
  candidate), for DAG missions;
- packaging: `standalone-mathlib` when the file imports only Mathlib and its
  dependencies, else `repo-snapshot` (it imports project modules and needs the
  repo-snapshot verifier), and whether it is packageable now (standalone, on
  the verifier's toolchain, permissive license). Repos on every Lean 4
  toolchain are reported, grouped by toolchain and license class.

The watchlist covers math, cryptography and optimization repos (--domain).

This is a static scan. It does not compile anything, so "compiles cleanly with
only this sorry" (criterion 2) still needs a `lake build` and an axiom audit
before a task ships. A candidate is also not proof the work is free: with
--check-prs, open upstream PRs (changed files and patches) and open issues are
fetched with read-only `gh api` GETs, and a candidate an open PR likely solves
is excluded; issue comments and forks are still worth a manual look.
Licenses are reported as permissive, or copyleft/unknown needing review.

Usage:
  python3 scripts/scout-upstream.py                       # whole watchlist, HEAD
  python3 scripts/scout-upstream.py --toolchain v4.36.0   # pin to a matching commit
  python3 scripts/scout-upstream.py --domain cryptography --domain optimization --check-prs
  python3 scripts/scout-upstream.py --repo AlexKontorovich/PrimeNumberTheoremAnd --format json
"""
import argparse
import glob
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (repo, domain). Domains group the report and can be selected with --domain.
WATCHLIST_DOMAINS = [
    ("AlexKontorovich/PrimeNumberTheoremAnd", "math"),
    ("ImperialCollegeLondon/FLT", "math"),
    ("fpvandoorn/carleson", "math"),
    ("thefundamentaltheor3m/Sphere-Packing-Lean", "math"),
    ("google-deepmind/formal-conjectures", "math"),
    ("teorth/IEANTN", "math"),
    ("leanprover-community/physlib", "math"),
    ("kbuzzard/ClassFieldTheory", "math"),
    ("frenzymath/FATE", "math"),
    ("teorth/equational_theories", "math"),
    ("Verified-zkEVM/ArkLib", "cryptography"),
    ("Verified-zkEVM/VCVio", "cryptography"),
    ("Verified-zkEVM/CompPoly", "cryptography"),
    ("Verified-zkEVM/clean", "cryptography"),
    ("Verified-zkEVM/evm-asm", "cryptography"),
    ("Verified-zkEVM/PolyFun", "cryptography"),
    ("Verified-zkEVM/rust-lean", "cryptography"),
    ("Verified-zkEVM/leanerVM", "cryptography"),
    ("leanprover/LNSym", "cryptography"),
    ("Beneficial-AI-Foundation/curve25519-dalek-lean-verify", "cryptography"),
    ("Beneficial-AI-Foundation/dalek-lean-bench", "cryptography"),
    ("leanEthereum/leanVM", "cryptography"),
    ("BobDyLean/dylean", "cryptography"),
    ("reilabs/proven-zk", "cryptography"),
    ("reilabs/lampe", "cryptography"),
    ("GaloisInc/zkLean", "cryptography"),
    ("cedar-policy/cedar-spec", "systems"),
    ("opencompl/lean-mlir", "systems"),
    ("opencompl/riscv-lean", "systems"),
    ("digama0/lean4lean", "systems"),
    ("sunblaze-ucb/verina", "systems"),
    ("k3nfalt/longtails", "optimization"),
    ("optsuite/optlib", "optimization"),
    ("verified-optimization/CvxLean", "optimization"),
    ("lean-dojo/FloatLib", "optimization"),
]
WATCHLIST = [r for r, _ in WATCHLIST_DOMAINS]
DOMAIN_OF = dict(WATCHLIST_DOMAINS)
DOMAINS = sorted(set(DOMAIN_OF.values()))

# Default per-subprocess timeouts (seconds), overridable via --timeout.
GIT_TIMEOUT = 120
GH_TIMEOUT = 60
HTTP_TIMEOUT = 30
DISCOVER_UA = "sunstead-scout-upstream/0.3"
MATHLIB_DOWNSTREAM_YML_URL = (
    "https://raw.githubusercontent.com/leanprover-community/mathlib4/master/scripts/downstream-repos.yml"
)
RESERVOIR_INDEX_REPO = "leanprover/reservoir-index"

# The toolchain the production verifier image runs (cloudflare/containers/lean4).
# Only standalone-mathlib candidates pinned to it can be packaged without new
# verifier work; everything else needs the repo-snapshot / multi-toolchain verifier.
SUPPORTED_TOOLCHAIN = "leanprover/lean4:v4.36.0"

# Import roots available in a standalone Mathlib checkout (Mathlib and its own
# dependencies). A file importing anything else needs its project's modules.
STANDALONE_IMPORT_ROOTS = {
    "Mathlib", "Batteries", "Std", "Lean", "Init", "Aesop", "Qq", "ProofWidgets",
    "Plausible", "ImportGraph", "LeanSearchClient",
}
IMPORT_RE = re.compile(r"^(?:public\s+|private\s+)?(?:meta\s+)?import\s+(?P<mods>.+)$")


def file_imports(src: str):
    """Module names imported in a Lean file's header (comments ignored)."""
    mods = []
    for line in mask_comments_and_strings(src).split("\n"):
        t = line.strip()
        if not t or t == "prelude" or re.match(r"^module\b", t):
            continue
        m = IMPORT_RE.match(t)
        if not m:
            break
        mods.extend(w for w in m.group("mods").split() if w not in ("all",))
    return mods


def classify_packaging(imports):
    """("standalone-mathlib", []) when every import resolves in a plain Mathlib
    checkout, else ("repo-snapshot", [the imports that need the project])."""
    extra = sorted({m for m in imports if m.split(".", 1)[0] not in STANDALONE_IMPORT_ROOTS})
    return ("repo-snapshot", extra) if extra else ("standalone-mathlib", [])


# DESIGN.md Section 4, criterion 4. Permissive licenses can be mirrored as-is;
# copyleft ones (which DESIGN.md allows, e.g. AGPL-3.0) need a license review first.
PERMISSIVE_SPDX = {"Apache-2.0", "MIT", "BSD-2-Clause", "BSD-3-Clause", "ISC"}
COPYLEFT_SPDX = {"AGPL-3.0", "GPL-3.0", "LGPL-3.0", "MPL-2.0"}


def license_status(spdx: str) -> str:
    if spdx in PERMISSIVE_SPDX:
        return "permissive"
    if spdx in COPYLEFT_SPDX:
        return "copyleft: needs license review before mirroring"
    return "unknown: needs license review before mirroring"

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
MARKER_RE = re.compile(
    r"\b(upstreamed|upstreaming|wip|work[- ]in[- ]progress|do[- ]not[- ]touch|don'?t touch|deprecated|"
    r"not intended to be proved|false as stated|this is false|from mathlib|mathlib pr|in mathlib now|"
    r"externally[_ ]verified)\b",  # curve25519-dalek: `@[externally_verified]` = intentional sorry
    re.IGNORECASE,
)
SKIP_PATH_RE = re.compile(r"(^|/)(test|tests|examples?|scratch|archive|\.lake|lake-packages)(/|$)", re.IGNORECASE)
SORRY_RE = re.compile(r"(?<![\w.'])sorry(?![\w'])")
IDENT_RE = re.compile(r"[A-Za-z_][\w'.]*")

# formal-conjectures gotcha classifiers:
# - `@[category research open | research solved | graduate | undergraduate | test | API | ...]`
# - `answer(sorry)` fill-in-the-blank statement placeholder
# - CC-BY-SA / GFDL / ShareAlike copyleft prose markers in comments/docstrings
FC_CATEGORY_RE = re.compile(
    r"@\[[^\]]*\bcategory\s+(?P<cat>research\s+open|research\s+solved|graduate|undergraduate|high_school|olympiad|test|API)\b",
    re.IGNORECASE,
)
FC_EXCLUDED_CATEGORIES = {"test", "API"}
ANSWER_SORRY_RE = re.compile(r"(?<![\w.'])answer\s*\(\s*sorry\s*\)")
COPYLEFT_DOC_RE = re.compile(
    r"\b(?:CC[- ]BY[- ]SA(?:\s*\d+(?:\.\d+)*)?|"
    r"Creative\s+Commons\s+Attribution[- ]ShareAlike|"
    r"ShareAlike\s+\d+(?:\.\d+)*|"
    r"GNU\s+Free\s+Documentation\s+License|"
    r"GFDL)\b",
    re.IGNORECASE,
)


def extract_fc_category(attr_text: str):
    """Extract normalized `formal-conjectures` `@[category ...]` tag from declaration attributes.

    Comments and strings are masked first so prose mentioning `@[category test]`
    never misclassifies a real theorem.
    """
    masked = mask_comments_and_strings(attr_text or "")
    matches = list(FC_CATEGORY_RE.finditer(masked))
    if not matches:
        return None
    raw = " ".join(matches[-1].group("cat").split())
    low = raw.lower()
    if low == "api":
        return "API"
    return low


def detect_copyleft_markers(text: str):
    """Return deduplicated CC-BY-SA / ShareAlike / GFDL docstring license markers."""
    seen, out = set(), []
    for m in COPYLEFT_DOC_RE.finditer(text or ""):
        norm = " ".join(m.group(0).split())
        key = re.sub(r"[-\s]+", "-", norm.lower())
        if key not in seen:
            seen.add(key)
            out.append(norm)
    return out


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


# ------------------------------------------------------------------ analysis

@dataclass
class Candidate:
    repo: str
    commit: str
    file: str
    line: int
    kind: str
    name: str
    url: str
    status: str  # "candidate" or "excluded"
    reasons: list
    blueprint: bool
    statement_uses_sorry_decl: list
    already_live: bool
    depends_on: list = field(default_factory=list)
    statement: str = ""
    hints: list = field(default_factory=list)
    domain: str = ""
    toolchain: str = ""
    packaging: str = ""  # "standalone-mathlib" or "repo-snapshot"
    project_imports: list = field(default_factory=list)
    packageable_now: bool = False
    open_work: list = field(default_factory=list)  # [{"kind", "number", "url", "match"}] from --check-prs
    category: str = ""  # formal-conjectures @[category ...] tag (e.g. "research open", "graduate")
    open_conjecture: bool = False  # True for @[category research open] two-sided prove-or-refute targets
    copyleft_markers: list = field(default_factory=list)  # CC-BY-SA / GFDL docstring markers flagged for license review
    raw_decl: str = ""  # verbatim declaration text (used by --scaffold; omitted from default compact reports)
    imports: list = field(default_factory=list)  # header imports of the upstream file


def analyze_file(rel: str, src: str):
    """Return [(decl, sorry_line, status, reasons)] for every sorry in a file."""
    out = []
    first_decl = next((i for i, l in enumerate(src.split("\n")) if DECL_RE.match(l)), 40)
    file_marked = bool(MARKER_RE.search("\n".join(src.split("\n")[: min(first_decl, 40)])))
    for d in split_declarations(src):
        if not d.sorry_lines:
            continue
        stmt_end = statement_end(d.code)
        stmt_code = d.code[:stmt_end] if stmt_end >= 0 else d.code
        stmt_line_end = d.start_line + d.code[: max(stmt_end, 0)].count("\n")
        stmt_has_answer_sorry = bool(ANSWER_SORRY_RE.search(stmt_code))
        stmt_has_sorry = bool(stmt_end >= 0 and SORRY_RE.search(stmt_code))
        fc_cat = extract_fc_category(d.attr_text)
        for sl in d.sorry_lines:
            reasons = []
            if d.kind not in PROOF_KINDS:
                reasons.append(f"{d.kind} sorry (not a theorem/lemma proof)")
            elif stmt_has_answer_sorry:
                reasons.append("statement contains answer(sorry) fill-in-the-blank")
            elif stmt_end < 0 or sl < stmt_line_end or stmt_has_sorry:
                reasons.append("sorry in the statement, not the proof")
            if fc_cat in FC_EXCLUDED_CATEGORIES:
                reasons.append(f"formal-conjectures @[category {fc_cat}]")
            if SKIP_PATH_RE.search(rel):
                reasons.append("test/example/scratch path")
            if file_marked:
                reasons.append("file header marked upstreamed/WIP/do-not-touch")
            m = MARKER_RE.search(d.attr_text + "\n" + d.raw)
            if m:
                reasons.append(f"marked '{m.group(0)}'")
            out.append((d, sl, "excluded" if reasons else "candidate", reasons))
    return out


LITERATURE_RE = re.compile(r"\\cite\{|\btitle\s*:=\s*\"[A-Z][\w-]+(?: et al\.?)? (?:\(\d{4}\) )?(?:Theorem|Lemma|Corollary|Proposition|Equation|Table)\b")
NUMERIC_RE = re.compile(
    r"10\s*\^\s*\(?\s*\d{2,}|\b\d+\.\d{3,}\b|\be\s*\^\s*\d{2,}|\b\d{7,}\b|\b\d+(?:\.\d+)?[eE]\d+\b|\bexp\s+\d{2,}\b|RH_up_to"
)
TRUSTED_FILE_RE = re.compile(r"trusted numerical|numerical (?:data|datum)|results? (?:are )?taken from|we record the results", re.IGNORECASE)


def feasibility_hints(attr_text: str, statement: str, file_text: str):
    """Soft signals for the human audit; they never exclude a candidate."""
    hints = []
    if LITERATURE_RE.search(attr_text):
        hints.append("cites a published result (may be a literature import, not meant to be proved here)")
    if NUMERIC_RE.search(statement):
        hints.append("explicit numerical constants (may need large verified computation)")
    if TRUSTED_FILE_RE.search("\n".join(file_text.split("\n")[:80])):
        hints.append("file collects trusted/literature results")
    if re.search(r"\bTODO\b", attr_text):
        hints.append("TODO near declaration")
    return hints


def detect_spdx(text: str) -> str:
    t = text[:4000]
    if re.search(r"Apache License\s*\n?\s*Version 2\.0", t, re.I):
        return "Apache-2.0"
    if re.search(r"GNU AFFERO GENERAL PUBLIC LICENSE", t, re.I):
        return "AGPL-3.0"
    if re.search(r"GNU LESSER GENERAL PUBLIC LICENSE", t, re.I):
        return "LGPL-3.0"
    if re.search(r"GNU GENERAL PUBLIC LICENSE", t, re.I):
        return "GPL-3.0"
    if re.search(r"Mozilla Public License", t, re.I):
        return "MPL-2.0"
    if re.search(r"Permission is hereby granted, free of charge", t, re.I):
        return "MIT"
    if re.search(r"Redistribution and use in source and binary forms", t, re.I):
        return "BSD-3-Clause" if re.search(r"Neither the name", t, re.I) else "BSD-2-Clause"
    return "UNKNOWN"


def live_task_lines(root: str = ROOT):
    """{(repo, path): [(lo, hi)]} for tasks already live in missions/*."""
    live = {}
    for mpath in glob.glob(os.path.join(root, "missions", "*", "sunstead.json")):
        try:
            with open(mpath, encoding="utf-8") as fh:
                manifest = json.load(fh)
        except (OSError, ValueError):
            continue
        for t in manifest.get("tasks", []):
            m = re.match(r"https://github\.com/([^/]+/[^/]+)/blob/[0-9a-f]{40}/([^#]+)#L(\d+)(?:-L(\d+))?", t.get("upstream_url") or "")
            if m:
                lo, hi = int(m.group(3)), int(m.group(4) or m.group(3))
                live.setdefault((m.group(1), m.group(2)), []).append((lo, hi))
    return live


def short(name: str) -> str:
    return name.rsplit(".", 1)[-1]


def link_dependencies(cands, proof_text_by_key):
    """Add `depends_on` edges: candidate A's proof text names candidate B
    (by full name, or by short name when that short name is unique)."""
    by_short = {}
    for c in cands:
        by_short.setdefault(short(c.name), []).append(c)
    for c in cands:
        idents = set(IDENT_RE.findall(proof_text_by_key.get((c.file, c.name), "")))
        deps = set()
        for other in cands:
            if other is c or other.name == c.name:
                continue
            s = short(other.name)
            hit = other.name in idents or any(i.endswith("." + s) and other.name.endswith(i) for i in idents)
            if not hit and s in idents and len(by_short[s]) == 1:
                hit = True
            if hit:
                deps.add(other.name)
        c.depends_on = sorted(deps)


# ------------------------------------------------- open upstream PRs/issues

def run_gh(args, timeout=None, run=subprocess.run):
    """Run a read-only `gh api` GET and return parsed JSON."""
    t = GH_TIMEOUT if timeout is None else timeout
    try:
        r = run(["gh", *args], capture_output=True, text=True, timeout=t, env={**os.environ, "GH_PROMPT_DISABLED": "1"})
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"gh {' '.join(args[:3])} timed out after {t}s")
    if r.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)}: {(r.stderr or '').strip().splitlines()[-1:] or r.returncode}")
    return json.loads(r.stdout or "null")


def gh_get(path, gh=run_gh):
    # Always an explicit GET: this tool never writes to GitHub.
    return gh(["api", "-X", "GET", "-H", "Accept: application/vnd.github+json", path])


def gh_paginate(path, gh=run_gh, max_items=200):
    items, page = [], 1
    sep = "&" if "?" in path else "?"
    while len(items) < max_items:
        batch = gh_get(f"{path}{sep}per_page=100&page={page}", gh) or []
        items.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return items[:max_items]


def fetch_open_work(repo, gh=run_gh, max_prs=100, max_issues=300):
    """Open PRs (with changed files and patches) and open issues of `repo`."""
    prs = []
    for pr in gh_paginate(f"repos/{repo}/pulls?state=open", gh, max_prs):
        files = gh_paginate(f"repos/{repo}/pulls/{pr['number']}/files", gh, 300)
        prs.append({
            "number": pr["number"], "url": pr.get("html_url", ""),
            "text": f"{pr.get('title') or ''}\n{pr.get('body') or ''}",
            "files": [{"filename": f.get("filename", ""), "patch": f.get("patch") or ""} for f in files],
        })
    issues = [
        {"number": i["number"], "url": i.get("html_url", ""), "text": f"{i.get('title') or ''}\n{i.get('body') or ''}"}
        for i in gh_paginate(f"repos/{repo}/issues?state=open", gh, max_issues)
        if "pull_request" not in i  # the issues endpoint lists PRs too
    ]
    return {"prs": prs, "issues": issues}


HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@(.*)$")


def hunks(patch):
    """[(old_start, old_len, header_context, lines)] of a unified diff."""
    out = []
    for line in patch.split("\n"):
        m = HUNK_RE.match(line)
        if m:
            out.append((int(m.group(1)), int(m.group(2) or 1), m.group(3), []))
        elif out:
            out[-1][3].append(line)
    return out


def name_pattern(name):
    return re.compile(r"(?<![\w.'])" + re.escape(short(name)) + r"(?![\w'])")


def declares(lines, sign, name):
    """Whether a diff line with this sign (+/-) starts the declaration `name`."""
    for l in lines:
        m = DECL_RE.match(l[1:]) if l.startswith(sign) else None
        if m and short(m.group("name")) == short(name):
            return True
    return False


def match_open_work(c, work):
    """Open PRs/issues that may already address candidate `c`.

    "deletes":  a PR removes the declaration itself (not a proof: flag it);
    "solves":   a PR hunk touching c.file removes more `sorry`s than it adds
                and either covers c.line in the old file or names the declaration;
    "edits":    a PR changes lines naming the declaration in c.file;
    "file":     a PR touches c.file;
    "mentions": a PR or issue title/body names the declaration."""
    pat = name_pattern(c.name)
    text_ok = len(short(c.name)) >= 4  # very short names give noisy text matches
    found = []
    for pr in work.get("prs", []):
        kind = None
        for f in pr["files"]:
            if f["filename"] != c.file:
                continue
            kind = kind or "file"
            for start, length, ctx, lines in hunks(f["patch"]):
                removed = sum(1 for l in lines if l.startswith("-") and SORRY_RE.search(l))
                added = sum(1 for l in lines if l.startswith("+") and SORRY_RE.search(l))
                covers = start <= c.line < start + max(length, 1)
                named = pat.search(ctx) or any(pat.search(l) for l in lines)
                if declares(lines, "-", c.name) and not declares(lines, "+", c.name):
                    kind = "deletes"  # the PR drops the declaration: flag it, it was not proved
                elif kind == "deletes":
                    pass
                elif removed > added and (covers or named):
                    kind = "solves"  # net fewer sorries: the PR fills it
                elif kind != "solves" and (
                    (removed and (covers or named))  # proof rewritten but still admitted
                    or any(l[:1] in "+-" and pat.search(l) for l in lines)
                ):
                    kind = "edits"
        if kind is None and text_ok and pat.search(pr["text"]):
            kind = "mentions"
        if kind:
            found.append({"kind": "pr", "number": pr["number"], "url": pr["url"], "match": kind})
    for iss in work.get("issues", []):
        if text_ok and pat.search(iss["text"]):
            found.append({"kind": "issue", "number": iss["number"], "url": iss["url"], "match": "mentions"})
    return found


def apply_open_work(cands, work):
    """Record open-work matches; a candidate a PR likely solves is excluded."""
    for c in cands:
        if c.status != "candidate":
            continue
        c.open_work = match_open_work(c, work)
        solving = [w for w in c.open_work if w["match"] == "solves"]
        if solving:
            c.status = "excluded"
            c.packageable_now = False
            c.reasons.append("likely solved in open PR " + ", ".join(f"#{w['number']}" for w in solving))


# ---------------------------------------------------------------------- git

def git(repo_dir, *args, check=True, timeout=None, run=subprocess.run):
    t = GIT_TIMEOUT if timeout is None else timeout
    try:
        r = run(["git", "-C", repo_dir, *args], capture_output=True, text=True, timeout=t)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"git {args[0] if args else ''} timed out after {t}s".strip())
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def ensure_clone(repo: str, workdir: str, timeout=None, run=subprocess.run) -> str:
    t = GIT_TIMEOUT if timeout is None else timeout
    d = os.path.join(workdir, repo.replace("/", "__"))
    if not os.path.isdir(os.path.join(d, ".git")):
        os.makedirs(workdir, exist_ok=True)
        try:
            r = run(
                ["git", "clone", "-q", "--filter=blob:none", "--no-checkout", f"https://github.com/{repo}", d],
                capture_output=True, text=True, timeout=t, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
            )
        except subprocess.TimeoutExpired:
            raise RuntimeError(f"clone timed out after {t}s")
        if r.returncode != 0:
            raise RuntimeError(f"clone failed: {r.stderr.strip().splitlines()[-1] if r.stderr.strip() else r.returncode}")
    else:
        git(d, "fetch", "-q", "origin", check=False, timeout=t, run=run)
    return d


PREFETCH_RE = re.compile(r"\.(lean|tex)$|(^|/)(LICENSE(\.md|\.txt)?|COPYING|lean-toolchain|lake-manifest\.json)$")


def wanted_blobs(ls_tree):
    """Blob ids of the files a scan reads, from `git ls-tree -r <commit>` output."""
    out = []
    for line in ls_tree.splitlines():
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) == 3 and parts[1] == "blob" and PREFETCH_RE.search(path):
            out.append(parts[2])
    return out


def prefetch_blobs(repo_dir, ls_tree, run=subprocess.run, timeout=None):
    """Fetch the blobs a scan needs in one round trip. In a blob:none partial
    clone, `git checkout` otherwise fetches missing blobs lazily, which takes
    minutes per repo. Best effort: on failure or timeout the lazy path still works."""
    blobs = wanted_blobs(ls_tree)
    if not blobs:
        return 0
    t = GIT_TIMEOUT if timeout is None else timeout
    try:
        r = run(
            ["git", "-C", repo_dir, "-c", "fetch.negotiationAlgorithm=noop", "fetch", "-q", "origin",
             "--no-tags", "--no-write-fetch-head", "--recurse-submodules=no", "--filter=blob:none", "--stdin"],
            input="\n".join(blobs) + "\n", capture_output=True, text=True, timeout=t,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        )
    except subprocess.TimeoutExpired:
        return 0
    return len(blobs) if r.returncode == 0 else 0


def show(repo_dir, commit, path, timeout=None, run=subprocess.run):
    t = GIT_TIMEOUT if timeout is None else timeout
    try:
        r = run(["git", "-C", repo_dir, "show", f"{commit}:{path}"], capture_output=True, timeout=t)
    except subprocess.TimeoutExpired:
        return None
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def pick_commit(repo_dir, toolchain):
    head = git(repo_dir, "rev-parse", "origin/HEAD" if git(repo_dir, "rev-parse", "--verify", "-q", "origin/HEAD", check=False).strip() else "HEAD").strip()
    if not toolchain:
        return head
    want = toolchain if toolchain.startswith("leanprover/") else f"leanprover/lean4:{toolchain}"
    if (show(repo_dir, head, "lean-toolchain") or "").strip() == want:
        return head
    for c in git(repo_dir, "log", "--format=%H", head, "--", "lean-toolchain").split():
        if (show(repo_dir, c, "lean-toolchain") or "").strip() == want:
            # newest commit *with* that toolchain: walk forward to the last one before it changed
            later = git(repo_dir, "rev-list", "--ancestry-path", "--reverse", f"{c}..{head}").split()
            last = c
            for nc in later:
                if (show(repo_dir, nc, "lean-toolchain") or "").strip() != want:
                    break
                last = nc
            return last
    return None


def mathlib_rev(manifest_text):
    try:
        for p in json.loads(manifest_text or "{}").get("packages", []):
            if p.get("name") == "mathlib":
                return p.get("inputRev") or p.get("rev")
    except ValueError:
        pass
    return None


def checkout_files(repo_dir, commit, files, chunk_size=500, runner=None):
    """Check out `files` at `commit` in bounded argv batches to avoid OS E2BIG."""
    run = runner or subprocess.run
    for i in range(0, len(files), chunk_size):
        run(
            ["git", "-C", repo_dir, "checkout", "-q", "--force", commit, "--", *files[i : i + chunk_size]],
            capture_output=True,
            timeout=GIT_TIMEOUT,
        )


def scout_repo(repo, workdir, toolchain, live, check_prs=False, gh=run_gh):
    info = {"repo": repo, "domain": DOMAIN_OF.get(repo, "other"), "error": None}
    try:
        d = ensure_clone(repo, workdir)
        commit = pick_commit(d, toolchain)
        if not commit:
            info["error"] = f"no commit with lean-toolchain {toolchain}"
            info["head_toolchain"] = (show(d, git(d, "rev-parse", "HEAD").strip(), "lean-toolchain") or "").strip()
            return info, []
    except RuntimeError as e:
        info["error"] = str(e)
        return info, []
    # One batched fetch of every blob read below (license, toolchain, manifest,
    # blueprint .tex, .lean); without it a partial clone fetches them one by one.
    prefetch_blobs(d, git(d, "ls-tree", "-r", commit))
    lic_text = next((t for t in (show(d, commit, p) for p in ("LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING")) if t), "")
    info.update(
        commit=commit,
        toolchain=(show(d, commit, "lean-toolchain") or "").strip(),
        mathlib=mathlib_rev(show(d, commit, "lake-manifest.json")),
        license=detect_spdx(lic_text),
        license_text=lic_text,
    )
    info["license_status"] = license_status(info["license"])
    files = [f for f in git(d, "ls-tree", "-r", "--name-only", commit).split("\n") if f.endswith(".lean")]
    blueprint_tex = "\n".join(
        show(d, commit, f) or "" for f in git(d, "ls-tree", "-r", "--name-only", commit).split("\n")
        if f.startswith("blueprint/") and f.endswith(".tex")
    )
    blueprint_names = set(re.findall(r"\\lean\{([^}]*)\}", blueprint_tex))
    blueprint_names = {n.strip() for group in blueprint_names for n in group.split(",")}

    # Check out the (prefetched) .lean blobs, then read them.
    cands, proof_text, sorry_decls = [], {}, {}
    contents = {}
    if files:
        try:
            checkout_files(d, commit, files)
        except subprocess.TimeoutExpired:
            info["error"] = f"git checkout timed out after {GIT_TIMEOUT}s"
            return info, []
    for f in files:
        p = os.path.join(d, f)
        try:
            contents[f] = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            contents[f] = show(d, commit, f) or ""
        if not SORRY_RE.search(contents[f]):
            continue
        f_imports = file_imports(contents[f])
        packaging, project_imports = classify_packaging(f_imports)
        file_header_copyleft = detect_copyleft_markers("\n".join(contents[f].split("\n")[:80]))
        for decl, line, status, reasons in analyze_file(f, contents[f]):
            sorry_decls.setdefault(decl.name, decl)
            stmt_end = statement_end(decl.code)
            stmt = decl.code[: stmt_end if stmt_end > 0 else len(decl.code)]
            proof_text[(f, decl.name)] = decl.code[stmt_end:] if stmt_end > 0 else ""
            has_bp = "@[blueprint" in decl.attr_text or "blueprint" in decl.attr_text.split("\n")[-1] or decl.name in blueprint_names or short(decl.name) in {short(n) for n in blueprint_names}
            is_live = any(lo <= line <= hi for lo, hi in live.get((repo, f), []))
            fc_cat = extract_fc_category(decl.attr_text) or ""
            copyleft_markers = list(dict.fromkeys(
                file_header_copyleft + detect_copyleft_markers(decl.attr_text + "\n" + decl.raw)
            ))
            hints = feasibility_hints(decl.attr_text, stmt, contents[f])
            if copyleft_markers:
                hints.append(
                    f"copyleft docstring marker ({', '.join(copyleft_markers)}): review/strip prose before mirroring"
                )
            cands.append(Candidate(
                repo=repo, commit=commit, file=f, line=line, kind=decl.kind, name=decl.name,
                url=f"https://github.com/{repo}/blob/{commit}/{f}#L{decl.start_line}-L{line}",
                status=status, reasons=reasons, blueprint=has_bp, statement_uses_sorry_decl=[],
                already_live=is_live, statement=" ".join(stmt.split())[:300],
                hints=hints,
                domain=info["domain"], toolchain=info["toolchain"],
                packaging=packaging, project_imports=project_imports,
                category=fc_cat,
                open_conjecture=(fc_cat == "research open"),
                copyleft_markers=copyleft_markers,
                raw_decl=decl.raw,
                imports=f_imports,
            ))
    # Vacuity hint: statement mentions a definition that itself has a sorry.
    sorry_defs = {n for n, dcl in sorry_decls.items() if dcl.kind not in PROOF_KINDS}
    sorry_def_short = {short(n): n for n in sorry_defs}
    for c in cands:
        idents = set(IDENT_RE.findall(c.statement.split(" ", 2)[-1]))
        c.statement_uses_sorry_decl = sorted({sorry_def_short[short(i)] for i in idents if short(i) in sorry_def_short and short(i) != short(c.name)})
        if c.status == "candidate" and c.statement_uses_sorry_decl:
            c.status = "excluded"
            c.reasons.append("statement uses a sorry'd definition: " + ", ".join(c.statement_uses_sorry_decl))
    # One entry per declaration for candidates (several sorries in one proof are one task).
    seen, uniq = set(), []
    for c in cands:
        key = (c.file, c.name, c.status)
        if key in seen:
            continue
        seen.add(key)
        uniq.append(c)
    for c in uniq:
        c.packageable_now = (
            c.status == "candidate" and c.packaging == "standalone-mathlib"
            and c.toolchain == SUPPORTED_TOOLCHAIN and info["license_status"] == "permissive"
            and not c.copyleft_markers
        )
    if check_prs and any(c.status == "candidate" for c in uniq):
        try:
            apply_open_work(uniq, fetch_open_work(repo, gh))
            info["open_work_checked"] = True
        except (RuntimeError, ValueError, KeyError, TypeError) as e:
            info["open_work_checked"] = False
            info["open_work_error"] = str(e)
    open_cands = [c for c in uniq if c.status == "candidate"]
    link_dependencies(open_cands, proof_text)
    return info, uniq


def license_class(spdx):
    return license_status(spdx).split(":", 1)[0]


def group_by_toolchain(results):
    """{(toolchain, license_class): counts} over repos that scanned cleanly."""
    groups = {}
    for info, cands in results:
        if info.get("error"):
            continue
        g = groups.setdefault((info["toolchain"] or "unknown", license_class(info["license"])), {
            "repos": [], "standalone-mathlib": 0, "repo-snapshot": 0, "packageable_now": 0,
        })
        g["repos"].append(info["repo"])
        for c in cands:
            if c.status == "candidate":
                g[c.packaging] = g.get(c.packaging, 0) + 1
                g["packageable_now"] += c.packageable_now
    return dict(sorted(groups.items()))


# ------------------------------------------------------- dynamic discovery

GITHUB_REPO_URL_RE = re.compile(
    r"https?://github\.com/(?P<owner>[A-Za-z0-9_.-]+)/(?P<name>[A-Za-z0-9_.-]+?)(?:\.git)?(?:[/#?\"'\s,}\]]|$)"
)
OWNER_REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
DISCOVER_SKIP_REPOS = {
    "leanprover-community/mathlib4",
    "leanprover/lean4",
    "leanprover/std4",
    "leanprover-community/batteries",
}


def normalize_github_repo(raw: str):
    """Extract canonical `owner/name` from a GitHub URL or `owner/name` slug, else None."""
    if not isinstance(raw, str):
        return None
    s = raw.strip().strip("\"'")
    if not s:
        return None
    m = GITHUB_REPO_URL_RE.search(s)
    if m:
        repo = f"{m.group('owner')}/{m.group('name')}"
    elif OWNER_REPO_RE.fullmatch(s):
        repo = s[:-4] if s.endswith(".git") else s
    else:
        return None
    if repo.endswith(".git"):
        repo = repo[:-4]
    return repo if OWNER_REPO_RE.fullmatch(repo) else None


def parse_downstream_repos_yml(text: str):
    """Parse Mathlib's `downstream-repos.yml` (stdlib-only, no PyYAML needed).

    Supports mapping-style (`name:\n  url: https://github.com/...`), list-of-dicts
    (`- repo: owner/name` / `- url: ...`), and plain URL/slug lists.
    Returns deduplicated `[{'repo', 'source', 'branch', 'name'}]`.
    """
    found = []
    seen = set()
    current_name = None
    current_branch = None
    for raw_line in (text or "").splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        stripped = line.strip()
        # Top-level YAML key (e.g. `flt:` or `PrimeNumberTheoremAnd:`)
        if not raw_line[0].isspace() and stripped.endswith(":") and not stripped.startswith("-"):
            current_name = stripped[:-1].strip().strip("\"'")
            current_branch = None
            continue
        bm = re.match(r"^-?\s*(?:branch|rev|default_branch)\s*:\s*(.+)$", stripped)
        if bm:
            current_branch = bm.group(1).strip().strip("\"'")
            if found and current_name and found[-1]["name"] == current_name and not found[-1]["branch"]:
                found[-1]["branch"] = current_branch
            continue
        repo = None
        for key_re in (
            r"^-?\s*(?:url|git|repo_url|repository|github)\s*:\s*(.+)$",
            r"^-?\s*repo\s*:\s*(.+)$",
        ):
            km = re.match(key_re, stripped)
            if km:
                repo = normalize_github_repo(km.group(1))
                break
        if repo is None and (stripped.startswith("- ") or "github.com/" in stripped):
            val = stripped[2:].strip() if stripped.startswith("- ") else stripped
            repo = normalize_github_repo(val)
        if repo and repo not in seen and repo not in DISCOVER_SKIP_REPOS:
            seen.add(repo)
            found.append({
                "repo": repo,
                "source": "mathlib-downstream",
                "name": current_name or repo.split("/", 1)[1],
                "branch": current_branch,
            })
    return found


def parse_reservoir_metadata(data, *, min_stars=0, lean_version_prefix=None):
    """Parse one or many `leanprover/reservoir-index` metadata JSON records.

    Accepts a JSON string, a single metadata dict, or a list of metadata dicts.
    Filters by `min_stars` and optional `lean_version_prefix` (e.g. 'v4.36.0' or '4.36').
    """
    if isinstance(data, str):
        data = json.loads(data or "[]")
    records = data if isinstance(data, list) else ([data] if isinstance(data, dict) else [])
    found = []
    seen = set()
    want_ver = (lean_version_prefix or "").lstrip("v").strip()
    for rec in records:
        if not isinstance(rec, dict):
            continue
        stars = int(rec.get("stars") or 0)
        if stars < min_stars:
            continue
        repo = None
        for src in rec.get("sources") or []:
            if not isinstance(src, dict):
                continue
            for k in ("fullName", "repoUrl", "gitUrl", "url"):
                repo = normalize_github_repo(src.get(k) or "")
                if repo:
                    break
            if repo:
                break
        if not repo:
            for k in ("fullName", "repo", "repository", "homepage"):
                repo = normalize_github_repo(rec.get(k) or "")
                if repo:
                    break
        if not repo or repo in seen or repo in DISCOVER_SKIP_REPOS:
            continue
        toolchains = []
        for b in rec.get("builds") or []:
            if isinstance(b, dict) and b.get("toolchain"):
                toolchains.append(str(b["toolchain"]))
        tc = str(rec.get("toolchain") or (toolchains[0] if toolchains else ""))
        if want_ver and tc and want_ver not in tc.lstrip("v"):
            continue
        if want_ver and not tc:
            continue
        seen.add(repo)
        found.append({
            "repo": repo,
            "source": "reservoir-index",
            "name": rec.get("name") or repo.split("/", 1)[1],
            "stars": stars,
            "license": rec.get("license") or "",
            "toolchain": tc,
            "keywords": list(rec.get("keywords") or []),
        })
    found.sort(key=lambda r: (-int(r.get("stars") or 0), r["repo"].lower()))
    return found


def parse_reservoir_tree(tree_payload):
    """Extract `owner/name` candidates from a single GitHub recursive tree response of
    `leanprover/reservoir-index` (`owner/pkg/metadata.json` paths, 1 API call total)."""
    if isinstance(tree_payload, str):
        tree_payload = json.loads(tree_payload or "{}")
    entries = tree_payload.get("tree", []) if isinstance(tree_payload, dict) else []
    found, seen = [], set()
    for e in entries:
        if not isinstance(e, dict):
            continue
        path = str(e.get("path") or "")
        parts = path.split("/")
        if len(parts) == 3 and parts[2] == "metadata.json":
            repo = normalize_github_repo(f"{parts[0]}/{parts[1]}")
            if repo and repo not in seen and repo not in DISCOVER_SKIP_REPOS:
                seen.add(repo)
                found.append({
                    "repo": repo,
                    "source": "reservoir-index",
                    "name": parts[1],
                    "metadata_path": path,
                })
    return found


def fetch_url_text(url: str, timeout=None) -> str:
    """Read-only HTTPS GET with explicit timeout and Sunstead User-Agent."""
    t = HTTP_TIMEOUT if timeout is None else timeout
    req = urllib.request.Request(url, headers={"User-Agent": DISCOVER_UA})
    try:
        with urllib.request.urlopen(req, timeout=t) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise RuntimeError(f"GET {url} failed: {e}")


def discover_repos(
    *,
    source="all",
    limit=50,
    min_stars=0,
    toolchain_prefix=None,
    exclude_watchlist=False,
    http_get=fetch_url_text,
    gh=run_gh,
):
    """Discover Lean 4 repositories from Mathlib's `downstream-repos.yml` and/or
    `leanprover/reservoir-index` with strict rate-limit/timeout hygiene.

    Returns `(discovered_records, warnings)`. Network/API failures degrade
    gracefully into warnings rather than crashing.
    """
    discovered = []
    warnings = []
    seen = set(WATCHLIST) if exclude_watchlist else set()

    if source in ("all", "downstream"):
        try:
            yml = http_get(MATHLIB_DOWNSTREAM_YML_URL)
            for item in parse_downstream_repos_yml(yml):
                if item["repo"] not in seen:
                    seen.add(item["repo"])
                    discovered.append(item)
        except Exception as e:
            warnings.append(f"downstream-repos.yml fetch failed: {e}")

    if source in ("all", "reservoir") and (limit <= 0 or len(discovered) < limit):
        try:
            tree = gh_get(f"repos/{RESERVOIR_INDEX_REPO}/git/trees/HEAD?recursive=1", gh=gh)
            tree_items = parse_reservoir_tree(tree)
            if min_stars > 0 or toolchain_prefix:
                # Rate-limit hygiene: fetch individual raw metadata.json only up to a bounded cap.
                cap = min(len(tree_items), max(limit * 3, 60) if limit > 0 else 150)
                meta_recs = []
                for ti in tree_items[:cap]:
                    raw_url = f"https://raw.githubusercontent.com/{RESERVOIR_INDEX_REPO}/HEAD/{ti['metadata_path']}"
                    try:
                        meta_recs.append(json.loads(http_get(raw_url)))
                    except Exception:
                        continue
                parsed = parse_reservoir_metadata(
                    meta_recs, min_stars=min_stars, lean_version_prefix=toolchain_prefix
                )
                for item in parsed:
                    if item["repo"] not in seen:
                        seen.add(item["repo"])
                        discovered.append(item)
            else:
                for item in tree_items:
                    if item["repo"] not in seen:
                        seen.add(item["repo"])
                        discovered.append(item)
        except Exception as e:
            warnings.append(f"reservoir-index discovery failed: {e}")

    if limit and limit > 0:
        discovered = discovered[:limit]
    return discovered, warnings


# ------------------------------------------------------- arena pack scaffold

TOOLCHAIN_VERIFIER_IMAGE = {
    "leanprover/lean4:v4.36.0": "sunstead/verifier-lean4:v0.2",
    "leanprover/lean4:v4.35.0": "sunstead/verifier-lean4-v4.35.0:v0.1",
    "leanprover/lean4:v4.31.0": "sunstead/verifier-lean4-v4.31.0:v0.1",
}


def slugify_id(raw: str, max_len=48) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "_", raw).strip("_").lower()
    if not s or not s[0].isalpha():
        s = "t_" + s
    return s[:max_len].rstrip("_")


def pascal_ident(raw: str, fallback="SunsteadPack") -> str:
    parts = [p for p in re.split(r"[^A-Za-z0-9]+", raw) if p]
    out = "".join(p[0].upper() + p[1:] for p in parts)
    if not out or not out[0].isalpha():
        out = fallback + out
    return out


def infer_topic_from_path(rel_path: str) -> str:
    """Derive a clean topic slug from a Lean file path (e.g. `FormalConjectures/ErdosProblems/12.lean` -> `erdos-problems`)."""
    norm = rel_path.replace("\\", "/").strip("/")
    parts = norm.split("/")
    if len(parts) >= 3:
        raw = parts[1]
    elif len(parts) == 2:
        raw = os.path.splitext(parts[1])[0]
    else:
        raw = os.path.splitext(parts[0])[0]
    # Split CamelCase -> kebab-case
    kebab = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", raw)
    kebab = re.sub(r"[^a-zA-Z0-9]+", "-", kebab).strip("-").lower()
    return kebab or "general"


def shard_candidates_by_topic(candidates, *, shard_size=50, prefix=""):
    """Group vetted candidates into topic-sharded Arena Packs (default 50 tasks/pack,
    splitting open conjectures (`research open`) cleanly from non-open tasks).

    Returns `[{'mission_id', 'topic', 'open_conjecture', 'candidates'}]`.
    """
    shard_size = max(1, int(shard_size))
    buckets = {}
    for c in candidates:
        topic = infer_topic_from_path(c.file)
        is_oc = bool(getattr(c, "open_conjecture", False) or getattr(c, "category", "") == "research open")
        buckets.setdefault((topic, is_oc), []).append(c)

    packs = []
    pref = re.sub(r"[^a-z0-9-]+", "-", (prefix or "").lower()).strip("-")
    for (topic, is_oc), items in sorted(buckets.items()):
        items = sorted(items, key=lambda x: (x.file, x.line, x.name))
        total_shards = (len(items) + shard_size - 1) // shard_size
        for shard_idx in range(total_shards):
            chunk = items[shard_idx * shard_size : (shard_idx + 1) * shard_size]
            parts = [p for p in (pref, topic, "open" if is_oc else "") if p]
            if total_shards > 1:
                parts.append(f"{shard_idx + 1:02d}")
            mission_id = "-".join(parts)
            packs.append({
                "mission_id": mission_id,
                "topic": topic,
                "open_conjecture": is_oc,
                "candidates": chunk,
            })
    return packs


def _extract_statement_prop_from_decl(cand: Candidate) -> str:
    """Build a best-effort Prop expression for `SunsteadStatements` from a candidate's statement."""
    stmt = (cand.statement or "").strip()
    # Strip leading attributes/modifiers and `theorem|lemma <name>`
    m = DECL_RE.match(stmt)
    rest = stmt[m.end():].strip() if m else stmt
    # Split top-level binders before `:` if present; fall back to `True` placeholder with comment.
    depth = 0
    colon_pos = -1
    for i, ch in enumerate(rest):
        if ch in "([{⦃⟨":
            depth += 1
        elif ch in ")]}⦄⟩":
            depth = max(0, depth - 1)
        elif depth == 0 and ch == ":":
            if i + 1 < len(rest) and rest[i + 1] == "=":
                break
            colon_pos = i
            break
    if colon_pos < 0:
        return rest or "True"
    binders = rest[:colon_pos].strip()
    ret = rest[colon_pos + 1 :].strip()
    if binders:
        return f"∀ {binders}, {ret}"
    return ret


def _strip_fc_category_attr(decl_body: str) -> str:
    """Strip inline `@[category ...]` attribute prefix when scaffolding standalone Mathlib stubs."""
    return re.sub(r"^@\[[^\]]*\bcategory\b[^\]]*\]\s*", "", decl_body.strip(), flags=re.IGNORECASE)


def _clean_task_stub(lib_root: str, task_thm_short: str, cand: Candidate) -> str:
    """Render a clean target `.lean` stub preserving the upstream signature + `sorry`."""
    imports = [f"import {lib_root}.Spec"]
    for imp in cand.imports or []:
        root = imp.split(".", 1)[0]
        if root in STANDALONE_IMPORT_ROOTS and imp != "Mathlib":
            imp_line = f"import {imp}"
            if imp_line not in imports:
                imports.append(imp_line)
    # Build declaration text: reuse verbatim upstream declaration if clean, else synthesize from statement.
    decl_body = _strip_fc_category_attr(cand.raw_decl or "")
    if decl_body:
        lines = [
            *imports,
            "",
            f"namespace {lib_root}",
            "",
            f"-- Upstream: {cand.url}",
            decl_body,
            "",
            f"end {lib_root}",
            "",
        ]
        return "\n".join(lines)
    stmt = _strip_fc_category_attr(cand.statement or f"theorem {task_thm_short} : True")
    return "\n".join([
        *imports,
        "",
        f"namespace {lib_root}",
        "",
        f"-- Upstream: {cand.url}",
        f"{stmt} := by",
        "  sorry",
        "",
        f"end {lib_root}",
        "",
    ])


def scaffold_arena_packs(
    results,
    out_dir: str,
    *,
    shard_size=50,
    prefix="",
    allow_copyleft_docs=False,
    include_live=False,
):
    """Turn vetted scout candidates into ready-to-verify Sunstead Arena Pack directories.

    Creates `<out_dir>/<mission-id>/` containing:
      - `sunstead.json` (with `"open_conjecture": true` on `research open` packs)
      - `UPSTREAM.json` (pinned 40-char commit SHA + verbatim snippet checks)
      - `LICENSE` (verbatim upstream license text)
      - `lean-toolchain` & `lakefile.toml`
      - `<LibRoot>/Spec.lean` & per-task `<LibRoot>/<Task>.lean` stubs
      - executable `./verify` script matching `sunstead_sandbox.lean_verify` + `sync-assets.mjs` AST contract

    Returns a list of summary dicts for every scaffolded pack.
    """
    os.makedirs(out_dir, exist_ok=True)
    written = []

    for info, cands in results:
        if info.get("error"):
            continue
        repo = info.get("repo", "")
        commit = info.get("commit", "")
        toolchain = (info.get("toolchain") or SUPPORTED_TOOLCHAIN).strip()
        lic = info.get("license") or "UNKNOWN"
        lic_text = info.get("license_text") or f"Upstream license ({lic}) from https://github.com/{repo}@{commit}\n"
        mathlib_ver = info.get("mathlib") or toolchain.split(":")[-1]
        verifier_img = TOOLCHAIN_VERIFIER_IMAGE.get(toolchain, TOOLCHAIN_VERIFIER_IMAGE[SUPPORTED_TOOLCHAIN])

        vetted = [
            c for c in cands
            if c.status == "candidate"
            and (include_live or not c.already_live)
            and (allow_copyleft_docs or not c.copyleft_markers)
        ]
        if not vetted:
            continue

        repo_prefix = prefix or slugify_id(repo.split("/", 1)[-1], max_len=24).replace("_", "-")
        packs = shard_candidates_by_topic(vetted, shard_size=shard_size, prefix=repo_prefix)
        for pack in packs:
            mission_id = pack["mission_id"]
            is_open_conj = pack["open_conjecture"]
            pack_cands = pack["candidates"]
            mdir = os.path.join(out_dir, mission_id)
            lib_root = pascal_ident(mission_id)
            lib_dir = os.path.join(mdir, lib_root)
            os.makedirs(lib_dir, exist_ok=True)

            # 1. lean-toolchain, LICENSE, lakefile.toml, Spec.lean
            with open(os.path.join(mdir, "lean-toolchain"), "w", encoding="utf-8") as fh:
                fh.write(toolchain + "\n")
            with open(os.path.join(mdir, "LICENSE"), "w", encoding="utf-8") as fh:
                fh.write(lic_text)
            uses_mathlib = any(
                any(imp == "Mathlib" or imp.startswith("Mathlib.") for imp in (c.imports or []))
                for c in pack_cands
            ) or any(c.packaging == "standalone-mathlib" for c in pack_cands)
            lakefile_lines = [
                f'name = "{mission_id.replace("-", "_")}"',
                'version = "0.1.0"',
                "",
            ]
            if uses_mathlib:
                lakefile_lines.extend([
                    "[[require]]",
                    'name = "mathlib"',
                    'git = "https://github.com/leanprover-community/mathlib4.git"',
                    f'rev = "{mathlib_ver}"',
                    "",
                ])
            lakefile_lines.extend(["[[lean_lib]]", f'name = "{lib_root}"', ""])
            with open(os.path.join(mdir, "lakefile.toml"), "w", encoding="utf-8") as fh:
                fh.write("\n".join(lakefile_lines))

            spec_rel = f"{lib_root}/Spec.lean"
            spec_lines = [
                "import Mathlib" if uses_mathlib else "-- Core Lean 4 spec",
                "",
                f"namespace {lib_root}",
                f"-- Shared frozen definitions for {mission_id} ({repo}@{commit[:12]}).",
                f"end {lib_root}",
                "",
            ]
            with open(os.path.join(mdir, spec_rel), "w", encoding="utf-8") as fh:
                fh.write("\n".join(spec_lines))

            # 2. Per-task target files, manifest tasks, verify TASKS, UPSTREAM.json checks
            used_task_ids = set()
            used_mod_names = set()
            manifest_tasks = []
            verify_tasks = {}
            upstream_checks = []
            cand_to_task_id = {}

            for idx, c in enumerate(pack_cands, start=1):
                base_tid = slugify_id(short(c.name) or f"task_{idx}")
                tid = base_tid
                suffix = 2
                while tid in used_task_ids:
                    tid = f"{base_tid}_{suffix}"
                    suffix += 1
                used_task_ids.add(tid)
                cand_to_task_id[c.name] = tid

                base_mod = pascal_ident(short(c.name) or f"Task{idx}", fallback="Task")
                mod_leaf = base_mod
                msuf = 2
                while mod_leaf in used_mod_names:
                    mod_leaf = f"{base_mod}{msuf}"
                    msuf += 1
                used_mod_names.add(mod_leaf)

                rel_target = f"{lib_root}/{mod_leaf}.lean"
                full_mod = f"{lib_root}.{mod_leaf}"
                clean_decl = _strip_fc_category_attr(c.raw_decl or "")
                dm = DECL_RE.match(clean_decl.splitlines()[0]) if clean_decl else None
                declared_name = (dm.group("name") if dm and dm.group("name") else short(c.name) or tid)
                stub_src = _clean_task_stub(lib_root, declared_name, c)
                with open(os.path.join(mdir, rel_target), "w", encoding="utf-8") as fh:
                    fh.write(stub_src)

                prop_expr = _extract_statement_prop_from_decl(c)
                verify_tasks[tid] = {
                    "module": full_mod,
                    "theorem": f"{lib_root}.{declared_name}",
                    "statement": f"\ndef {tid} : Prop :=\n  {prop_expr}\n",
                }
                snippet = (clean_decl.splitlines()[0] if clean_decl else _strip_fc_category_attr(c.statement)).strip()
                if snippet:
                    upstream_checks.append({
                        "local_file": rel_target,
                        "upstream_file": c.file,
                        "verbatim_snippet": snippet,
                    })
                manifest_tasks.append({
                    "id": tid,
                    "title": f"{'Open conjecture' if is_open_conj else 'Prove'}: {c.name}",
                    "description": f"Upstream `{c.file}:{c.line}` from `{repo}@{commit[:12]}`"
                    + (f" (`@[category {c.category}]`)" if c.category else "") + ".",
                    "target_files": [rel_target],
                    "depends_on": [],  # wired in second pass below
                    "upstream_url": c.url,
                })

            # Wire intra-pack dependency edges cleanly.
            for t_obj, c in zip(manifest_tasks, pack_cands):
                deps = [
                    cand_to_task_id[d]
                    for d in (c.depends_on or [])
                    if d in cand_to_task_id and cand_to_task_id[d] != t_obj["id"]
                ]
                t_obj["depends_on"] = sorted(set(deps))

            frozen_paths = [
                spec_rel,
                "UPSTREAM.json",
                "lakefile.toml",
                "lean-toolchain",
                "verify",
                "sunstead.json",
            ]
            manifest = {
                "id": mission_id,
                "title": f"{repo.split('/', 1)[-1]} ({pack['topic']}): "
                + ("Open Conjectures" if is_open_conj else "Upstream Proof Obligations"),
                "description": (
                    f"Scaffolded Arena Pack ({len(manifest_tasks)} tasks) from {repo}@{commit[:12]} "
                    f"({lic}, {toolchain}). Audit compiled statements and axioms before publishing."
                ),
                "tier": 1,
                "mode": "dag",
                "repo": f"https://github.com/{repo}",
                "upstream": {
                    "repo": repo,
                    "commit": commit,
                    "license": lic,
                },
                **({"open_conjecture": True} if is_open_conj else {}),
                "frozen_paths": frozen_paths,
                "verifier": {
                    "image": verifier_img,
                    "toolchain": toolchain,
                    "command": ["./verify"],
                    "timeout_sec": 180,
                    "memory_mb": 6144,
                },
                "score_direction": "maximize",
                "tasks": manifest_tasks,
            }
            with open(os.path.join(mdir, "sunstead.json"), "w", encoding="utf-8") as fh:
                json.dump(manifest, fh, indent=2, ensure_ascii=False)
                fh.write("\n")

            upstream_json = {
                "repo": repo,
                "commit": commit,
                "license": lic,
                "checks": upstream_checks,
            }
            with open(os.path.join(mdir, "UPSTREAM.json"), "w", encoding="utf-8") as fh:
                json.dump(upstream_json, fh, indent=2, ensure_ascii=False)
                fh.write("\n")

            verify_frozen = [spec_rel, "UPSTREAM.json", "lakefile.toml", "lean-toolchain"]
            verify_src = (
                "#!/usr/bin/env python3\n"
                f'"""Frozen verifier for `{mission_id}` (scaffolded by scout-upstream.py)."""\n'
                "import sys\n\n"
                'sys.path.insert(0, "/opt/sunstead")\n'
                "from sunstead_sandbox import emit, lean_verify  # noqa: E402\n\n"
                f"LIB_ROOT = {lib_root!r}\n"
                f"FROZEN_FILES = {json.dumps(verify_frozen, indent=4)}\n"
                'STATEMENT_PREAMBLE = ""\n'
                f"TASKS = {json.dumps(verify_tasks, indent=4, ensure_ascii=False)}\n\n"
                'if __name__ == "__main__":\n'
                "    if len(sys.argv) < 2:\n"
                '        emit(False, "usage: ./verify <task_id>")\n'
                "    lean_verify(\n"
                "        sys.argv[1],\n"
                "        lib_root=LIB_ROOT,\n"
                "        frozen_files=FROZEN_FILES,\n"
                "        tasks=TASKS,\n"
                f"        uses_mathlib={uses_mathlib!r},\n"
                "        statement_preamble=STATEMENT_PREAMBLE,\n"
                "        timeout_sec=170,\n"
                "    )\n"
            )
            verify_path = os.path.join(mdir, "verify")
            with open(verify_path, "w", encoding="utf-8") as fh:
                fh.write(verify_src)
            os.chmod(verify_path, os.stat(verify_path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

            written.append({
                "mission_id": mission_id,
                "dir": mdir,
                "repo": repo,
                "commit": commit,
                "toolchain": toolchain,
                "open_conjecture": is_open_conj,
                "tasks": len(manifest_tasks),
            })
    return written


def load_results_from_json(path: str):
    """Reload `[(info, [Candidate, ...])]` from a previous `--format json` output."""
    with open(path, encoding="utf-8") as fh:
        raw = json.load(fh)
    valid_fields = set(Candidate.__dataclass_fields__.keys())
    results = []
    for entry in raw:
        info = {k: v for k, v in entry.items() if k != "sorries"}
        cands = [
            Candidate(**{k: v for k, v in row.items() if k in valid_fields})
            for row in entry.get("sorries", [])
        ]
        results.append((info, cands))
    return results


# ------------------------------------------------------------------- output

def open_work_cell(c, checked):
    if not checked:
        return "not checked"
    if not c.open_work:
        return "clear"
    return ", ".join(f"[{'PR' if w['kind'] == 'pr' else 'issue'} #{w['number']}]({w['url']}) {w['match']}" for w in c.open_work)


def render_markdown(results, toolchain, check_prs=False):
    out = [
        f"# Upstream sorry scout{f' (toolchain {toolchain})' if toolchain else ''}",
        "",
        "> A candidate here passed a static scan only. Before packaging one, check that it is still open on",
        "> upstream main and not claimed in an open upstream PR or issue thread, then `lake build` it at the",
        "> pin and audit its axioms (DESIGN.md Section 4, criteria 2 and 3).",
        ">",
        f"> `standalone-mathlib`: the file imports only Mathlib and its dependencies. `repo-snapshot`: it imports",
        f"> project modules and needs the repo-snapshot verifier. Packageable now = standalone-mathlib on",
        f"> `{SUPPORTED_TOOLCHAIN}` with a permissive license.",
        "",
    ]
    out.append("| Repo | Domain | Commit | Toolchain | Mathlib | License | Candidates | Excluded |")
    out.append("|---|---|---|---|---|---|---|---|")
    for info, cands in results:
        if info.get("error"):
            out.append(f"| {info['repo']} | {info.get('domain', '')} | — | {info.get('head_toolchain', '—')} | — | — | error: {info['error']} | — |")
            continue
        n_c = sum(1 for c in cands if c.status == "candidate")
        out.append(
            f"| {info['repo']} | {info.get('domain', '')} | `{info['commit'][:12]}` | {info['toolchain']} | "
            f"{info['mathlib'] or '—'} | {info['license']} | {n_c} | {len(cands) - n_c} |"
        )
    out.append("")
    out.append("## Candidates by toolchain and license")
    out.append("")
    out.append("| Toolchain | License | Repos | standalone-mathlib | repo-snapshot | Packageable now |")
    out.append("|---|---|---|---|---|---|")
    for (tc, lic), g in group_by_toolchain(results).items():
        out.append(f"| {tc} | {lic} | {', '.join(g['repos'])} | {g['standalone-mathlib']} | {g['repo-snapshot']} | {g['packageable_now']} |")
    out.append("")
    for info, cands in results:
        open_c = [c for c in cands if c.status == "candidate"]
        if info.get("open_work_error"):
            out.append(f"> {info['repo']}: open PR/issue check failed: {info['open_work_error']}")
            out.append("")
        if not open_c:
            continue
        checked = check_prs and info.get("open_work_checked")
        out.append(f"## {info['repo']}@{info['commit']} ({info['toolchain']}, {info['license']}, {license_status(info['license'])})")
        out.append("")
        out.append("| Declaration | Location | Packaging | Category | Blueprint | Live | Depends on | Open PRs/issues | Hints |")
        out.append("|---|---|---|---|---|---|---|---|---|")
        for c in sorted(open_c, key=lambda c: (c.already_live, not c.packageable_now, bool(c.open_work), bool(c.hints), not c.blueprint, c.file, c.line)):
            pkg = c.packaging + (" (packageable now)" if c.packageable_now else "")
            cat_cell = (c.category + (" (two-sided)" if c.open_conjecture else "")) if c.category else "—"
            out.append(
                f"| `{c.name}` ({c.kind}) | [{c.file}:{c.line}]({c.url}) | {pkg} | {cat_cell} | {'yes' if c.blueprint else 'no'} | "
                f"{'already live' if c.already_live else ''} | {', '.join(f'`{short(d)}`' for d in c.depends_on)} | "
                f"{open_work_cell(c, checked)} | {'; '.join(c.hints)} |"
            )
        out.append("")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", action="append", help="owner/name to scan (repeatable; default: the watchlist)")
    ap.add_argument("--domain", action="append", choices=DOMAINS, help="only watchlist repos in this domain (repeatable)")
    ap.add_argument("--toolchain", help="pin each repo to its newest commit with this lean-toolchain, e.g. v4.36.0")
    ap.add_argument("--workdir", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "sunstead-scout"))
    ap.add_argument("--format", choices=["md", "json"], default="md")
    ap.add_argument("--include-excluded", action="store_true", help="list excluded sorries too (json only)")
    ap.add_argument(
        "--check-prs", action="store_true",
        help="cross-check candidates against open upstream PRs and issues via `gh api` (read-only GETs); "
             "a candidate an open PR likely solves is excluded",
    )
    ap.add_argument(
        "--discover", action="store_true",
        help="dynamically discover candidate Lean 4 repos from Mathlib downstream-repos.yml and leanprover/reservoir-index",
    )
    ap.add_argument(
        "--discover-source", choices=["all", "downstream", "reservoir"], default="all",
        help="discovery source for --discover (default: all)",
    )
    ap.add_argument(
        "--discover-limit", type=int, default=50,
        help="maximum number of discovered repositories (rate-limit hygiene, default: 50)",
    )
    ap.add_argument(
        "--discover-min-stars", type=int, default=0,
        help="minimum GitHub stars filter for reservoir-index discovery",
    )
    ap.add_argument(
        "--discover-list-only", action="store_true",
        help="with --discover, print discovered repositories without cloning/scanning them",
    )
    ap.add_argument(
        "--from-json",
        help="load previously scouted JSON results instead of cloning (useful with --scaffold)",
    )
    ap.add_argument(
        "--scaffold",
        metavar="OUT_DIR",
        help="write topic-sharded Sunstead Arena Pack directories for vetted candidates into OUT_DIR",
    )
    ap.add_argument(
        "--shard-size", type=int, default=50,
        help="maximum tasks per topic-sharded Arena Pack in --scaffold mode (default: 50)",
    )
    ap.add_argument(
        "--scaffold-prefix", default="",
        help="mission id prefix for --scaffold packs (default: derived from repo name)",
    )
    ap.add_argument(
        "--timeout", type=int, default=GIT_TIMEOUT,
        help=f"per-subprocess timeout in seconds for git/gh/http calls (default: {GIT_TIMEOUT}s)",
    )
    args = ap.parse_args(argv)
    if args.timeout is not None and args.timeout > 0:
        globals()["GIT_TIMEOUT"] = args.timeout
        globals()["GH_TIMEOUT"] = min(args.timeout, GH_TIMEOUT) if args.timeout < GH_TIMEOUT else args.timeout
        globals()["HTTP_TIMEOUT"] = min(args.timeout, HTTP_TIMEOUT) if args.timeout < HTTP_TIMEOUT else args.timeout

    if args.from_json:
        results = load_results_from_json(args.from_json)
    else:
        repos = list(args.repo or [])
        if args.discover:
            discovered, warnings = discover_repos(
                source=args.discover_source,
                limit=args.discover_limit,
                min_stars=args.discover_min_stars,
                toolchain_prefix=args.toolchain,
                exclude_watchlist=bool(args.domain or args.repo),
            )
            for w in warnings:
                print(f"[discover warning] {w}", file=sys.stderr)
            if args.discover_list_only:
                if args.format == "json":
                    print(json.dumps({"discovered": discovered, "warnings": warnings}, indent=2))
                else:
                    print(f"# Discovered Lean 4 repositories ({len(discovered)})\n")
                    for item in discovered:
                        extra = f" ({item.get('toolchain')})" if item.get("toolchain") else ""
                        print(f"- `{item['repo']}` [{item['source']}]{extra}")
                return 0
            repos.extend(item["repo"] for item in discovered if item["repo"] not in repos)
        if not repos:
            repos = [r for r, d in WATCHLIST_DOMAINS if not args.domain or d in args.domain]
        live = live_task_lines()
        results = []
        for repo in repos:
            print(f"scouting {repo} ...", file=sys.stderr)
            results.append(scout_repo(repo, args.workdir, args.toolchain, live, check_prs=args.check_prs))

    if args.scaffold:
        packs = scaffold_arena_packs(
            results,
            args.scaffold,
            shard_size=args.shard_size,
            prefix=args.scaffold_prefix,
        )
        print(f"scaffolded {len(packs)} Arena Pack(s) into {args.scaffold}", file=sys.stderr)

    if args.format == "json":
        print(json.dumps([
            {
                **info,
                "sorries": [asdict(c) for c in cands if args.include_excluded or c.status == "candidate"],
            }
            for info, cands in results
        ], indent=2, ensure_ascii=False))
    else:
        print(render_markdown(results, args.toolchain, args.check_prs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
