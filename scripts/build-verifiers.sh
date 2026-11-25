#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Build context is missions/ so the images include the shared trusted harness
# in missions/verifier-common/.
echo "==> Building hermetic Lean 4.36.0 + Mathlib verifier image (sunstead/verifier-lean4:v0.2)..."
docker build -t sunstead/verifier-lean4:v0.2 -f "$ROOT_DIR/missions/verifier-lean4/Dockerfile" "$ROOT_DIR/missions"

echo "==> Building hermetic Lean 4.35.0 repo-snapshot verifier image (sunstead/verifier-lean4-v4.35.0:v0.1)..."
docker build -t sunstead/verifier-lean4-v4.35.0:v0.1 -f "$ROOT_DIR/missions/verifier-lean4-v4.35.0/Dockerfile" "$ROOT_DIR/missions"

echo "==> Sunstead Lean 4 verifier images ready."
