# Extended Matrix Multiplication Tensor Rank over F₂ (26 Open Shapes)

Pure Lean 4.36.0 (zero Mathlib) Tier 2 certified optimization Arena Pack covering **26 open `⟨n,m,p⟩` matrix multiplication shapes** over $\mathbb{F}_2$ (disjoint from `matrix-rank444-f2` and `matrix-rank-alphatensor-f2`).

## Provenance
- Upstream catalog & ternary/F₂ baselines: [`dronperminov/FastMatrixMultiplication@f70078cd9d`](https://github.com/dronperminov/FastMatrixMultiplication/tree/f70078cd9d1674cbc9c27e71011d4d6dff771d40) (MIT License)
- Specification: [`RankF2Ext/Spec.lean`](RankF2Ext/Spec.lean) formalizes `RankLE n m p r`, proves full bilinear matrix-multiplication correctness (`bilinear_of_rankLE`), and proves soundness of the bit-packed Brent-equation verifier `checkBrentF2` (`rankLE_of_checkBrentF2`) with zero Mathlib and standard axioms only.

## Tracks

| Task ID | Shape | Seed Rank (F₂) | Q Reference | Target File |
| :--- | :--- | ---: | ---: | :--- |
| `rank_2_4_5` | `⟨2,4,5⟩` | `34` | `32` | `RankF2Ext/Cert2x4x5.lean` |
| `rank_2_5_5` | `⟨2,5,5⟩` | `40` | `40` | `RankF2Ext/Cert2x5x5.lean` |
| `rank_2_5_6` | `⟨2,5,6⟩` | `47` | `47` | `RankF2Ext/Cert2x5x6.lean` |
| `rank_3_3_5` | `⟨3,3,5⟩` | `36` | `36` | `RankF2Ext/Cert3x3x5.lean` |
| `rank_3_3_6` | `⟨3,3,6⟩` | `42` | `40` | `RankF2Ext/Cert3x3x6.lean` |
| `rank_3_3_7` | `⟨3,3,7⟩` | `49` | `49` | `RankF2Ext/Cert3x3x7.lean` |
| `rank_3_3_8` | `⟨3,3,8⟩` | `56` | `55` | `RankF2Ext/Cert3x3x8.lean` |
| `rank_3_4_6` | `⟨3,4,6⟩` | `54` | `54` | `RankF2Ext/Cert3x4x6.lean` |
| `rank_3_4_7` | `⟨3,4,7⟩` | `64` | `63` | `RankF2Ext/Cert3x4x7.lean` |
| `rank_3_4_8` | `⟨3,4,8⟩` | `73` | `73` | `RankF2Ext/Cert3x4x8.lean` |
| `rank_3_5_6` | `⟨3,5,6⟩` | `68` | `68` | `RankF2Ext/Cert3x5x6.lean` |
| `rank_3_5_7` | `⟨3,5,7⟩` | `79` | `79` | `RankF2Ext/Cert3x5x7.lean` |
| `rank_3_5_8` | `⟨3,5,8⟩` | `90` | `90` | `RankF2Ext/Cert3x5x8.lean` |
| `rank_3_6_6` | `⟨3,6,6⟩` | `82` | `80` | `RankF2Ext/Cert3x6x6.lean` |
| `rank_3_6_7` | `⟨3,6,7⟩` | `96` | `94` | `RankF2Ext/Cert3x6x7.lean` |
| `rank_4_4_6` | `⟨4,4,6⟩` | `73` | `73` | `RankF2Ext/Cert4x4x6.lean` |
| `rank_4_4_7` | `⟨4,4,7⟩` | `85` | `85` | `RankF2Ext/Cert4x4x7.lean` |
| `rank_4_4_8` | `⟨4,4,8⟩` | `96` | `95` | `RankF2Ext/Cert4x4x8.lean` |
| `rank_4_5_5` | `⟨4,5,5⟩` | `76` | `76` | `RankF2Ext/Cert4x5x5.lean` |
| `rank_4_5_6` | `⟨4,5,6⟩` | `90` | `90` | `RankF2Ext/Cert4x5x6.lean` |
| `rank_4_5_7` | `⟨4,5,7⟩` | `104` | `104` | `RankF2Ext/Cert4x5x7.lean` |
| `rank_4_6_6` | `⟨4,6,6⟩` | `105` | `105` | `RankF2Ext/Cert4x6x6.lean` |
| `rank_5_5_5` | `⟨5,5,5⟩` | `93` | `93` | `RankF2Ext/Cert5x5x5.lean` |
| `rank_5_5_6` | `⟨5,5,6⟩` | `110` | `110` | `RankF2Ext/Cert5x5x6.lean` |
| `rank_5_6_6` | `⟨5,6,6⟩` | `130` | `130` | `RankF2Ext/Cert5x6x6.lean` |
| `rank_6_6_6` | `⟨6,6,6⟩` | `153` | `153` | `RankF2Ext/Cert6x6x6.lean` |
