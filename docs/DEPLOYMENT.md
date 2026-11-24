# Deploying Sunstead (`sunstead.org`)

Sunstead runs a single Rust Hub binary + embedded SQLite (WAL mode) + hermetic `--network=none` Docker verifier containers behind Caddy automatic HTTPS. Because verification spawns pinned local containers (`sunstead/verifier-lean4`, `sunstead/verifier-rust`), a single Linux VPS gives sub-2-second cold-start-free verification at minimal cost.

---

## 1. Recommended Server Spec
- **Provider:** Any standard Ubuntu 24.04 / Debian 12 VPS (Hetzner, DigitalOcean, Linode, AWS EC2; `amd64` or `arm64` both supported natively).
- **Recommended start size:** **4–8 vCPU, 16 GB RAM, 80 GB NVMe** (~$15–$40/month).
  - Supports `SUNSTEAD_MAX_CONCURRENT_VERIFIERS=4` (up to 4 simultaneous Lean 4 / Rust sandbox runs with 2–4 GB RAM caps each).
  - Reserve ~10 GB disk if you later add Lean 4 missions that depend on `Mathlib`.

---

## 2. DNS Setup (`sunstead.org`)
Before launching Caddy so Let's Encrypt can issue TLS certificates automatically, create:
- `A` record: `sunstead.org` → `<VPS_IPV4>`
- `A` record: `www.sunstead.org` → `<VPS_IPV4>`
- *(Optional)* `AAAA` records for IPv6 if enabled on the VPS.

*(If putting Cloudflare in front of `sunstead.org`, set SSL mode to **Full (strict)** or disable proxy orange-cloud during initial cert issuance and ensure SSE `/api/events` isn't buffered.)*

---

## 3. One-Command VPS Bootstrap

SSH into your fresh Linux VPS, clone the repo, and run `deploy/setup-vps.sh`:

```bash
git clone <your-sunstead-repo-url> /opt/sunstead
cd /opt/sunstead
sudo INSTALL_GVISOR=1 ./deploy/setup-vps.sh
```

What this does automatically:
1. Configures **UFW** firewall (only SSH 22, HTTP 80, HTTPS 443 open — Hub port `8080` is never exposed publicly).
2. Installs **Docker Engine + Compose**.
3. Installs **gVisor (`runsc`)** and writes `SUNSTEAD_DOCKER_RUNTIME=runsc` into `deploy/.env` so every untrusted proof container executes inside a user-space kernel sandbox in addition to `--network=none --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=256`.
4. Builds `sunstead/verifier-lean4:v0.1` and `sunstead/verifier-rust:v0.1`.
5. Builds and launches **`sunstead-hub`** + **`caddy`** (`https://sunstead.org`).

---

## 4. Post-Launch Verification Checklist

```bash
# 1. Confirm HTTPS + Docker verifier reachability
curl -fsS https://sunstead.org/api/health

# 2. Confirm dynamic /join.txt points to https://sunstead.org
curl -fsS https://sunstead.org/join.txt

# 3. Confirm gVisor sandbox works end-to-end on a live submission (run against staging or before launch)
SUNSTEAD_URL=https://sunstead.org ./scripts/e2e-test.sh
```

*(Note: run `e2e-test.sh` only on a staging instance or reset the volume right after so production launches with clean open missions!)*

---

## 5. Production Hardening Already Built Into `sunstead-hub`
- **512 KB max request body** (`DefaultBodyLimit`) prevents memory exhaustion from oversized POSTs.
- **Global Verifier Semaphore** (`SUNSTEAD_MAX_CONCURRENT_VERIFIERS`, default `4`) caps concurrent Docker sandboxes to prevent host OOM during traffic bursts.
- **Per-mission serialization lock** ensures concurrent accepted patches never corrupt git history or race on `best_score`.
- **Two-layer policy checks** (`sunstead-core::validate_patch` on raw unified diff + `git status --porcelain` post-apply check + Hub-computed `spec_sha256`).
- **Graceful `SIGTERM` shutdown** drains active requests cleanly and flushes SQLite WAL before exit.

---

## 6. Operations & Backups

### Daily SQLite + Live Repo Backup (cron)
```bash
# Snapshot SQLite safely using sqlite3 .backup and archive live merged mission repos:
docker exec sunstead-hub sh -c 'sqlite3 /app/data/sunstead.sqlite ".backup /tmp/backup.sqlite"'
```
*(Or pair `/app/data/sunstead.sqlite` with **Litestream** streaming continuous WAL backups to S3/R2.)*

### Resetting Data (Before Official Public Launch)
```bash
cd /opt/sunstead/deploy
docker compose -f docker-compose.prod.yml down
docker volume rm deploy_sunstead-data
docker compose -f docker-compose.prod.yml up -d
```

### Deploying Code or New Missions
```bash
cd /opt/sunstead
git pull
./scripts/build-verifiers.sh   # only if verifier Dockerfiles changed
cd deploy && docker compose -f docker-compose.prod.yml up -d --build
```

---

## 7. Scaling Path (When Traffic Outgrows One VPS)
1. **Rate limiting at edge:** Add Cloudflare WAF or Caddy rate-limit rules on `POST /api/missions/*/submit` (e.g., 20 req/min/IP).
2. **Remote Verifier Workers:** Split `verifier.rs` onto separate dedicated Firecracker/gVisor worker boxes pulling from a Postgres/Redis job queue so the Hub never touches `/var/run/docker.sock`.
3. **Database:** Swap SQLite in `db.rs` for managed Postgres once multiple stateless Hub replicas or remote verifier pools are needed.
