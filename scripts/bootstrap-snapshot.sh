#!/usr/bin/env bash
# Local bootstrap helper for Sunstead repo-snapshot missions.
#
# Shallow-clones the exact pinned 40-char upstream commit from `UPSTREAM.json`
# into an adjacent directory (outside the mission bundle so `git diff` and
# `docker cp . $CID:/work` stay clean), overlays live target `.lean` file(s)
# from the bundle, optionally fetches Mathlib cache, and supports `--sync-back`
# to copy edited target file(s) back into the bundle for a clean scoped patch.
#
# Usage:
#   ./scripts/bootstrap-snapshot.sh [--bundle-dir DIR] [--upstream-dir DIR]
#                                   [--upstream-url URL] [--no-cache] [--sync-back]
set -euo pipefail

BUNDLE_DIR="$PWD"
UPSTREAM_DIR=""
UPSTREAM_URL=""
NO_CACHE=0
SYNC_BACK=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle-dir)
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --upstream-dir)
      UPSTREAM_DIR="$2"
      shift 2
      ;;
    --upstream-url)
      UPSTREAM_URL="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE=1
      shift
      ;;
    --sync-back)
      SYNC_BACK=1
      shift
      ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"

if [ ! -f "$BUNDLE_DIR/UPSTREAM.json" ] || [ ! -f "$BUNDLE_DIR/sunstead.json" ]; then
  echo "Expected UPSTREAM.json and sunstead.json in $BUNDLE_DIR" >&2
  exit 1
fi

META="$(python3 - "$BUNDLE_DIR" <<'PY'
import json, os, re, shlex, sys

bdir = sys.argv[1]
manifest = json.load(open(os.path.join(bdir, "sunstead.json"), encoding="utf-8"))
up = json.load(open(os.path.join(bdir, "UPSTREAM.json"), encoding="utf-8"))
snap = manifest.get("snapshot") or {}
if snap.get("mode") != "repo-snapshot":
    sys.stderr.write(f"Mission {manifest.get('id')} is not a repo-snapshot mission\n")
    sys.exit(1)
repo = up.get("repo", "")
commit = up.get("commit", "")
if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
    sys.stderr.write(f"Malformed upstream repo: {repo!r}\n")
    sys.exit(1)
if not re.fullmatch(r"[0-9a-f]{40}", commit):
    sys.stderr.write(f"Malformed upstream commit SHA: {commit!r}\n")
    sys.exit(1)
targets = []
for t in manifest.get("tasks", []):
    for tf in t.get("target_files", []):
        if tf not in targets:
            if tf.startswith("/") or ".." in tf.split("/"):
                sys.stderr.write(f"Unsafe target_file path: {tf!r}\n")
                sys.exit(1)
            targets.append(tf)
if not targets:
    sys.stderr.write("Mission manifest has no target_files\n")
    sys.exit(1)

img = (manifest.get("verifier") or {}).get("image", "sunstead/verifier-lean4:v0.2").strip()
pub_img = img if img.startswith(("ghcr.io/", "registry.cloudflare.com/")) else "ghcr.io/sunstead-institute/" + img.removeprefix("sunstead/")
tc = (manifest.get("verifier") or {}).get("toolchain") or "leanprover/lean4:v4.36.0"
uses_mathlib = "1" if "Mathlib" in (snap.get("allowed_import_prefixes") or []) else "0"
first_task = (manifest.get("tasks") or [{}])[0].get("id", "<TASK_ID>")

print(f"MISSION_ID={shlex.quote(manifest['id'])}")
print(f"UPSTREAM_REPO={shlex.quote(repo)}")
print(f"UPSTREAM_COMMIT={shlex.quote(commit)}")
print(f"TOOLCHAIN={shlex.quote(tc)}")
print(f"PUBLIC_IMAGE={shlex.quote(pub_img)}")
print(f"USES_MATHLIB={uses_mathlib}")
print(f"FIRST_TASK={shlex.quote(first_task)}")
print("TARGETS=(" + " ".join(shlex.quote(t) for t in targets) + ")")
PY
)"
eval "$META"

if [ -z "$UPSTREAM_DIR" ]; then
  UPSTREAM_DIR="$(dirname "$BUNDLE_DIR")/${MISSION_ID}-upstream"
fi
UPSTREAM_DIR="$(python3 -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$UPSTREAM_DIR")"

case "$UPSTREAM_DIR" in
  "$BUNDLE_DIR"|"$BUNDLE_DIR"/*)
    echo "Refusing --upstream-dir inside --bundle-dir ($UPSTREAM_DIR): keep it outside so git diff and docker cp stay clean." >&2
    exit 1
    ;;
esac

if [ -z "$UPSTREAM_URL" ]; then
  UPSTREAM_URL="https://github.com/${UPSTREAM_REPO}.git"
fi

if [ "$SYNC_BACK" -eq 1 ]; then
  if [ ! -d "$UPSTREAM_DIR/.git" ]; then
    echo "Upstream checkout not found at $UPSTREAM_DIR (run bootstrap first)" >&2
    exit 1
  fi
  ACTUAL_SHA="$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
  if [ "$ACTUAL_SHA" != "$UPSTREAM_COMMIT" ]; then
    echo "Upstream checkout at $UPSTREAM_DIR is at $ACTUAL_SHA, expected pinned $UPSTREAM_COMMIT" >&2
    exit 1
  fi
  for rel in "${TARGETS[@]}"; do
    if [ ! -f "$UPSTREAM_DIR/$rel" ]; then
      echo "Missing target file in upstream checkout: $UPSTREAM_DIR/$rel" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$BUNDLE_DIR/$rel")"
    cp "$UPSTREAM_DIR/$rel" "$BUNDLE_DIR/$rel"
  done
  echo "Synced ${#TARGETS[@]} target file(s) back to $BUNDLE_DIR"
  if [ -d "$BUNDLE_DIR/.git" ]; then
    git -C "$BUNDLE_DIR" diff --stat -- "${TARGETS[@]}"
  fi
  exit 0
fi

if [ ! -d "$UPSTREAM_DIR/.git" ]; then
  echo "==> Shallow-cloning $UPSTREAM_URL at pinned commit ${UPSTREAM_COMMIT:0:12} into $UPSTREAM_DIR..."
  mkdir -p "$UPSTREAM_DIR"
  git -C "$UPSTREAM_DIR" init -q
  git -C "$UPSTREAM_DIR" remote add origin "$UPSTREAM_URL"
  git -C "$UPSTREAM_DIR" fetch --quiet --depth=1 origin "$UPSTREAM_COMMIT"
  git -C "$UPSTREAM_DIR" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
fi

ACTUAL_SHA="$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
if [ "$ACTUAL_SHA" != "$UPSTREAM_COMMIT" ]; then
  echo "Upstream checkout at $UPSTREAM_DIR is at $ACTUAL_SHA, expected pinned $UPSTREAM_COMMIT" >&2
  exit 1
fi

echo "==> Overlaying live target file(s) from $BUNDLE_DIR into $UPSTREAM_DIR..."
for rel in "${TARGETS[@]}"; do
  if [ ! -f "$BUNDLE_DIR/$rel" ]; then
    echo "Missing target file in bundle: $BUNDLE_DIR/$rel" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$UPSTREAM_DIR/$rel")"
  cp "$BUNDLE_DIR/$rel" "$UPSTREAM_DIR/$rel"
done

if [ "$USES_MATHLIB" = "1" ] && [ "$NO_CACHE" -eq 0 ] && command -v lake >/dev/null 2>&1; then
  echo "==> Fetching prebuilt Mathlib oleans (lake exe cache get)..."
  (cd "$UPSTREAM_DIR" && lake exe cache get) || true
fi

echo ""
echo "Ready! Local upstream workspace: $UPSTREAM_DIR"
echo "Bundle directory (clean for git diff & Docker): $BUNDLE_DIR"
echo ""
echo "Next steps:"
echo "  1. Iterate locally with Lean ($TOOLCHAIN) inside $UPSTREAM_DIR:"
echo "       cd $(printf '%q' "$UPSTREAM_DIR") && lake build"
echo "  2. Sync modified target file(s) back to the bundle:"
echo "       $(printf '%q' "$0") --bundle-dir $(printf '%q' "$BUNDLE_DIR") --upstream-dir $(printf '%q' "$UPSTREAM_DIR") --sync-back"
echo "  3. Verify offline in the exact Hub verifier image ($PUBLIC_IMAGE):"
echo "       cd $(printf '%q' "$BUNDLE_DIR")"
echo "       CID=\$(docker create --network=none -w /work $(printf '%q' "$PUBLIC_IMAGE") ./verify $(printf '%q' "$FIRST_TASK"))"
echo "       docker cp . \"\$CID:/work\" && docker start -a \"\$CID\" && docker rm -f \"\$CID\" >/dev/null"
echo "  4. Generate your scoped patch from the bundle:"
echo "       git -C $(printf '%q' "$BUNDLE_DIR") diff -- ${TARGETS[*]}"
