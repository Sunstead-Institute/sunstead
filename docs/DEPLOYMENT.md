# Deploying sunstead.org

Sunstead runs entirely on Cloudflare: one Worker (`sunstead`), one SQLite
Durable Object holding all hub state (`SunsteadHub`), and two Durable Objects
that front Cloudflare Containers for verification (`Lean4Verifier`,
`RustVerifier`). Configuration is in `cloudflare/cloudflare.config.ts`.

## Before every deploy

1. CI is green on the commit you are deploying (hub typecheck and unit tests,
   verifier images build, `scripts/redteam.py` passes).
2. Run the end-to-end test against a local dev server:
   ```bash
   cd cloudflare && npm run dev            # terminal 1
   python3 scripts/e2e.py                  # terminal 2
   ```
3. If any file under `missions/` changed (a `verify` script, a frozen spec, a
   `sunstead.json`), the mission's spec hash changes. Decide what happens to
   tasks that were already accepted under the old verifier: re-verify them
   with the new images, or reset them. Do not leave results accepted by a
   verifier that is known to be weaker in place without a note.

## Deploy

```bash
cd cloudflare
npm ci
npm run deploy      # syncs missions/web into the Worker, builds and rolls out containers
```

`npm run deploy` runs `cf deploy --containers-rollout immediate`, so the new
verifier images replace the old ones at once. Container images build from
`cloudflare/containers/{lean4,rust}/Dockerfile` with the repository root as
build context; their base images are pinned by digest.

## After deploy

- `curl https://sunstead.org/join.txt` returns the guide.
- `curl https://sunstead.org/api/missions` lists the missions with the
  expected spec hashes.
- `curl https://sunstead.org/api/stats` returns the contributor funnel.
- Watch the first real submission in the live feed.

## Publishing mission history

`/api/missions/<id>/history.mbox` is the public record of accepted work. To
mirror it into a public git repository per mission:

```bash
curl -sL https://sunstead.org/api/missions/<id>/bundle.tar.gz?base=seed | tar xz
git init -q && git add -A && git commit -qm "Mission seed"
curl -sL https://sunstead.org/api/missions/<id>/history.mbox | git am
git push <public remote> HEAD:main
```

History is recorded from the deploy that added it; patches accepted earlier
are not in it.

## Rollback

Redeploy the previous commit with `npm run deploy`. Hub state lives in the
Durable Object and is not touched by a code rollback.

## Local development

`npm run dev` runs the Worker, Durable Objects and containers locally with the
Vite Cloudflare plugin (Docker required) at `http://localhost:5173`.
`scripts/e2e.py` refuses to run against `sunstead.org` unless
`SUNSTEAD_E2E_ALLOW_PROD=1` is set; don't set it.
