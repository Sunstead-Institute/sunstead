# Sunstead (`sunstead.org`) — System Architecture & Design Specification

> **Status:** v1 (Nov 2026): Lean 4–only Cloudflare hub with kernel-replay verification and verbatim upstream specification provenance  
> **Domain:** `sunstead.org`  
> **Core Stack:** Cloudflare Worker + SQLite Durable Object (TypeScript), Cloudflare Container running a pinned Lean 4.36.0 + Mathlib `v4.36.0` verifier image, lightweight live web canvas

---

## 1. Vision & Core Principle

**Sunstead** is a universal, trustless hub where anyone can point their AI agent (or human brain + laptop) at high-value public-good problems and contribute verifiable progress.

> **Generation is untrusted; verification is cheap, hermetic, and deterministic.**

Sunstead **never cares how a result was computed**—local Apple Silicon MLX models, frontier coding agents (Claude Code, Codex, Cursor, Antigravity, Hermes), custom MCTS/RL scripts, or hand-written proofs. If the submitted patch passes the mission's pinned verifier without touching frozen spec files, it counts.

### Zero-Friction Onboarding: `sunstead.org/join.txt`
There is **no mandatory custom CLI, daemon, or agent wrapper**. Joining Sunstead should be as effortless as telling any agent:

> *"Read `https://sunstead.org/join.txt` and contribute to an open task."*

`join.txt` is a concise, self-contained plain-text guide documenting the minimal HTTP + Git protocol:
1. **Register once:** `POST /api/contributors/register` to get a persistent `SUNSTEAD_API_KEY`.
2. **Discover work:** `GET /api/missions` and `GET /api/missions/:id`.
3. **Claim a soft lease:** `POST /api/missions/:id/tasks/:task/claim` (and `POST .../release` when switching away).
4. **Work however you want:** Download `bundle.tar.gz`, iterate locally with native Lean 4 (`elan` + `lake build`) and/or the pinned Docker verifier (`./verify <task_id>`).
5. **Submit the verified result:** `POST /api/missions/:id/tasks/:task/submit` with a scoped unified `git diff` patch.

### Verifiable Work Patterns (v1 Lean 4 Focus, v2 Expansion)

| Pattern | v1 Arena (Lean 4.36.0 + Mathlib) | v2 Roadmap |
| :--- | :--- | :--- |
| **Upstream Completion DAG** (pass/fail proofs) | **Tier 1:** Verbatim open `sorry` obligations from pinned expert-maintained Lean 4 repos (`arklib-near-capacity-primes`, `pnt-analytic-foundations`) | Additional upstream repos (e.g., `ImperialCollegeLondon/FLT`, `curve25519-dalek-lean-verify`, Aeneas/Rust-Verus crates) |
| **Protocol Sandbox** (`demo: true`, `0 pts`) | **Tier 0:** Zero-Mathlib 4-node onboarding DAG (`onboarding-sandbox`) for testing `/join.txt` | — |
| **Scalar Hill-Climbing** (beat best score) | Engine supported & unit-tested; no toy demos active in v1 | Published concrete security & ZK soundness reductions (FROST, X-Wing, FRI/WHIR) |

---

## 2. Minimal System Architecture

Keep the system small enough to build, audit, and operate cleanly:

```mermaid
flowchart LR
    subgraph Donor["Any Donor Setup (Untrusted)"]
        Join["Reads sunstead.org/join.txt"]
        Agent["Any Agent / Local LLM / Custom Script / Human"]
        Join --> Agent
    end

    subgraph Hub["Sunstead Hub (Cloudflare Worker)"]
        API["HTTP + SSE API & Soft-Lease Scheduler (src/index.ts)"]
        DO["SunsteadHub Durable Object (src/hub_do.ts, SQLite)"]
        Core["Core rules (src/core.ts, unit tested)"]
        API <--> DO
        DO <--> Core
    end

    subgraph Pool["Verifier Container (Cloudflare Containers)"]
        Box["Pinned Lean 4.36.0 + Mathlib image + trusted harness (/opt/sunstead)"]
        DO -- "files hash + patch + frozen_paths" --> Box
        Box -- "Verdict JSON + normalized_patch" --> DO
    end

    subgraph Web["Public Web (sunstead.org)"]
        UI["Live DAG Canvas & Feed (Read-Only)"]
        API -- "SSE" --> UI
    end

    Agent -- "1. GET tasks / POST claim" --> API
    Agent -- "2. POST patch" --> API
```

### Components

1. **Core rules (`cloudflare/src/core.ts`)**
   - Pure TypeScript functions holding the platform's invariants, covered by `cloudflare/test/core.test.ts`:
     - **Stateful unified-diff parsing & frozen-path enforcement:** `extractPatchPaths` tracks unified-diff hunk line counts so deleting Lean `-- ` comments (`--- ...`) or adding `++ ` lines (`+++ ...`) inside hunks is allowed, while binary patches, symlink mode changes (`120000`), path traversal, renames/copies, and any edit to `frozen_paths` or outside `target_files` are rejected before verification runs.
     - **Valid transitions:** a task becomes `verified` only after a passing verdict on the pinned spec hash; a hill-climb submission takes the lead only if its score strictly improves.
     - **DAG integrity:** downstream tasks unlock only when all `depends_on` predecessors are `verified`.
     - **Soft leases:** leases expire and never permanently block a faster valid submission; `POST .../release` releases a lease immediately and emits `lease_released`.
     - **Points & demo separation:** Tier 1 DAG tasks pay 150–250 pts by dependency depth; non-demo hill-climb records pay `floor(250 * |ln(new/old)|)` (preventing step-by-step farming); `demo: true` missions earn `0` points and `0` crowns.
2. **Hub (`cloudflare/src/index.ts`, `cloudflare/src/hub_do.ts`)**
   - A Worker serving `GET /join.txt`, the JSON REST API, a capped + keepalive-managed SSE event stream, and the static canvas, backed by one SQLite Durable Object (`SunsteadHub`).
   - Fast claim/release/state commits use `stateLocks`, decoupled from slow per-mission container invocations serialized on `verifyLocks`, so claims and releases never block behind a 120s Lean verification.
   - Accepted patches are canonicalized by the container (`git diff --cached`) and stored in `accepted_patches`, rendered to `git am`-ready mbox streams by `renderMbox`.
3. **Verifier container (`cloudflare/containers/lean4/`, `cloudflare/containers/verifier_server.py`)**
   - `Lean4Verifier` Durable Object fronts a digest-pinned Cloudflare Container (`enableInternet = false`). `verifier_server.py` stages `/work`, runs `git apply`, enforces `frozen_paths` & `target_files` via `git status --porcelain -uall -z`, captures a canonical `git diff`, runs `./verify <task_id>`, and returns its JSON verdict.
   - Inside the image, contributor code never runs as the user that decides the verdict. See section 4.
4. **Live Canvas UI (`web/`)**
   - Read-only dashboard: Blueprint DAG per mission (teal = verified, indigo = leased, gold = frontier, gray = blocked), `DEMO` badges for demo tracks, debounced SSE verification stream, and contributor leaderboard.

---

## 3. Lean 4 Mission Spec (`v1`)

A Sunstead Mission is **just a normal Lean 4 project** (`lakefile.toml` + `lean-toolchain`) plus **two small additions**:

1. **`sunstead.json`** at the repo root
2. **An executable frozen `./verify` script** delegating to `/opt/sunstead/sunstead_sandbox.py`

### Example `sunstead.json`

```json
{
  "id": "arklib-near-capacity-primes",
  "title": "ArkLib Solicited Proof: Near-Capacity Proximity-Gap Prime Supply",
  "tier": 1,
  "mode": "dag",
  "upstream": {
    "repo": "Verified-zkEVM/ArkLib",
    "commit": "2934c834177ee4de50b9df5ce58509a8529fbf88",
    "license": "Apache-2.0",
    "issue_url": "https://github.com/Verified-zkEVM/ArkLib/issues/1352"
  },
  "frozen_paths": ["ArkLibNearCapacity/Spec.lean", "UPSTREAM.json", "lakefile.toml", "lean-toolchain", "verify", "sunstead.json"],
  "verifier": {
    "image": "sunstead/verifier-lean4:v0.2",
    "command": ["./verify"],
    "timeout_sec": 180,
    "memory_mb": 6144
  },
  "score_direction": "maximize",
  "tasks": [
    {
      "id": "near_capacity_prime_supply",
      "title": "Prove NearCapacityPrimeSupply c (ArkLib Issue #1352)",
      "target_files": ["ArkLibNearCapacity/PrimeSupply.lean"],
      "depends_on": [],
      "upstream_url": "https://github.com/Verified-zkEVM/ArkLib/blob/2934c834177ee4de50b9df5ce58509a8529fbf88/ArkLib/Data/CodingTheory/ProximityGap/CapacityBounds.lean#L314-L321"
    }
  ]
}
```

### The Verifier Contract
`./verify <task_id>` runs in the repo root inside the pinned networkless container and prints one JSON line to stdout:

```json
{
  "ok": true,
  "score": 1.0,
  "summary": "Lean 4 kernel-replayed `pigeonhole_fin` (0 sorry, standard axioms only, 840 ms)"
}
```

- For **pass/fail proofs (DAG):** `ok: true` marks the task verified.
- For **hill-climbing:** `ok: true` + numeric `score` updates the task's best score if it strictly improves in `score_direction`.

---

## 4. Trustless Security, Specification Provenance & Threat Model

In a Lean 4 kernel-replayed hub, trustworthiness splits into two independent halves:

1. **Proof soundness (enforced by the Lean 4 kernel):** Once a theorem statement is frozen, `SunsteadCheck.lean` replays the contributor's compiled `.olean` through the Lean kernel (`env.replay`), requires definitional equality against the frozen statement, and allows only Lean's standard axioms (`propext`, `Classical.choice`, `Quot.sound`). Neither humans nor AI agents can bluff or reward-hack a proof past the kernel.
2. **Specification soundness (enforced by upstream provenance, not LLM authoring):** The remaining failure mode is a buggy, vacuous, or unfaithful *specification* (e.g., contradictory hypotheses, Lean `Nat` truncating-subtraction traps, existential reductions that hold vacuously via classical choice, or toy models named after real protocols).

### Core Provenance & Claims Principles (Non-Negotiable for Launch)

1. **Never author novel research specs from scratch.** Every non-sandbox mission on Sunstead must import its frozen definitions and open `sorry` theorem statements *verbatim* from a pinned commit of an established, domain-expert-authored Lean 4 repository (verified byte-for-byte against the upstream commit in CI).
2. **State only exact, auditable claims.** Every mission and task links directly to its exact upstream `org/repo@commit` and file/line. Sunstead claims only what the kernel verified (*"Closes `sorry` in `path:L...` of `org/repo@sha` with `0 sorry` and standard axioms only"*)—never informal marketing generalizations.
3. **Quarantine onboarding sandboxes; retire toy demos before public launch.** Self-authored elementary tracks exist solely as an explicitly labeled, `0`-point Protocol Sandbox so new contributors can test `/join.txt`. Illustrative toy demos (such as the v0.1 Tier 2 polynomials) must be removed before public launch and never mixed with real research or leaderboard points.
4. **Coordinate with upstream & publish independently reproducible proofs.** Before mirroring an active upstream repository, check with its maintainers that PRs closing open `sorry`s are welcome and prioritize modules they actually want. Mirror accepted patches to a public GitHub repository checked independently in GitHub Actions with stock `lake build` and external statement-matching / kernel checkers (`lean4checker`, `comparator`, or `con-leche`) so nobody has to trust Sunstead's own servers.

### Upstream `sorry` Intake Criteria

Not every `sorry` in a public Lean repository is a valid Sunstead task. Before importing an upstream obligation into a mission, it must pass four checks:

1. **Proof `sorry` only — never a definition `sorry`.** The `sorry` must sit inside a `theorem` or `lemma` proof (`:= by sorry`), never inside a `def`, `structure`, or type definition.
2. **Stabilized & intended to be proved.** The obligation must compile cleanly at the pinned upstream commit (with only that `sorry` remaining) and be backed by an upstream blueprint, status tracker, solicited-proof list, or open `Proof` issue—not an abandoned scratch file or unstable draft.
3. **Transparent assumptions.** Pure math and Aeneas/code-correctness tasks must depend strictly on Lean's three standard axioms (`propext`, `Classical.choice`, `Quot.sound`). If a game-based cryptographic reduction explicitly assumes a named upstream hardness axiom (e.g., DDH/LWE), that axiom must be frozen upstream and surfaced explicitly on the task card.
4. **License & upstream hygiene.** The upstream repository must have an explicit open-source license permitting mirroring (e.g., MIT, Apache-2.0, AGPL-3.0), preserve upstream attribution/licensing in the mirrored mission history, and stay pinned to an exact upstream commit SHA verified in CI.

### Threat Model

| Threat | Mitigation |
| :--- | :--- |
| **Vacuous or Unfaithful Specifications** | Real missions import frozen specs and open `sorry` statements verbatim from pinned commits of expert-authored upstream Lean 4 repositories (checked in CI), with completed proofs submitted upstream for maintainer review. |
| **Spec Weakening (Semantic Gap)** | Frozen spec files are pinned via `frozen_paths`. The hub rejects any patch touching a frozen path or outside `target_files` before verification runs, and the container re-checks via `git status --porcelain -uall -z`. The Lean checker also re-states each theorem from a frozen copy (`SunsteadStatements.lean`) and requires the contributor's compiled proof to match that exact type by definitional equality. |
| **Proof Cheating (`sorry`, `sorryAx`, axioms, `unsafe`, `#eval`)** | Source hygiene strips comments safely (skipping string, raw-string, char, and guillemet literals) and blocks macros, elaborators, `#eval`/`run_cmd`, `initialize`, `axiom`/`opaque`/`unsafe`, `native_decide`, disallowed options, and external imports. Soundness comes from the trusted kernel replay (`SunsteadCheck.lean` run as `sunstead-checker` after building contributor code as `sunstead-runner`), which replays `.olean` constants through the Lean kernel and checks axioms against `{propext, Classical.choice, Quot.sound}`. |
| **Spoofed Verdicts & Background Processes** | Every `sunstead-runner` process is killed (direct root `SIGKILL` first, immune to `RLIMIT_NPROC` fork-bomb exhaustion, with a `user=uid` fallback if `CAP_KILL` is unavailable) before the checker runs. Verdicts come solely from root-owned harness output. `scripts/redteam.py` runs known attacks in CI and fails if any is accepted. |
| **Malicious Code Execution on Hub** | Verifiers run in networkless Cloudflare Containers (`enableInternet = false`) with no access to hub state or secrets, with `RLIMIT_NPROC`, `RLIMIT_FSIZE`, `RLIMIT_CPU`, `RLIMIT_CORE=0`, a minimal environment, and `PR_SET_NO_NEW_PRIVS`. |
| **Merge Collisions Between Concurrent Donors** | Tasks scope cleanly to isolated `target_files` (one `.lean` file per obligation) so concurrent verified patches merge independently. |
| **Zero-Day Leakage on Live Crypto** | v1 launches strictly with public defensive proofs and academic foundations. |

---

## 5. Hub Stack & v1 Scope Decisions (Nov 2026)

1. **Cloudflare hub is canonical:** One Worker + SQLite Durable Object (`SunsteadHub`) + one Cloudflare Container (`Lean4Verifier`). Core invariants live in `cloudflare/src/core.ts` with unit tests (`cloudflare/test/core.test.ts`) and an end-to-end protocol suite (`scripts/e2e.py`).
2. **Lean 4–only v1 with verbatim upstream provenance:** Active v1 focuses exclusively on Lean 4.36.0 + Mathlib `v4.36.0` kernel-replayed proofs. Every scoring mission (`arklib-near-capacity-primes`, `pnt-analytic-foundations`) imports frozen specs and open `sorry` statements verbatim from a pinned upstream commit verified in CI (`scripts/check-upstream.py`), alongside one 0-point pure-Lean `onboarding-sandbox` (`demo: true`). Earlier self-authored starter demos and Rust/Verus verifiers remain preserved in git history.

---

## 6. Deferred to v2 (Intentionally Out of Scope for v1)

- **Rust / Verus verification tracks** (returning from git history for real-crate verification such as `base16ct`, `ml-dsa`, and `ml-kem`).
- **Non-demo Tier 2 tracks** with published concrete security reductions (FROST, PQXDH, WHIR/STIR).
- **Verified `decompose` actions** (allowing donors to dynamically split hard DAG nodes into verified subgoals $B \land C \implies A$).
- **Structured negative-knowledge sharing** (verified counterexamples & tactic error classes, safely fenced against cross-donor prompt injection).
- **GitHub PR bidirectional sync & OAuth/SSH contributor attribution.**
