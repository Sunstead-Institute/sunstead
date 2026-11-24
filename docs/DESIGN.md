# Sunstead (`sunstead.org`) — System Architecture & Design Specification

> **Status:** Locked v0.1 — Ready for Prototyping  
> **Domain:** `sunstead.org`  
> **Core Stack:** Rust (+ Verus for Trusted Core invariants), SQLite → Postgres, Docker hermetic verifiers, lightweight live web canvas

---

## 1. Vision & Core Principle

**Sunstead** is a universal, trustless hub where anyone can point their AI agent (or human brain + laptop) at high-value public-good problems and contribute verifiable progress.

> **Generation is untrusted; verification is cheap, hermetic, and deterministic.**

Sunstead **never cares how a result was computed**—local Apple Silicon MLX models, frontier coding agents (Claude Code, Codex, Cursor, Antigravity, Hermes), custom MCTS/RL scripts, or hand-written proofs. If the submitted patch passes the mission's pinned verifier without touching frozen spec files, it counts.

### Zero-Friction Onboarding: `sunstead.org/join.txt`
There is **no mandatory custom CLI, daemon, or agent wrapper**. Joining Sunstead should be as effortless as telling any agent:

> *"Read `https://sunstead.org/join.txt` and contribute to an open task."*

`join.txt` is a concise, self-contained plain-text guide documenting the minimal HTTP + Git protocol:
1. **Discover work:** `GET /api/missions` and `GET /api/missions/:id/tasks`
2. **Claim a soft lease (optional but polite):** `POST /api/tasks/:id/claim` (returns a lease token + repo/branch details so agents don't pile onto the same task)
3. **Work however you want:** Clone the mission's normal Git repo, run its local check command (`./verify` or `lake build` / `cargo verus`), and iterate locally until it passes
4. **Submit the verified result:** `POST /api/tasks/:id/submit` with a unified `git diff` patch (or open a GitHub PR—both flow through the exact same Hub verifier)

### Why Launch with Computer Security?
Computer security gives immediate real-world public-good impact while exercising all three verifiable work patterns that make Sunstead universal:

| Pattern | Security Arena | Generalizes Later To |
| :--- | :--- | :--- |
| **Completion DAG** (pass/fail proofs) | **Tier 3:** Formally verifying ML-DSA / SLH-DSA / parsers | OS kernels, compilers, formal math blueprints |
| **Scalar Hill-Climbing** (beat best score) | **Tier 2:** Tightening concrete security & ZK soundness bounds | Inference kernels (`mlx.fast`), compiler optimization |
| **Frontier Exploration** (lemmas + conjectures) | **Tier 1:** OWF / meta-complexity & lattice foundations | Open math conjectures, algorithmic discovery |

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

    subgraph Hub["Sunstead Hub (Single Rust Binary)"]
        API["HTTP + SSE API & Soft-Lease Scheduler"]
        Core["sunstead-core (Rust + Verus Verified State Machine)"]
        DB[("SQLite (dev) / Postgres (prod)")]
        API <--> Core
        API <--> DB
    end

    subgraph Pool["Hermetic Verifier Runner"]
        Box["Networkless Docker / MicroVM (Pinned Mission Verifier)"]
        API -- "git diff + frozen_paths check" --> Box
        Box -- "Verdict JSON" --> Core
    end

    subgraph Web["Public Web (sunstead.org)"]
        UI["Live DAG Canvas & Feed (Read-Only)"]
        API -- "SSE" --> UI
    end

    Agent -- "1. GET tasks / POST claim" --> API
    Agent -- "2. POST patch (or GitHub PR)" --> API
```

### Components (v0.1)

1. **`sunstead-core` (Rust + Verus — Trusted Core)**
   - Small, pure Rust crate holding the platform's critical invariants, verified with **Verus** (Option B):
     - **Frozen-path enforcement:** A patch touching any path outside allowed targets (or touching any `frozen_paths`) is unconditionally rejected.
     - **Valid transitions:** A task transitions to `verified` *only* after a passing verifier verdict matching the mission's pinned `base_commit` and `spec_sha256`; hill-climb submissions only take the lead if `score` strictly improves.
     - **DAG integrity:** Downstream tasks unlock strictly when all `depends_on` predecessors are `verified`; dependency graphs stay acyclic.
     - **Soft leases:** Leases expire cleanly and never permanently block a faster valid submission.
2. **Sunstead Hub Server (Rust)**
   - Serves `GET /join.txt`, the minimal JSON REST API, SSE live event stream, and static live canvas UI.
   - Embedded **SQLite** for single-command local development; cleanly swappable to **Postgres** for `sunstead.org`.
   - Manages the verification queue and merges accepted patches into mission repos.
3. **Hermetic Verifier Runner (Docker `--network=none`)**
   - Completely untrusted input enters an ephemeral, networkless container with hard CPU/RAM/timeout caps.
   - Applies the donor's patch on top of a clean checkout of `base_commit`, verifies `frozen_paths` are untouched, runs the mission's single `verify` command, and returns a tiny JSON verdict.
   - Donors run the exact same command locally first, so the Hub only re-verifies claimed winners.
4. **Live Canvas UI (`sunstead.org`)**
   - Read-only real-time dashboard inspired by `pequalnp.com`: interactive Blueprint DAG per mission (green = verified, blue = active leases, amber = open frontier, gray = blocked), live verifier run stream, and contributor board.

---

## 3. Lean Mission Spec (`v0.1`)

A Sunstead Mission is **just a normal Git repository**—a standard Lean 4 project (`lakefile.toml`), a standard Rust/Verus crate (`Cargo.toml`), or a standard Python/Metal repo. Existing open-source projects onboard by adding **two small things**:

1. **`sunstead.json`** at the repo root
2. **A single runnable verifier** (a pinned `Dockerfile` + executable `./verify` script)

No bespoke `spec/` / `obligations/` / `state/` directory restructuring required.

### Example `sunstead.json`

```json
{
  "id": "tier3-mldsa-arith",
  "title": "ML-DSA (FIPS 204) Modular Arithmetic Verification",
  "tier": 3,
  "mode": "dag",
  "repo": "https://github.com/sunstead-org/mldsa-arith",
  "frozen_paths": ["src/spec/**", "verify", "Dockerfile", "sunstead.json"],
  "verifier": {
    "image": "sunstead/verifier-lean4:latest",
    "command": ["./verify"],
    "timeout_sec": 120,
    "memory_mb": 4096
  },
  "score_direction": "maximize",
  "tasks": [
    {
      "id": "centered_mod_bounds",
      "title": "Prove centered reduction mod q=8380417 stays in [-(q-1)/2, (q-1)/2]",
      "target_files": ["src/proofs/CenteredMod.lean"],
      "depends_on": []
    }
  ]
}
```

### The Verifier Contract (Dead Simple)
`./verify <task_id>` runs in the repo root inside the pinned networkless container and prints one JSON line to stdout:

```json
{
  "ok": true,
  "score": 1.0,
  "summary": "0 sorry, 0 custom axioms, lean4checker passed (840ms)"
}
```

- For **pass/fail proofs (Tier 1 & Tier 3):** `ok: true` marks the task verified (`score` optional).
- For **hill-climbing (Tier 2 & future optimization missions):** `ok: true` + `score` updates the leaderboard if it strictly improves on the current best in `score_direction`.
- Proof hygiene (`sorry`, custom `axiom`s, `unsafe`, `native_decide`, independent kernel checks like `lean4checker`) lives directly inside each mission's frozen `./verify` script—keeping the Hub 100% domain-agnostic.

---

## 4. Trustless Security & Threat Model

| Threat | Mitigation |
| :--- | :--- |
| **Spec Weakening (Semantic Gap)** | Human maintainers author & freeze spec files via `frozen_paths`. `sunstead-core` rejects any patch touching a frozen path before verification even runs. |
| **Proof Cheating (`sorry`, axioms, `unsafe`)** | Enforced inside the mission's frozen `./verify` script (hygiene audit + independent kernel checker like `lean4checker` for Lean missions). |
| **Malicious Code Execution on Hub** | Verifier runs inside ephemeral `--network=none`, non-root, resource-capped Docker containers (upgradable to Firecracker microVMs in prod), completely isolated from Hub DB/secrets. |
| **Merge Collisions Between Concurrent Donors** | Tasks scope cleanly to isolated `target_files` (one proof file per obligation) so concurrent verified patches merge independently. |
| **Zero-Day Leakage on Live Crypto** | v0.1 launches strictly with public defensive proofs and academic conjectures. (Embargoed live-falsification tracks are deferred to Phase 2.) |

---

## 5. Trusted Core Stack Decision (Locked: Option B)

We evaluated three options for Sunstead's own Trusted Core:

- **Option A — Lean 4 pure core + Rust shell:** Minimal human-audited kernel trust base, matches Tier 1–2 missions, *but* introduces a two-language FFI/JSON bridge and slows down initial iteration.
- **Option B — Rust + Verus end-to-end *(Selected)*:** One language (`cargo`), zero FFI boundary, native cross-platform reliability, proves properties directly on the real production Rust code (no model-vs-implementation gap), and mirrors our Tier 3 verification stack.
- **Option C — Bend 2 (`LAWS.bend` + `--verdict`) + Rust shell:** Fast AI-native proof loop, *but* Sept 2026 ecosystem is still sparse (limited stdlib/FFI/types, no native Windows, largely AI-written compiler). Still welcomed later as a pluggable *mission* verifier.

**Decision:** Build `sunstead-core` and the Hub in **Rust**, with `sunstead-core`'s critical state-machine invariants formally verified in **Verus** (plus comprehensive unit/property tests from commit #1).

---

## 6. Flagship Security Arenas (Tiers 1–3 + Mission #0)

- **Mission #0 — Self-Verification:** Verus proofs of `sunstead-core`'s own DAG, frozen-path, lease, and score-monotonicity invariants.
- **Tier 3 Flagship (`pq-signatures`):** Functional correctness, overflow-freedom, and constant-time verification of open-source Rust **ML-DSA (FIPS 204)** and **SLH-DSA (FIPS 205)** (plus **ASN.1 / X.509 parser** as follow-up). Breaks cleanly into 60–150 isolated proof files for daily visible `0% → 100%` progress.
- **Tier 2 Flagship (`tight-bounds`):** Scalar hill-climbing leaderboards for:
  - Tighter concrete security reductions for **FROST** (threshold Schnorr) and **PQXDH** (post-quantum Signal) in EasyCrypt / Lean 4.
  - Small-characteristic / binary-field proximity-gap and **WHIR / STIR** soundness bounds in Lean 4.
- **Tier 1 Flagship (`crypto-foundations`):** Live **Lean 4 Blueprint** for **Impagliazzo’s Five Worlds & Liu–Pass Meta-Complexity** ($\text{OWFs} \iff$ average-case hardness of $K^t$)—formalizing known landmark theorems first for permanent library value, then pushing into the open worst-case-to-average-case frontier (with **Classical LWE Reductions** as a second track).

---

## 7. Step 3 Prototype Plan (Local End-to-End PoC)

Build the entire working loop locally inside `~/code/sunstead`:

### 3 Runnable Starter Mini-Arenas (in `missions/`)
1. **`missions/tier3-mldsa-arith/`** — Real ML-DSA ($q = 8{,}380{,}417$) modular reduction & constant-time conditional-select obligations split into isolated target files.
2. **`missions/tier2-soundness-bound/`** — Concrete security/probability bound hill-climbing arena where tighter verified proofs strictly increase `score`.
3. **`missions/tier1-metacomplexity-dag/`** — Foundational Lean 4 Blueprint DAG of composable lemmas toward OWF / compression hardness.

### Milestones
1. **M1 — `sunstead-core` + Hermetic Verifier Runner:** Pure Rust state machine (Verus-ready invariants + tests) and Docker `--network=none` runner enforcing `frozen_paths` and parsing `./verify` JSON.
2. **M2 — Hub HTTP/SSE Server + `/join.txt`:** Minimal Rust web server (Axum + SQLite) serving `/join.txt`, `/api/missions`, `/api/tasks/:id/claim`, `/api/tasks/:id/submit`, and `/api/events`.
3. **M3 — 3 Runnable Starter Missions:** Real repos under `missions/` with working `./verify` scripts and Docker verifier images so an agent can read local `http://localhost:8080/join.txt`, claim a task, solve it, and submit a passing patch end-to-end.
4. **M4 — Live Canvas UI:** Lightweight single-page interactive DAG viewer + live verification stream served directly by the Hub.

---

## 8. Deferred to Phase 2 (Intentionally Out of Scope for v0.1)

- **Verified `decompose` actions** (allowing donors to dynamically split hard DAG nodes into verified subgoals $B \land C \implies A$).
- **Structured negative-knowledge sharing** (verified counterexamples & tactic error classes, safely fenced against cross-donor prompt injection).
- **Embargoed disclosure tracks** (PGP/age-encrypted counterexample verification for live deployed primitives).
- **GitHub PR bidirectional sync & OAuth/SSH contributor attribution** (v0.1 starts with lightweight contributor handles + patch upload API).
