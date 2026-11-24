#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8787}"

if ! docker image inspect sunstead/verifier-lean4:v0.1 >/dev/null 2>&1 \
   || ! docker image inspect sunstead/verifier-rust:v0.1 >/dev/null 2>&1; then
  "$ROOT_DIR/scripts/build-verifiers.sh"
fi

echo "==> Building sunstead/hub:v0.1..."
docker build -t sunstead/hub:v0.1 "$ROOT_DIR"

docker rm -f sunstead-hub >/dev/null 2>&1 || true

echo "==> Starting Sunstead Hub on http://localhost:${PORT} ..."
docker run -d \
  --name sunstead-hub \
  -p "${PORT}:8080" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v sunstead-data:/app/data \
  -e RUST_LOG=sunstead_hub=info,tower_http=info \
  sunstead/hub:v0.1 >/dev/null

echo "==> Sunstead Hub is running!"
echo "    Live UI  : http://localhost:${PORT}/"
echo "    Join doc : http://localhost:${PORT}/join.txt"
echo "    Logs     : docker logs -f sunstead-hub"
echo "    Reset DB : docker rm -f sunstead-hub && docker volume rm sunstead-data"
