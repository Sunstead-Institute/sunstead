"""
Trusted verification harness shared by every Sunstead Lean 4 mission `verify` script.

Installed read-only at /opt/sunstead/ inside the Lean 4 verifier image. Never
copied into a mission repo, so a submission cannot modify it.

Trust model
-----------
* The orchestrating `verify` process runs as root inside the container (with
  only CAP_SETUID/CAP_SETGID in the local Docker runner). It never executes
  contributor code itself.
* Contributor-controlled code (compiling a target `.lean` file and its internal
  mission dependencies via `lean`) only ever runs as the unprivileged
  ``sunstead-runner`` user, in a scratch directory that user owns, with rlimits
  and a minimal environment. Every ``sunstead-runner`` process is killed before
  and after each untrusted step, so nothing it starts can outlive its step.
* Trusted checks (building frozen spec + frozen statements modules, kernel-
  replaying the contributor's Lean `.olean` output, collecting axioms, reading
  the score) run as a third user, ``sunstead-checker``, only after every runner
  process is dead. The verdict is computed from the checker's output, never
  from text the contributor's code printed.
"""
import glob
import hashlib
import json
import os
import pwd
import re
import resource
import signal
import subprocess
import sys
import tempfile
import time

RUNNER_USER = "sunstead-runner"
CHECKER_USER = "sunstead-checker"
SUNSTEAD_HOME = os.path.dirname(os.path.abspath(__file__))
LEAN_CHECKER = os.path.join(SUNSTEAD_HOME, "SunsteadCheck.lean")
LEAN_CHECKER_BIN = os.path.join(SUNSTEAD_HOME, "sunstead-check")
MISSION_CACHE_DIR = os.environ.get("SUNSTEAD_MISSION_CACHE", "/opt/sunstead/mission-cache")
MATHLIB_CACHE_DIR = os.environ.get("SUNSTEAD_MATHLIB_DIR", "/opt/mathlib")
ALLOWED_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}

# Lean toolchain location baked into the image.
BASE_PATH = os.environ.get("SUNSTEAD_BASE_PATH",
                           "/opt/elan/bin:/usr/local/bin:/usr/bin:/bin")


# ---------------------------------------------------------------------------
# Verdict output
# ---------------------------------------------------------------------------

MAX_DIAGNOSTICS_CHARS = 2000


def emit(ok, summary, score=None, *, stage=None, diagnostics=None):
    out = {"ok": bool(ok), "summary": str(summary)[:600]}
    if score is not None:
        out["score"] = score
    if not ok and stage:
        out["stage"] = str(stage)
    if not ok and diagnostics:
        clipped = diag_clip(str(diagnostics), MAX_DIAGNOSTICS_CHARS)
        if clipped:
            out["diagnostics"] = clipped
    sys.stdout.write(json.dumps(out) + "\n")
    sys.stdout.flush()
    sys.exit(0 if ok else 1)


def tail(text, n=350):
    text = (text or "").strip()
    return text[-n:]


def diag_clip(text, n=MAX_DIAGNOSTICS_CHARS):
    """Clip verbose compiler/checker diagnostics while keeping both head and tail.

    Lean puts the primary root-cause file:line:col error at the top of output and
    summary context at the bottom; preserving both ends gives agents the exact
    diagnostic needed to repair proofs without unbounded payload growth.
    """
    text = (text or "").strip()
    if len(text) <= n:
        return text
    marker = "\n... [truncated] ...\n"
    head = (n - len(marker)) // 2
    tail_len = n - len(marker) - head
    return text[:head].rstrip() + marker + text[-tail_len:].lstrip()


# ---------------------------------------------------------------------------
# Privilege separation
# ---------------------------------------------------------------------------

def _ids(user):
    pw = pwd.getpwnam(user)
    return pw.pw_uid, pw.pw_gid


def _limits(nproc, fsize_mb, cpu_sec):
    def apply():
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        resource.setrlimit(resource.RLIMIT_NPROC, (nproc, nproc))
        fsize = fsize_mb * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_FSIZE, (fsize, fsize))
        if cpu_sec:
            resource.setrlimit(resource.RLIMIT_CPU, (cpu_sec, cpu_sec + 5))
        try:
            import ctypes
            libc = ctypes.CDLL(None, use_errno=True)
            libc.prctl(38, 1, 0, 0, 0)  # PR_SET_NO_NEW_PRIVS
        except Exception:
            pass
    return apply


def _clean_env(home, extra=None):
    env = {
        "PATH": BASE_PATH,
        "HOME": home,
        "LANG": "C.UTF-8",
        "ELAN_HOME": os.environ.get("ELAN_HOME", "/opt/elan"),
    }
    if extra:
        env.update(extra)
    return env


def run_as(user, argv, cwd, timeout, env_extra=None, input_text=None,
           nproc=256, fsize_mb=512, cpu_sec=None):
    """Run argv as `user` with a clean env and rlimits. Returns CompletedProcess.

    On timeout returns a CompletedProcess with returncode -9 and the partial
    output; callers must still call kill_all_processes(user) afterwards.
    """
    uid, gid = _ids(user)
    env_copy = dict(env_extra) if env_extra else None
    home = env_copy.pop("HOME") if env_copy and "HOME" in env_copy else cwd
    # Output goes to root-owned temp files, not pipes: a background process
    # left behind by contributor code must not be able to hold the step open.
    with tempfile.TemporaryFile("w+") as out, tempfile.TemporaryFile("w+") as err:
        proc = subprocess.Popen(
            argv,
            cwd=cwd,
            env=_clean_env(home, env_copy),
            user=uid,
            group=gid,
            extra_groups=[],
            start_new_session=True,
            preexec_fn=_limits(nproc, fsize_mb, cpu_sec),
            stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL,
            stdout=out,
            stderr=err,
            text=True,
        )
        timed_out = False
        try:
            if input_text is not None:
                proc.stdin.write(input_text)
                proc.stdin.close()
            rc = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
            rc = proc.wait()
        out.seek(0)
        err.seek(0)
        stdout, stderr = out.read(), err.read()
    if timed_out:
        stderr += f"\n[sunstead] timed out after {timeout}s"
        rc = -9
    return subprocess.CompletedProcess(argv, rc, stdout, stderr)


def _pids_of(uid):
    pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/status", "r") as f:
                state, owner = "", None
                for line in f:
                    if line.startswith("State:"):
                        state = line.split()[1]
                    elif line.startswith("Uid:"):
                        owner = int(line.split()[1])
                        break
            # Zombies hold no resources and cannot act; they wait to be reaped.
            if owner == uid and state not in ("Z", "X"):
                pids.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return pids


def kill_all_processes(user):
    """Kill every process owned by `user`.

    Tries direct SIGKILL from root first (immune to RLIMIT_NPROC fork-bomb
    exhaustion in Cloudflare Containers). Falls back to spawning a killer as
    `user` only on PermissionError (e.g. local Docker without CAP_KILL).
    """
    uid, gid = _ids(user)
    killer = (
        "import os, signal\n"
        "try:\n"
        "    os.kill(-1, signal.SIGKILL)\n"
        "except ProcessLookupError:\n"
        "    pass\n"
    )
    for _ in range(20):
        pids = _pids_of(uid)
        if not pids:
            return True
        need_fallback = False
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except PermissionError:
                need_fallback = True
                break
        if need_fallback:
            try:
                subprocess.run(
                    [sys.executable, "-I", "-c", killer],
                    user=uid,
                    group=gid,
                    extra_groups=[],
                    env={"PATH": BASE_PATH},
                    cwd="/",
                    capture_output=True,
                )
            except OSError:
                pass
        time.sleep(0.05)
    return not _pids_of(uid)


def ensure_no_processes(user):
    if not kill_all_processes(user):
        emit(False, f"sandbox error: could not terminate all {user} processes")


class Job:
    """A per-submission scratch area with one subdirectory per principal.

    The job root is created by root with mode 1733 (sticky, no listing), so the
    runner and checker can each create their own subdirectory but cannot list,
    rename or delete the other's.
    """

    def __init__(self):
        ensure_no_processes(RUNNER_USER)
        ensure_no_processes(CHECKER_USER)
        self.root = tempfile.mkdtemp(prefix="sunstead-job-", dir="/tmp")
        os.chmod(self.root, 0o1733)
        self.runner_dir = self._mkdir_as(RUNNER_USER, "runner")
        self.checker_dir = self._mkdir_as(CHECKER_USER, "checker")

    def _mkdir_as(self, user, name):
        path = os.path.join(self.root, name + "-" + os.urandom(8).hex())
        p = run_as(user, ["mkdir", "-m", "0755", path], cwd="/", timeout=30)
        if p.returncode != 0:
            emit(False, f"sandbox error: mkdir as {user} failed: {tail(p.stderr)}")
        return path

    def copy_tree_as(self, user, src, dst, exclude=(".git", ".lake")):
        """Copy src into dst as `user` (dst must not exist)."""
        script = (
            "import shutil, sys\n"
            "shutil.copytree(sys.argv[1], sys.argv[2], symlinks=False,"
            " ignore=shutil.ignore_patterns(*sys.argv[3:]))\n"
        )
        p = run_as(user, [sys.executable, "-I", "-c", script, src, dst, *exclude],
                   cwd="/", timeout=60)
        if p.returncode != 0:
            emit(False, f"sandbox error: copy as {user} failed: {tail(p.stderr)}")

    def write_as(self, user, path, content):
        p = run_as(user, [sys.executable, "-I", "-c",
                          "import sys\nopen(sys.argv[1],'w',encoding='utf-8').write(sys.stdin.read())\n",
                          path], cwd="/", timeout=30, input_text=content)
        if p.returncode != 0:
            emit(False, f"sandbox error: write as {user} failed: {tail(p.stderr)}")

    def cleanup(self):
        kill_all_processes(RUNNER_USER)
        kill_all_processes(CHECKER_USER)
        for user, d in ((RUNNER_USER, self.runner_dir), (CHECKER_USER, self.checker_dir)):
            run_as(user, ["rm", "-rf", d], cwd="/", timeout=60)
        try:
            os.rmdir(self.root)
        except OSError:
            pass


def require_root():
    if os.geteuid() != 0:
        emit(False, "sandbox error: verify must run as root inside the verifier container "
                    "(it drops privileges for contributor code)")


# ---------------------------------------------------------------------------
# Source hygiene lints (defence in depth; soundness comes from the checker)
# ---------------------------------------------------------------------------

_LEAN_CHAR_RE = re.compile(r"'(?:\\(?:x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|.)|[^'\\\n])'")
_LEAN_RAW_STR_RE = re.compile(r'r(#+)"')
_MOD_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _is_lean_id_char(ch):
    return ch.isalnum() or ch in "_'?!\u00bb"


def _strip_lean_comments(src):
    """Strip Lean 4 `--` line comments and nested `/- ... -/` block comments.

    Skips string literals (`"..."` with `\\` / `\"`), raw string literals
    (`r#"..."#`), character literals (`'...'`, distinguishing identifier primes
    like `k'`), and escaped identifiers (`«...»`) so comment delimiters inside
    literals cannot hide forbidden constructs.
    """
    out, i, n = [], 0, len(src)
    while i < n:
        # Block comment `/- ... -/` (nestable; strings inside comments do not escape `-/`).
        if src.startswith("/-", i):
            depth, i = 1, i + 2
            saw_nl = False
            while i < n and depth > 0:
                if src.startswith("/-", i):
                    depth += 1
                    i += 2
                elif src.startswith("-/", i):
                    depth -= 1
                    i += 2
                else:
                    if src[i] == "\n":
                        saw_nl = True
                    i += 1
            out.append("\n" if saw_nl else " ")
            continue
        # Line comment `-- ...` to newline.
        if src.startswith("--", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        # Raw string literal `r#"..."#` (when `r` is not continuing an identifier).
        if src[i] == "r" and (i == 0 or not _is_lean_id_char(src[i - 1])):
            m = _LEAN_RAW_STR_RE.match(src, i)
            if m:
                closer = '"' + m.group(1)
                end = src.find(closer, m.end())
                if end < 0:
                    out.append(src[i:])
                    break
                end += len(closer)
                out.append(src[i:end])
                i = end
                continue
        # Standard string literal `"..."` handling backslash escapes (`\\`, `\"`, ...).
        if src[i] == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                elif src[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            out.append(src[i:j])
            i = j
            continue
        # Character literal `'...'` (only when `'` is not a prime in/after an identifier).
        if src[i] == "'" and (i == 0 or not _is_lean_id_char(src[i - 1])):
            m = _LEAN_CHAR_RE.match(src, i)
            if m:
                out.append(m.group(0))
                i = m.end()
                continue
        # Guillemet-escaped identifier `«...»`.
        if src[i] == "«":
            end = src.find("»", i + 1)
            if end < 0:
                out.append(src[i:])
                break
            out.append(src[i:end + 1])
            i = end + 1
            continue
        out.append(src[i])
        i += 1
    return "".join(out)


LEAN_FORBIDDEN = [
    (r"(?m)^\s*module\b",
     "Lean 4 `module` files are not allowed in target files"),
    (r"(?<![\w.])(?:public|private|meta|all)\s+import\b",
     "module-system import modifiers are not allowed"),
    (r"(?<![\w.])(elab|elab_rules|macro|macro_rules|syntax|declare_syntax_cat|notation|infix|infixl|infixr|prefix|postfix)\b",
     "custom syntax, macros and elaborators are not allowed in target files"),
    (r"(?<![\w.])(initialize|builtin_initialize)\b", "`initialize` blocks are not allowed"),
    (r"#(eval|exit|reduce)\b|(?<![\w.])(run_cmd|run_elab|run_meta)\b",
     "build-time code execution (`#eval`, `run_cmd`, ...) is not allowed"),
    (r"(?<![\w.])(implemented_by|extern|unsafe|opaque|axiom)\b",
     "`axiom`, `opaque`, `unsafe`, `extern` and `implemented_by` are not allowed"),
    (r"\bnative_decide\b|\bofReduceBool\b", "`native_decide` is not allowed"),
    (r"(?<![\w.])sorry\b", "`sorry` is not allowed"),
]
LEAN_ALLOWED_OPTIONS = {"maxHeartbeats", "maxRecDepth", "linter.unusedVariables"}


def _import_allowed(mod, allowed_prefixes):
    return any(mod == p or mod.startswith(p + ".") for p in allowed_prefixes)


def _extract_imports(code):
    mods = []
    for line in code.splitlines():
        m = re.match(r"\s*import\s+(.+)$", line)
        if m:
            for tok in m.group(1).split():
                mods.append(tok)
    for mod in re.findall(r"(?<![\w.])import\s+([\w.]+)", code):
        if mod not in mods:
            mods.append(mod)
    return mods


def lint_lean_file(path, rel, lib_root, allowed_import_prefixes=None):
    allowed = tuple(allowed_import_prefixes) if allowed_import_prefixes else (lib_root,)
    with open(path, "r", encoding="utf-8") as f:
        code = _strip_lean_comments(f.read())
    for pat, reason in LEAN_FORBIDDEN:
        if re.search(pat, code):
            return f"{rel}: {reason}"
    for opt in re.findall(r"\bset_option\s+([\w.]+)", code):
        if opt not in LEAN_ALLOWED_OPTIONS:
            return f"{rel}: `set_option {opt}` is not allowed"
    allowed_desc = ", ".join(f"{p}.*" for p in allowed)
    for mod in _extract_imports(code):
        if not _import_allowed(mod, allowed):
            return f"{rel}: import of `{mod}` is not allowed (only {allowed_desc})"
    return None


# ---------------------------------------------------------------------------
# Lean missions (direct offline `lean` build + trusted kernel replay)
# ---------------------------------------------------------------------------

def _mathlib_lib_paths():
    pkgs_dir = os.path.join(MATHLIB_CACHE_DIR, ".lake", "packages")
    if not os.path.isdir(pkgs_dir):
        emit(False, f"sandbox error: Mathlib cache not found at {pkgs_dir}")
    libs = []
    for pkg in sorted(os.listdir(pkgs_dir)):
        lean_lib = os.path.join(pkgs_dir, pkg, ".lake", "build", "lib", "lean")
        if os.path.isdir(lean_lib):
            libs.append(lean_lib)
            continue
        legacy_lib = os.path.join(pkgs_dir, pkg, ".lake", "build", "lib")
        if os.path.isdir(legacy_lib) and glob.glob(os.path.join(legacy_lib, "*.olean")):
            libs.append(legacy_lib)
    if not libs:
        emit(False, f"sandbox error: no compiled Mathlib .olean directories found under {pkgs_dir}")
    return libs


def _validate_mod_name(mod):
    segs = mod.split(".")
    if not segs or not all(_MOD_IDENT_RE.match(s) for s in segs):
        emit(False, f"invalid Lean module name: {mod}")
    return segs


def _resolve_local_build_order(project_dir, lib_root, root_modules, skip_modules=None):
    """Topologically order `<lib_root>.*` modules needed to compile `root_modules`.

    Modules in `skip_modules` (excluding `root_modules` themselves) are assumed
    to be prebuilt in a read-only directory on `LEAN_PATH` and are not rebuilt.
    """
    skip = set(skip_modules or ()) - set(root_modules)
    order = []
    state = {}  # mod -> 1 (visiting) | 2 (done)

    def dfs(mod):
        if mod in skip:
            return
        st = state.get(mod, 0)
        if st == 2:
            return
        if st == 1:
            emit(False, f"cyclic Lean import involving `{mod}`")
        segs = _validate_mod_name(mod)
        src_path = os.path.join(project_dir, *segs) + ".lean"
        if not os.path.isfile(src_path):
            emit(False, f"missing Lean module file for `{mod}`")
        state[mod] = 1
        with open(src_path, "r", encoding="utf-8") as f:
            code = _strip_lean_comments(f.read())
        for imp in _extract_imports(code):
            if imp == lib_root or imp.startswith(lib_root + "."):
                dfs(imp)
        state[mod] = 2
        order.append(mod)

    for m in root_modules:
        dfs(m)
    return order


def _compile_lean_graph(user, project_dir, lib_root, root_modules, extra_lib_paths,
                        deadline_fn, home_dir, cpu_sec=None, fsize_mb=512,
                        prebuilt_dir=None, prebuilt_modules=None):
    """Compile `root_modules` and their `<lib_root>.*` dependencies directly with `lean`.

    Direct invocation with an explicit `LEAN_PATH` avoids `lake` touching `.git`,
    network, or read-only `/opt/mathlib`, and compiles single Mathlib files in ~1-2s.
    When `prebuilt_dir` and `prebuilt_modules` are given, those read-only `.olean`
    files are symlinked into `out_lib` so Lean's single-root package lookup finds
    them without recompiling frozen specs.
    """
    out_lib = os.path.join(project_dir, ".lake", "build", "lib", "lean")
    skip = set(prebuilt_modules or ()) - set(root_modules)
    if prebuilt_dir and skip:
        for mod in sorted(skip):
            segs = _validate_mod_name(mod)
            src_olean = os.path.join(prebuilt_dir, *segs) + ".olean"
            dst_olean = os.path.join(out_lib, *segs) + ".olean"
            p_mk = run_as(user, ["mkdir", "-p", os.path.dirname(dst_olean)], cwd="/", timeout=30)
            if p_mk.returncode != 0:
                emit(False, f"sandbox error: mkdir for cached {mod} failed: {tail(p_mk.stderr)}")
            p_ln = run_as(user, ["ln", "-sf", src_olean, dst_olean], cwd="/", timeout=30)
            if p_ln.returncode != 0:
                emit(False, f"sandbox error: symlink for cached {mod} failed: {tail(p_ln.stderr)}")
    order = _resolve_local_build_order(project_dir, lib_root, root_modules, skip_modules=skip)
    lean_path = ":".join([out_lib] + list(extra_lib_paths))
    for mod in order:
        segs = _validate_mod_name(mod)
        rel_src = os.path.join(*segs) + ".lean"
        out_olean = os.path.join(out_lib, *segs) + ".olean"
        p_mk = run_as(user, ["mkdir", "-p", os.path.dirname(out_olean)], cwd="/", timeout=30)
        if p_mk.returncode != 0:
            emit(False, f"sandbox error: mkdir for {mod} failed: {tail(p_mk.stderr)}")
        p = run_as(
            user,
            ["lean", f"--root={project_dir}", "-o", out_olean, rel_src],
            cwd=project_dir,
            timeout=deadline_fn(),
            env_extra={"HOME": home_dir, "LEAN_PATH": lean_path},
            fsize_mb=fsize_mb,
            cpu_sec=cpu_sec,
        )
        if p.returncode != 0:
            return mod, p
    return None, None


def _frozen_lean_modules(lib_root, frozen_paths):
    """Return Lean module names for frozen `.lean` files under `<lib_root>/`."""
    prefix = lib_root + "/"
    mods = []
    for rel in sorted(frozen_paths):
        norm = rel.replace("\\", "/")
        if norm.startswith(prefix) and norm.endswith(".lean"):
            mod = norm[:-5].replace("/", ".")
            _validate_mod_name(mod)
            mods.append(mod)
    return mods


def trusted_cache_key(lib_root, uses_mathlib, frozen_contents, statements_src):
    """Cryptographic SHA-256 key over every trusted input for a mission's prebuilt `.olean`s."""
    h = hashlib.sha256()
    h.update(f"sunstead-trusted-v1\0{lib_root}\0{int(bool(uses_mathlib))}\0".encode("utf-8"))
    for rel in sorted(frozen_contents.keys()):
        h.update(rel.encode("utf-8") + b"\0" + frozen_contents[rel].encode("utf-8") + b"\0")
    h.update(b"__SunsteadStatements__\0" + statements_src.encode("utf-8") + b"\0")
    return h.hexdigest()


def _lookup_prebuilt_cache(cache_key, lib_root, frozen_mods):
    """Return `(cache_spec_dir, cache_trusted_dir)` if all prebuilt `.olean`s exist, else None."""
    cache_root = os.path.join(MISSION_CACHE_DIR, cache_key)
    spec_dir = os.path.join(cache_root, "spec")
    trusted_dir = os.path.join(cache_root, "trusted")
    if not (os.path.isdir(spec_dir) and os.path.isdir(trusted_dir)):
        return None
    for mod in frozen_mods:
        segs = _validate_mod_name(mod)
        if not os.path.isfile(os.path.join(spec_dir, *segs) + ".olean"):
            return None
        if not os.path.isfile(os.path.join(trusted_dir, *segs) + ".olean"):
            return None
    stmts_segs = _validate_mod_name(f"{lib_root}.SunsteadStatements")
    if not os.path.isfile(os.path.join(trusted_dir, *stmts_segs) + ".olean"):
        return None
    return spec_dir, trusted_dir


def _statements_module_source(lib_root, statements, preamble=""):
    lines = [f"import {lib_root}.Spec", ""]
    if preamble and preamble.strip():
        lines.append(preamble.strip())
        lines.append("")
    lines.extend(["namespace SunsteadStatements", ""])
    for task_id, src in statements.items():
        lines.append(f"/-- Frozen statement for task `{task_id}`. -/")
        lines.append(src.strip())
        lines.append("")
    lines.append("end SunsteadStatements")
    return "\n".join(lines) + "\n"


def lean_verify(task_id, *, lib_root, frozen_files, tasks,
                uses_mathlib=False, statement_preamble="", timeout_sec=110):
    """Verify a Lean 4 task (the only entry point mission `verify` scripts use)."""
    _lean_check(task_id, lib_root=lib_root, frozen_files=frozen_files, tasks=tasks,
                uses_mathlib=uses_mathlib, statement_preamble=statement_preamble,
                timeout_sec=timeout_sec, allow_sorry=False)


def check_seed_statement(task_id, *, lib_root, frozen_files, tasks,
                         uses_mathlib=False, statement_preamble="", timeout_sec=110):
    """CI only (scripts/check-statements.py): check that an unmodified seed's
    theorem has exactly the type of the task's frozen `statement`.

    Same pipeline and kernel comparison as `lean_verify`, but `sorry` in the
    seed and the `sorryAx` axiom are accepted, because seeds are unsolved.
    Nothing a contributor submits reaches this function: mission `verify`
    scripts and the verifier server only call `lean_verify`.
    """
    _lean_check(task_id, lib_root=lib_root, frozen_files=frozen_files, tasks=tasks,
                uses_mathlib=uses_mathlib, statement_preamble=statement_preamble,
                timeout_sec=timeout_sec, allow_sorry=True)


def _lean_check(task_id, *, lib_root, frozen_files, tasks,
                uses_mathlib, statement_preamble, timeout_sec, allow_sorry):
    """Shared Lean 4 pipeline for `lean_verify` and `check_seed_statement`.

    tasks[task_id] = {
        "module":    "PntFoundations.LiouvilleMult",        # module to build
        "theorem":   "PntFoundations.isCompletelyMultiplicative_liouville",
        "statement": "def is_completely_multiplicative_liouville : Prop := ...",
        "score_const": "SoundnessBound.claimedX" (optional) # hill-climb: statement takes it as (C : Nat)
        "label": "..." (optional, hill-climb summary; may use {score})
    }
    """
    require_root()
    task = tasks.get(task_id)
    if task is None:
        emit(False, f"unknown task id: {task_id}")
    started = time.monotonic()
    deadline = lambda: max(5, int(timeout_sec - (time.monotonic() - started)))

    work = os.getcwd()
    lib_dir = os.path.join(work, lib_root)
    frozen_set = set(frozen_files)
    allowed_imports = (
        (lib_root, "Mathlib", "Std", "Init", "Batteries")
        if uses_mathlib else (lib_root,)
    )
    extra_lib_paths = _mathlib_lib_paths() if uses_mathlib else []
    fsize_mb = 1024 if uses_mathlib else 512

    # 0. Lint every contributor-owned Lean file in the library.
    for dirpath, _, files in os.walk(lib_dir):
        for fn in sorted(files):
            if not fn.endswith(".lean"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), work)
            if rel in frozen_set:
                continue
            if rel == os.path.join(lib_root, "SunsteadStatements.lean"):
                emit(False, f"{rel}: reserved file name", stage="lint", diagnostics=f"{rel}: reserved file name")
            # Unsolved stubs still contain `sorry`; only the files the target
            # depends on must be sorry-free, which the checker enforces. Lint
            # the remaining rules for every file.
            problem = lint_lean_file(os.path.join(dirpath, fn), rel, lib_root, allowed_imports)
            if problem and "`sorry`" not in problem:
                emit(False, f"hygiene check failed: {problem}", stage="lint", diagnostics=problem)
    target_rel = task["module"].replace(".", "/") + ".lean"
    problem = lint_lean_file(os.path.join(work, target_rel), target_rel, lib_root, allowed_imports)
    if problem and not (allow_sorry and "`sorry`" in problem):
        emit(False, f"hygiene check failed: {problem}", stage="lint", diagnostics=problem)

    job = Job()
    try:
        # 1. Trusted frozen spec + frozen statements (cache hit or live checker build).
        frozen_contents = {}
        for rel in frozen_files:
            src = os.path.join(work, rel)
            if not os.path.isfile(src):
                continue
            with open(src, "r", encoding="utf-8") as f:
                frozen_contents[rel] = f.read()
        stmts = {tid: t["statement"] for tid, t in tasks.items()}
        statements_src = _statements_module_source(lib_root, stmts, preamble=statement_preamble)
        frozen_mods = _frozen_lean_modules(lib_root, frozen_contents.keys())
        if f"{lib_root}.Spec" not in frozen_mods:
            frozen_mods.insert(0, f"{lib_root}.Spec")
        cache_key = trusted_cache_key(lib_root, uses_mathlib, frozen_contents, statements_src)
        cached = _lookup_prebuilt_cache(cache_key, lib_root, frozen_mods)

        if cached is not None:
            cache_spec_dir, cache_trusted_dir = cached
            trusted_lib_paths = [cache_trusted_dir] + extra_lib_paths
            runner_prebuilt_dir = cache_spec_dir
            runner_prebuilt_modules = set(frozen_mods)
            checker_cwd = job.checker_dir
        else:
            trusted = os.path.join(job.checker_dir, "trusted")
            run_as(CHECKER_USER, ["mkdir", "-p", os.path.join(trusted, lib_root)], cwd="/", timeout=30)
            for rel, content in frozen_contents.items():
                dst = os.path.join(trusted, rel)
                run_as(CHECKER_USER, ["mkdir", "-p", os.path.dirname(dst)], cwd="/", timeout=30)
                job.write_as(CHECKER_USER, dst, content)
            job.write_as(
                CHECKER_USER,
                os.path.join(trusted, lib_root, "SunsteadStatements.lean"),
                statements_src,
            )
            failed_mod, p = _compile_lean_graph(
                CHECKER_USER, trusted, lib_root,
                frozen_mods + [f"{lib_root}.SunsteadStatements"],
                extra_lib_paths, deadline, job.checker_dir, fsize_mb=fsize_mb,
            )
            ensure_no_processes(CHECKER_USER)
            if failed_mod is not None:
                combined = (p.stdout + "\n" + p.stderr).strip()
                st = "timeout" if p.returncode == -9 else "sandbox"
                emit(False, f"trusted spec build failed ({failed_mod}): {tail(combined)}",
                     stage=st, diagnostics=combined)
            trusted_lib_paths = [os.path.join(trusted, ".lake", "build", "lib", "lean")] + extra_lib_paths
            runner_prebuilt_dir = None
            runner_prebuilt_modules = set()
            checker_cwd = trusted

        # 2. Untrusted build of the contributor's module (runner user).
        src_dir = os.path.join(job.runner_dir, "src")
        job.copy_tree_as(RUNNER_USER, work, src_dir)
        # Allow multi-threaded Lean CPU time above wall-clock timeout; wall-clock timeout enforces deadline.
        runner_cpu = max(timeout_sec * 4, 240)
        failed_mod, p = _compile_lean_graph(
            RUNNER_USER, src_dir, lib_root,
            [task["module"]],
            extra_lib_paths, deadline, job.runner_dir,
            cpu_sec=runner_cpu, fsize_mb=fsize_mb,
            prebuilt_dir=runner_prebuilt_dir,
            prebuilt_modules=runner_prebuilt_modules,
        )
        ensure_no_processes(RUNNER_USER)
        if failed_mod is not None:
            combined = (p.stdout + "\n" + p.stderr).strip()
            st = "timeout" if p.returncode == -9 else "compile"
            emit(False, f"lean build {failed_mod} failed: {tail(combined)}",
                 stage=st, diagnostics=combined)

        # 3. Trusted kernel replay + statement + axiom check (checker user).
        # Prefer the precompiled native binary `/opt/sunstead/sunstead-check` when present.
        # key=value tokens: `lean --run` fallback parses any `--flag` as its own option.
        if os.path.isfile(LEAN_CHECKER_BIN) and os.access(LEAN_CHECKER_BIN, os.X_OK):
            checker_cmd = [LEAN_CHECKER_BIN]
        else:
            checker_cmd = ["lean", "--run", LEAN_CHECKER]
        frozen_list = list(dict.fromkeys(frozen_mods + [f"{lib_root}.SunsteadStatements"]))
        argv = checker_cmd + [
            "trusted-lib=" + ":".join(trusted_lib_paths),
            "untrusted-lib=" + os.path.join(src_dir, ".lake", "build", "lib", "lean"),
            "lib-root=" + lib_root,
            "frozen=" + ",".join(frozen_list),
            "target-module=" + task["module"],
            "target-const=" + task["theorem"],
            "statement=" + f"SunsteadStatements.{task_id}",
        ]
        if task.get("score_const"):
            argv.append("score-const=" + task["score_const"])
        p = run_as(CHECKER_USER, argv, cwd=checker_cwd, timeout=deadline(),
                   env_extra={"HOME": job.checker_dir}, fsize_mb=fsize_mb)
        ensure_no_processes(CHECKER_USER)
        result = None
        for line in reversed(p.stdout.splitlines()):
            line = line.strip()
            if line.startswith("{"):
                try:
                    result = json.loads(line)
                    break
                except ValueError:
                    pass
        if result is None:
            combined = (p.stdout + "\n" + p.stderr).strip()
            st = "timeout" if p.returncode == -9 else "kernel"
            emit(False, f"trusted checker produced no result: {tail(combined)}",
                 stage=st, diagnostics=combined)
        if not result.get("ok"):
            err_msg = str(result.get("error", "unknown error"))
            emit(False, f"kernel check failed: {err_msg[:400]}",
                 stage="kernel", diagnostics=err_msg)
        allowed_axioms = set(ALLOWED_AXIOMS) | ({"sorryAx"} if allow_sorry else set())
        bad = [a for a in result.get("axioms", []) if a not in allowed_axioms]
        if bad:
            msg = f"forbidden axioms: {', '.join(bad)}"
            emit(False, msg, stage="axioms",
                 diagnostics=f"{msg} (allowed: {', '.join(sorted(allowed_axioms))})")
        elapsed = int((time.monotonic() - started) * 1000)
        if allow_sorry:
            emit(True, f"seed `{task['theorem']}` has exactly the frozen statement of `{task_id}` "
                       f"(axioms: {', '.join(result.get('axioms', [])) or 'none'}, {elapsed} ms)")
        if task.get("score_const"):
            score = result.get("score")
            if not isinstance(score, int):
                emit(False, "trusted checker did not return a score",
                     stage="kernel", diagnostics="trusted checker did not return an integer score")
            label = task.get("label", "score {score}").format(score=score)
            emit(True, f"Lean 4 kernel-replayed: {label} (0 sorry, standard axioms only, {elapsed} ms)",
                 score=float(score))
        emit(True, f"Lean 4 kernel-replayed `{task_id}` (0 sorry, standard axioms only, {elapsed} ms)",
             score=1.0)
    finally:
        job.cleanup()
