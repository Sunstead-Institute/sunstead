#!/usr/bin/env python3
"""
Internal HTTP verifier server running inside the Cloudflare Lean 4 Container
(`enableInternet = false`). Never exposed publicly; only reachable from
SunsteadHub Durable Object via Container.fetch().

Security properties:
- The server itself never executes contributor code. It runs as root so that the
  frozen mission `./verify` (also root) can drop to the unprivileged
  `sunstead-runner` user for contributor builds and to `sunstead-checker` for the
  trusted checks (see /opt/sunstead/sunstead_sandbox.py).
- `/work` and everything in it is owned by root and not writable by either
  sandbox user, so contributor code cannot alter the verifier, the frozen spec
  or a later submission's files.
- Every sandbox-user process is killed before and after each request, so nothing
  a submission starts survives into the next one in this warm container.
- Seed mission repos live under read-only `/missions` (owned by root, mode 0555/0444).
- Every request stages into a freshly wiped `/work`, runs `git apply`, checks frozen_paths &
  target_files, computes `spec_sha256`, captures a canonical `git diff`, and runs the
  frozen mission `./verify <task_id>`.
"""
import hashlib
import http.server
import io
import json
import os
import shutil
import signal
import struct
import subprocess
import sys
import tarfile
import time

sys.path.insert(0, "/opt/sunstead")
from sunstead_sandbox import CHECKER_USER, RUNNER_USER, kill_all_processes  # noqa: E402

MISSIONS_ROOT = "/missions"
WORK_DIR = "/work"
MAX_PAYLOAD_BYTES = 16 * 1024 * 1024
MAX_DIAGNOSTICS_CHARS = 2000
VALID_STAGES = {"patch", "lint", "compile", "kernel", "axioms", "timeout", "sandbox"}


def segment_matches(pat: str, seg: str) -> bool:
    dp = [[False] * (len(seg) + 1) for _ in range(len(pat) + 1)]
    dp[0][0] = True
    for i in range(1, len(pat) + 1):
        if pat[i - 1] == "*":
            dp[i][0] = dp[i - 1][0]
    for i in range(1, len(pat) + 1):
        for j in range(1, len(seg) + 1):
            if pat[i - 1] == "*":
                dp[i][j] = dp[i - 1][j] or dp[i][j - 1]
            elif pat[i - 1] == "?" or pat[i - 1] == seg[j - 1]:
                dp[i][j] = dp[i - 1][j - 1]
    return dp[len(pat)][len(seg)]


def match_segments(pat, path):
    if not pat and not path:
        return True
    if pat and pat[0] == "**":
        return match_segments(pat[1:], path) or (bool(path) and match_segments(pat, path[1:]))
    if pat and path:
        return segment_matches(pat[0], path[0]) and match_segments(pat[1:], path[1:])
    return False


def glob_matches(pattern: str, rel_path: str) -> bool:
    return match_segments([s for s in pattern.split("/") if s], [s for s in rel_path.split("/") if s])


def compute_spec_sha256(repo_dir: str, frozen_paths):
    matched = []
    for root, dirs, files in os.walk(repo_dir):
        dirs[:] = [d for d in dirs if d not in (".git", "target", ".lake")]
        for fn in files:
            abs_path = os.path.join(root, fn)
            rel = os.path.relpath(abs_path, repo_dir).replace("\\", "/")
            if any(glob_matches(p, rel) for p in frozen_paths):
                matched.append((rel, abs_path))
    matched.sort(key=lambda item: item[0])

    h = hashlib.sha256()
    for rel, abs_path in matched:
        with open(abs_path, "rb") as f:
            data = f.read()
        h.update(rel.encode("utf-8"))
        h.update(b"\x00")
        h.update(struct.pack("<Q", len(data)))
        h.update(b"\x00")
        h.update(data)
        h.update(b"\n")
    return "sha256:" + h.hexdigest()


# mission_id -> (state sha256, accepted files). Lets the hub send only a hash
# while this container stays warm; see filesStateSha256 in cloudflare/src/core.ts.
_STATE_CACHE = {}


def files_sha256(files: dict) -> str:
    h = hashlib.sha256()
    for rel in sorted(files):
        data = files[rel].encode("utf-8")
        h.update(rel.encode("utf-8") + b"\x00" + struct.pack("<Q", len(data)) + b"\x00" + data + b"\n")
    return "sha256:" + h.hexdigest()


class NeedFiles(Exception):
    pass


def resolve_current_files(req: dict) -> dict:
    """Accepted files for this request: sent in full, or taken from the cache by hash."""
    mission_id = req["mission_id"]
    want = req.get("current_files_sha256")
    cache_state = bool(req.get("cache_state", True))
    if "current_files" in req:
        files = req.get("current_files") or {}
        if not isinstance(files, dict) or not all(
            isinstance(k, str) and isinstance(v, str) for k, v in files.items()
        ):
            raise ValueError("current_files must map paths to strings")
        sha = files_sha256(files)
        if want and want != sha:
            raise ValueError("current_files_sha256 does not match current_files")
        if cache_state:
            _STATE_CACHE[mission_id] = (sha, dict(files))
        return files
    cached = _STATE_CACHE.get(mission_id)
    if want and cached and cached[0] == want:
        return dict(cached[1])
    raise NeedFiles()


def parse_porcelain_z(raw: str) -> list:
    """Parse `git status --porcelain -uall -z` output, returning all touched paths.

    Handles untracked files inside new directories (`-uall`), unquoted paths
    with spaces/special characters (`-z`), and renames/copies (where porcelain
    v1 `-z` emits `XY DEST\\0SRC\\0`).
    """
    touched = []
    entries = raw.split("\0")
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        xy = entry[:2]
        path = entry[3:]
        if path:
            touched.append(path)
        if "R" in xy or "C" in xy:
            if i < len(entries) and entries[i]:
                touched.append(entries[i])
            i += 1
    return list(dict.fromkeys(touched))


def kill_sandbox_processes():
    kill_all_processes(RUNNER_USER)
    kill_all_processes(CHECKER_USER)


def reset_work_from_seed(mission_id: str, current_files: dict, frozen_paths: list):
    kill_sandbox_processes()
    seed_dir = os.path.join(MISSIONS_ROOT, mission_id)
    if not os.path.isdir(seed_dir):
        raise ValueError(f"mission not present in this verifier container: {mission_id}")

    for entry in os.listdir(WORK_DIR):
        p = os.path.join(WORK_DIR, entry)
        if os.path.isdir(p) and not os.path.islink(p):
            shutil.rmtree(p)
        else:
            os.unlink(p)

    for root, dirs, files in os.walk(seed_dir):
        dirs[:] = [d for d in dirs if d not in (".git", "target", ".lake")]
        rel_root = os.path.relpath(root, seed_dir)
        dst_root = WORK_DIR if rel_root == "." else os.path.join(WORK_DIR, rel_root)
        os.makedirs(dst_root, exist_ok=True)
        for fn in files:
            src_f = os.path.join(root, fn)
            dst_f = os.path.join(dst_root, fn)
            shutil.copyfile(src_f, dst_f)
            # Keep the execute bit (e.g. ./verify); owner (root) write for git apply only.
            mode = os.stat(src_f).st_mode & 0o555
            os.chmod(dst_f, mode | 0o200)

    # Overlay previously verified non-frozen file contents from Durable Object SQLite.
    for rel, content in (current_files or {}).items():
        norm = rel.strip().lstrip("/")
        if ".." in norm.split("/") or any(glob_matches(p, norm) for p in frozen_paths):
            continue
        dst = os.path.join(WORK_DIR, norm)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="utf-8") as f:
            f.write(content)

    # Initialize a clean git repository so `git apply` & `git diff` behave identically to local Docker.
    for args in [
        ["git", "init", "-q", "-b", "main"],
        ["git", "config", "user.name", "Sunstead Hub"],
        ["git", "config", "user.email", "hub@sunstead.org"],
        ["git", "add", "."],
        ["git", "commit", "-q", "-m", "Sunstead live mission state"],
    ]:
        subprocess.run(args, cwd=WORK_DIR, check=True, capture_output=True)


def parse_verdict(stdout: str):
    for line in reversed(stdout.splitlines()):
        s = line.strip()
        if s.startswith("{") and s.endswith("}"):
            try:
                return json.loads(s)
            except Exception:
                pass
    return None


class VerifierHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send_json(self, code: int, obj: dict):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            missions = sorted(
                d for d in os.listdir(MISSIONS_ROOT)
                if os.path.isdir(os.path.join(MISSIONS_ROOT, d))
            )
            self.send_json(200, {"ok": True, "missions": missions})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_json(400, {"ok": False, "summary": "invalid Content-Length"})
            return
        if length < 0:
            self.send_json(400, {"ok": False, "summary": "invalid Content-Length"})
            return
        if length > MAX_PAYLOAD_BYTES:
            self.send_json(413, {"ok": False, "summary": "payload too large"})
            return
        raw = self.rfile.read(length)
        try:
            req = json.loads(raw.decode("utf-8"))
        except Exception as e:
            self.send_json(400, {"ok": False, "summary": f"invalid json: {e}"})
            return

        if self.path == "/bundle":
            self.handle_bundle(req)
        elif self.path == "/verify":
            self.handle_verify(req)
        else:
            self.send_json(404, {"error": "not found"})

    def handle_bundle(self, req: dict):
        try:
            mission_id = req["mission_id"]
            frozen_paths = req.get("frozen_paths", [])
            current_files = resolve_current_files(req)
            reset_work_from_seed(mission_id, current_files, frozen_paths)

            buf = io.BytesIO()
            with tarfile.open(fileobj=buf, mode="w:gz") as tf:
                for root, dirs, files in os.walk(WORK_DIR):
                    dirs[:] = [d for d in dirs if d not in ("target", ".lake")]
                    for fn in files:
                        abs_f = os.path.join(root, fn)
                        rel_f = os.path.relpath(abs_f, WORK_DIR)
                        tf.add(abs_f, arcname=rel_f)
            data = buf.getvalue()
            self.send_response(200)
            self.send_header("Content-Type", "application/gzip")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except NeedFiles:
            self.send_json(409, {"need_files": True})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_verify(self, req: dict):
        started = time.monotonic()
        try:
            mission_id = req["mission_id"]
            task_id = req["task_id"]
            patch = req["patch"]
            frozen_paths = req.get("frozen_paths", [])
            target_files = req.get("target_files", [])
            current_files = resolve_current_files(req)
            timeout_sec = max(5, min(int(req.get("timeout_sec", 90)), 240))

            reset_work_from_seed(mission_id, current_files, frozen_paths)

            patch_file = "/tmp/incoming.patch"
            with open(patch_file, "w", encoding="utf-8") as f:
                f.write(patch)

            ap = subprocess.run(
                ["git", "apply", "--whitespace=nowarn", patch_file],
                cwd=WORK_DIR,
                capture_output=True,
                text=True,
            )
            if os.path.exists(patch_file):
                os.unlink(patch_file)

            if ap.returncode != 0:
                ms = int((time.monotonic() - started) * 1000)
                err_txt = ap.stderr.strip()
                self.send_json(200, {
                    "ok": False,
                    "score": None,
                    "summary": f"git apply failed: {err_txt[:400]}",
                    "stage": "patch",
                    "diagnostics": err_txt[:MAX_DIAGNOSTICS_CHARS],
                    "spec_sha256": "",
                    "updated_files": {},
                    "normalized_patch": "",
                    "verify_ms": ms,
                })
                return

            st = subprocess.run(
                ["git", "status", "--porcelain", "-uall", "-z"],
                cwd=WORK_DIR,
                capture_output=True,
                text=True,
                check=True,
            )
            touched = parse_porcelain_z(st.stdout)
            if not touched:
                ms = int((time.monotonic() - started) * 1000)
                self.send_json(200, {
                    "ok": False,
                    "score": None,
                    "summary": "patch modified no files",
                    "stage": "patch",
                    "diagnostics": "patch modified no files",
                    "spec_sha256": "",
                    "updated_files": {},
                    "normalized_patch": "",
                    "verify_ms": ms,
                })
                return

            for rel in touched:
                for fp in frozen_paths:
                    if glob_matches(fp, rel):
                        ms = int((time.monotonic() - started) * 1000)
                        msg = f"post-apply frozen path violation: {rel}"
                        self.send_json(200, {
                            "ok": False,
                            "score": None,
                            "summary": msg,
                            "stage": "patch",
                            "diagnostics": msg,
                            "spec_sha256": "",
                            "updated_files": {},
                            "normalized_patch": "",
                            "verify_ms": ms,
                        })
                        return
                if target_files and not any(glob_matches(tf, rel) for tf in target_files):
                    ms = int((time.monotonic() - started) * 1000)
                    msg = f"post-apply outside target_files: {rel}"
                    self.send_json(200, {
                        "ok": False,
                        "score": None,
                        "summary": msg,
                        "stage": "patch",
                        "diagnostics": msg,
                        "spec_sha256": "",
                        "updated_files": {},
                        "normalized_patch": "",
                        "verify_ms": ms,
                    })
                    return

            post_spec_sha256 = compute_spec_sha256(WORK_DIR, frozen_paths)

            # Capture a canonical `git diff` (including newly created files) before
            # stripping `.git` so `accepted_patches` always stores clean diffs for `git am`.
            subprocess.run(["git", "add", "-A"], cwd=WORK_DIR, check=True, capture_output=True)
            diff_proc = subprocess.run(
                ["git", "diff", "--cached"],
                cwd=WORK_DIR,
                capture_output=True,
                text=True,
                check=True,
            )
            normalized_patch = diff_proc.stdout

            # Remove .git before invoking mission verifier so ./verify operates on a clean tree.
            shutil.rmtree(os.path.join(WORK_DIR, ".git"), ignore_errors=True)

            try:
                proc = subprocess.run(
                    ["./verify", task_id],
                    cwd=WORK_DIR,
                    capture_output=True,
                    text=True,
                    timeout=timeout_sec,
                )
            except subprocess.TimeoutExpired:
                kill_sandbox_processes()
                ms = int((time.monotonic() - started) * 1000)
                msg = f"verification timed out after {timeout_sec}s"
                self.send_json(200, {
                    "ok": False,
                    "score": None,
                    "summary": msg,
                    "stage": "timeout",
                    "diagnostics": msg,
                    "spec_sha256": post_spec_sha256,
                    "updated_files": {},
                    "normalized_patch": "",
                    "verify_ms": ms,
                })
                return

            kill_sandbox_processes()
            ms = int((time.monotonic() - started) * 1000)
            verdict = parse_verdict(proc.stdout)
            if verdict is None:
                combined = (proc.stdout + "\n" + proc.stderr).strip()
                self.send_json(200, {
                    "ok": False,
                    "score": None,
                    "summary": f"verifier did not emit JSON verdict: {combined[-350:]}",
                    "stage": "sandbox",
                    "diagnostics": combined[-MAX_DIAGNOSTICS_CHARS:],
                    "spec_sha256": post_spec_sha256,
                    "updated_files": {},
                    "normalized_patch": "",
                    "verify_ms": ms,
                })
                return

            ok = bool(verdict.get("ok")) and proc.returncode == 0
            updated_files = {}
            if ok:
                for rel in touched:
                    abs_f = os.path.join(WORK_DIR, rel)
                    if os.path.isfile(abs_f):
                        with open(abs_f, "r", encoding="utf-8") as f:
                            updated_files[rel] = f.read()

            resp_body = {
                "ok": ok,
                "score": verdict.get("score"),
                "summary": str(verdict.get("summary", "")),
                "spec_sha256": post_spec_sha256,
                "updated_files": updated_files,
                "normalized_patch": normalized_patch if ok else "",
                "verify_ms": ms,
            }
            if not ok:
                stage = verdict.get("stage")
                if isinstance(stage, str) and stage in VALID_STAGES:
                    resp_body["stage"] = stage
                diag = verdict.get("diagnostics")
                if isinstance(diag, str) and diag.strip():
                    resp_body["diagnostics"] = diag.strip()[:MAX_DIAGNOSTICS_CHARS]
            self.send_json(200, resp_body)
        except NeedFiles:
            self.send_json(409, {"need_files": True})
        except Exception as e:
            self.send_json(500, {"error": f"verifier container error: {e}"})


if __name__ == "__main__":
    if os.geteuid() != 0:
        raise SystemExit("verifier_server.py must run as root (verify drops privileges itself)")
    os.makedirs(WORK_DIR, exist_ok=True)
    os.chmod(WORK_DIR, 0o755)
    # This server is PID 1, and the kernel drops default-action signals sent to
    # PID 1: without a handler, the runtime's SIGTERM on idle shutdown is
    # ignored and the container hangs half-stopped.
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    server = http.server.HTTPServer(("0.0.0.0", 8080), VerifierHandler)
    print("Sunstead verifier container listening on 0.0.0.0:8080", flush=True)
    server.serve_forever()
