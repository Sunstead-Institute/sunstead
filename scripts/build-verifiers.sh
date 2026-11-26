#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Build context is missions/ so the images include the shared trusted harness
# in missions/verifier-common/.
# Pass optional toolchain args (e.g. `v4.36.0`, `v4.35.0`, `v4.31.0`) to build
# a subset; with no arguments, all pinned Lean 4 verifier images are built.
# Set `SUNSTEAD_CACHE_FROM=1` to pull read-only BuildKit inline layer cache
# from the public GHCR verifier images published from `main`.
if [ "$#" -eq 0 ]; then
  TARGETS=(v4.36.0 v4.35.0 v4.31.0)
else
  TARGETS=("$@")
fi

build_verifier() {
  local label="$1"
  local tag="$2"
  local dockerfile="$3"
  local ghcr_ref="$4"
  local -a build_args=(-t "$tag" -f "$dockerfile")

  if [ "${SUNSTEAD_CACHE_FROM:-0}" = "1" ]; then
    export DOCKER_BUILDKIT=1
    if docker manifest inspect "$ghcr_ref" >/dev/null 2>&1; then
      echo "==> Using read-only BuildKit cache from ${ghcr_ref}"
      build_args+=(--cache-from "$ghcr_ref")
    else
      echo "==> Skipping --cache-from ${ghcr_ref} (manifest unavailable; cold build)"
    fi
  fi

  echo "==> Building ${label} (${tag})..."
  docker build "${build_args[@]}" "$ROOT_DIR/missions"
}

for target in "${TARGETS[@]}"; do
  case "$target" in
    v4.36.0|4.36.0|lean4)
      build_verifier \
        "hermetic Lean 4.36.0 + Mathlib verifier image" \
        "sunstead/verifier-lean4:v0.2" \
        "$ROOT_DIR/missions/verifier-lean4/Dockerfile" \
        "ghcr.io/sunstead-institute/verifier-lean4:v0.2"
      ;;
    v4.35.0|4.35.0|lean4-v4.35.0)
      build_verifier \
        "hermetic Lean 4.35.0 repo-snapshot verifier image" \
        "sunstead/verifier-lean4-v4.35.0:v0.1" \
        "$ROOT_DIR/missions/verifier-lean4-v4.35.0/Dockerfile" \
        "ghcr.io/sunstead-institute/verifier-lean4-v4.35.0:v0.1"
      ;;
    v4.31.0|4.31.0|lean4-v4.31.0)
      build_verifier \
        "hermetic Lean 4.31.0 + Mathlib + Aeneas repo-snapshot verifier image" \
        "sunstead/verifier-lean4-v4.31.0:v0.1" \
        "$ROOT_DIR/missions/verifier-lean4-v4.31.0/Dockerfile" \
        "ghcr.io/sunstead-institute/verifier-lean4-v4.31.0:v0.1"
      ;;
    *)
      echo "unknown verifier target: $target (expected v4.36.0, v4.35.0, or v4.31.0)" >&2
      exit 2
      ;;
  esac
done

echo "==> Sunstead Lean 4 verifier image(s) ready."
