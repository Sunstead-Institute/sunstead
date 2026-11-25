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

```bash
cd cloudflare
npm ci
npm run deploy      # syncs missions/web into the Worker, builds and rolls out the Lean 4 container
```

`npm run deploy` runs `cf deploy --containers-rollout immediate`, so the new
Lean 4 verifier image replaces the old one at once. The container image builds
from `cloudflare/containers/lean4/Dockerfile` with the repository root as build
context; its base image is pinned by digest.

### Retiring v0.2 Rust / Verus Durable Objects (one-time v1 migration)

`cloudflare/cloudflare.config.ts` declares deleted tombstones for the removed
v0.2 verifier classes:

```ts
RustVerifier: exports.durableObject({ state: "deleted" }),
VerusVerifier: exports.durableObject({ state: "deleted" }),
```

Cloudflare's `cf` 1.0 `exports` model uses `state: "deleted"` (replacing legacy
Wrangler `deleted_classes` migrations) to retire previously-deployed Durable
Object namespaces once their classes and bindings have been removed from code.

- On the first Lean-only v1 deploy, Cloudflare retires any existing
  `RustVerifier` / `VerusVerifier` Durable Object namespaces. If either class
  was never deployed on the target account, Cloudflare emits a non-fatal
  `stale_tombstone` notice.
- If orphaned container applications (`sunstead-verifier-rust`,
  `sunstead-verifier-verus`) remain in the account, list and delete them via:
  ```bash
  npx cf containers applications list
  npx cf containers applications delete <application-id>
  ```
- On the next deploy after retirement completes, Cloudflare prints
  `stale_tombstone` / "Safe to remove from `exports`" — you can then delete the
  two tombstone lines from `cloudflare/cloudflare.config.ts`.
- Inside `SunsteadHub`, `seedMissions()` automatically prunes retired missions
  from active `missions`, `tasks`, `mission_files`, and `bundle_cache` tables
  while preserving historical `submissions`, `contributors`, `claims_log`, and
  `accepted_patches`.

## After deploy

- `curl https://sunstead.org/join.txt` returns the Lean 4 onboarding guide.
- `curl https://sunstead.org/api/missions` lists the 4 Lean 4 missions with the
  expected spec hashes and `demo` flags.
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
