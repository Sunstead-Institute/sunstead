# Deploying sunstead.org

Sunstead runs entirely on Cloudflare: one Worker (`sunstead`), one SQLite
Durable Object holding all hub state (`SunsteadHub`), and one Durable Object
fronting the Lean 4 Cloudflare Container (`Lean4Verifier`). Configuration is in
`cloudflare/cloudflare.config.ts`.

## Before every deploy

1. CI is green on the commit you are deploying (hub typecheck and unit tests,
   Lean 4 verifier image builds, `scripts/redteam.py` passes, and the Cloudflare
   container image builds).
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

There are two deploy modes. Both run `scripts/sync-assets.mjs` first and use
`cf deploy --containers-rollout immediate`.

### Full deploy (rebuilds the Lean 4 verifier image)

```bash
cd cloudflare
npm ci
npm run deploy      # syncs missions/web into the Worker, builds and rolls out the Lean 4 container
```

The container image builds from `cloudflare/containers/lean4/Dockerfile` with
the repository root as build context; its base image is pinned by digest. On
Apple Silicon this is a `linux/amd64` Lean + Mathlib build under emulation and
takes 10 to 20 minutes. Use it whenever anything the image copies in has
changed: `missions/` (frozen specs, `verify` scripts, `sunstead.json`),
`missions/verifier-common/`, `cloudflare/containers/verifier_server.py`, or the
Dockerfile itself.

After a successful full deploy, `scripts/deploy.mjs` records a SHA-256 of the
Dockerfile and every file it copies in (`npm run verifier-inputs` prints it)
in `cloudflare/.cloudflare/verifier-image.json`. That file is git-ignored and
local to the checkout.

### Worker-only deploy (UI, hub and Worker code; about 5 seconds)

```bash
cd cloudflare
npm run deploy:worker                 # add -- --dry-run to build and check without uploading
```

This looks up the image the live `sunstead-verifier-lean4` application runs
(`cf containers applications list`), sets `SUNSTEAD_VERIFIER_IMAGE` to it, and
runs `cf deploy`. With that variable set, `cloudflare.config.ts` declares
`image: { reference: <digest> }` instead of the Dockerfile, so no Docker build
happens and the container keeps the image it already has. To pin a specific
image yourself, set the variable before running it:

```bash
SUNSTEAD_VERIFIER_IMAGE=registry.cloudflare.com/<account>/sunstead-verifier-lean4@sha256:<digest> npm run deploy:worker
```

Guard rails:

- Only `registry.cloudflare.com/...@sha256:<64 hex>` is accepted, by both the
  script and `cloudflare.config.ts`. A mutable tag could swap the verifier
  without anyone noticing.
- The verifier image carries its own copy of the missions. If the
  verifier-inputs hash differs from the one recorded by the last full deploy,
  `deploy:worker` refuses, because the Worker and the verifier would then
  disagree about the missions. Run `npm run deploy` instead.
- With no record (a fresh checkout, CI, or a full deploy made before this
  script existed), it also refuses. If you have confirmed that the live image
  was built from the same `missions/` and verifier code, pass
  `npm run deploy:worker -- --force`.

### GitHub Actions deploy (native `linux/amd64`, recommended for full deploys)

`.github/workflows/deploy.yml` runs on native x86_64 `ubuntu-latest` runners,
avoiding Apple Silicon QEMU emulation during full Lean 4.36 + Mathlib container
builds. Trigger it manually from **Actions → Deploy Production (sunstead.org) →
Run workflow** (or via `gh workflow run deploy.yml`):

- **`mode: full`** (default): runs the `hub`, `python`, and `verifiers`
  (`redteam.py` + `check-statements.py`) gates, frees runner disk headroom, builds
  the Lean 4 container natively on x86_64, deploys via `node scripts/deploy.mjs full`,
  and runs post-deploy read-only smoke checks against `https://sunstead.org`.
- **`mode: worker`**: runs the `hub` and `python` gates, skips the container
  Docker build, and deploys Worker/UI/hub changes via
  `node scripts/deploy.mjs worker --force`. Only choose `worker` when `missions/`
  and `cloudflare/containers/` are unchanged relative to the live container image.
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
  running the old code (in practice `SunsteadHub`, plus `Lean4Verifier` if a
  verification is running) onto the new code. Storage is untouched.
- Every SSE stream drops. Each stream starts with `retry: 2000`, so browsers
  reconnect after about 2 seconds, and the UI reloads missions and the
  leaderboard on reconnect to catch events it missed.
- A claim, release or other short request finishes inside the 15 seconds.
- A verification still running when the reset happens is cut off and the
  contributor gets an error and resubmits. Nothing is lost: the hub writes the
  verdict, points and files only after the verifier answers. To avoid this,
  deploy when the live feed shows no "Verifying patch" in progress.

To change the delay, edit `DO_CODE_UPDATE_MAX_DELAY_SEC` (0 to 86400 seconds).
`mode: "immediate"` would reset at once and cut off even short requests.

## Publishing public GHCR verifier images

`.github/workflows/publish-verifiers.yml` builds and pushes public multi-toolchain verifier images to GitHub Container Registry under `ghcr.io/sunstead-institute/` on pushes to `main` touching `missions/**` or manually via **Actions → Publish Verifier Images (GHCR) → Run workflow**:

- `ghcr.io/sunstead-institute/verifier-lean4:v0.2` (Lean `v4.36.0` + Mathlib)
- `ghcr.io/sunstead-institute/verifier-lean4-v4.35.0:v0.1` (Lean `v4.35.0` repo-snapshot, e.g. LNSym)
- `ghcr.io/sunstead-institute/verifier-lean4-v4.31.0:v0.1` (Lean `v4.31.0` + Mathlib + Aeneas repo-snapshot, once its Dockerfile is present on `main`)

Each job runs `/opt/sunstead/sunstead-check selftest` offline before pushing, tags both the version tag and `sha-<commit>`, and writes the immutable `@sha256:` digest to the workflow summary. On the very first push of a new package name under the `Sunstead-Institute` GitHub org, confirm its package visibility is set to **Public** in GitHub Packages settings so contributors can `docker pull` without authentication.

## After deploy

- `curl https://sunstead.org/join.txt` returns the Lean 4.36.0 + Mathlib onboarding guide.
- `curl https://sunstead.org/api/missions` lists the active Lean 4 missions (from `missions/*/sunstead.json`) with pinned upstream provenance, spec hashes, and `demo` flags.
- `curl https://sunstead.org/api/stats` returns the contributor funnel.
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

`npm run dev` runs the Worker, Durable Objects and Lean 4 container locally with
the Vite Cloudflare plugin (Docker required) at `http://localhost:5173`.
`scripts/e2e.py` refuses to run against `sunstead.org` unless
`SUNSTEAD_E2E_ALLOW_PROD=1` is set; don't set it.
