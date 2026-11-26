# Binary Error-Correcting & Constant-Weight Codes (`A(n, d)` and `A(n, d, w)`)

Maximize the number of codewords `M` in binary block codes `A(n, d)` and binary constant-weight codes `A(n, d, w)` across 16 classical open research frontiers, certified purely inside the Lean 4.36.0 kernel (zero Mathlib, standard axioms only).

## Tracks & Benchmarks

Anchored to [`williamechols/cwc-seeded-tabu-search@4f0bf18`](https://github.com/williamechols/cwc-seeded-tabu-search/tree/4f0bf18b094fb15c3634001ea8aed847e8353d1c) (MIT), building on Christopher D. Rosin's `CWBC` ([arXiv:2603.00174](https://arxiv.org/abs/2603.00174)) and A. E. Brouwer's lower/upper bound tables:

| Task ID | Parameter | Editable File | Seed (`M`) | Literature Frontier |
| :--- | :---: | :--- | :---: | :---: |
| `code_17_8` | `A(17, 8)` | `CodingBounds/Code17_8.lean` | 28 | 36–37 |
| `code_18_8` | `A(18, 8)` | `CodingBounds/Code18_8.lean` | 48 | 64–72 |
| `code_19_8` | `A(19, 8)` | `CodingBounds/Code19_8.lean` | 80 | 128–142 |
| `code_21_10` | `A(21, 10)` | `CodingBounds/Code21_10.lean` | 17 | 42–47 |
| `code_22_10` | `A(22, 10)` | `CodingBounds/Code22_10.lean` | 23 | 64–84 |
| `code_23_10` | `A(23, 10)` | `CodingBounds/Code23_10.lean` | 33 | 80–151 |
| `code_24_10` | `A(24, 10)` | `CodingBounds/Code24_10.lean` | 40 | 136–268 |
| `code_26_12` | `A(26, 12)` | `CodingBounds/Code26_12.lean` | 24 | 44–62 |
| `cwc_17_6_6` | `A(17, 6, 6)` | `CodingBounds/Cwc17_6_6.lean` | 32 | 44–61 |
| `cwc_18_6_7` | `A(18, 6, 7)` | `CodingBounds/Cwc18_6_7.lean` | 56 | 97–137 |
| `cwc_20_8_7` | `A(20, 8, 7)` | `CodingBounds/Cwc20_8_7.lean` | 24 | 34–41 |
| `cwc_21_6_5` | `A(21, 6, 5)` | `CodingBounds/Cwc21_6_5.lean` | 68 | 109–113 |
| `cwc_24_10_8` | `A(24, 10, 8)` | `CodingBounds/Cwc24_10_8.lean` | 24 | 39–48 |
| `cwc_26_10_8` | `A(26, 10, 8)` | `CodingBounds/Cwc26_10_8.lean` | 32 | 68–95 |
| `cwc_27_10_8` | `A(27, 10, 8)` | `CodingBounds/Cwc27_10_8.lean` | 37 | 76–115 |
| `cwc_29_12_10` | `A(29, 12, 10)` | `CodingBounds/Cwc29_12_10.lean` | 28 | 70–131 |

## Code Format

Each editable file `CodingBounds/<Tag>.lean` contains exactly two literal definitions:

```lean
def CodingBounds.score_<id> : Nat := <M>
def CodingBounds.words_<id> : List Nat := [ ... ]
```

Each entry is a natural number `x < 2^n` representing a binary codeword of length `n` via its low `n` bits (`x.testBit i`).

## Formal Specification & Verification

`CodingBounds/Spec.lean` is frozen and proves end-to-end soundness with zero `sorry` and zero Mathlib:
1. Semantic length-`n` binary vectors (`Fin n → Bool`), `hammingWeight`, and `hammingDist`.
2. Target predicates `ValidBinaryCode n d M` and `ValidConstantWeightCode n d w M`, explicitly enforcing pairwise distinctness (`C.get i ≠ C.get j`), minimum Hamming distance `≥ d`, and (for constant-weight tracks) exact weight `w`.
3. A proved-exact 32-bit carry-free SWAR popcount (`popcount32_eq_hammingWeight`) checked purely via `decide +kernel`.
