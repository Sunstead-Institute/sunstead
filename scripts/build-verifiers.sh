#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "==> Building hermetic Lean 4 verifier image (sunstead/verifier-lean4:v0.1)..."
docker build -t sunstead/verifier-lean4:v0.1 "$ROOT_DIR/missions/verifier-lean4"

echo "==> Building hermetic Rust verifier image (sunstead/verifier-rust:v0.1)..."
docker build -t sunstead/verifier-rust:v0.1 "$ROOT_DIR/missions/verifier-rust"

echo "==> All Sunstead verifier images ready."
