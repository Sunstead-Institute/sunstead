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

## After deploy

- `curl https://sunstead.org/join.txt` returns the Lean 4.36.0 + Mathlib onboarding guide.
- `curl https://sunstead.org/api/missions` lists the 3 Lean 4 missions (`arklib-near-capacity-primes`, `pnt-analytic-foundations`, `onboarding-sandbox`) with pinned upstream provenance, spec hashes, and `demo` flags.
- `curl https://sunstead.org/api/stats` returns the contributor funnel.
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
