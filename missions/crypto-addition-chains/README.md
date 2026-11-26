# Cryptographic Elliptic-Curve Addition Chains (20 Production Curves)

Twenty pure Lean 4.36.0 (zero Mathlib) kernel-verified shortest addition-chain hill-climb tracks for real production elliptic-curve field and scalar inversion exponents (Curve25519, NIST P-256/P-384/P-224/P-192, secp256k1/secp224k1/secp192k1, Ed448-Goldilocks, Curve41417, M-221/E-222/Curve1174/E-382/M-383/M-511), pinned verbatim to `mmcloughlin/addchain@6c4dbba3ac` (BSD-3-Clause). Every track starts from a clean 4-bit windowed baseline strictly above published `addchain` / Brian Smith frontiers.

## Provenance
- Upstream: [`mmcloughlin/addchain@6c4dbba3ac`](https://github.com/mmcloughlin/addchain/tree/6c4dbba3acc1bf0269d4a90bb9cdfdf865017601) (`BSD-3-Clause`)
- Formal specification: [`AddChain/Spec.lean`](AddChain/Spec.lean) (pure Lean 4.36.0, zero Mathlib, proving `evalPow_eq_powSucc` for any associative multiplication).

## Tracks

| Task ID | Exponent | Seed Length | Known Frontier | Target File |
| :--- | :--- | ---: | ---: | :--- |
| `curve25519_field_inv` | Curve25519 Field p-2 | `329` | `265` | `AddChain/ChainCurve25519Field.lean` |
| `curve25519_scalar_inv` | Curve25519 Scalar l-2 | `298` | `283` | `AddChain/ChainCurve25519Scalar.lean` |
| `p256_field_inv` | NIST P-256 Field p-2 | `298` | `267` | `AddChain/ChainP256Field.lean` |
| `p256_scalar_inv` | NIST P-256 Scalar n-2 | `321` | `292` | `AddChain/ChainP256Scalar.lean` |
| `p384_field_inv` | NIST P-384 Field p-2 | `473` | `397` | `AddChain/ChainP384Field.lean` |
| `p384_scalar_inv` | NIST P-384 Scalar n-2 | `487` | `433` | `AddChain/ChainP384Scalar.lean` |
| `secp256k1_field_inv` | secp256k1 Field p-2 | `329` | `270` | `AddChain/ChainSecp256k1Field.lean` |
| `secp256k1_scalar_inv` | secp256k1 Scalar n-2 | `327` | `290` | `AddChain/ChainSecp256k1Scalar.lean` |
| `goldilocks_ed448_inv` | Ed448-Goldilocks Field p-2 | `569` | `460` | `AddChain/ChainGoldilocksEd448.lean` |
| `p224_field_inv` | NIST P-224 Field p-2 | `289` | `234` | `AddChain/ChainP224Field.lean` |
| `p192_field_inv` | NIST P-192 Field p-2 | `249` | `203` | `AddChain/ChainP192Field.lean` |
| `secp192k1_field_inv` | secp192k1 Field p-2 | `249` | `205` | `AddChain/ChainSecp192k1Field.lean` |
| `secp224k1_field_inv` | secp224k1 Field p-2 | `289` | `238` | `AddChain/ChainSecp224k1Field.lean` |
| `p2213_field_inv` | M-221 Field p-2 | `289` | `231` | `AddChain/ChainP2213Field.lean` |
| `p222117_field_inv` | E-222 Field p-2 | `289` | `233` | `AddChain/ChainP222117Field.lean` |
| `p2519_field_inv` | Curve1174 Field p-2 | `324` | `263` | `AddChain/ChainP2519Field.lean` |
| `p382105_field_inv` | E-382 Field p-2 | `489` | `395` | `AddChain/ChainP382105Field.lean` |
| `p383187_field_inv` | M-383 Field p-2 | `489` | `396` | `AddChain/ChainP383187Field.lean` |
| `p41417_field_inv` | Curve41417 Field p-2 | `529` | `426` | `AddChain/ChainP41417Field.lean` |
| `p511187_field_inv` | M-511 Field p-2 | `649` | `525` | `AddChain/ChainP511187Field.lean` |
