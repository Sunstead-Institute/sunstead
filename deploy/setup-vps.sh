#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu/Debian Linux VPS for https://sunstead.org
# Usage (as root or via sudo):
#   INSTALL_GVISOR=1 ./deploy/setup-vps.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_GVISOR="${INSTALL_GVISOR:-1}"

echo "==> 1/5 Installing base tools & firewall (ufw)..."
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg ufw git sqlite3

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

echo "==> 2/5 Installing Docker Engine + Compose plugin..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

if [ "$INSTALL_GVISOR" = "1" ]; then
  echo "==> 3/5 Installing gVisor (runsc) for kernel-isolated verifier containers..."
  curl -fsSL https://gvisor.dev/archive.key | gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" \
    > /etc/apt/sources.list.d/gvisor.list
  apt-get update
  apt-get install -y runsc
  runsc install
  systemctl reload docker
  export SUNSTEAD_DOCKER_RUNTIME=runsc
  echo "SUNSTEAD_DOCKER_RUNTIME=runsc" > "$ROOT_DIR/deploy/.env"
else
  echo "==> 3/5 Skipping gVisor (INSTALL_GVISOR=0); using standard hardened runc."
fi

echo "==> 4/5 Building pinned Lean 4 and Rust verifier images..."
"$ROOT_DIR/scripts/build-verifiers.sh"

echo "==> 5/5 Launching Sunstead Hub + Caddy HTTPS for sunstead.org..."
cd "$ROOT_DIR/deploy"
docker compose -f docker-compose.prod.yml up -d --build

echo ""
echo "==> Done! Verify DNS points sunstead.org to this server, then check:"
echo "    curl -s https://sunstead.org/api/health"
echo "    curl -s https://sunstead.org/join.txt"
