# Deploying sunstead.org

Sunstead runs entirely on Cloudflare: one Worker (`sunstead`), one SQLite
Durable Object holding all hub state (`SunsteadHub`), and three Durable Object
pools fronting pinned, networkless Lean 4 Cloudflare Containers. Configuration
is in `cloudflare/cloudflare.config.ts`.

### Verifier Container Pools

| Container Application | Durable Object Class | Dockerfile | Instance Type & Pool | Env Override (Worker-Only Deploy) | Pinned Toolchain |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `sunstead-verifier-lean4` | `Lean4Verifier` | `cloudflare/containers/lean4/Dockerfile` | `standard-3` (2 vCPU, 8 GiB RAM, 16 GB disk), `maxInstances: 6` | `SUNSTEAD_VERIFIER_IMAGE` | Lean `v4.36.0` + Mathlib |
| `sunstead-verifier-lean4-v435` | `Lean4V435Verifier` | `cloudflare/containers/lean4-v4.35.0/Dockerfile` | `standard-2` (1 vCPU, 6 GiB RAM, 12 GB disk), `maxInstances: 4` | `SUNSTEAD_VERIFIER_V435_IMAGE` | Lean `v4.35.0` repo-snapshots (LNSym) |
| `sunstead-verifier-lean4-v431` | `Lean4V431Verifier` | `cloudflare/containers/lean4-v4.31.0/Dockerfile` | `standard-3` (2 vCPU, 8 GiB RAM, 16 GB disk), `maxInstances: 4` | `SUNSTEAD_VERIFIER_V431_IMAGE` | Lean `v4.31.0` + Mathlib + Aeneas + PrimeCert (`curve25519-dalek`) |

## Before every deploy

1. CI is green on the commit you are deploying (hub typecheck and unit tests,
   Python/provenance/`best-known` gates, and any applicable path-gated Lean 4
   verifier builds, `scripts/redteam.py`, `scripts/check-statements.py`, and
   Cloudflare container image builds). Both `scripts/check-statements.py` and
   `scripts/redteam.py` support parallel execution via `--jobs <N>` (e.g.
   `--jobs 3` for `v4.36.0`, `--jobs 2` for `v4.35.0`).
2. Run the end-to-end test against a local dev server:
   ```bash
   cd cloudflare && npm run dev            # terminal 1
   python3 scripts/e2e.py                  # terminal 2
   ```
3. If any file under `missions/` changed (a `verify` script, a frozen spec, a
   `sunstead.json`), the mission's spec hash changes. Decide what happens to
   tasks that were already accepted under the old verifier: re-verify them
   with the new image, or reset them. Do not leave results accepted by a
   verifier that is known to be weaker in place without a note.

## Deploy

There are two deploy modes. Both run `scripts/sync-assets.mjs` first (generating
deduplicated `SEED_FILE_BLOBS` assets under `cloudflare/src/generated/`) and
use `cf deploy --containers-rollout immediate`.

### Full deploy (rebuilds all 3 Lean 4 verifier images)

```bash
cd cloudflare
npm ci
npm run deploy      # syncs missions/web into the Worker, builds and rolls out all 3 Lean 4 containers
```

Each container image builds from its Dockerfile under
`cloudflare/containers/lean4*/Dockerfile` with the repository root as build
context; base images are pinned by digest. On Apple Silicon this is a
`linux/amd64` Lean + Mathlib build under emulation and takes 10 to 20+ minutes
(prefer the native x86_64 GitHub Actions workflow below for full deploys). Use
`full` whenever anything any verifier image copies in has changed: `missions/`
(frozen specs, `verify` scripts, `sunstead.json`), `missions/verifier-common/`,
`cloudflare/containers/verifier_server.py`, or any verifier Dockerfile itself.

After a successful full deploy, `scripts/deploy.mjs` records a combined SHA-256
of all three Dockerfiles and every file they copy in (`npm run verifier-inputs`
prints it) in `cloudflare/.cloudflare/verifier-image.json`. That file is
git-ignored and local to the checkout.

### Worker-only deploy (UI, hub and Worker code; about 5 seconds)

```bash
cd cloudflare
npm run deploy:worker                 # add -- --dry-run to build and check without uploading
```

For each of the three verifier applications (`sunstead-verifier-lean4`,
`sunstead-verifier-lean4-v435`, and `sunstead-verifier-lean4-v431`),
`scripts/deploy.mjs` finds the application ID via
`cf containers applications list --name <app>` and then reads the authoritative
single-application record via `cf containers applications get <id>` (avoiding
stale `active_rollout_id` or pre-rollout digests that the list endpoint can
report right after a rollout completes). It exports `SUNSTEAD_VERIFIER_IMAGE`,
`SUNSTEAD_VERIFIER_V435_IMAGE`, and `SUNSTEAD_VERIFIER_V431_IMAGE` to those
digest-pinned images and runs `cf deploy`. With those variables set,
`cloudflare.config.ts` declares `image: { reference: <digest> }` instead of the
Dockerfiles, so no Docker build happens and all three container pools keep the
exact images they already run. To pin specific images manually, set any of the
three env vars before running:

```bash
SUNSTEAD_VERIFIER_IMAGE=registry.cloudflare.com/<account>/sunstead-verifier-lean4@sha256:<digest> \
SUNSTEAD_VERIFIER_V435_IMAGE=registry.cloudflare.com/<account>/sunstead-verifier-lean4-v435@sha256:<digest> \
SUNSTEAD_VERIFIER_V431_IMAGE=registry.cloudflare.com/<account>/sunstead-verifier-lean4-v431@sha256:<digest> \
  npm run deploy:worker
```

Guard rails:

- Only `registry.cloudflare.com/...@sha256:<64 hex>` is accepted, by both the
  script and `cloudflare.config.ts`. A mutable tag could swap a verifier
  without anyone noticing.
- Each verifier image carries its own copy of its missions. If the
  verifier-inputs hash differs from the one recorded by the last full deploy,
  `deploy:worker` refuses, because the Worker and verifier containers would then
  disagree about the missions. Run `npm run deploy` instead.
- With no record (a fresh checkout, CI, or a full deploy made before this
  script existed), it also refuses. If you have confirmed that all three live
  images were built from the same `missions/` and verifier code, pass
  `npm run deploy:worker -- --force`.

### Worker secrets (`ADMIN_API_TOKEN`)

`ADMIN_API_TOKEN` is an optional Cloudflare Worker secret authenticating the
Phase 1 decomposition allowlist management endpoint
(`/api/admin/decomposition-allowlist`, which returns HTTP `503` when unset).
Configure or rotate it on the `sunstead` Worker using Cloudflare's `cf` CLI
(never commit secrets into `cloudflare.config.ts` or git):

```bash
cd cloudflare
# Preview the request without sending it:
npx cf workers secrets update ADMIN_API_TOKEN \
  --worker sunstead --type secret_text --text "$ADMIN_API_TOKEN" --dry-run

# Apply the secret to production (creates a new Worker version with the binding):
npx cf workers secrets update ADMIN_API_TOKEN \
  --worker sunstead --type secret_text --text "$ADMIN_API_TOKEN"
```

### GitHub Actions deploy (native `linux/amd64`, recommended for full deploys)

`.github/workflows/deploy.yml` runs on native x86_64 `ubuntu-latest` runners,
avoiding Apple Silicon QEMU emulation during full Lean 4 + Mathlib container
builds. Trigger it manually from **Actions → Deploy Production (sunstead.org) →
Run workflow** (or via `gh workflow run deploy.yml`):

- **`mode: full`** (default): runs the `hub`, `python`, `verifiers`
  (`v4.36.0` + `v4.35.0`), and `verifiers-v431` (`v4.31.0`) gates — running
  `scripts/redteam.py` and `scripts/check-statements.py` with parallel `--jobs`
  workers (e.g. `--jobs 3` on `v4.36.0`, `--jobs 2` on `v4.35.0`) — frees
  runner disk headroom, builds all 3 Lean 4 containers natively on x86_64,
  deploys via `node scripts/deploy.mjs full`, and runs post-deploy read-only
  smoke checks against `https://sunstead.org`.
- **`mode: worker`**: runs the `hub` and `python` gates, skips the container
  Docker builds, and deploys Worker/UI/hub changes via
  `node scripts/deploy.mjs worker --force` (reusing all three live container
  digests via `applications get`). Only choose `worker` when `missions/` and
  `cloudflare/containers/` are unchanged relative to the live container images.
- **`rollout`**: `immediate` (default) or `gradual`.

Required GitHub Actions repository secrets (**Settings → Secrets and variables → Actions**):

- `CLOUDFLARE_API_TOKEN` (required): a Cloudflare API token with permissions to
  deploy Workers, Durable Objects, and Cloudflare Containers (e.g. **Workers
  Scripts: Edit**, **Workers KV / Durable Objects / Containers: Edit**,
  **Account Settings: Read**).
- `CLOUDFLARE_ACCOUNT_ID` (optional if the token is scoped to a single account):
  the Cloudflare account ID owning `sunstead`.

Concurrent runs are serialized via `concurrency: production-deploy`
(`cancel-in-progress: false`).

### Retired v0.2 Rust / Verus verifiers

The Rust and Verus Durable Object classes and their deleted-class tombstones
are gone from `cloudflare/cloudflare.config.ts`. If orphaned container
applications (`sunstead-verifier-rust`, `sunstead-verifier-verus`) still exist
in the account, list and delete them:

```bash
npx cf containers applications list
npx cf containers applications delete <application-id>
```

Inside `SunsteadHub`, `seedMissions()` prunes retired missions from the active
`missions`, `tasks`, `mission_files` and `bundle_cache` tables and keeps the
historical `submissions`, `contributors`, `claims_log` and `accepted_patches`.

### Durable Object code updates (new hub code runs within about 15 seconds)

By default Cloudflare applies new code to an active Durable Object only once it
hibernates, or after 300 seconds. `SunsteadHub` never hibernates while a browser
holds `/api/events` open, so every deploy used to take about 5 minutes to reach
the hub. Shortening each stream would not help: browsers reconnect at once, so
some stream is always open.

`cloudflare.config.ts` therefore sends
`code_update_strategy: { mode: "deferred", max_delay: 15 }` with every deploy
(through `unsafe.metadata`, because `cf/config` has no typed field for it yet;
`cf deploy --dry-run` prints it under "unsafe metadata"). Both deploy modes use it.

What a deploy does to traffic:

- Within 15 seconds of the deploy, Cloudflare resets any Durable Object still
  running the old code (in practice `SunsteadHub`, plus `Lean4Verifier`,
  `Lean4V435Verifier`, or `Lean4V431Verifier` if a verification is running)
  onto the new code. Storage is untouched.
- Every SSE stream drops. Each stream starts with `retry: 2000`, so browsers
  reconnect after about 2 seconds, and the UI reloads missions and the
  leaderboard on reconnect to catch events it missed.
- A claim, release or other short request finishes inside the 15 seconds.
- A verification still running when the reset happens is cut off and the
  contributor gets an error and resubmits (any orphaned `verifying` submission
  row is automatically reaped to `status = 'error'` after `STALE_VERIFYING_SEC = 600`
  seconds on Durable Object startup or polling). Nothing is lost: the hub writes
  the verdict, points and files only after the verifier answers. To avoid this,
  deploy when the live feed shows no "Verifying patch" in progress.

To change the delay, edit `DO_CODE_UPDATE_MAX_DELAY_SEC` (0 to 86400 seconds).
`mode: "immediate"` would reset at once and cut off even short requests.

## Publishing public GHCR verifier images

`.github/workflows/publish-verifiers.yml` builds and pushes public multi-toolchain verifier images to GitHub Container Registry under `ghcr.io/sunstead-institute/` on pushes to `main` touching `missions/**` or manually via **Actions → Publish Verifier Images (GHCR) → Run workflow**:

- `ghcr.io/sunstead-institute/verifier-lean4:v0.2` (Lean `v4.36.0` + Mathlib)
- `ghcr.io/sunstead-institute/verifier-lean4-v4.35.0:v0.1` (Lean `v4.35.0` repo-snapshot, e.g. LNSym)
- `ghcr.io/sunstead-institute/verifier-lean4-v4.31.0:v0.1` (Lean `v4.31.0` + Mathlib + Aeneas + PrimeCert repo-snapshot, e.g. `curve25519-dalek`)

Each job runs `/opt/sunstead/sunstead-check selftest` offline before pushing, tags both the version tag and `sha-<commit>`, and writes the immutable `@sha256:` digest to the workflow summary. On the very first push of a new package name under the `Sunstead-Institute` GitHub org, confirm its package visibility is set to **Public** in GitHub Packages settings so contributors can `docker pull` without authentication.

## After deploy

Run the strictly read-only post-deploy smoke suite against production (verifies
edge CSP/HSTS/Permissions-Policy security headers on `/`, `/proofs`, and
`/what-is-this`, `/api/health`, `/api/missions` and filtered queries,
`/api/frontier?unclaimed=true&tier=1&limit=10`,
`/api/submissions?status=accepted&limit=5`, `/api/proofs`, `/api/leaderboard`,
`/api/stats`, `/join.txt`, `/verify.py` syntax compilation, and `/mcp`
`OPTIONS` + `tools/list`, with zero mutations):

```bash
python3 scripts/e2e.py --smoke --base https://sunstead.org
```

And visually verify:

- The live feed indicator goes back to LIVE within about 20 seconds (the hub reset plus the 2-second reconnect).
- Watch the first real submission in the live feed.

## Publishing mission history

`/api/missions/<id>/history.mbox` is the public record of accepted work.
`bundle.tar.gz?base=seed` already contains a `.git` repository with the initial
seed commit, so `git am` applies directly on top of it:

```bash
mkdir -p mirror-<id> && cd mirror-<id>
curl -sL https://sunstead.org/api/missions/<id>/bundle.tar.gz?base=seed | tar xz
curl -sL https://sunstead.org/api/missions/<id>/history.mbox | git am
git push <public remote> HEAD:main
```

History is recorded from the deploy that added it; patches accepted earlier
are not in it.

## Rollback

Redeploy the previous commit with `npm run deploy`. Hub state lives in the
Durable Object and is not touched by a code rollback.

## Local development

`npm run dev` runs the Worker, Durable Objects and Lean 4 containers locally with
the Vite Cloudflare plugin (Docker required) at `http://localhost:5173`.
Without `--smoke`, `scripts/e2e.py` refuses to run against `sunstead.org` unless
`SUNSTEAD_E2E_ALLOW_PROD=1` is set; don't set it (use `python3 scripts/e2e.py --smoke --base https://sunstead.org` for safe read-only production verification).
