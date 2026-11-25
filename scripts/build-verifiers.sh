#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Build context is missions/ so the images include the shared trusted harness
# in missions/verifier-common/.
# Pass optional toolchain args (e.g. `v4.36.0`, `v4.35.0`, `v4.31.0`) to build
# a subset; with no arguments, all pinned Lean 4 verifier images are built.
if [ "$#" -eq 0 ]; then
  TARGETS=(v4.36.0 v4.35.0 v4.31.0)
else
  TARGETS=("$@")
fi

for target in "${TARGETS[@]}"; do
  case "$target" in
    v4.36.0|4.36.0|lean4)
      echo "==> Building hermetic Lean 4.36.0 + Mathlib verifier image (sunstead/verifier-lean4:v0.2)..."
      docker build -t sunstead/verifier-lean4:v0.2 -f "$ROOT_DIR/missions/verifier-lean4/Dockerfile" "$ROOT_DIR/missions"
      ;;
    v4.35.0|4.35.0|lean4-v4.35.0)
      echo "==> Building hermetic Lean 4.35.0 repo-snapshot verifier image (sunstead/verifier-lean4-v4.35.0:v0.1)..."
      docker build -t sunstead/verifier-lean4-v4.35.0:v0.1 -f "$ROOT_DIR/missions/verifier-lean4-v4.35.0/Dockerfile" "$ROOT_DIR/missions"
      ;;
    v4.31.0|4.31.0|lean4-v4.31.0)
      echo "==> Building hermetic Lean 4.31.0 + Mathlib + Aeneas repo-snapshot verifier image (sunstead/verifier-lean4-v4.31.0:v0.1)..."
      docker build -t sunstead/verifier-lean4-v4.31.0:v0.1 -f "$ROOT_DIR/missions/verifier-lean4-v4.31.0/Dockerfile" "$ROOT_DIR/missions"
      ;;
    *)
      echo "unknown verifier target: $target (expected v4.36.0, v4.35.0, or v4.31.0)" >&2
      exit 2
      ;;
  esac
done

echo "==> Sunstead Lean 4 verifier image(s) ready."
