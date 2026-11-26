# ZK STARK/SNARK Prime Field Addition Chains (Plonky3: Goldilocks, BabyBear, KoalaBear, Mersenne31, BN254)

Ten pure Lean 4.36.0 (zero Mathlib) kernel-verified shortest addition-chain hill-climb tracks for Plonky3's five production ZK prime fields — Goldilocks (2^64-2^32+1), BabyBear (2^31-2^27+1), KoalaBear (2^31-2^24+1), Mersenne31 (2^31-1), and BN254 — covering both Fermat field inversions (`p-2`) and Rescue/Poseidon inverse S-box roots (`1/7`, `1/3`, `1/5` mod `p-1`) where Plonky3's own `exponentiation.rs` invites shorter chains. Pinned verbatim to `Plonky3/Plonky3@0d803737b6` (Apache-2.0).

## Provenance
- Upstream: [`Plonky3/Plonky3@0d803737b6`](https://github.com/Plonky3/Plonky3/tree/0d803737b681774186cd283b1fd2d8e493655c82) (`Apache-2.0`)
- Formal specification: [`ZkAddChain/Spec.lean`](ZkAddChain/Spec.lean) (pure Lean 4.36.0, zero Mathlib, proving `evalPow_eq_powSucc` for any associative multiplication).

## Tracks

| Task ID | Exponent | Seed Length | Known Frontier | Target File |
| :--- | :--- | ---: | ---: | :--- |
| `goldilocks_inv` | Goldilocks p-2 | `125` | `72` | `ZkAddChain/ChainGoldilocksInv.lean` |
| `goldilocks_inv_d7` | Goldilocks 1/7 (x^10540996611094048183) | `89` | `71` | `ZkAddChain/ChainGoldilocksInvD7.lean` |
| `babybear_inv` | BabyBear p-2 | `59` | `38` | `ZkAddChain/ChainBabyBearInv.lean` |
| `babybear_inv_d7` | BabyBear 1/7 (x^1725656503) | `50` | `37` | `ZkAddChain/ChainBabyBearInvD7.lean` |
| `koalabear_inv` | KoalaBear p-2 | `59` | `38` | `ZkAddChain/ChainKoalaBearInv.lean` |
| `koalabear_inv_d3` | KoalaBear 1/3 (x^1420470955) | `45` | `36` | `ZkAddChain/ChainKoalaBearInvD3.lean` |
| `mersenne31_inv` | Mersenne31 p-2 | `59` | `37` | `ZkAddChain/ChainMersenne31Inv.lean` |
| `mersenne31_inv_d5` | Mersenne31 1/5 (x^1717986917) | `45` | `37` | `ZkAddChain/ChainMersenne31InvD5.lean` |
| `bn254_inv` | BN254 Field p-2 | `325` | `295` | `ZkAddChain/ChainBn254Inv.lean` |
| `bn254_inv_d5` | BN254 Rescue/Poseidon 1/5 | `328` | `295` | `ZkAddChain/ChainBn254InvD5.lean` |
