# Repo-Snapshot + Multi-Toolchain Lean 4 Verifier

> **Status:** Implemented (v1.1)
>
> **Scope:** Extending Sunstead's hermetic Lean 4 verifier from standalone Mathlib-only extractions (`v4.36.0`) to full-repository upstream snapshots across multiple pinned Lean 4 toolchains (`v4.36.0`, `v4.35.0`, `v4.31.0`, and future versions), while preserving every trust and provenance invariant in [docs/DESIGN.md](./DESIGN.md) Section 4.

---

## 1. Why Repo-Snapshot + Multi-Toolchain Verification?

Sunstead v1 proved the kernel-replay model on standalone Mathlib `v4.36.0` extractions (`arklib-near-capacity-primes`, `pnt-analytic-foundations`), where a curator manually copies frozen definitions into `<Lib>/Spec.lean` and re-states each open `sorry` theorem inside `./verify`.

That model hits two hard limits across active Lean 4 cryptography, optimization, and mathematics repositories:

1. **Deep project-local import graphs:** Real verification codebases (`leanprover/LNSym`, `Verified-zkEVM/ArkLib`, `Beneficial-AI-Foundation/curve25519-dalek-lean-verify`, `ImperialCollegeLondon/FLT`, `Sphere-Packing-Lean`) import dozens to hundreds of project-local ISA semantics, tactic, memory-model, and algebra modules. Hand-extracting standalone specs is infeasible and risks subtle statement drift.
2. **Toolchain diversity:** Active upstream repositories are spread across multiple Lean 4 releases (`v4.36.0`, `v4.35.0`, `v4.31.0`, `v4.37.0-rc1`, etc.) rather than moving in lockstep to a single version.

**Repo-Snapshot mode** solves both: the pinned upstream commit itself *is* the frozen specification, its upstream dependency `.olean`s are prebuilt read-only at image-build time under the repository's own `lean-toolchain`, and accepted patches apply directly upstream with `git apply`.

---

## 2. Repo-Snapshot Mission Format

A repo-snapshot mission lives under `missions/<mission-id>/` and stays lightweight in the Sunstead git repository (only the mission metadata, verbatim upstream `lean-toolchain`, verbatim upstream target `.lean` file(s), and frozen `./verify` script—never vendoring tens of megabytes of upstream dependencies into git).

### Directory Layout

```text
missions/lnsym-aes-gcm-armv8/
├── sunstead.json                           # Mission manifest with `snapshot` + `verifier.toolchain`
├── UPSTREAM.json                           # Pinned 40-char SHA + `exact_sha256` checks
├── lean-toolchain                          # Verbatim upstream toolchain (e.g. leanprover/lean4:v4.35.0)
├── verify                                  # Frozen script calling `lean_repo_snapshot_verify`
└── Proofs/AES-GCM/AESGCMEncKernelSym.lean  # Verbatim upstream target file(s) at original path
```

### Manifest Schema Extensions (`sunstead.json`)

```json
{
  "id": "lnsym-aes-gcm-armv8",
  "tier": 1,
  "mode": "dag",
  "upstream": {
    "repo": "leanprover/LNSym",
    "commit": "49f8a1d9e46f8dcfc345f4bc15d35b0ba845ff5c",
    "license": "Apache-2.0"
  },
  "snapshot": {
    "mode": "repo-snapshot",
    "snapshot_id": "lnsym-aes-gcm-armv8",
    "lean_options": ["linter.unusedSimpArgs=false"],
    "allowed_import_prefixes": ["Arm", "Correctness", "Specs", "Tactics", "Proofs", "Tests", "Std", "Init"]
  },
  "frozen_paths": ["UPSTREAM.json", "lean-toolchain", "verify", "sunstead.json"],
  "verifier": {
    "image": "sunstead/verifier-lean4-v4.35.0:v0.1",
    "toolchain": "leanprover/lean4:v4.35.0",
    "command": ["./verify"],
    "timeout_sec": 240,
    "memory_mb": 4096
  },
  "tasks": [
    {
      "id": "aes_gcm_enc_kernel_run_139",
      "title": "...",
      "target_files": ["Proofs/AES-GCM/AESGCMEncKernelSym.lean"],
      "depends_on": [],
      "upstream_url": "https://github.com/leanprover/LNSym/blob/49f8a1d9e46f8dcfc345f4bc15d35b0ba845ff5c/Proofs/AES-GCM/AESGCMEncKernelSym.lean#L22-L52"
    }
  ]
}
```

### Verbatim Provenance (`UPSTREAM.json` + `scripts/check-upstream.py`)

Every repo-snapshot mission sets `"mode": "repo-snapshot"` in `UPSTREAM.json` and lists `exact_sha256` checks for `lean-toolchain` and every target `.lean` file. `scripts/check-upstream.py` fetches each file from `https://raw.githubusercontent.com/<repo>/<40-char-commit>/<path>` and verifies **byte-for-byte equality** and exact SHA-256 agreement with the local mission file.

---

## 3. Build-Time Prebuilt Snapshot Layout

At container image build time, `missions/verifier-common/prebuild_snapshot.py`:

1. Shallow-fetches the upstream repository at the exact pinned 40-char commit SHA (`git fetch --depth=1 origin <sha>` and asserts `HEAD == <sha>`).
2. Verifies `lean-toolchain` and every target `.lean` file match the mission directory byte-for-byte.
3. Computes the minimal transitive local dependency closure of the mission's target module(s) (e.g. the 80 modules needed by `Proofs.«AES-GCM».AESGCMEncKernelSym` in `LNSym`, skipping unrelated tests, docs, and unused packages like `ELFSage` / `doc-gen4`).
4. Compiles all dependency modules in parallel topological waves into read-only `/opt/sunstead/snapshots/<snapshot_id>/deps/`.
5. Compiles the unmodified pinned upstream target module(s) into a **separate** read-only directory `/opt/sunstead/snapshots/<snapshot_id>/frozen-targets/`.
6. Writes `manifest.json` recording SHA-256 hashes of every frozen upstream dependency `.lean` file, every dependency `.olean`, and every frozen target `.olean`, then deletes the temporary upstream checkout and marks `/opt/sunstead` read-only (`a-w,a+rX`).

```text
/opt/sunstead/snapshots/<snapshot_id>/
├── manifest.json            # Pinned repo, commit SHA, target_files, SHA-256 hashes
├── deps/                    # Prebuilt read-only .olean tree for upstream dependencies ONLY
└── frozen-targets/          # Prebuilt read-only .olean of unmodified pinned target module(s)
                             # (NEVER placed on LEAN_PATH; read ONLY by sunstead-check)
```

Separating `deps/` from `frozen-targets/` guarantees `sunstead-runner` can never import the `sorry`-bearing pinned target `.olean`, while `sunstead-checker` can read its exact kernel type directly via `Lean.readModuleData`.

---

## 4. Security & Kernel Verification Invariants

Repo-snapshot verification preserves the full three-principal trust boundary (`root` orchestrator → `sunstead-runner` UID 10002 → `sunstead-checker` UID 10003) and enforces six layered defenses:

1. **Hub & Container Path Policy:** `cloudflare/src/core.ts` (`validatePatch`) and `verifier_server.py` (`git status --porcelain -uall -z`) reject any patch touching `frozen_paths` or anything outside the task's `target_files`.
2. **Workspace Hygiene & Sibling Tampering Rejection (`sunstead_sandbox.py`):**
   - Rejects any pre-existing `.olean`, `.olean.private`, `.ilean`, or `.c` artifact in `/work` (defeating forged `.olean` injection).
   - Rejects any non-target `.lean` file in `/work` that is not an exact SHA-256 match for the pinned snapshot (defeating sibling-module tampering even when running `./verify` directly outside `verifier_server.py`).
   - Runs comment/string-aware `lint_lean_file` on every target file (blocking `module`, macros/elaborators/syntax/notation, `initialize`, `#eval`/`run_cmd`/`#reduce`, `axiom`/`opaque`/`unsafe`/`extern`/`implemented_by`, `native_decide`, `sorry`, disallowed `set_option`, and imports outside `allowed_import_prefixes`—specifically blocking `import Lean`).
3. **Minimal Writable Runner Workspace:** Only `target_files` are copied into `sunstead-runner`'s isolated scratch directory. All upstream dependencies live root-owned read-only in `/opt/sunstead/snapshots/<snapshot_id>/deps/`. `sunstead-runner` runs under `RLIMIT_NPROC`, `RLIMIT_FSIZE`, `RLIMIT_CPU`, `RLIMIT_CORE=0`, clean env, and `PR_SET_NO_NEW_PRIVS`. Every `sunstead-runner` process is terminated (`SIGKILL`) before `sunstead-checker` runs.
4. **Zero Elaboration, Zero Extensions (`SunsteadCheck.lean`):**
   - Compiled to a per-toolchain native binary `/opt/sunstead/sunstead-check` (`lean -c` + `leanc -O2`).
   - Loads trusted dependency `.olean`s with explicit `Lean.importModules ... (loadExts := false)` so zero environment extensions, `initialize` hooks, macros, or `elab_rules` execute during checking.
   - Only modules in the explicit `untrusted-modules=` allowlist are read from `untrusted-lib`; every sibling or dependency module is loaded strictly from root-owned `trusted-lib`. Any forged sibling `.olean` placed in `untrusted-lib` is ignored, and redefining any trusted constant is rejected.
   - Rejects Lean 4 `module` files (`mod.isModule == true`) and `.olean.private` files.
5. **Pinned Kernel Type + Local `FrozenTypeDeps(M, T)` Lock:**
   - Because upstream target files often define local `abbrev` or `def` helpers right above the open theorem (e.g. `abbrev rounds_addr` and `abbrev in_addr` in `LNSym/Proofs/AES-GCM/AESGCMEncKernelSym.lean`), checking only the theorem name is insufficient—a malicious contributor could edit `rounds_addr` inside the writable target file to make a hypothesis vacuously `False`.
   - `sunstead-check` reads `frozen-targets/<TargetMod>.olean` via `readModuleData`, extracts `frozenTargetCI` (requiring it to be `ConstantInfo.thmInfo`), and computes `FrozenTypeDeps(M, T)`: the transitive closure of every constant defined inside `M` referenced by `frozenTargetCI.type` (types, definition bodies, inductives, constructors, recursors).
   - After replaying the contributor's `.olean` through `Kernel.Environment.replay`, `sunstead-check` verifies that **every constant `c ∈ FrozenTypeDeps(M, T)` in the contributor's module is structurally identical** (`name`, `levelParams`, `type`, `value`, `safety` / inductive layout, never `axiomInfo` or `opaqueInfo`) to the pinned upstream `.olean`.
   - Finally, `sunstead-check` requires `targetConst` to be `ConstantInfo.thmInfo`, asks the Lean kernel to accept `Declaration.thmDecl` proving `frozenTargetCI.type` from `targetConst`, and checks `collectAxioms _sunstead_check ⊆ {propext, Classical.choice, Quot.sound}` (`0 sorryAx`).

### Note on Lean 4.36 `module` System Repositories (e.g. `ArkLib`)

`Verified-zkEVM/ArkLib` currently sets `requiresModuleSystem = true` in `lakefile.toml`, causing Lean 4.36 to split private proof terms into `.olean.private` files. Under our current strict zero-`.olean.private` invariant, classic Lean 4 repositories (`LNSym`, `curve25519-dalek-lean-verify`, `PrimeNumberTheoremAnd`, `FLT`, `Sphere-Packing-Lean`) work immediately. Safely admitting `requiresModuleSystem = true` repo snapshots is a straightforward follow-up: `SunsteadCheck` would opt-in to reading both `.olean` and `.olean.private` for the target module, merging all public and private constants into the `Kernel.Environment.replay` map before verifying `Declaration.thmDecl` and `collectAxioms`.

---

## 5. Multi-Toolchain Container Routing

Each Lean toolchain runs in its own digest-pinned, networkless (`enableInternet = false`) Cloudflare Container with its own per-toolchain compiled `/opt/sunstead/sunstead-check` binary and prebuilt snapshot caches:

| `verifier_kind` | `verifier.toolchain` | Local / Hub Image | Cloudflare DO Binding | Target Upstream Repos |
| :--- | :--- | :--- | :--- | :--- |
| `lean4` (default) | `leanprover/lean4:v4.36.0` | `sunstead/verifier-lean4:v0.2` (`cloudflare/containers/lean4/Dockerfile`) | `LEAN4_VERIFIER` (`Lean4Verifier`) | `PrimeNumberTheoremAnd`, `ArkLib` (standalone), `onboarding-sandbox`, `v4.36.0` Mathlib snapshots |
| `lean4-v4.35.0` | `leanprover/lean4:v4.35.0` | `sunstead/verifier-lean4-v4.35.0:v0.1` (`cloudflare/containers/lean4-v4.35.0/Dockerfile`) | `LEAN4_V435_VERIFIER` (`Lean4V435Verifier`) | `leanprover/LNSym` (pure Lean, zero Mathlib), plus `v4.35.0` snapshots (`Clean`, `FLT` once Mathlib `v4.35.0` layer is added) |
| `lean4-v4.31.0` | `leanprover/lean4:v4.31.0` | `sunstead/verifier-lean4-v4.31.0:v0.1` (`cloudflare/containers/lean4-v4.31.0/Dockerfile`) | `LEAN4_V431_VERIFIER` (`Lean4V431Verifier`) | `Beneficial-AI-Foundation/curve25519-dalek-lean-verify` (`aeneas` + `PrimeCert` + Mathlib `v4.31.0`) |

### Routing Flow

1. `sunstead.json` declares `verifier.image` and `verifier.toolchain`.
2. `resolveVerifierKind(verifier)` in `cloudflare/src/core.ts` deterministically maps the toolchain/image to a `VerifierKind` (failing closed on unknown toolchains).
3. `cloudflare/scripts/sync-assets.mjs` embeds `verifier_kind` into `src/generated/missions.ts`.
4. `SunsteadHub.getVerifierStub(mission)` routes requests to the matching Durable Object namespace (`LEAN4_VERIFIER`, `LEAN4_V435_VERIFIER`, or `LEAN4_V431_VERIFIER`), keyed by `verifier_kind:image:mission_id`.
5. `cloudflare/scripts/deploy.mjs` hashes all verifier Dockerfiles and their `COPY` sources together and supports digest-pinned Worker-only reuse for every container app (`SUNSTEAD_VERIFIER_IMAGE`, `SUNSTEAD_VERIFIER_V435_IMAGE`, `SUNSTEAD_VERIFIER_V431_IMAGE`).

---

## 6. Red-Team Attack Matrix (`scripts/redteam.py`)

| Attack | Target | Expected | Enforcing Layer |
| :--- | :--- | :--- | :--- |
| Honest repo-snapshot proof | `__synthetic_repo_snapshot__` | **Accept** | Full `sunstead-runner` → `sunstead-checker` replay |
| Plain `sorry` / unproved seed | Synthetic & `lnsym-aes-gcm-armv8` | **Reject** | Source lint + kernel `sorryAx` check |
| `sorryAx _ false` bypass | Synthetic & `lnsym-aes-gcm-armv8` | **Reject** | Kernel `collectAxioms` (`stage=axioms`) |
| Weakened theorem statement (`: True`) | Synthetic & `lnsym-aes-gcm-armv8` | **Reject** | Kernel `Declaration.thmDecl` vs `frozen-target-olean` (`stage=kernel`) |
| Mutated local `abbrev`/`def` in target file | Synthetic & `lnsym-aes-gcm-armv8` | **Reject** | `FrozenTypeDeps(M, T)` structural equality (`stage=kernel`) |
| Tampered frozen sibling `.lean` module | Synthetic & `lnsym-aes-gcm-armv8` | **Reject** | Sandbox sibling SHA-256 check + root-owned `deps/` isolation |
| Forged `.olean` in workspace | Synthetic | **Reject** | Sandbox `.olean` rejection + `untrusted-modules` allowlist |
| `elab_rules` / `import Lean` spoofing | Synthetic & `lnsym-aes-gcm-armv8` | **Reject** | Source lint + `importModules (loadExts := false)` + `Kernel.Environment.replay` |
| Lean 4 `module` header / `.olean.private` | Synthetic | **Reject** | Source lint + `SunsteadCheck` `mod.isModule` & `.olean.private` rejection |
