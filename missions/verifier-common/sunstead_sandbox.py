"""
Trusted verification harness shared by every Sunstead mission `verify` script.

Installed read-only at /opt/sunstead/ inside each verifier image. Never copied
into a mission repo, so a submission cannot modify it.

Trust model
-----------
* The orchestrating `verify` process runs as root inside the container (with
  only CAP_SETUID/CAP_SETGID in the local Docker runner). It never executes
  contributor code itself.
* Contributor-controlled code (``lake build`` of a target file, ``cargo test``
  linking a target file) only ever runs as the unprivileged ``sunstead-runner``
  user, in a scratch directory that user owns, with rlimits and a minimal
  environment. Every ``sunstead-runner`` process is killed before and after
  each untrusted step, so nothing it starts can outlive its step.
* Trusted checks (building frozen spec modules, kernel-replaying the
  contributor's Lean output, collecting axioms, reading the score) run as a
  third user, ``sunstead-checker``, only after every runner process is dead.
  The verdict is computed from the checker's output, never from text the
  contributor's code printed.
"""
import json
import os
import pwd
import re
import resource
import shutil
import signal
import subprocess
import sys
import tempfile
import time

RUNNER_USER = "sunstead-runner"
CHECKER_USER = "sunstead-checker"
SUNSTEAD_HOME = os.path.dirname(os.path.abspath(__file__))
LEAN_CHECKER = os.path.join(SUNSTEAD_HOME, "SunsteadCheck.lean")
ALLOWED_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}

# Lean/Rust/Verus toolchain locations baked into the images.
BASE_PATH = os.environ.get("SUNSTEAD_BASE_PATH",
                           "/opt/elan/bin:/opt/verus:/usr/local/cargo/bin:/usr/local/bin:/usr/bin:/bin")


# ---------------------------------------------------------------------------
# Verdict output
# ---------------------------------------------------------------------------

def emit(ok, summary, score=None):
    out = {"ok": bool(ok), "summary": str(summary)[:600]}
    if score is not None:
        out["score"] = score
    sys.stdout.write(json.dumps(out) + "\n")
    sys.stdout.flush()
    sys.exit(0 if ok else 1)


def tail(text, n=350):
    text = (text or "").strip()
    return text[-n:]


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
        "CARGO_HOME": os.environ.get("CARGO_HOME", "/usr/local/cargo"),
        "RUSTUP_HOME": os.environ.get("RUSTUP_HOME", "/usr/local/rustup"),
        "CARGO_NET_OFFLINE": "true",
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
    home = env_extra.pop("HOME") if env_extra and "HOME" in env_extra else cwd
    # Output goes to root-owned temp files, not pipes: a background process
    # left behind by contributor code must not be able to hold the step open.
    with tempfile.TemporaryFile("w+") as out, tempfile.TemporaryFile("w+") as err:
        proc = subprocess.Popen(
            argv,
            cwd=cwd,
            env=_clean_env(home, env_extra),
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
    """Kill every process owned by `user` (as that user, so no CAP_KILL needed)."""
    uid, gid = _ids(user)
    killer = "import os, signal\ntry:\n    os.kill(-1, signal.SIGKILL)\nexcept ProcessLookupError:\n    pass\n"
    for _ in range(20):
        if not _pids_of(uid):
            return True
        subprocess.run([sys.executable, "-I", "-c", killer], user=uid, group=gid,
                       extra_groups=[], env={"PATH": BASE_PATH}, cwd="/",
                       capture_output=True)
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

    def copy_tree_as(self, user, src, dst, exclude=(".git", ".lake", "target")):
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

def _strip_lean_comments(src):
    out, i, depth, n = [], 0, 0, len(src)
    while i < n:
        if src.startswith("/-", i):
            depth += 1
            i += 2
        elif depth and src.startswith("-/", i):
            depth -= 1
            i += 2
        elif depth:
            i += 1
        elif src.startswith("--", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


LEAN_FORBIDDEN = [
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


def lint_lean_file(path, rel, lib_root):
    with open(path, "r", encoding="utf-8") as f:
        code = _strip_lean_comments(f.read())
    for pat, reason in LEAN_FORBIDDEN:
        if re.search(pat, code):
            return f"{rel}: {reason}"
    for opt in re.findall(r"\bset_option\s+([\w.]+)", code):
        if opt not in LEAN_ALLOWED_OPTIONS:
            return f"{rel}: `set_option {opt}` is not allowed"
    for line in code.splitlines():
        m = re.match(r"\s*import\s+(.+)$", line)
        if m:
            for mod in m.group(1).split():
                if not (mod == lib_root or mod.startswith(lib_root + ".")):
                    return f"{rel}: import of `{mod}` is not allowed (only {lib_root}.* modules)"
    return None


def _strip_rust_comments(code):
    code = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    return re.sub(r"//[^\n]*", "", code)


RUST_COMMON_FORBIDDEN = [
    (r"\bunsafe\b", "unsafe code is forbidden"),
    (r"\b(std|core|alloc)\s*::|\bextern\b|\buse\s+(std|core|alloc)\b",
     "the standard library, `core` and `extern` items are not available to target files"),
    (r"\bstatic\b", "`static` items are forbidden"),
    (r"#\s*!?\s*\[", "attributes are forbidden in target files"),
    (r"\bmod\b", "declaring modules is forbidden in target files"),
    (r"\b(super|self)\s*::", "only `crate::` paths are allowed"),
    (r"\bspec_\w+", "target files may not call the reference implementation in spec.rs"),
]
RUST_ALLOWED_MACROS = {"matches"}


def lint_rust_file(path, rel, allowed_modules):
    with open(path, "r", encoding="utf-8") as f:
        code = _strip_rust_comments(f.read())
    for pat, reason in RUST_COMMON_FORBIDDEN:
        if re.search(pat, code):
            return f"{rel}: {reason}"
    for mac in re.findall(r"\b(\w+)\s*!\s*[(\[{]", code):
        if mac not in RUST_ALLOWED_MACROS:
            return f"{rel}: macro `{mac}!` is not allowed"
    if re.search(r"\bcrate\s*::\s*\{", code):
        return f"{rel}: grouped `crate::{{...}}` imports are not allowed"
    spec_ok = 0
    for m in re.finditer(r"\bcrate\s*::\s*(\w+)\s*::\s*(\{[^}]*\}|\*|\w+)", code):
        module, items = m.group(1), m.group(2)
        names = ["*"] if items == "*" else re.findall(r"\w+", items)
        if "*" in names:
            return f"{rel}: glob imports are not allowed"
        if module == "spec":
            bad = [x for x in names if x != "as" and not re.fullmatch(r"[A-Z][A-Za-z0-9_]*", x)]
            if bad:
                return f"{rel}: only constants and types may be used from crate::spec (found {', '.join(bad)})"
            spec_ok += 1
    for module in re.findall(r"\bcrate\s*::\s*(\w+)", code):
        if module != "spec" and module not in allowed_modules:
            return f"{rel}: `crate::{module}` is not an allowed module"
    if len(re.findall(r"\bcrate\s*::\s*spec\b", code)) != spec_ok:
        return f"{rel}: unsupported use of `crate::spec`"
    return None


# ---------------------------------------------------------------------------
# Lean missions
# ---------------------------------------------------------------------------

def _statements_module_source(lib_root, statements):
    lines = [f"import {lib_root}.Spec", "", "namespace SunsteadStatements", ""]
    for task_id, src in statements.items():
        lines.append(f"/-- Frozen statement for task `{task_id}`. -/")
        lines.append(src.strip())
        lines.append("")
    lines.append("end SunsteadStatements")
    return "\n".join(lines) + "\n"


def lean_verify(task_id, *, lib_root, frozen_files, tasks, timeout_sec=110):
    """Verify a Lean 4 task.

    tasks[task_id] = {
        "module":    "MetaComplexity.Pigeonhole",           # module to build
        "theorem":   "MetaComplexity.no_inj_lt",            # constant that must prove the statement
        "statement": "def pigeonhole_fin : Prop := ...",    # frozen statement, in SunsteadStatements
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

    # 0. Lint every contributor-owned Lean file in the library.
    for dirpath, _, files in os.walk(lib_dir):
        for fn in sorted(files):
            if not fn.endswith(".lean"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), work)
            if rel in frozen_set:
                continue
            if rel == os.path.join(lib_root, "SunsteadStatements.lean"):
                emit(False, f"{rel}: reserved file name")
            # Unsolved stubs still contain `sorry`; only the files the target
            # depends on must be sorry-free, which the checker enforces. Lint
            # the remaining rules for every file.
            problem = lint_lean_file(os.path.join(dirpath, fn), rel, lib_root)
            if problem and "`sorry`" not in problem:
                emit(False, f"hygiene check failed: {problem}")
    target_rel = task["module"].replace(".", "/") + ".lean"
    problem = lint_lean_file(os.path.join(work, target_rel), target_rel, lib_root)
    if problem:
        emit(False, f"hygiene check failed: {problem}")

    job = Job()
    try:
        # 1. Trusted build of the frozen spec + frozen statements (checker user).
        trusted = os.path.join(job.checker_dir, "trusted")
        run_as(CHECKER_USER, ["mkdir", "-p", os.path.join(trusted, lib_root)], cwd="/", timeout=30)
        for rel in frozen_files:
            src = os.path.join(work, rel)
            if not os.path.isfile(src):
                continue
            with open(src, "r", encoding="utf-8") as f:
                content = f.read()
            dst = os.path.join(trusted, rel)
            run_as(CHECKER_USER, ["mkdir", "-p", os.path.dirname(dst)], cwd="/", timeout=30)
            job.write_as(CHECKER_USER, dst, content)
        stmts = {tid: t["statement"] for tid, t in tasks.items()}
        job.write_as(CHECKER_USER, os.path.join(trusted, lib_root, "SunsteadStatements.lean"),
                     _statements_module_source(lib_root, stmts))
        p = run_as(CHECKER_USER, ["lake", "build", f"{lib_root}.Spec", f"{lib_root}.SunsteadStatements"],
                   cwd=trusted, timeout=deadline(), env_extra={"HOME": job.checker_dir})
        if p.returncode != 0:
            emit(False, f"trusted spec build failed: {tail(p.stdout + p.stderr)}")
        ensure_no_processes(CHECKER_USER)

        # 2. Untrusted build of the contributor's module (runner user).
        src_dir = os.path.join(job.runner_dir, "src")
        job.copy_tree_as(RUNNER_USER, work, src_dir)
        p = run_as(RUNNER_USER, ["lake", "build", task["module"]], cwd=src_dir,
                   timeout=deadline(), env_extra={"HOME": job.runner_dir}, cpu_sec=timeout_sec)
        ensure_no_processes(RUNNER_USER)
        if p.returncode != 0:
            emit(False, f"lake build {task['module']} failed: {tail(p.stdout + p.stderr)}")

        # 3. Trusted kernel replay + statement + axiom check (checker user).
        # key=value tokens: `lean --run` parses any `--flag` as its own option.
        argv = [
            "lean", "--run", LEAN_CHECKER,
            "trusted-lib=" + os.path.join(trusted, ".lake", "build", "lib"),
            "untrusted-lib=" + os.path.join(src_dir, ".lake", "build", "lib"),
            "lib-root=" + lib_root,
            "frozen=" + ",".join([f"{lib_root}.Spec", f"{lib_root}.SunsteadStatements"]),
            "target-module=" + task["module"],
            "target-const=" + task["theorem"],
            "statement=" + f"SunsteadStatements.{task_id}",
        ]
        if task.get("score_const"):
            argv.append("score-const=" + task["score_const"])
        p = run_as(CHECKER_USER, argv, cwd=trusted, timeout=deadline(),
                   env_extra={"HOME": job.checker_dir})
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
            emit(False, f"trusted checker produced no result: {tail(p.stdout + p.stderr)}")
        if not result.get("ok"):
            emit(False, f"kernel check failed: {str(result.get('error', 'unknown error'))[:400]}")
        bad = [a for a in result.get("axioms", []) if a not in ALLOWED_AXIOMS]
        if bad:
            emit(False, f"forbidden axioms: {', '.join(bad)}")
        elapsed = int((time.monotonic() - started) * 1000)
        if task.get("score_const"):
            score = result.get("score")
            if not isinstance(score, int):
                emit(False, "trusted checker did not return a score")
            label = task.get("label", "score {score}").format(score=score)
            emit(True, f"Lean 4 kernel-replayed: {label} (0 sorry, standard axioms only, {elapsed} ms)",
                 score=float(score))
        emit(True, f"Lean 4 kernel-replayed `{task_id}` (0 sorry, standard axioms only, {elapsed} ms)",
             score=1.0)
    finally:
        job.cleanup()


# ---------------------------------------------------------------------------
# Rust missions
# ---------------------------------------------------------------------------

def rust_verify(task_id, *, tasks, profiles, allowed_modules, summary_fmt, timeout_sec=110):
    """Verify a Rust task: lint target, then run the frozen integration test as the runner.

    tasks[task_id] = (target_rel, test_name, profile_name)
    """
    require_root()
    if task_id not in tasks:
        emit(False, f"unknown task id: {task_id}")
    target_rel, test_name, profile = tasks[task_id]
    work = os.getcwd()

    target_path = os.path.join(work, target_rel)
    problem = lint_rust_file(target_path, target_rel, allowed_modules)
    if problem:
        emit(False, f"hygiene check failed: {problem}")
    with open(target_path, "r", encoding="utf-8") as f:
        cleaned = _strip_rust_comments(f.read())
    for pattern, reason in profiles[profile]:
        if re.search(pattern, cleaned):
            emit(False, f"hygiene check failed in {target_rel}: {reason}")

    job = Job()
    try:
        src_dir = os.path.join(job.runner_dir, "src")
        job.copy_tree_as(RUNNER_USER, work, src_dir)
        # Target files cannot reach std (lint above), so they cannot print or
        # exit early; still require libtest to report the exact pass count.
        p = run_as(RUNNER_USER,
                   ["cargo", "test", "--release", "--offline", "--test", test_name, "--",
                    "--test-threads=1"],
                   cwd=src_dir, timeout=timeout_sec,
                   env_extra={"HOME": job.runner_dir,
                              "CARGO_TARGET_DIR": os.path.join(job.runner_dir, "target")},
                   cpu_sec=timeout_sec)
        ensure_no_processes(RUNNER_USER)
        out = p.stdout + "\n" + p.stderr
        if p.returncode != 0:
            emit(False, f"verification test `{test_name}` failed: {tail(out)}")
        expected = _count_tests(os.path.join(work, "tests", test_name + ".rs"))
        m = re.findall(r"^test result: ok\. (\d+) passed; 0 failed", p.stdout, flags=re.M)
        if not m or int(m[-1]) != expected or expected == 0:
            emit(False, f"verification test `{test_name}` did not report {expected} passing tests")
        emit(True, summary_fmt.format(task_id=task_id, profile=profile), score=1.0)
    finally:
        job.cleanup()


def _count_tests(path):
    with open(path, "r", encoding="utf-8") as f:
        return len(re.findall(r"#\[test\]", f.read()))


# ---------------------------------------------------------------------------
# Verus missions
# ---------------------------------------------------------------------------
#
# A Verus mission verifies code copied verbatim from an existing crate. Each
# task has a frozen statement file (statements/<module>.rs): the upstream
# function(s) with Verus `requires`/`ensures` and no proof. The contributor's
# file (src/<module>.rs) may only add ghost code to it:
#   * `proof { ... }` blocks, `assert ...;` and `let ghost ...;` statements
#     inside function bodies,
#   * new `proof fn lemma_*` / `spec fn aux_*` items,
#   * a body for each `proof fn` the statement declares.
# After erasing exactly those, the file must be token-for-token identical to the
# statement, so the executable code and its specification cannot change. The
# statement's executable functions are in turn checked token-for-token against
# the vendored upstream source. Verus then verifies the task's module.

VERUS_ADDED_ITEM = re.compile(r"(lemma|aux)_\w+")
VERUS_ALLOWED_ATTRS = {
    "trigger", "auto", "verifier::rlimit", "verifier::spinoff_prover",
    "verifier::nonlinear", "verifier::loop_isolation", "verifier::opaque",
}
VERUS_FORBIDDEN_IDENTS = {
    "unsafe", "extern", "static", "mod", "macro_rules", "include", "include_str",
    "include_bytes", "cfg", "cfg_attr", "path", "external", "external_body",
    "external_fn_specification", "external_type_specification", "trusted",
    "exec_allows_no_decreases_clause", "assume_termination", "allow_in_spec",
    "uninterp", "axiom", "const", "impl", "trait",
}
_VERUS_PUNCT = sorted("""
    ::= ... ..= ==> <== <==> &&& ||| === !== >>= <<=
    :: -> => == != <= >= && || << >> += -= *= /= %= ^= &= |= .. ##
    ! # $ % & ( ) * + , - . / : ; < = > ? @ [ ] ^ { | } ~
""".split(), key=len, reverse=True)


def _verus_strip_comments(src):
    """Remove // and (nested) /* */ comments. Returns None on an unterminated comment."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif src.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            if depth:
                return None
            out.append(" ")
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif src[i] == "'" and re.match(r"'(?:\\.|[^'\\])'", src[i:i + 4]):
            m = re.match(r"'(?:\\.|[^'\\])'", src[i:i + 4])
            out.append(m.group(0))
            i += len(m.group(0))
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def verus_tokens(src):
    """Tokenize Rust/Verus source (comments dropped). Raises ValueError on bad input."""
    code = _verus_strip_comments(src)
    if code is None:
        raise ValueError("unterminated block comment")
    toks, i, n = [], 0, len(code)
    while i < n:
        c = code[i]
        if c.isspace():
            i += 1
            continue
        m = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|[0-9][A-Za-z0-9_]*").match(code, i)
        if m:
            toks.append(m.group(0))
            i = m.end()
            continue
        if c == '"':
            m = re.compile(r'"(?:\\.|[^"\\])*"').match(code, i)
            if not m:
                raise ValueError("unterminated string literal")
            toks.append(m.group(0))
            i = m.end()
            continue
        if c == "'":
            m = re.compile(r"'(?:\\.|[^'\\])'|'[A-Za-z_][A-Za-z0-9_]*").match(code, i)
            if not m:
                raise ValueError("bad character literal")
            toks.append(m.group(0))
            i = m.end()
            continue
        for p in _VERUS_PUNCT:
            if code.startswith(p, i):
                toks.append(p)
                i += len(p)
                break
        else:
            raise ValueError(f"unexpected character {c!r}")
    return toks


def _match_close(toks, i):
    """toks[i] is an opening bracket; return the index of its matching closer."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = []
    for j in range(i, len(toks)):
        t = toks[j]
        if t in pairs:
            stack.append(pairs[t])
        elif t in (")", "]", "}"):
            if not stack or stack.pop() != t:
                raise ValueError("unbalanced brackets")
            if not stack:
                return j
    raise ValueError("unbalanced brackets")


def _fn_body_start(toks, i):
    """i indexes `fn`; return the index of the body's `{` (or of `;` for a bodiless fn)."""
    depth = 0
    j = i
    while j < len(toks):
        t = toks[j]
        if t in ("(", "["):
            depth += 1
        elif t in (")", "]"):
            depth -= 1
        elif depth == 0 and t in ("{", ";"):
            return j
        j += 1
    raise ValueError("function without body")


_ITEM_PREFIX = {"pub", "open", "closed", "broadcast", "proof", "spec", "exec", "tracked"}


def _item_start(toks, fn_idx):
    """Walk back from `fn` over modifiers and outer attributes to the item's first token."""
    j = fn_idx
    while j > 0:
        if toks[j - 1] in _ITEM_PREFIX:
            j -= 1
        elif toks[j - 1] == ")" and j >= 4 and toks[j - 4:j - 1] == ["pub", "(", "crate"]:
            j -= 4
        elif toks[j - 1] == "]":
            # outer attribute `# [ ... ]`
            k = j - 1
            depth = 0
            while k >= 0:
                if toks[k] == "]":
                    depth += 1
                elif toks[k] == "[":
                    depth -= 1
                    if depth == 0:
                        break
                k -= 1
            if k >= 1 and toks[k - 1] == "#":
                j = k - 1
            else:
                break
        else:
            break
    return j


def _fn_mode(toks, start, fn_idx):
    mods = toks[start:fn_idx]
    if "proof" in mods:
        return "proof"
    if "spec" in mods:
        return "spec"
    return "exec"


def _erase_ghost(toks, statement_proof_fns):
    """Erase contributor-added ghost code (see comment above).

    Returns (remaining tokens, erased tokens). Raises ValueError.
    """
    out = list(toks)
    erased = []
    # 1. Added lemma_/aux_ items and statement proof-fn bodies.
    i = 0
    while i < len(out):
        if out[i] == "fn" and i + 1 < len(out):
            name = out[i + 1]
            start = _item_start(out, i)
            mode = _fn_mode(out, start, i)
            body = _fn_body_start(out, i)
            end = _match_close(out, body) if out[body] == "{" else body
            if VERUS_ADDED_ITEM.fullmatch(name):
                if mode == "exec":
                    raise ValueError(f"added function `{name}` must be a proof fn or spec fn")
                erased += out[start:end + 1]
                del out[start:end + 1]
                i = start
                continue
            if mode == "proof" and name in statement_proof_fns and out[body] == "{":
                erased += out[body + 1:end]
                out[body + 1:end] = []
                i = body + 2
                continue
        i += 1
    # 2. proof blocks and assert statements.
    i = 0
    while i < len(out):
        t = out[i]
        if t == "proof" and i + 1 < len(out) and out[i + 1] == "{":
            end = _match_close(out, i + 1)
            erased += out[i:end + 1]
            del out[i:end + 1]
            continue
        if t == "let" and i + 1 < len(out) and out[i + 1] in ("ghost", "tracked") \
                and i > 0 and out[i - 1] in ("{", ";", "}"):
            j = i + 2
            while j < len(out) and out[j] != ";":
                if out[j] in ("(", "[", "{"):
                    j = _match_close(out, j)
                j += 1
            erased += out[i:j + 1]
            del out[i:j + 1]
            continue
        if t == "assert" and i > 0 and out[i - 1] in ("{", ";", "}") \
                and i + 1 < len(out) and out[i + 1] != "!":
            j = i + 1
            while j < len(out):
                if out[j] in ("(", "["):
                    j = _match_close(out, j) + 1
                elif out[j] == ";":
                    j += 1
                    break
                elif out[j] == "{":
                    j = _match_close(out, j) + 1
                    if j < len(out) and out[j] == ";":
                        j += 1
                    break
                elif out[j] == "}":
                    raise ValueError("assert statement without `;`")
                else:
                    j += 1
            erased += out[i:j]
            del out[i:j]
            continue
        i += 1
    return out, erased


def _statement_proof_fns(toks):
    names = set()
    for i, t in enumerate(toks):
        if t == "fn" and i + 1 < len(toks):
            if _fn_mode(toks, _item_start(toks, i), i) == "proof":
                names.add(toks[i + 1])
    return names


def lint_verus_ghost(toks, rel):
    """Hygiene rules for the ghost code a contributor added. Returns an error string or None.

    Everything else in the file is checked to be identical to the frozen statement.
    """
    for i, t in enumerate(toks):
        if t[0] in "\"'":
            return f"{rel}: string and character literals are not allowed in proof code"
        if t in VERUS_FORBIDDEN_IDENTS:
            return f"{rel}: `{t}` is not allowed in proof code"
        if "assume" in t or "admit" in t:
            return f"{rel}: `{t}` is not allowed (no assumptions)"
        if t == "!" and i > 0 and re.fullmatch(r"[A-Za-z_]\w*", toks[i - 1]) \
                and i + 1 < len(toks) and toks[i + 1] in ("(", "[", "{"):
            return f"{rel}: macro `{toks[i - 1]}!` is not allowed in proof code"
        if t == "#":
            j = i + 1
            if j < len(toks) and toks[j] == "!":
                j += 1
            if j >= len(toks) or toks[j] != "[":
                return f"{rel}: stray `#`"
            try:
                close = _match_close(toks, j)
            except ValueError as e:
                return f"{rel}: {e}"
            path = []
            for x in toks[j + 1:close]:
                if x in ("(", "["):
                    break
                path.append(x)
            name = "".join(path)
            if name not in VERUS_ALLOWED_ATTRS:
                return f"{rel}: attribute `#[{name}]` is not allowed"
    return None


def _strip_spec_for_upstream(toks):
    """Statement exec fn tokens -> plain Rust tokens: drop `pub`, named returns, requires/ensures."""
    out = list(toks)
    while out and out[0] in ("pub", "open", "closed", "exec"):
        out.pop(0)
    if out[:1] == ["pub"]:
        out.pop(0)
    # `-> ( name : Ty )` -> `-> Ty`
    if "->" in out:
        k = out.index("->")
        if out[k + 1] == "(" and out[k + 3] == ":":
            close = _match_close(out, k + 1)
            out[k + 1:close + 1] = out[k + 4:close]
    body = _fn_body_start(out, 0)
    for kw in ("requires", "ensures", "recommends", "decreases"):
        if kw in out[:body]:
            k = out.index(kw)
            out[k:body] = []
            body = _fn_body_start(out, 0)
    return out


def _find_fn(toks, name):
    for i, t in enumerate(toks):
        if t == "fn" and i + 1 < len(toks) and toks[i + 1] == name:
            start = i
            # include modifiers but not attributes
            while start > 0 and toks[start - 1] in _ITEM_PREFIX:
                start -= 1
            if start >= 4 and toks[start - 1] == ")" and toks[start - 4:start - 1] == ["pub", "(", "crate"]:
                start -= 4
            body = _fn_body_start(toks, i)
            end = _match_close(toks, body)
            return toks[start:end + 1]
    return None


def check_verus_upstream(statement_toks, upstream_src, fn_name):
    """The statement's `fn_name` must be the upstream function, token for token."""
    mine = _find_fn(statement_toks, fn_name)
    theirs = _find_fn(verus_tokens(upstream_src), fn_name)
    if mine is None or theirs is None:
        return f"function `{fn_name}` not found"
    a = _strip_spec_for_upstream(mine)
    b = [t for t in theirs if t not in ("pub",)]
    a = [t for t in a if t not in ("pub",)]
    if a != b:
        return f"function `{fn_name}` differs from upstream"
    return None


def verus_check_file(work, rel, statement_rel):
    """Check a task file is its statement plus allowed ghost code. Returns error or None."""
    with open(os.path.join(work, rel), "r", encoding="utf-8") as f:
        src = f.read()
    if not src.isascii():
        return f"{rel}: only ASCII source is allowed"
    with open(os.path.join(work, statement_rel), "r", encoding="utf-8") as f:
        stmt_src = f.read()
    try:
        toks = verus_tokens(src)
        stmt = verus_tokens(stmt_src)
        proof_fns = _statement_proof_fns(stmt)
        mine, erased = _erase_ghost(toks, proof_fns)
        expected, _ = _erase_ghost(stmt, proof_fns)
    except ValueError as e:
        return f"{rel}: {e}"
    problem = lint_verus_ghost(erased, rel)
    if problem:
        return problem
    if mine != expected:
        k = next((i for i, (x, y) in enumerate(zip(mine, expected)) if x != y),
                 min(len(mine), len(expected)))
        near = " ".join(mine[max(0, k - 6):k + 6])
        return (f"{rel}: after removing proof code the file must equal {statement_rel} "
                f"(first difference near `{near}`)")
    return None


def _count_fns(toks):
    return sum(1 for i, t in enumerate(toks)
               if t == "fn" and i + 1 < len(toks) and not VERUS_ADDED_ITEM.fullmatch(toks[i + 1]))


def _verus_results(stdout):
    """Return (verified, errors) from `verus --output-json` stdout, or None."""
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and "verified" in line:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            r = d.get("verification-results", d)
            if isinstance(r, dict) and "verified" in r and "errors" in r:
                if r.get("encountered-vir-error") or r.get("success") is False:
                    return (int(r["verified"]), max(1, int(r["errors"])))
                return (int(r["verified"]), int(r["errors"]))
    m = re.findall(r"^verification results:: (\d+) verified, (\d+) errors?$", stdout, flags=re.M)
    if m:
        return (int(m[-1][0]), int(m[-1][1]))
    return None


def verus_verify(task_id, *, tasks, crate_root="src/lib.rs", timeout_sec=110):
    """Verify a Verus task.

    tasks[task_id] = {
        "module":    "lower_decode",                      # src/<module>.rs, statements/<module>.rs
        "upstream":  [("upstream/base16ct-1.0.0/src/lower.rs", "decode_nibble")],  # optional
    }
    """
    require_root()
    task = tasks.get(task_id)
    if task is None:
        emit(False, f"unknown task id: {task_id}")
    work = os.getcwd()

    # 1. Every task file (not just the target) must be its statement plus ghost code.
    for tid, t in sorted(tasks.items()):
        rel = f"src/{t['module']}.rs"
        stmt_rel = f"statements/{t['module']}.rs"
        if not os.path.isfile(os.path.join(work, rel)):
            emit(False, f"missing {rel}")
        problem = verus_check_file(work, rel, stmt_rel)
        if problem:
            emit(False, f"hygiene check failed: {problem}")

    # 2. The statement's executable code is the upstream crate's code, verbatim.
    stmt_rel = f"statements/{task['module']}.rs"
    with open(os.path.join(work, stmt_rel), "r", encoding="utf-8") as f:
        stmt = verus_tokens(f.read())
    for up_rel, fn_name in task.get("upstream", []):
        with open(os.path.join(work, up_rel), "r", encoding="utf-8") as f:
            problem = check_verus_upstream(stmt, f.read(), fn_name)
        if problem:
            emit(False, f"statement check failed ({stmt_rel} vs {up_rel}): {problem}")

    # 3. Verus, as the runner, on a scratch copy. Verus only type-checks and
    # verifies; it never runs the code it is given.
    job = Job()
    try:
        src_dir = os.path.join(job.runner_dir, "src")
        job.copy_tree_as(RUNNER_USER, work, src_dir)
        p = run_as(RUNNER_USER,
                   ["verus", crate_root, "--crate-type=lib", "--verify-module", task["module"],
                    "--output-json", "--no-cheating"],
                   cwd=src_dir, timeout=timeout_sec,
                   env_extra={"HOME": job.runner_dir}, cpu_sec=timeout_sec, fsize_mb=1024)
        ensure_no_processes(RUNNER_USER)
        out = p.stdout + "\n" + p.stderr
        res = _verus_results(p.stdout)
        expected = _count_fns(stmt)
        if p.returncode != 0 or res is None or res[1] != 0:
            emit(False, f"Verus did not verify `{task['module']}`: {tail(out)}")
        if res[0] < expected:
            emit(False, f"Verus verified {res[0]} functions in `{task['module']}`, expected at least {expected}")
        emit(True, f"Verus verified `{task['module']}` ({res[0]} functions, 0 errors, no assumptions)",
             score=1.0)
    finally:
        job.cleanup()
