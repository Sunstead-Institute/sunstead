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
MOD_SEGMENT = r"(?:[A-Za-z_][A-Za-z_0-9']*|\u00ab[A-Za-z0-9_ -]+\u00bb)"
MOD_IDENT = re.compile(rf"{MOD_SEGMENT}(?:\.{MOD_SEGMENT})*\Z")
LEAN_OPT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*=(?:true|false|[0-9]+)\Z")
TOOLCHAIN_VERSION_RE = re.compile(r"leanprover/lean4:v([0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?)\Z")
DEFAULT_IMAGE = "sunstead/verifier-lean4:v0.2"
ALLOWED_IMAGES = {
    "sunstead/verifier-lean4:v0.2",
    "sunstead/verifier-lean4-v4.35.0:v0.1",
    "sunstead/verifier-lean4-v4.31.0:v0.1",
}
AXIOMS = {"propext", "Classical.choice", "Quot.sound"}


def require(value, reason):
    if not value:
        raise ValueError(reason)


def is_repo_snapshot(manifest):
    return (manifest.get("snapshot") or {}).get("mode") == "repo-snapshot"


def module_to_relpath(module):
    require(MOD_IDENT.fullmatch(module), "invalid Lean module identifier")
    parts = []
    for seg in module.split("."):
        if seg.startswith("\u00ab") and seg.endswith("\u00bb"):
            seg = seg[1:-1]
        require(seg and seg not in (".", "..") and "/" not in seg and "\\" not in seg, "invalid Lean module segment")
        parts.append(seg)
    return "/".join(parts) + ".lean"


def parse_toolchain_images(specs, image_v435=None, image_v431=None):
    mapping = {}
    if image_v435:
        mapping["4.35.0"] = image_v435
    if image_v431:
        mapping["4.31.0"] = image_v431
    for spec in specs or ():
        require("=" in spec, f"invalid --toolchain-image (expected TOOLCHAIN=IMAGE): {spec}")
        tc_key, img = spec.split("=", 1)
        tc_key = tc_key.strip()
        img = img.strip()
        require(tc_key and img, f"invalid --toolchain-image (empty key or image): {spec}")
        if tc_key.startswith("leanprover/lean4:"):
            tc_key = tc_key[len("leanprover/lean4:"):]
        tc_key = tc_key.lstrip("v")
        mapping[tc_key] = img
    return mapping


def resolve_audit_target(mission, manifest, image_override=None, toolchain_images=None):
    tc_path = mission / "lean-toolchain"
    require(tc_path.is_file(), "mission missing lean-toolchain")
    tc = tc_path.read_text(encoding="utf-8").strip()
    m = TOOLCHAIN_VERSION_RE.fullmatch(tc)
    require(m, f"unsupported lean-toolchain: {tc}")
    expected_version = m[1]
    verifier = manifest.get("verifier") or {}
    if verifier.get("toolchain"):
        require(verifier["toolchain"].strip() == tc, "manifest verifier.toolchain disagrees with lean-toolchain")
    tc_override = (toolchain_images or {}).get(expected_version)
    override = tc_override or image_override
    image = override or verifier.get("image") or DEFAULT_IMAGE
    if not override:
        require(image in ALLOWED_IMAGES, f"unsupported verifier image: {image}")
    return image, expected_version


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
        require(task_id in tasks, "unknown verified task")
        if manifest.get("mode") != "hillclimb":
            require(task_id not in accepted, "duplicate verified task")
        require(set(tasks[task_id].get("depends_on", [])) <= set(accepted), "verified task precedes its dependency")
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


AUDIT_CHECKER_LEAN = r"""import Lean
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

def optExprEq : Option Expr → Option Expr → Bool
  | none, none => true
  | some a, some b => a == b
  | _, _ => false

def quotKindEq : QuotKind → QuotKind → Bool
  | .type, .type => true
  | .ctor, .ctor => true
  | .lift, .lift => true
  | .ind, .ind => true
  | _, _ => false

def constInfoStructEq (a b : ConstantInfo) : Bool :=
  if a.levelParams != b.levelParams || a.type != b.type then
    false
  else
    match a, b with
    | .axiomInfo x, .axiomInfo y => x.isUnsafe == y.isUnsafe
    | .defnInfo x, .defnInfo y =>
      x.value == y.value && x.safety == y.safety && x.all == y.all
    | .thmInfo x, .thmInfo y => x.all == y.all
    | .opaqueInfo x, .opaqueInfo y =>
      x.value == y.value && x.isUnsafe == y.isUnsafe && x.all == y.all
    | .quotInfo x, .quotInfo y => quotKindEq x.kind y.kind
    | .inductInfo x, .inductInfo y =>
      x.numParams == y.numParams && x.numIndices == y.numIndices &&
      x.all == y.all && x.ctors == y.ctors && x.numNested == y.numNested &&
      x.isRec == y.isRec && x.isUnsafe == y.isUnsafe && x.isReflexive == y.isReflexive
    | .ctorInfo x, .ctorInfo y =>
      x.induct == y.induct && x.cidx == y.cidx &&
      x.numParams == y.numParams && x.numFields == y.numFields && x.isUnsafe == y.isUnsafe
    | .recInfo x, .recInfo y =>
      x.all == y.all && x.numParams == y.numParams && x.numIndices == y.numIndices &&
      x.numMotives == y.numMotives && x.numMinors == y.numMinors &&
      x.k == y.k && x.isUnsafe == y.isUnsafe &&
      x.rules.length == y.rules.length &&
      (x.rules.zip y.rules).all fun (rx, ry) =>
        rx.ctor == ry.ctor && rx.nfields == ry.nfields && rx.rhs == ry.rhs
    | _, _ => false

def collectFrozenTypeDeps (frozenMap : Std.HashMap Name ConstantInfo) (rootExpr : Expr) : List Name :=
  let initNames := rootExpr.getUsedConstants.toList
  let rec go (fuel : Nat) (queue : List Name) (visited : NameSet) (acc : List Name) : List Name :=
    match fuel, queue with
    | 0, _ => acc
    | _, [] => acc
    | fuel + 1, n :: rest =>
      if visited.contains n then
        go fuel rest visited acc
      else
        match frozenMap[n]? with
        | none => go fuel rest (visited.insert n) acc
        | some ci =>
          let visited' := visited.insert n
          let extraFromVal :=
            match ci with
            | .defnInfo v => v.value.getUsedConstants.toList
            | .opaqueInfo v => v.value.getUsedConstants.toList
            | .inductInfo v => v.ctors ++ v.all
            | .ctorInfo v => [v.induct]
            | .recInfo v => v.all ++ (v.rules.flatMap fun r => r.ctor :: r.rhs.getUsedConstants.toList)
            | _ => []
          let next := ci.type.getUsedConstants.toList ++ extraFromVal
          go fuel (next ++ rest) visited' (n :: acc)
  go 100000 initNames {} []

def verifyTargetOleanClean (targetMod : Name) : IO UInt32 := do
  let targetPath ← findOLean targetMod
  let privPath : System.FilePath := targetPath.toString ++ ".private"
  if (← privPath.pathExists) then
    IO.eprintln s!"PRIVATE_OLEAN {targetMod}"
    return 2
  let (modData, _) ← readModuleData targetPath
  if modData.isModule then
    IO.eprintln s!"MODULE_SYSTEM_DISALLOWED {targetMod}"
    return 2
  return 0

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--repo-snapshot", frozenOleanPath, targetModStr, targetConstStr] =>
    let targetMod := parseLeanName targetModStr
    let targetConst := parseLeanName targetConstStr
    initSearchPath (← findSysroot)
    let cleanRc ← verifyTargetOleanClean targetMod
    if cleanRc != 0 then return cleanRc
    let (frozenData, _) ← readModuleData (System.FilePath.mk frozenOleanPath)
    if frozenData.isModule then
      IO.eprintln s!"FROZEN_MODULE_SYSTEM_DISALLOWED {targetMod}"
      return 2
    let mut frozenMap : Std.HashMap Name ConstantInfo := {}
    for i in [:frozenData.constNames.size] do
      if h1 : i < frozenData.constNames.size then
        if h2 : i < frozenData.constants.size then
          frozenMap := frozenMap.insert frozenData.constNames[i] frozenData.constants[i]
    let some frozenCi := frozenMap[targetConst]?
      | do IO.eprintln s!"MISSING_FROZEN_TARGET {targetConst}"; return 3
    match frozenCi with
    | .thmInfo _ => pure ()
    | _ =>
      IO.eprintln s!"FROZEN_NOT_THEOREM {targetConst}"
      return 3
    -- loadExts := false ensures untrusted contributor elab_rules/macro_rules/initialize never run.
    let env ← importModules #[{ module := targetMod }] {} 0 (loadExts := false)
    let some tci := env.find? targetConst
      | do IO.eprintln s!"MISSING_TARGET {targetConst}"; return 4
    match tci with
    | .thmInfo _ => pure ()
    | _ =>
      IO.eprintln s!"TARGET_NOT_THEOREM {targetConst}"
      return 4
    unless tci.levelParams.length == frozenCi.levelParams.length do
      IO.eprintln s!"UNIVERSE_MISMATCH {targetConst}"
      return 5
    -- Lock every local definition/abbrev/inductive referenced by the theorem's type against modification.
    let frozenDeps := collectFrozenTypeDeps frozenMap frozenCi.type
    for depName in frozenDeps do
      if depName == targetConst then
        continue
      match frozenMap[depName]?, env.find? depName with
      | some fci, some lci =>
        unless constInfoStructEq fci lci do
          IO.eprintln s!"FROZEN_DEP_MODIFIED {depName}"
          return 6
      | _, _ =>
        IO.eprintln s!"FROZEN_DEP_MISSING {depName}"
        return 6
    let ctx : Core.Context := { fileName := "<sunstead-audit>", fileMap := default }
    let lvls := frozenCi.levelParams.map Level.param
    let checkName := `_sunstead_audit_check
    let (axs, _) ← (do
      addDecl <| Declaration.thmDecl
        { name := checkName
          levelParams := frozenCi.levelParams
          type := frozenCi.type
          value := mkConst targetConst lvls
          all := [checkName] }
      collectAxioms checkName : CoreM (Array Name)).toIO ctx { env := env }
    for a in axs do
      IO.println s!"SUNSTEAD_AUDIT_AXIOM {targetConst} {a}"
    IO.println s!"SUNSTEAD_AUDIT_OK {targetConst}"
    return 0
  | [specModStr, targetModStr, specConstStr, targetConstStr] =>
    let specMod := parseLeanName specModStr
    let targetMod := parseLeanName targetModStr
    let specConst := parseLeanName specConstStr
    let targetConst := parseLeanName targetConstStr
    initSearchPath (← findSysroot)
    let cleanRc ← verifyTargetOleanClean targetMod
    if cleanRc != 0 then return cleanRc
    -- loadExts := false ensures untrusted contributor elab_rules/macro_rules/initialize never run.
    let env ← importModules #[{ module := specMod }, { module := targetMod }] {} 0 (loadExts := false)
    let some sci := env.find? specConst
      | do IO.eprintln s!"MISSING_SPEC {specConst}"; return 3
    let some tci := env.find? targetConst
      | do IO.eprintln s!"MISSING_TARGET {targetConst}"; return 4
    match tci with
    | .thmInfo _ => pure ()
    | _ =>
      IO.eprintln s!"TARGET_NOT_THEOREM {targetConst}"
      return 4
    unless tci.levelParams.length == sci.levelParams.length do
      IO.eprintln s!"UNIVERSE_MISMATCH {targetConst}"
      return 5
    let ctx : Core.Context := { fileName := "<sunstead-audit>", fileMap := default }
    let lvls := sci.levelParams.map Level.param
    let checkName := `_sunstead_audit_check
    let (axs, _) ← (do
      addDecl <| Declaration.thmDecl
        { name := checkName
          levelParams := sci.levelParams
          type := mkConst specConst lvls
          value := mkConst targetConst lvls
          all := [checkName] }
      collectAxioms checkName : CoreM (Array Name)).toIO ctx { env := env }
    for a in axs do
      IO.println s!"SUNSTEAD_AUDIT_AXIOM {targetConst} {a}"
    IO.println s!"SUNSTEAD_AUDIT_OK {targetConst}"
    return 0
  | _ =>
    IO.eprintln "usage: lean --run SunsteadAuditCheck.lean <specMod> <targetMod> <specConst> <targetConst> | --repo-snapshot <frozenOlean> <targetMod> <targetConst>"
    return 2
"""


def lean_input(tree, manifest, accepted, contracts, preamble):
    modules = []
    spec_decls = []
    checks = []  # list of (target_module, spec_const, target_const)
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
        idx = len(modules)
        spec_decls.append(f"namespace AuditSpec_{idx}\n" + entry["statement"] + f"\nend AuditSpec_{idx}\n")
        checks.append((module, f"AuditSpec_{idx}.{m[1]}", symbol))
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
        # SunsteadAuditSpec imports ONLY frozen modules — never untrusted contributor modules.
        spec_header = "".join(f"import {m}\n" for m in frozen)
        add("SunsteadAuditSpec.lean", (spec_header + preamble + "\n" + "\n".join(spec_decls)).encode("utf-8"))
        add("SunsteadAuditCheck.lean", AUDIT_CHECKER_LEAN.encode("utf-8"))
        check_manifest = "\n".join(f"{mod} {spec_c} {target_c}" for mod, spec_c, target_c in checks) + "\n"
        add("audit_checks.txt", check_manifest.encode("utf-8"))
    return out.getvalue(), frozen, modules, checks


def repo_snapshot_input(seed_tree, live_tree, manifest, accepted, contracts):
    snap = manifest.get("snapshot") or {}
    snapshot_id = snap.get("snapshot_id", "")
    require(SLUG.fullmatch(snapshot_id), "invalid repo-snapshot snapshot_id")
    lean_options = snap.get("lean_options") or []
    require(isinstance(lean_options, list) and all(isinstance(o, str) and LEAN_OPT_RE.fullmatch(o) for o in lean_options),
            "invalid repo-snapshot lean_options")
    touched = {t["id"]: t["target_files"] for t in manifest["tasks"]}
    checks = []  # list of (target_module, rel_no_ext, target_const)
    packed = set()
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w") as tar:
        def add(name, data):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))

        check_lines = []
        for task in accepted:
            entry = contracts[task]
            symbol, module = entry["theorem"], entry["module"]
            require(IDENT.fullmatch(symbol) and MOD_IDENT.fullmatch(module), "invalid Lean identifier")
            rel = module_to_relpath(module)
            require(rel in touched[task], "audit module is outside task scope")
            require(rel in seed_tree and rel in live_tree, "missing snapshot target file in bundle")
            if rel not in packed:
                add("seed/" + rel, seed_tree[rel][0])
                add("live/" + rel, live_tree[rel][0])
                packed.add(rel)
            bridge_rels = []
            for bm in (entry.get("bridge_modules") or []):
                brel = module_to_relpath(bm)
                bridge_rels.append(brel[:-5])
            checks.append((module, rel[:-5], symbol))
            check_lines.append(f"{module}\t{rel[:-5]}\t{symbol}\t{','.join(bridge_rels)}")
        add("SunsteadAuditCheck.lean", AUDIT_CHECKER_LEAN.encode("utf-8"))
        check_manifest = "\n".join(check_lines) + "\n"
        add("audit_checks.txt", check_manifest.encode("utf-8"))
    return out.getvalue(), snapshot_id, lean_options, checks


RUN = r"""
mkdir /tmp/work /tmp/home
cd /tmp/work
tar xf -
export HOME=/tmp/home
export LEAN_PATH="$PWD"
for p in /opt/mathlib/.lake/packages/*/.lake/build/lib/lean \
         /opt/mathlib/.lake/packages/*/*/.lake/build/lib/lean \
         /opt/mathlib/.lake/packages/*/*/*/.lake/build/lib/lean; do
    if [ -d "$p" ]; then LEAN_PATH="$LEAN_PATH:$p"; fi
done
lean --version
checker="$(lean --print-prefix)/bin/leanchecker"
test -x "$checker"
for mod do
    src="$(printf '%s' "$mod" | tr . /)"
    lean --root="$PWD" -o "$src.olean" "$src.lean"
    test ! -e "$src.olean.private"
    "$checker" "$mod"
done
lean --root="$PWD" -o SunsteadAuditSpec.olean SunsteadAuditSpec.lean
while read -r mod spec_const target_const; do
    [ -n "$mod" ] || continue
    lean --run SunsteadAuditCheck.lean SunsteadAuditSpec "$mod" "$spec_const" "$target_const"
done < audit_checks.txt
"""


RUN_REPO_SNAPSHOT = r"""
snapshot_id="$1"
shift
mkdir -p /tmp/work /tmp/home /tmp/frozen_merged /tmp/merged
cd /tmp/work
tar xf -
export HOME=/tmp/home
snap="/opt/sunstead/snapshots/$snapshot_id"
deps="$snap/deps"
frozen_srcs="$snap/frozen-sources"
test -d "$deps"
cp -rs "$deps/." /tmp/frozen_merged/
find /tmp/frozen_merged -type d -exec chmod 755 {} +
cp -rs "$deps/." /tmp/merged/
find /tmp/merged -type d -exec chmod 755 {} +
frozen_path="/tmp/frozen_merged"
merged_path="/tmp/merged"
for p in /opt/mathlib/.lake/packages/*/.lake/build/lib/lean \
         /opt/mathlib/.lake/packages/*/*/.lake/build/lib/lean \
         /opt/mathlib/.lake/packages/*/*/*/.lake/build/lib/lean; do
    if [ -d "$p" ]; then
        frozen_path="$frozen_path:$p"
        merged_path="$merged_path:$p"
    fi
done
lean --version
checker="$(lean --print-prefix)/bin/leanchecker"
test -x "$checker"
tab="$(printf '\t')"
while IFS="$tab" read -r mod rel_no_ext target_const bridge_csv; do
    [ -n "$mod" ] || continue
    if [ -n "$bridge_csv" ]; then
        old_ifs="$IFS"
        IFS=","
        for b_rel in $bridge_csv; do
            [ -n "$b_rel" ] || continue
            b_src="$frozen_srcs/$b_rel.lean"
            test -f "$b_src"
            mkdir -p "$(dirname "/tmp/frozen_merged/$b_rel.olean")" "$(dirname "/tmp/merged/$b_rel.olean")"
            rm -f "/tmp/frozen_merged/$b_rel.olean" "/tmp/frozen_merged/$b_rel.olean.private" \
                  "/tmp/merged/$b_rel.olean" "/tmp/merged/$b_rel.olean.private"
            LEAN_PATH="$frozen_path" lean "$@" --root="$frozen_srcs" -o "/tmp/frozen_merged/$b_rel.olean" "$b_src"
            test ! -e "/tmp/frozen_merged/$b_rel.olean.private"
            LEAN_PATH="$merged_path" lean "$@" --root="$frozen_srcs" -o "/tmp/merged/$b_rel.olean" "$b_src"
            test ! -e "/tmp/merged/$b_rel.olean.private"
        done
        IFS="$old_ifs"
    fi
    mkdir -p "$(dirname "/tmp/frozen_merged/$rel_no_ext.olean")" "$(dirname "/tmp/merged/$rel_no_ext.olean")"
    rm -f "/tmp/frozen_merged/$rel_no_ext.olean" "/tmp/frozen_merged/$rel_no_ext.olean.private" \
          "/tmp/merged/$rel_no_ext.olean" "/tmp/merged/$rel_no_ext.olean.private"
    LEAN_PATH="$frozen_path" lean "$@" --root=/tmp/work/seed -o "/tmp/frozen_merged/$rel_no_ext.olean" "/tmp/work/seed/$rel_no_ext.lean"
    test ! -e "/tmp/frozen_merged/$rel_no_ext.olean.private"
    LEAN_PATH="$merged_path" lean "$@" --root=/tmp/work/live -o "/tmp/merged/$rel_no_ext.olean" "/tmp/work/live/$rel_no_ext.lean"
    test ! -e "/tmp/merged/$rel_no_ext.olean.private"
    LEAN_PATH="$merged_path" "$checker" "$mod"
    LEAN_PATH="$merged_path" lean --run /tmp/work/SunsteadAuditCheck.lean --repo-snapshot "/tmp/frozen_merged/$rel_no_ext.olean" "$mod" "$target_const"
done < /tmp/work/audit_checks.txt
"""


def parse_audit_output(out, checks, expected_version="4.36.0"):
    require(re.search(rf"^Lean \(version {re.escape(expected_version)},", out, re.MULTILINE), "wrong Lean version")
    results = {}
    for _mod, _spec_c, theorem in checks:
        oks = re.findall(r"^SUNSTEAD_AUDIT_OK " + re.escape(theorem) + r"\s*$", out, re.MULTILINE)
        require(len(oks) == 1, "missing or ambiguous audit result for " + theorem)
        axioms = set(re.findall(
            r"^SUNSTEAD_AUDIT_AXIOM " + re.escape(theorem) + r" (\S+)\s*$", out, re.MULTILINE
        ))
        require(axioms <= AXIOMS, "non-standard axiom in " + theorem + f": {sorted(axioms - AXIOMS)}")
        results[theorem] = sorted(axioms)
    return results


def _run_container(image, script, script_args, data, tmpfs_size="512m"):
    with tempfile.TemporaryDirectory(prefix="sunstead-audit-container-") as tmp:
        cid = Path(tmp) / "cid"
        cmd = ["docker", "run", "--rm", "-i", "--pull=never",
               "--network=none", "--read-only", f"--tmpfs=/tmp:rw,nosuid,nodev,size={tmpfs_size},mode=1777",
               "--user=10003:10003", "--cap-drop=ALL", "--security-opt=no-new-privileges",
               "--pids-limit=128", "--memory=5g", "--cpus=2", f"--cidfile={cid}",
               "--entrypoint=/bin/sh", image, "-ceu", script, "sunstead-audit", *script_args]
        try:
            result = subprocess.run(cmd, input=data, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=360, check=True)
        finally:
            if cid.is_file():
                container = cid.read_text(encoding="ascii").strip()
                if re.fullmatch(r"[a-f0-9]{64}", container):
                    subprocess.run(["docker", "rm", "-f", container], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, timeout=20, check=False)
    return result.stdout.decode("utf-8", errors="replace")


def check_lean(image, data, frozen, modules, checks, expected_version="4.36.0"):
    out = _run_container(image, RUN, [*frozen, *modules], data)
    results = parse_audit_output(out, checks, expected_version=expected_version)
    for _mod, _spec_c, theorem in checks:
        actual = results[theorem]
        print(f"  PASS {theorem}: stock Lean {expected_version} + leanchecker + loadExts:=false kernel check; axioms: {', '.join(actual) or 'none'}")
    return results


def check_lean_repo_snapshot(image, data, snapshot_id, lean_options, checks, expected_version="4.35.0"):
    opt_flags = [f"-D{opt}" for opt in lean_options]
    out = _run_container(image, RUN_REPO_SNAPSHOT, [snapshot_id, *opt_flags], data, tmpfs_size="1g")
    results = parse_audit_output(out, checks, expected_version=expected_version)
    for _mod, _rel, theorem in checks:
        actual = results[theorem]
        print(f"  PASS {theorem}: stock Lean {expected_version} + leanchecker + repo-snapshot FrozenTypeDeps check; axioms: {', '.join(actual) or 'none'}")
    return results


RANK_TASK_SPECS = {
    ("matrix-rank444-f2", "reduce_rank"): (4, 4, 4, 47, "Rank444/Certificate.lean", "B334.score", "certificate", 8192),
    ("matrix-rank-alphatensor-f2", "rank_333"): (3, 3, 3, 23, "RankF2/Cert333.lean", "B334.score333", "B334.cert333", 16384),
    ("matrix-rank-alphatensor-f2", "rank_334"): (3, 3, 4, 29, "RankF2/Cert334.lean", "B334.score334", "B334.cert334", 16384),
    ("matrix-rank-alphatensor-f2", "rank_344"): (3, 4, 4, 38, "RankF2/Cert344.lean", "B334.score344", "B334.cert344", 16384),
    ("matrix-rank-alphatensor-f2", "rank_345"): (3, 4, 5, 47, "RankF2/Cert345.lean", "B334.score345", "B334.cert345", 16384),
    ("matrix-rank-alphatensor-f2", "rank_355"): (3, 5, 5, 58, "RankF2/Cert355.lean", "B334.score355", "B334.cert355", 16384),
    ("matrix-rank-alphatensor-f2", "rank_445"): (4, 4, 5, 63, "RankF2/Cert445.lean", "B334.score445", "B334.cert445", 16384),
}


def check_rank_table(source, n=4, m=4, p=4, max_rank=47, score_name="B334.score", cert_name="certificate", max_bytes=8192):
    """Read only the literal masks. Compare ordinary elementary-matrix products over F2."""
    header = f"def {cert_name} : List (Nat × Nat × Nat) :="
    score_line, _, table = source.partition("\n")
    score_match = re.fullmatch(rf"def {re.escape(score_name)} : Nat := ([1-9][0-9]{{0,2}})", score_line)
    require(score_match and len(source.encode("utf-8")) <= max_bytes, "unexpected rank certificate")
    source = table.strip()
    require(source.startswith(header), "unexpected certificate header")
    literal = source[len(header):].strip()
    require(re.fullmatch(r"[0-9\s(),\[\]]+", literal), "invalid mask table")
    terms = ast.literal_eval(literal)
    require(type(terms) is list and 1 <= len(terms) <= max_rank and len(terms) == int(score_match[1]), "invalid term count")
    lim_a, lim_b, lim_c = 1 << (n * m), 1 << (m * p), 1 << (p * n)
    for term in terms:
        require(
            type(term) is tuple and len(term) == 3
            and type(term[0]) is int and 0 <= term[0] < lim_a
            and type(term[1]) is int and 0 <= term[1] < lim_b
            and type(term[2]) is int and 0 <= term[2] < lim_c,
            "invalid mask triple",
        )
    for x in range(n * m):
        for y in range(m * p):
            output = 0
            for left, right, product in terms:
                if left & (1 << x) and right & (1 << y):
                    output ^= product
            # E_ij times E_jk equals E_ik. Output masks use the transposed index n*k+i.
            i, j = divmod(x, m)
            j2, k = divmod(y, p)
            expected = 1 << (n * k + i) if j == j2 else 0
            require(output == expected, f"matrix product differs at inputs {x}, {y}")
    return len(terms)


def audit_rank_history(repo, mid, accepted, tasks_by_id):
    commits = repo_git(repo, "rev-list", "--reverse", "HEAD").decode().splitlines()
    require(len(commits) == 1 + len(accepted), "unexpected rank history length")
    seed_commit = commits[0]
    previous = {}
    for task_id in dict.fromkeys(accepted):
        n, m, p, max_rank, cert_path, score_name, cert_name, max_bytes = RANK_TASK_SPECS[(mid, task_id)]
        seed_src = repo_git(repo, "show", seed_commit + ":" + cert_path).decode("utf-8")
        seed_score = check_rank_table(seed_src, n, m, p, max_rank, score_name, cert_name, max_bytes)
        require(seed_score == max_rank, "seed rank differs from expected baseline")
        previous[task_id] = seed_score
    for commit, task_id in zip(commits[1:], accepted):
        n, m, p, max_rank, cert_path, score_name, cert_name, max_bytes = RANK_TASK_SPECS[(mid, task_id)]
        source = repo_git(repo, "show", commit + ":" + cert_path).decode("utf-8")
        score = check_rank_table(source, n, m, p, max_rank, score_name, cert_name, max_bytes)
        require(score < previous[task_id], "invalid rank progression")
        eqs = (n * m) * (m * p) * (p * n)
        print(f"  PASS {commit[:12]} ({task_id}): all {eqs} coefficients correct at {score} products")
        previous[task_id] = score
    for task_id, final_score in previous.items():
        require(final_score == tasks_by_id[task_id]["best_score"], "published best score differs from certificate")


def _fips197_aes_sbox():
    """Independently compute the 256-entry NIST FIPS 197 AES S-box over GF(2^8)."""
    def gf_mul(a, b):
        res = 0
        for _ in range(8):
            if b & 1:
                res ^= a
            hi = a & 0x80
            a = (a << 1) & 0xFF
            if hi:
                a ^= 0x1B
            b >>= 1
        return res

    def gf_inv(x):
        if x == 0:
            return 0
        res, base, exp = 1, x, 254
        while exp:
            if exp & 1:
                res = gf_mul(res, base)
            base = gf_mul(base, base)
            exp >>= 1
        return res

    table = []
    for x in range(256):
        b = gf_inv(x)
        out = 0
        for i in range(8):
            bit = (
                (b >> i)
                ^ (b >> ((i + 4) % 8))
                ^ (b >> ((i + 5) % 8))
                ^ (b >> ((i + 6) % 8))
                ^ (b >> ((i + 7) % 8))
                ^ (0x63 >> i)
            ) & 1
            out |= bit << i
        table.append(out)
    return table


_AES_SBOX_TABLE = _fips197_aes_sbox()
_AES_SBOX_TARGETS = {
    "minimize_total_gates": (
        "AesSbox/TotalCircuit.lean",
        "AesSbox.totalScore",
        "AesSbox.totalGates",
        "AesSbox.totalOutputs",
    ),
    "minimize_and_gates": (
        "AesSbox/AndCircuit.lean",
        "AesSbox.andScore",
        "AesSbox.andGates",
        "AesSbox.andOutputs",
    ),
}


def check_aes_sbox_circuit(source, task_id):
    """Read only literal gate/output definitions and verify all 256 FIPS 197 AES S-box inputs."""
    require(task_id in _AES_SBOX_TARGETS, f"unknown AES S-box task: {task_id}")
    require(len(source.encode("utf-8")) <= 16384, "AES S-box circuit exceeds 16384 bytes")
    _, score_name, gates_name, outputs_name = _AES_SBOX_TARGETS[task_id]
    pattern = (
        rf"\s*def\s+{re.escape(score_name)}\s*:\s*Nat\s*:=\s*(0|[1-9][0-9]{{0,3}})\s*\n"
        rf"\s*def\s+{re.escape(gates_name)}\s*:\s*List\s*\(Nat\s*×\s*Nat\s*×\s*Nat\)\s*:=\s*(\[[\s\S]*?\])\s*\n"
        rf"\s*def\s+{re.escape(outputs_name)}\s*:\s*List\s+Nat\s*:=\s*(\[[\s\S]*?\])\s*"
    )
    match = re.fullmatch(pattern, source)
    require(match, "unexpected AES S-box circuit format")
    claimed_score = int(match[1])
    gates_lit, outputs_lit = match[2], match[3]
    require(re.fullmatch(r"[0-9\s(),\[\]]+", gates_lit), "invalid AES S-box gate table")
    require(re.fullmatch(r"[0-9\s,\[\]]+", outputs_lit), "invalid AES S-box output list")
    gates = ast.literal_eval(gates_lit)
    outputs = ast.literal_eval(outputs_lit)
    require(type(gates) is list and 1 <= len(gates) <= 1024, "invalid AES S-box gate count")
    require(type(outputs) is list and len(outputs) == 8, "invalid AES S-box output count")
    for i, gate in enumerate(gates):
        require(
            type(gate) is tuple and len(gate) == 3 and all(type(v) is int for v in gate),
            "invalid AES S-box gate triple",
        )
        op, w1, w2 = gate
        require(0 <= op < 4, f"invalid AES S-box opcode {op} at gate {i}")
        require(0 <= w1 < 8 + i and 0 <= w2 < 8 + i, f"non-causal wire index at gate {i}")
    num_wires = 8 + len(gates)
    require(all(type(w) is int and 0 <= w < num_wires for w in outputs), "out-of-range output wire index")

    actual_score = len(gates) if task_id == "minimize_total_gates" else sum(1 for op, _, _ in gates if op == 2)
    require(actual_score == claimed_score, "invalid AES S-box circuit score")

    mask = (1 << 256) - 1
    wires = [sum(((x >> b) & 1) << x for x in range(256)) for b in range(8)]
    for op, w1, w2 in gates:
        v1, v2 = wires[w1], wires[w2]
        if op == 0:
            wires.append(v1 ^ v2)
        elif op == 1:
            wires.append((v1 ^ v2) ^ mask)
        elif op == 2:
            wires.append(v1 & v2)
        else:
            wires.append(v1 ^ mask)
    for x in range(256):
        got = sum(((wires[ow] >> x) & 1) << b for b, ow in enumerate(outputs))
        require(got == _AES_SBOX_TABLE[x], f"AES S-box differs at input 0x{x:02x}")
    return actual_score


def audit_aes_sbox_history(repo, accepted, snapshot_tasks, manifest):
    commits = repo_git(repo, "rev-list", "--reverse", "HEAD").decode().splitlines()
    require(len(commits) == 1 + len(accepted), "unexpected AES S-box history length")
    baselines = {t["id"]: t["baseline_score"] for t in manifest["tasks"]}
    previous = {}
    for task_id, (rel_path, _, _, _) in _AES_SBOX_TARGETS.items():
        seed_src = repo_git(repo, "show", commits[0] + ":" + rel_path).decode("utf-8")
        seed_score = check_aes_sbox_circuit(seed_src, task_id)
        require(seed_score == baselines[task_id], f"unexpected AES S-box seed baseline for {task_id}")
        previous[task_id] = seed_score
    for commit, task_id in zip(commits[1:], accepted):
        rel_path = _AES_SBOX_TARGETS[task_id][0]
        source = repo_git(repo, "show", commit + ":" + rel_path).decode("utf-8")
        score = check_aes_sbox_circuit(source, task_id)
        require(score < previous[task_id], f"invalid AES S-box progression for {task_id}")
        print(f"  PASS {commit[:12]} ({task_id}): all 256 FIPS 197 inputs verified at score {score}")
        previous[task_id] = score
    for task in snapshot_tasks:
        tid = task["def"]["id"]
        if task["status"] == "verified":
            require(previous[tid] == task["best_score"], f"published best score differs from circuit for {tid}")


def build_audit_attestation(
    *,
    status="passed",
    auditor="github-actions/audit-proofs",
    toolchain=None,
    axioms=None,
    summary=None,
    run_url=None,
    commit_sha=None,
    audited_at=None,
):
    payload = {
        "status": status,
        "auditor": auditor,
    }
    if audited_at is not None:
        payload["audited_at"] = int(audited_at)
    if toolchain:
        payload["toolchain"] = toolchain
    if axioms is not None:
        payload["axioms"] = list(axioms)
    if summary:
        payload["summary"] = summary
    if run_url:
        payload["run_url"] = run_url
    if commit_sha:
        payload["commit_sha"] = commit_sha
    return payload


def github_actions_run_url(env=None):
    env = os.environ if env is None else env
    server = (env.get("GITHUB_SERVER_URL") or "").rstrip("/")
    repo = (env.get("GITHUB_REPOSITORY") or "").strip("/")
    run_id = (env.get("GITHUB_RUN_ID") or "").strip()
    if server.startswith("https://") and repo and run_id.isdigit():
        return f"{server}/{repo}/actions/runs/{run_id}"
    return None


def publish_audit_attestation(proof_id, payload, token, hub_base=None, opener=None):
    base = (hub_base or BASE).rstrip("/")
    key = proof_id.lower().removeprefix("sha256:")
    require(re.fullmatch(r"[0-9a-f]{64}", key), f"invalid proof_id for audit publication: {proof_id}")
    req = urllib.request.Request(
        f"{base}/api/proofs/{key}/audit",
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "sunstead-independent-audit",
        },
    )
    do_open = urllib.request.urlopen if opener is None else opener
    with do_open(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def mission_ledger_proof_ids(mid):
    """Map seq -> proof_id (64-hex) for accepted proofs of one mission."""
    try:
        data = json.loads(download(f"/api/proofs?mission_id={mid}&limit=200"))
    except Exception:
        return {}
    return {
        row["seq"]: row["proof_id"]
        for row in data.get("proofs", [])
        if isinstance(row.get("seq"), int) and isinstance(row.get("proof_id"), str)
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default=None, help="override stock Lean toolchain image (default: per-mission verifier image)")
    parser.add_argument("--image-v435", default=None, help="override stock Lean v4.35.0 image (default: sunstead/verifier-lean4-v4.35.0:v0.1)")
    parser.add_argument("--image-v431", default=None, help="override stock Lean v4.31.0 image (default: sunstead/verifier-lean4-v4.31.0:v0.1)")
    parser.add_argument(
        "--toolchain-image",
        action="append",
        default=[],
        metavar="TOOLCHAIN=IMAGE",
        help="override image for a specific toolchain (e.g. v4.35.0=sunstead/verifier-lean4-v4.35.0:v0.1); repeatable",
    )
    parser.add_argument("--mission", help="limit audit to this mission ID")
    parser.add_argument(
        "--publish-audit",
        action="store_true",
        help="POST verified audit attestations to /api/proofs/:id/audit when SUNSTEAD_AUDIT_TOKEN is set",
    )
    args = parser.parse_args()
    require(not args.mission or SLUG.fullmatch(args.mission), "invalid mission ID")
    toolchain_images = parse_toolchain_images(
        args.toolchain_image, image_v435=args.image_v435, image_v431=args.image_v431
    )
    source = json.loads(download("/api/missions"))["missions"]
    count = 0
    attestations = []
    run_url = github_actions_run_url()
    commit_sha = (os.environ.get("GITHUB_SHA") or "").strip() or None
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
        rank_mission = mid in ("matrix-rank444-f2", "matrix-rank-alphatensor-f2") and manifest["mode"] == "hillclimb"
        aes_sbox_mission = mid == "aes-sbox-circuit" and manifest["mode"] == "hillclimb"
        hillclimb_mission = rank_mission or aes_sbox_mission
        require(not manifest.get("demo") and (hillclimb_mission or manifest["mode"] == "dag"), "unsupported audited mission")
        require(manifest == detail["manifest"], "live manifest differs from trusted checkout")
        history = json.loads(download(endpoint + "/history"))["commits"]
        verified = {t["def"]["id"] for t in snapshot["tasks"] if t["status"] == "verified"}
        require(history and (hillclimb_mission or len(history) == len(verified)), "history incomplete or changed during audit")
        require(verified == {row["task_id"] for row in history}, "verified tasks and history disagree")
        seq_to_proof_id = mission_ledger_proof_ids(mid) if args.publish_audit else {}
        seed_files = archive_files(download(endpoint + "/bundle.tar.gz?base=seed"))
        live_files = archive_files(download(endpoint + "/bundle.tar.gz"))
        with tempfile.TemporaryDirectory(prefix="sunstead-independent-audit-") as tmp:
            accepted, tree = replay(Path(tmp) / "repo", mission, manifest, history,
                                    download(endpoint + "/history.mbox"),
                                    seed_files, live_files, detail["spec_sha256"])
            if rank_mission:
                tasks_by_id = {t["def"]["id"]: t for t in snapshot["tasks"]}
                audit_rank_history(Path(tmp) / "repo", mid, accepted, tasks_by_id)
                for row in history:
                    pid = seq_to_proof_id.get(row["seq"])
                    if pid:
                        attestations.append((
                            pid,
                            build_audit_attestation(
                                toolchain="python-f2-evaluator",
                                axioms=[],
                                summary=f"Independent F2 multiplication tensor audit passed for {mid}/{row['task_id']}",
                                run_url=run_url,
                                commit_sha=commit_sha,
                            ),
                        ))
                count += len(accepted)
                continue
            if aes_sbox_mission:
                audit_aes_sbox_history(Path(tmp) / "repo", accepted, snapshot["tasks"], manifest)
                for row in history:
                    pid = seq_to_proof_id.get(row["seq"])
                    if pid:
                        attestations.append((
                            pid,
                            build_audit_attestation(
                                toolchain="python-fips197-evaluator",
                                axioms=[],
                                summary=f"Independent 256-input FIPS 197 AES S-box audit passed for {mid}/{row['task_id']}",
                                run_url=run_url,
                                commit_sha=commit_sha,
                            ),
                        ))
                count += len(accepted)
                continue
            image, expected_version = resolve_audit_target(
                mission, manifest, image_override=args.image, toolchain_images=toolchain_images
            )
            contracts, preamble = proof_contract(mission)
            if is_repo_snapshot(manifest):
                data, snapshot_id, lean_options, checks = repo_snapshot_input(
                    seed_files, tree, manifest, accepted, contracts
                )
                print(f"{mid}: {len(accepted)} accepted patches replayed against matching frozen repo-snapshot spec", flush=True)
                axiom_map = check_lean_repo_snapshot(image, data, snapshot_id, lean_options, checks, expected_version=expected_version)
                for row, (_mod, _rel, theorem) in zip(history, checks):
                    pid = seq_to_proof_id.get(row["seq"])
                    if pid:
                        attestations.append((
                            pid,
                            build_audit_attestation(
                                toolchain=f"lean4:v{expected_version}",
                                axioms=axiom_map.get(theorem, []),
                                summary=f"Stock Lean {expected_version} + leanchecker + FrozenTypeDeps audit passed for {theorem}",
                                run_url=run_url,
                                commit_sha=commit_sha,
                            ),
                        ))
                count += len(checks)
                continue
            data, frozen, modules, checks = lean_input(tree, manifest, accepted, contracts, preamble)
            print(f"{mid}: {len(accepted)} accepted patches replayed against matching frozen spec", flush=True)
            axiom_map = check_lean(image, data, frozen, modules, checks, expected_version=expected_version)
            for row, (_mod, _spec_c, theorem) in zip(history, checks):
                pid = seq_to_proof_id.get(row["seq"])
                if pid:
                    attestations.append((
                        pid,
                        build_audit_attestation(
                            toolchain=f"lean4:v{expected_version}",
                            axioms=axiom_map.get(theorem, []),
                            summary=f"Stock Lean {expected_version} + leanchecker + loadExts:=false audit passed for {theorem}",
                            run_url=run_url,
                            commit_sha=commit_sha,
                        ),
                    ))
            count += len(checks)
    require(count > 0, "no accepted non-demo proofs audited")
    print(f"Independently verified {count} proof(s).")
    if args.publish_audit:
        token = (os.environ.get("SUNSTEAD_AUDIT_TOKEN") or "").strip()
        if not token:
            print("Skipping audit attestation publication (SUNSTEAD_AUDIT_TOKEN not set).")
        else:
            published = 0
            for proof_id, payload in attestations:
                publish_audit_attestation(proof_id, payload, token)
                published += 1
            print(f"Published {published} independent audit attestation(s) to {BASE}.")


if __name__ == "__main__":
    try:
        main()
    except (TypeError, OSError, ValueError, KeyError, subprocess.SubprocessError, tarfile.TarError) as error:
        if isinstance(error, subprocess.CalledProcessError):
            print((error.output or b"")[-2500:].decode("utf-8", errors="replace"), file=sys.stderr)
        print(f"Audit failed: {error}", file=sys.stderr)
        sys.exit(1)
