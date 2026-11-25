# Spike Report: Reducing GitHub Actions Minutes Without Weakening Proof Verification

**Date:** 2026-11-25  
**Repo:** `Sunstead-Institute/sunstead` (`visibility: PRIVATE`, Free org allowance = **2,000 included Linux minutes/month**)  
**Trigger:** 92 workflow runs across 7 hours (`12:25Z`–`19:19Z` on 2026-11-25) exhausted the monthly 2,000-minute cap and blocked PR #34/#35/#36 hosted CI jobs before a runner started.

---

## 1. Usage Breakdown (Measured vs. Estimated Billed Minutes)

### Measurement Methodology
- **Official billing endpoints:** `GET /orgs/Sunstead-Institute/settings/billing/actions` returned `HTTP 410` (endpoint moved / requires `admin:org` scope), and `GET /actions/runs/{id}/timing` returned `billable.UBUNTU.total_ms: 0` across all 92 runs. Direct invoice-billed totals are therefore not exposed to the repo token.
- **Measured runner wall time:** Summed directly from GitHub Jobs API `started_at` → `completed_at` across all **353 jobs** in all **92 runs**, excluding jobs with zero started steps (billing-blocked or concurrency-cancelled before runner assignment): **`2,281.4` measured wall minutes** on `ubuntu-latest` (`1×` Linux multiplier; 100% of jobs ran on `ubuntu-latest`).
- **Estimated billed minutes:** GitHub rounds each executed job **up** to the nearest whole minute (`Σ ceil(job_wall_sec / 60)`): **`2,441` estimated billed minutes** (`2,131` success, `171` cancelled, `139` failed). The first 0-step billing-blocked run occurred at `2026-11-25T19:19:33Z` (run `45684059014`, `Publish Verifier Images (GHCR)`), after concurrent in-flight 4-job waves pushed cumulative usage past the 2,000-minute cap.

### Breakdown by Workflow and Trigger

| Workflow | Trigger | Runs (Ran / Blocked / Total) | Measured Wall Min | Est. Billed Min | Share | Cancelled Billed Min |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: |
| `CI` | `pull_request` | 41 / 6 / 49 | 1,641.2 | **1,759** | 72.1% | 171 |
| `CI` | `push` (`main`) | 13 / 3 / 32\* | 480.8 | **514** | 21.1% | 0 |
| `Publish Verifier Images (GHCR)` | `push` (`main`) | 3 / 4 / 7 | 92.4 | **97** | 4.0% | 0 |
| `Audit published proofs` | `workflow_dispatch` | 3 / 0 / 3 | 66.1 | **68** | 2.8% | 0 |
| `Deploy Production (sunstead.org)` | `workflow_dispatch` | 1 / 0 / 1 | 0.9 | **3** | 0.1% | 0 |
| **Total** | | **61 / 13 / 92** | **2,281.4** | **2,441** | **100%** | **171** |

\* *16 of 32 `CI` `push` (`main`) runs ended `cancelled` with 0 executed jobs because `concurrency: cancel-in-progress: false` holds at most 1 running + 1 pending run on `refs/heads/main`; rapid merges auto-evicted queued middle runs while still burning 514 min on the 13 runs that executed.*

### Top Minute Drivers (Current 3-Toolchain Layout at `59a5184`)

Every **single PR push** currently executes **7 jobs** costing **~108 estimated billed minutes** (even for 1-line `web/`, `cloudflare/src/`, or `docs/` edits):

| Job (Workflow) | Avg Wall (Success) | Est. Billed / Run | Dominant Steps |
| :--- | ---: | ---: | :--- |
| `verifiers` (`v4.36.0 + v4.35.0`, `CI`) | 42.1 min | 43 min | Build 19.9m · `check-statements` 10.2m · `redteam` 8.6m · `test_audit_live` 1.7m · free disk 1.7m |
| `verifiers-v431` (`v4.31.0`, `CI`) | 23.1 min | 24 min | Build 14.3m · free disk 3.1m · `test_audit_live` 2.7m · `redteam` 2.1m · `check-statements` 0.8m |
| `hub-images` (`v4.36.0 + v4.35.0`, `CI`) | 22.3 min | 23 min | **Duplicate** build 19.8m · free disk 2.3m · smoke check **0.16m** |
| `hub-images-v431` (`v4.31.0`, `CI`) | 14.3 min | 15 min | **Duplicate** build 12.7m · free disk 1.5m · smoke check **0.09m** |
| `export-upstream` (`CI`) | 0.93 min | 1 min | `elan` install + `test_export_upstream.py` |
| `hub` + `python` (`CI`) | 0.5 min | 2 min | `npm ci`/`typecheck`/`test` + offline Python checks |
| `Publish GHCR` (`v4.36` + `v4.35` + `v4.31`) | 41.3 min | 42 min | `v4.36.0` 17.4m + `v4.35.0` 8.0m + `v4.31.0` 15.9m (all 3 built on any `missions/**` push) |

### Root Causes of the 7-Hour Burn
1. **100% duplicate Docker builds (`909` of `2,273` CI min = 40.0% of all CI spend):** `missions/verifier-lean4*/Dockerfile` and `cloudflare/containers/lean4*/Dockerfile` have **byte-for-byte identical** `apt-get`, `elan`, `/opt/mathlib`, and `Aeneas`/`PrimeCert` layers (only `--platform=linux/amd64` differs on line 1, which resolves to the same image on `ubuntu-latest`). Running `hub-images` and `hub-images-v431` on separate fresh runners throws away the Docker layer cache and rebuilds all 3 toolchains from scratch solely to run 15 seconds of `test -d` / `selftest` smoke checks.
2. **Zero path filtering (`16/36` PRs = 44.4% touched zero verifier/mission/container files):** Pure Hub, UI, docs, and scout/tooling PRs still burn ~108 min per push + ~108 min on `main` merge = **~216 min/PR**. Even a single-toolchain mission PR rebuilds the other two toolchains (e.g., a `v4.36.0` IEANTN PR burns 39 extra min on `v4.31.0`).
3. **PR + `main`-push double-billing (`514` billed min = 21.1%):** GitHub's `pull_request` event already builds and tests the merge ref (`refs/pull/<n>/merge`). Merging immediately triggers a second identical 108-min `CI` run on `push: main`, plus a third 42-min all-3-toolchain rebuild in `publish-verifiers.yml` if any file under `missions/**` changed (**~258 min** for one single-push mission PR, or **~366 min** with one review revision).
4. **Superseded PR runs (`171` billed min = 7.0%):** `ci.yml` already cancels superseded non-`main` PR runs, but rapid follow-up pushes during 20–42 min Docker builds still bill the partial minutes already elapsed.

---

## 2. Option Comparison & Security Posture

| Option | Est. Impact | Proof / Security Coverage | Operational Complexity & Risk |
| :--- | :--- | :--- | :--- |
| **A. Fail-closed per-toolchain path gate (`scripts/ci-path-gate.py`)** | Saves ~105 min on Hub/UI/docs PRs (97%); ~39–93 min on single-toolchain mission PRs | **Zero weakening:** dynamically reads every `missions/*/sunstead.json` image; fails closed to all 3 toolchains on `verifier-common/**`, test/audit scripts, `verifier_server.py`, `ci.yml`, deleted/unknown missions, or diff errors | **Low** — ~150 lines of stdlib Python with offline unit tests + always-on `ci-gate` check for branch protection |
| **B. Co-locate Cloudflare container build inside each per-toolchain verifier job** | Saves **~34 min/run** (eliminates separate 23m `hub-images` + 15m `hub-images-v431` runners) | **Zero weakening:** builds exact same `cloudflare/containers/lean4*/Dockerfile` and runs exact same smoke assertions; zero changes to `cf deploy` | **Very low** — local Docker BuildKit automatically hits the `apt-get`/`elan`/`/opt/mathlib`/`Aeneas` layers built minutes earlier on the same runner |
| **C. Deduplicate `push: main` heavy matrix + weekly full sweep** | Saves **~105 min/merge** (eliminates 2× PR+merge billing) | **Zero weakening on PRs/deploys:** PR merge-ref checks gate every merge, `publish-verifiers.yml` builds+selftests changed toolchains on `main`, `deploy.yml full` gates production container deploys, and weekly `schedule` sweeps all 3 toolchains on `main` | **Very low** — `hub` + `python` remain always-on for every `main` commit (~2 min) |
| **D. Per-toolchain gating in `publish-verifiers.yml`** | Saves 24–34 min on single-toolchain mission merges (42m → 8–18m) | **Zero weakening:** `missions/verifier-common/**` still publishes all 3; `workflow_dispatch` still allows manual `all` or single target | **Very low** — reuses `scripts/ci-path-gate.py` |
| **E. GHCR BuildKit registry layer cache (Tier 2 follow-up)** | Additional ~11m saved per cold `v4.36.0` / `v4.31.0` run (~30–35% faster verifier PRs) | Safe **only** if cache writes are restricted to trusted `main` pushes (`--cache-to`) and PRs get **read-only** `--cache-from` (prevents PR cache poisoning); `audit-proofs.yml` must remain independent | **Medium** — requires Buildx setup + GHCR cache tag lifecycle; good Phase 2 after Tier 1 lands |
| **F. Self-hosted persistent runner** | Could drop hosted minutes to ~0 | **Rejected for untrusted PRs:** violates isolation rule (*never run untrusted PR/proof code on a persistent host with secrets* — e.g. `CLOUDFLARE_API_TOKEN`, `SUNSTEAD_AUDIT_TOKEN`, or shared Docker daemon) | **High** — host maintenance, secret-isolation risk |
| **G. Making repo public (org policy decision)** | Public repos get unlimited free standard GitHub-hosted minutes | Aligns with Sunstead's Apache-2.0 public auditability model (does not replace Tier 1 speedups, which still cut PR latency from 42m to 1–35m) | **Non-engineering decision** — separate from workflow changes |

---

## 3. Recommended Smallest Safe Change (Tier 1) & Savings Model

Implement **Options A + B + C + D together** (included as a ready-to-review patch in this branch, with **zero** changes to Lean kernel checks, verifier Dockerfiles, `cf deploy`, or `audit-proofs.yml`):
1. Add fail-closed `scripts/ci-path-gate.py` + offline unit tests `scripts/test_ci_path_gate.py` (run in `python` on every PR/push).
2. Add `--image` filter to `scripts/redteam.py` and `scripts/check-statements.py` so each per-toolchain CI job automatically covers every mission targeting that toolchain image (no fragile hardcoded `--exclude-mission` lists).
3. Update `.github/workflows/ci.yml`: split into `changes`, always-on `hub` + `python`, gated `export-upstream`, gated per-toolchain `verifiers-v436` / `verifiers-v435` / `verifiers-v431` (each co-locating its Cloudflare container build + smoke test on the same runner to reuse cached `elan`/`Mathlib`/`Aeneas` layers), weekly `schedule` full 3-toolchain sweep, and always-on `ci-gate` for branch protection.
4. Update `.github/workflows/publish-verifiers.yml`: add `changes` job using `ci-path-gate.py` so `push: main` publishes only affected toolchain image(s).

### Estimated Savings per PR (1 push + merge to `main`, including GHCR publish where triggered)

| PR Type | Current (`59a5184`) | Tier 1 Proposed | Savings | Tier 1 + Tier 2 (GHCR Cache) |
| :--- | ---: | ---: | ---: | ---: |
| Hub / UI / Docs / Scout PR | **216 min** | **5 min** | **-97.7%** (-211m) | 5 min |
| Single `v4.36.0` mission PR | **258 min** | **58 min** | **-77.5%** (-200m) | ~37 min |
| Single `v4.35.0` mission PR | **258 min** | **25 min** | **-90.3%** (-233m) | ~19 min |
| Single `v4.31.0` mission PR | **258 min** | **45 min** | **-82.6%** (-213m) | ~24 min |
| Shared `verifier-common/**` PR (all 3 toolchains) | **258 min** | **119 min** | **-53.9%** (-139m) | ~71 min |

### Estimated Monthly Usage vs. 2,000-Minute Allowance

Steady-state workload assumption: **30 merged PRs/month** at **1.5 CI pushes/PR** (16 Hub/UI/docs, 8 `v4.36.0` mission, 2 `v4.35.0` mission, 1 `v4.31.0` mission, 3 `verifier-common`), plus **4 weekly `audit-proofs.yml` runs** (~35m each), **4 weekly full `main` sweeps** (~72m each in Tier 1), **4 `worker` deploys** (3m each), and **2 `full` deploys**:

| Configuration | Est. Monthly Minutes | % of 2,000-Min Cap | Savings vs. Current |
| :--- | ---: | ---: | ---: |
| **Current workflows (`59a5184`)** | **~9,030 min/mo** | **451% (4.5× over cap)** | baseline |
| **Tier 1 (this patch)** | **~1,893 min/mo** | **95% (fits inside 2,000 min)** | **-7,137 min/mo (-79.0%)** |
| **Tier 1 + Tier 2 (read-only GHCR BuildKit cache on PRs)** | **~1,252 min/mo** | **63% (748 min/mo headroom)** | **-7,778 min/mo (-86.1%)** |

*(Note: during high-velocity sprint weeks with >30 PRs/month on a private repo, either adding Tier 2 BuildKit caching, switching `publish-verifiers.yml` to `workflow_dispatch`/tag-driven, or making the repo public provides comfortable headroom.)*

---

## 4. Validation & Rollback

### Local Validation (Zero Hosted Reruns)
- `python3 -m py_compile scripts/ci-path-gate.py scripts/test_ci_path_gate.py scripts/redteam.py scripts/check-statements.py`
- `python3 scripts/test_ci_path_gate.py -v` (verifies Hub/UI skip, single-toolchain isolation, `verifier-common` / `redteam.py` / `verifier_server.py` fan-out, deleted/unknown mission fail-closed, `schedule`/`workflow_dispatch` fail-closed, and dynamic `sunstead.json` discovery)
- `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml")); yaml.safe_load(open(".github/workflows/publish-verifiers.yml"))'`
- `python3 scripts/ci-path-gate.py --event pull_request --base origin/main --head HEAD` (dry-run check on real branch diffs)
- Once GitHub Actions billing quota resets/reopens: open one docs-only test PR (confirm only `changes`, `hub`, `python`, `ci-gate` run in ~2 min) and one `verifier-common` PR (confirm all 3 per-toolchain jobs run and local Docker cache hits on the co-located Cloudflare container build step).

### Rollback
- Single-commit `git revert` restores `.github/workflows/ci.yml` and `.github/workflows/publish-verifiers.yml` to the unconditional 7-job matrix immediately (`--image` flags in `redteam.py` and `check-statements.py` are strictly additive and backwards-compatible).
- If GitHub branch protection is updated to require `CI Gate (required branch-protection check)`, reverting `ci.yml` only requires re-selecting the original job names in branch protection settings.
