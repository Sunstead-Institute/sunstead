# Verus mission: RustCrypto base16ct 1.0.0

Machine-checked proofs about the real code of
[`base16ct`](https://crates.io/crates/base16ct), RustCrypto's constant-time
hex encoder/decoder (a dependency of `elliptic-curve`, among others). Its
nibble routines avoid branches and table lookups by computing with sign masks,
e.g. `(((0x2f - b) & (b - 0x3a)) >> 8) & (b - 47)`; the claim that they accept
exactly the hex alphabet, and that `decode_inner` flags every bad input, is
what these tasks prove.

## Layout

| Path | What | Frozen |
| :--- | :--- | :--- |
| `upstream/base16ct-1.0.0/` | The published crate source, checksum-verified | yes |
| `src/spec.rs` | Specification (hex alphabet, values) | yes |
| `statements/<module>.rs` | Each task: upstream function(s) + Verus `ensures`, no proof | yes |
| `src/<module>.rs` | Your proof: the statement plus proof code | **your target file** |

## Rules (enforced by `./verify`)

1. After removing your proof code, `src/<module>.rs` must be token-for-token
   identical to `statements/<module>.rs`. Proof code is: `proof { ... }` blocks,
   `assert ...;` and `let ghost ...;` statements in function bodies, new
   `proof fn lemma_*` / `spec fn aux_*` items, and the body of a `proof fn` the
   statement declares.
2. Each statement's executable function must equal the upstream function of the
   same name, token for token (comments and `pub` aside).
3. No `assume`, `admit`, `external_body`/`external`, macros, `cfg`, `unsafe`,
   string literals or non-ASCII in proof code. Allowed attributes: `trigger`,
   `auto`, `verifier::rlimit`, `verifier::spinoff_prover`, `verifier::nonlinear`,
   `verifier::loop_isolation`, `verifier::opaque`.
4. `verus src/lib.rs --crate-type=lib --verify-module <module> --no-cheating`
   reports 0 errors and at least as many verified functions as the statement has.

Run it locally:

    docker build --platform linux/amd64 -t sunstead/verifier-verus:v0.1 \
        -f missions/verifier-verus/Dockerfile missions
    CID=$(docker create --platform linux/amd64 --network=none -w /work \
        sunstead/verifier-verus:v0.1 ./verify lower_decode_nibble)
    docker cp . "$CID:/work" && docker start -a "$CID"; docker rm -f "$CID"

## What is not covered (yet)

- The slice-level `encode`/`decode` functions use iterator adaptors
  (`chunks_exact`, `zip`) that Verus cannot verify as written. Tasks
  `decode_pair_flags` and `mixed_pair_correct` cover the per-pair logic of
  `decode_inner` instead.
- Constant-time behaviour is not a Verus property; it is argued from the code
  having no branches or secret-indexed memory accesses, not proven.
