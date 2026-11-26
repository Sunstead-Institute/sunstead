# Lightweight Cipher S-box Circuits (SKINNY-128, Ascon, Keccak-χ, PRESENT, GIFT, Spongent, Saturnin, KNOT, Clyde, Pyjamask)

Sixteen pure Lean 4.36.0 (zero Mathlib) certified Boolean-circuit hill-climb tracks minimizing total gates, multiplicative complexity (AND gates), and multiplicative depth (AND-depth for masked/MPC/FHE implementations) across ten NIST Lightweight Cryptography, FIPS 202, and ISO 29192-2 cipher S-boxes, pinned verbatim to `rweather/lightweight-crypto@fa4ec9a021` (MIT).

## Provenance
- Upstream: [`rweather/lightweight-crypto@fa4ec9a021`](https://github.com/rweather/lightweight-crypto/tree/fa4ec9a021b9233263de77e7dd971de8c9761495) (`MIT`)
- Formal specification: [`LwcSbox/Spec.lean`](LwcSbox/Spec.lean) (pure Lean 4.36.0, zero Mathlib, universal bit-sliced `BitVec (2^w)` soundness theorem).

## Tracks

| Task ID | Cipher S-box | Metric | Seed | Literature Frontier | Target File |
| :--- | :--- | :--- | ---: | ---: | :--- |
| `skinny8_total_gates` | SKINNY-128 (8-bit) | `total` | `252` | `~24` | `LwcSbox/Skinny8TotalCircuit.lean` |
| `skinny8_and_gates` | SKINNY-128 (8-bit) | `and` | `96` | `8` | `LwcSbox/Skinny8AndCircuit.lean` |
| `skinny8_and_depth` | SKINNY-128 (8-bit) | `and_depth` | `5` | `3-4` | `LwcSbox/Skinny8DepthCircuit.lean` |
| `ascon_total_gates` | Ascon 5-bit (5-bit) | `total` | `46` | `~16-20` | `LwcSbox/AsconTotalCircuit.lean` |
| `ascon_and_gates` | Ascon 5-bit (5-bit) | `and` | `19` | `5` | `LwcSbox/AsconAndCircuit.lean` |
| `keccak_chi_total_gates` | Keccak-χ 5-bit (5-bit) | `total` | `20` | `15` | `LwcSbox/KeccakChiTotalCircuit.lean` |
| `present_total_gates` | PRESENT/PHOTON (4-bit) | `total` | `57` | `14` | `LwcSbox/PresentTotalCircuit.lean` |
| `present_and_gates` | PRESENT/PHOTON (4-bit) | `and` | `34` | `4` | `LwcSbox/PresentAndCircuit.lean` |
| `gift_total_gates` | GIFT-128 (4-bit) | `total` | `33` | `11-13` | `LwcSbox/GiftTotalCircuit.lean` |
| `gift_and_gates` | GIFT-128 (4-bit) | `and` | `18` | `4` | `LwcSbox/GiftAndCircuit.lean` |
| `spongent_total_gates` | Spongent/Elephant (4-bit) | `total` | `48` | `14-16` | `LwcSbox/SpongentTotalCircuit.lean` |
| `spongent_and_gates` | Spongent/Elephant (4-bit) | `and` | `28` | `4` | `LwcSbox/SpongentAndCircuit.lean` |
| `saturnin_total_gates` | Saturnin (4-bit) | `total` | `61` | `~15` | `LwcSbox/SaturninTotalCircuit.lean` |
| `knot_total_gates` | KNOT (4-bit) | `total` | `40` | `~14` | `LwcSbox/KnotTotalCircuit.lean` |
| `clyde_total_gates` | Clyde-128/Spook (4-bit) | `total` | `27` | `~12` | `LwcSbox/ClydeTotalCircuit.lean` |
| `pyjamask_total_gates` | Pyjamask-128 (4-bit) | `total` | `42` | `~14` | `LwcSbox/PyjamaskTotalCircuit.lean` |
