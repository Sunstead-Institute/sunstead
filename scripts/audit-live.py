#!/usr/bin/env python3
"""Reproduce Sunstead's published proofs without running its verifier wrapper.

The checkout is the trust root for mission manifests, seed files and theorem
statements. Public bundles and Git history are inputs, never executable setup.
Lean runs offline under an unprivileged user with no host mounts or secrets.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://sunstead.org"
LIMIT = 32 * 1024 * 1024
SLUG = re.compile(r"[a-z0-9][a-z0-9_-]{0,119}\Z")
IDENT = re.compile(r"[A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*\Z")
AXIOMS = {"propext", "Classical.choice", "Quot.sound"}


def require(value, reason):
    if not value:
        raise ValueError(reason)


def download(path):
    request = urllib.request.Request(BASE + path, headers={"User-Agent": "sunstead-independent-audit/1"})
    with urllib.request.urlopen(request, timeout=35) as response:
        require(response.geturl().startswith(BASE + "/"), "unexpected redirect")
        data = response.read(LIMIT + 1)
    require(len(data) <= LIMIT, "response exceeds audit limit")
    return data


def archive_files(data):
    """Read regular files into memory; never restore a server-supplied .git."""
    result, seen, total = {}, set(), 0
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for item in archive:
            p = PurePosixPath(item.name)
            require(not p.is_absolute() and ".." not in p.parts and p.parts, "unsafe archive path")
            require(item.isfile() or item.isdir(), "unsupported archive entry")
            name = p.as_posix()
            require(name not in seen and len(seen) < 4096, "duplicate or excessive archive entries")
            seen.add(name)
            total += item.size
            require(total <= LIMIT, "expanded bundle exceeds audit limit")
            if item.isfile() and p.parts[0] != ".git":
                result[name] = (archive.extractfile(item).read(), bool(item.mode & 0o111))
    return result


def repo_git(path, *args):
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, LC_ALL="C")
    return subprocess.check_output(
        ["git", "-C", str(path), "-c", "core.hooksPath=/dev/null",
         "-c", "user.name=Sunstead Audit", "-c", "user.email=audit@localhost", *args],
        env=env, stderr=subprocess.STDOUT, timeout=25,
    )


def proof_contract(mission):
    tree = ast.parse((mission / "verify").read_text(encoding="utf-8"))
    values = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for name in node.targets:
                if isinstance(name, ast.Name) and name.id in {"TASKS", "STATEMENT_PREAMBLE"}:
                    values[name.id] = ast.literal_eval(node.value)
    return values["TASKS"], values.get("STATEMENT_PREAMBLE", "")


def spec_hash(manifest, files):
    digest = hashlib.sha256()
    for path in sorted(manifest["frozen_paths"]):
        # Current upstream missions use literal frozen paths. Fail closed on
        # a new manifest convention rather than silently omitting evidence.
        data = files[path][0]
        digest.update(path.encode("utf-8") + b"\0" + struct.pack("<Q", len(data)) + b"\0" + data + b"\n")
    return "sha256:" + digest.hexdigest()


def replay(root, mission, manifest, history, mbox, seed, live, current_hash):
    trusted = {(str(p.relative_to(mission))): p.read_bytes()
               for p in mission.rglob("*") if p.is_file() and not
               any(x.startswith(".") for x in p.relative_to(mission).parts)}
    require({p: b for p, (b, _) in seed.items()} == trusted, "seed differs from trusted checkout")
    require(spec_hash(manifest, seed) == spec_hash(manifest, live) == current_hash, "frozen hash mismatch")
    tasks = {t["id"]: t for t in manifest["tasks"]}
    accepted = []
    previous_seq = 0
    for row in history:
        task_id = row["task_id"]
        require(isinstance(row["seq"], int) and row["seq"] > previous_seq, "invalid history order")
        require(row["spec_sha256"] == current_hash, "history refers to a different frozen spec")
        require(task_id in tasks and task_id not in accepted, "unknown or duplicate verified task")
        require(set(tasks[task_id]["depends_on"]) <= set(accepted), "verified task precedes its dependency")
        accepted.append(task_id)
        previous_seq = row["seq"]

    root.mkdir()
    for p, (data, exe) in seed.items():
        f = root / p
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(data)
        f.chmod(0o755 if exe else 0o644)
    repo_git(root, "init", "--quiet", "--template=")
    repo_git(root, "add", "--", ".")
    repo_git(root, "commit", "--quiet", "-m", "trusted seed")
    base = repo_git(root, "rev-parse", "HEAD").strip().decode("ascii")
    mbox_path = root.parent / "history.mbox"
    mbox_path.write_bytes(mbox)
    repo_git(root, "am", "--no-3way", "--", str(mbox_path))
    commits = repo_git(root, "rev-list", "--reverse", base + "..HEAD").decode("ascii").splitlines()
    require(len(commits) == len(accepted), "patch count differs from accepted history")
    for commit, task in zip(commits, accepted):
        changed = set(repo_git(root, "diff-tree", "--no-commit-id", "-r", "--name-only", "-z", commit)
                      .decode("utf-8").strip("\0").split("\0"))
        require(changed and changed <= set(tasks[task]["target_files"]), "patch changes unexpected task files")
    tree = {}
    for line in repo_git(root, "ls-tree", "-r", "-z", "HEAD").strip(b"\0").split(b"\0"):
        meta, raw_path = line.split(b"\t", 1)
        mode, kind, obj = meta.split()
        require(kind == b"blob" and mode in (b"100644", b"100755"), "non-regular rebuilt entry")
        tree[raw_path.decode("utf-8")] = (repo_git(root, "cat-file", "blob", obj.decode("ascii")), mode == b"100755")
    require(tree == live, "rebuilt Git tree differs from live bundle")
    return accepted, tree


def lean_input(tree, manifest, accepted, contracts, preamble):
    modules = []
    audit = []
    check = []
    touched = {t["id"]: t["target_files"] for t in manifest["tasks"]}
    for task in accepted:
        entry = contracts[task]
        symbol, module = entry["theorem"], entry["module"]
        require(IDENT.fullmatch(symbol) and IDENT.fullmatch(module), "invalid Lean identifier")
        path = module.replace(".", "/") + ".lean"
        require(path in touched[task], "audit module is outside task scope")
        modules.append(module)
        m = re.fullmatch(r"\s*def\s+([A-Za-z_][A-Za-z_0-9]*)\s*:\s*Prop\s*:=([\s\S]+)", entry["statement"])
        require(m, "unsupported frozen Lean statement shape")
        audit.append(f"namespace Audit_{len(modules)}\n" + entry["statement"]
                     + f"\nexample : {m[1]} := {symbol}\nend Audit_{len(modules)}\n")
        check.append(symbol)
    frozen = [p[:-5].replace("/", ".") for p in manifest["frozen_paths"] if p.endswith(".lean")]
    require(all(IDENT.fullmatch(m) for m in frozen), "invalid frozen module")
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w") as tar:
        def add(name, data):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
        for mod in [*frozen, *modules]:
            rel = mod.replace(".", "/") + ".lean"
            add(rel, tree[rel][0])
        audit_header = "".join(f"import {m}\n" for m in modules)
        add("Audit.lean", (audit_header + preamble + "\n" + "\n".join(audit)
                           + "\n".join(f"#print axioms {x}" for x in check) + "\n").encode("utf-8"))
    return out.getvalue(), [*frozen, *modules], check


RUN = r"""
mkdir /tmp/work /tmp/home
cd /tmp/work
tar xf -
export HOME=/tmp/home
export LEAN_PATH="$PWD"
for p in /opt/mathlib/.lake/packages/*/.lake/build/lib/lean; do
    if [ -d "$p" ]; then LEAN_PATH="$LEAN_PATH:$p"; fi
done
lean --version
checker="$(lean --print-prefix)/bin/leanchecker"
test -x "$checker"
for mod do
    src="$(printf '%s' "$mod" | tr . /)"
    lean --root="$PWD" -o "$src.olean" "$src.lean"
    "$checker" "$mod"
done
lean --root="$PWD" Audit.lean
"""


def check_lean(image, data, modules, checks):
    with tempfile.TemporaryDirectory(prefix="sunstead-audit-container-") as tmp:
        cid = Path(tmp) / "cid"
        cmd = ["docker", "run", "--rm", "-i", "--pull=never",
               "--network=none", "--read-only", "--tmpfs=/tmp:rw,nosuid,nodev,size=512m,mode=1777",
               "--user=10003:10003", "--cap-drop=ALL", "--security-opt=no-new-privileges",
               "--pids-limit=128", "--memory=5g", "--cpus=2", f"--cidfile={cid}",
               "--entrypoint=/bin/sh", image, "-ceu", RUN, "sunstead-audit", *modules]
        try:
            result = subprocess.run(cmd, input=data, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=360, check=True)
        finally:
            if cid.is_file():
                container = cid.read_text(encoding="ascii").strip()
                if re.fullmatch(r"[a-f0-9]{64}", container):
                    subprocess.run(["docker", "rm", "-f", container], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, timeout=20, check=False)
    out = result.stdout.decode("utf-8", errors="replace")
    require(re.search(r"^Lean \(version 4\.36\.0,", out, re.MULTILINE), "wrong Lean version")
    for theorem in checks:
        m = re.findall(r"^'" + re.escape(theorem) + r"' depends on axioms: \[([^\]]*)\]\s*$",
                       out, re.MULTILINE)
        no_axioms = re.findall(r"^'" + re.escape(theorem) + r"' does not depend on any axioms\s*$",
                               out, re.MULTILINE)
        require(len(m) + len(no_axioms) == 1, "missing or ambiguous axiom result")
        actual = {x.strip() for x in (m[0].split(",") if m else []) if x.strip()}
        require(actual <= AXIOMS, "non-standard axiom in " + theorem)
        print(f"  PASS {theorem}: stock Lean + leanchecker; axioms: {', '.join(sorted(actual)) or 'none'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default="sunstead/verifier-lean4:v0.2", help="preinstalled stock Lean/Mathlib toolchain image")
    parser.add_argument("--mission", help="limit audit to this mission ID")
    args = parser.parse_args()
    require(not args.mission or SLUG.fullmatch(args.mission), "invalid mission ID")
    source = json.loads(download("/api/missions"))["missions"]
    count = 0
    for item in source:
        mid = item["id"]
        require(SLUG.fullmatch(mid), "invalid mission ID in index")
        if item.get("demo") or not item.get("verified_tasks") or args.mission not in (None, mid):
            continue
        endpoint = "/api/missions/" + mid
        snapshot = json.loads(download(endpoint))
        detail = snapshot["mission"]
        mission = ROOT / "missions" / mid
        manifest = json.loads((mission / "sunstead.json").read_text(encoding="utf-8"))
        require(not manifest.get("demo") and manifest["mode"] == "dag", "unsupported audited mission")
        require(manifest == detail["manifest"], "live manifest differs from trusted checkout")
        history = json.loads(download(endpoint + "/history"))["commits"]
        require(history and len(history) == item["verified_tasks"], "history incomplete or changed during audit")
        verified = {t["def"]["id"] for t in snapshot["tasks"] if t["status"] == "verified"}
        require(verified == {row["task_id"] for row in history}, "verified tasks and history disagree")
        with tempfile.TemporaryDirectory(prefix="sunstead-independent-audit-") as tmp:
            accepted, tree = replay(Path(tmp) / "repo", mission, manifest, history,
                                    download(endpoint + "/history.mbox"),
                                    archive_files(download(endpoint + "/bundle.tar.gz?base=seed")),
                                    archive_files(download(endpoint + "/bundle.tar.gz")), detail["spec_sha256"])
            data, modules, checks = lean_input(tree, manifest, accepted, *proof_contract(mission))
            print(f"{mid}: {len(accepted)} accepted patches replayed against matching frozen spec", flush=True)
            check_lean(args.image, data, modules, checks)
            count += len(checks)
    require(count > 0, "no accepted non-demo proofs audited")
    print(f"Independently verified {count} proof(s).")


if __name__ == "__main__":
    try:
        main()
    except (TypeError, OSError, ValueError, KeyError, subprocess.SubprocessError, tarfile.TarError) as error:
        if isinstance(error, subprocess.CalledProcessError):
            print((error.output or b"")[-2500:].decode("utf-8", errors="replace"), file=sys.stderr)
        print(f"Audit failed: {error}", file=sys.stderr)
        sys.exit(1)
