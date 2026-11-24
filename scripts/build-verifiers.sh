#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Build context is missions/ so both images can include the shared trusted
# harness in missions/verifier-common/.
echo "==> Building hermetic Lean 4 verifier image (sunstead/verifier-lean4:v0.1)..."
docker build -t sunstead/verifier-lean4:v0.1 -f "$ROOT_DIR/missions/verifier-lean4/Dockerfile" "$ROOT_DIR/missions"

echo "==> Building hermetic Rust verifier image (sunstead/verifier-rust:v0.1)..."
docker build -t sunstead/verifier-rust:v0.1 -f "$ROOT_DIR/missions/verifier-rust/Dockerfile" "$ROOT_DIR/missions"

echo "==> Building hermetic Verus verifier image (sunstead/verifier-verus:v0.1)..."
docker build -t sunstead/verifier-verus:v0.1 -f "$ROOT_DIR/missions/verifier-verus/Dockerfile" "$ROOT_DIR/missions"

echo "==> All Sunstead verifier images ready."
