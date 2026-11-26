# Combinatorial Designs: Covering Arrays `CAN(t, k, v)` & Optimal Golomb Rulers `G(k)`

Minimize row count `N` in Covering Arrays `CA(N; t, k, v)` and ruler length `L` in `k`-mark Optimal Golomb Rulers `G(k)` across 14 classical open and benchmark frontiers, certified purely inside the Lean 4.36.0 kernel (zero Mathlib, standard axioms only).

## Tracks & Benchmarks

Anchored to [`huayaow/DPSO@e28d4f2`](https://github.com/huayaow/DPSO/tree/e28d4f2c4e2f989e5d9ff5f78c5214a3331fe2dc) (MIT, Wu, Nie, Kuo, Leung & C. J. Colbourn, *IEEE Trans. Evol. Comput.* 2015):

| Task ID | Problem | Editable File | Seed Score | Literature Frontier |
| :--- | :--- | :--- | :---: | :--- |
| `ca_2_15_3` | `CAN(2, 15, 3)` (min rows `N`) | `CombDesigns/CA_2_15_3.lean` | 20 | 15 (Colbourn table) |
| `ca_2_20_3` | `CAN(2, 20, 3)` (min rows `N`) | `CombDesigns/CA_2_20_3.lean` | 22 | 15 (Colbourn table) |
| `ca_2_15_4` | `CAN(2, 15, 4)` (min rows `N`) | `CombDesigns/CA_2_15_4.lean` | 34 | 24 (Colbourn table) |
| `ca_2_20_4` | `CAN(2, 20, 4)` (min rows `N`) | `CombDesigns/CA_2_20_4.lean` | 41 | 28 (Colbourn table) |
| `ca_3_12_2` | `CAN(3, 12, 2)` (min rows `N`) | `CombDesigns/CA_3_12_2.lean` | 23 | 15 (exact/Colbourn) |
| `ca_3_16_2` | `CAN(3, 16, 2)` (min rows `N`) | `CombDesigns/CA_3_16_2.lean` | 27 | 17 (Colbourn frontier) |
| `ca_3_20_2` | `CAN(3, 20, 2)` (min rows `N`) | `CombDesigns/CA_3_20_2.lean` | 29 | 18 (open Colbourn frontier) |
| `ca_3_10_3` | `CAN(3, 10, 3)` (min rows `N`) | `CombDesigns/CA_3_10_3.lean` | 77 | 45 (Colbourn frontier) |
| `golomb_k12` | Golomb Ruler `G(12)` (min length `L`) | `CombDesigns/Golomb12.lean` | 122 | 85 (exact OGR-12) |
| `golomb_k14` | Golomb Ruler `G(14)` (min length `L`) | `CombDesigns/Golomb14.lean` | 181 | 127 (exact OGR-14) |
| `golomb_k16` | Golomb Ruler `G(16)` (min length `L`) | `CombDesigns/Golomb16.lean` | 251 | 177 (exact OGR-16) |
| `golomb_k20` | Golomb Ruler `G(20)` (min length `L`) | `CombDesigns/Golomb20.lean` | 474 | 283 (exact OGR-20) |
| `golomb_k25` | Golomb Ruler `G(25)` (min length `L`) | `CombDesigns/Golomb25.lean` | 821 | 480 (exact OGR-25) |
| `golomb_k29` | Golomb Ruler `G(29)` (min length `L`) | `CombDesigns/Golomb29.lean` | 1158 | 620 (open research frontier OGR-29) |

## Formal Specification & Verification

`CombDesigns/Spec.lean` is frozen and proves end-to-end soundness with zero `sorry` and zero Mathlib:
1. `ValidCoveringArray2` & `ValidCoveringArray3`: bit-sliced column-mask evaluator (`checkCA2`, `checkCA3`) verifying all `N` rows per symbol tuple via bitwise `&&&` (`validCoveringArray2_of_check`, `validCoveringArray3_of_check`).
2. `ValidGolombRuler`: strict ordering, bound `≤ L`, and pairwise distinctness of all `C(k, 2)` positive differences (`validGolombRuler_of_check`).
