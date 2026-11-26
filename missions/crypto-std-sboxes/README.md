# ISO/RFC 8-Bit S-box Circuits (Whirlpool, ARIA S2 & InvS2): Total Gates, AND Gates & AND-Depth

Nine pure Lean 4.36.0 (zero Mathlib) certified Boolean-circuit hill-climb tracks minimizing total gates, multiplicative complexity (AND gates), and multiplicative depth (AND-depth for masked/MPC/FHE implementations) for Whirlpool (ISO/IEC 10118-3) and ARIA S2 / InvS2 (RFC 5794 / ISO 18033-3), pinned verbatim to `openssl/openssl@d94024ff` (Apache-2.0).

## Provenance
- Upstream: [`openssl/openssl@d94024ffc7`](https://github.com/openssl/openssl/tree/d94024ffc7e726566a6255228ad0a7de4cfc956d) (`Apache-2.0`)
- Formal specification: [`StdSbox/Spec.lean`](StdSbox/Spec.lean) (pure Lean 4.36.0, zero Mathlib, universal bit-sliced `BitVec (2^w)` soundness theorem).

## Tracks

| Task ID | Cipher S-box | Metric | Seed | Literature Frontier | Target File |
| :--- | :--- | :--- | ---: | ---: | :--- |
| `whirlpool_total_gates` | Whirlpool (8-bit) | `total` | `202` | `~100-120` | `StdSbox/WhirlpoolTotalCircuit.lean` |
| `whirlpool_and_gates` | Whirlpool (8-bit) | `and` | `50` | `~28-34` | `StdSbox/WhirlpoolAndCircuit.lean` |
| `whirlpool_and_depth` | Whirlpool (8-bit) | `and_depth` | `6` | `3-4` | `StdSbox/WhirlpoolDepthCircuit.lean` |
| `aria_s2_total_gates` | ARIA S2 (8-bit) | `total` | `292` | `~113-120` | `StdSbox/AriaS2TotalCircuit.lean` |
| `aria_s2_and_gates` | ARIA S2 (8-bit) | `and` | `45` | `32-34` | `StdSbox/AriaS2AndCircuit.lean` |
| `aria_s2_and_depth` | ARIA S2 (8-bit) | `and_depth` | `6` | `3-4` | `StdSbox/AriaS2DepthCircuit.lean` |
| `aria_invs2_total_gates` | ARIA InvS2 (8-bit) | `total` | `285` | `~113-120` | `StdSbox/AriaInvS2TotalCircuit.lean` |
| `aria_invs2_and_gates` | ARIA InvS2 (8-bit) | `and` | `45` | `32-34` | `StdSbox/AriaInvS2AndCircuit.lean` |
| `aria_invs2_and_depth` | ARIA InvS2 (8-bit) | `and_depth` | `6` | `3-4` | `StdSbox/AriaInvS2DepthCircuit.lean` |
