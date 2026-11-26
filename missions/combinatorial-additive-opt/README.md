# Additive Combinatorics: Cap Sets in `F_3^n`, 3-AP-Free & Sidon Sets

Maximize set cardinality across 14 classic additive combinatorics frontiers — Cap Sets in `F_3^n` (`n = 4..7`), Salem–Spencer 3-AP-free sets (`r_3(N)`), and Sidon (`B_2`) sets — certified purely inside the Lean 4.36.0 kernel (zero Mathlib, standard axioms only).

## Tracks & Benchmarks

Anchored to [`google-deepmind/funsearch@cc53f27`](https://github.com/google-deepmind/funsearch/tree/cc53f274237d7ab05c19df939edbc1f9616a7c19) (Apache-2.0, Romera-Paredes et al., *Nature* 2023):

| Task ID | Problem | Editable File | Seed (`M`) | Literature Frontier |
| :--- | :--- | :--- | :---: | :--- |
| `capset_f3_4` | Cap Set in `F_3^4` | `AdditiveComb/CapF3_4.lean` | 16 | 20 (exact) |
| `capset_f3_5` | Cap Set in `F_3^5` | `AdditiveComb/CapF3_5.lean` | 35 | 45 (exact) |
| `capset_f3_6` | Cap Set in `F_3^6` | `AdditiveComb/CapF3_6.lean` | 71 | 112 (exact) |
| `capset_f3_7` | Cap Set in `F_3^7` | `AdditiveComb/CapF3_7.lean` | 140 | 236 (open frontier, UB 276) |
| `ap3_n64` | 3-AP-Free in `{0..63}` | `AdditiveComb/AP3_64.lean` | 16 | 20 (exact r_3(64)) |
| `ap3_n100` | 3-AP-Free in `{0..99}` | `AdditiveComb/AP3_100.lean` | 22 | 26 (exact r_3(100)) |
| `ap3_n150` | 3-AP-Free in `{0..149}` | `AdditiveComb/AP3_150.lean` | 28 | 35 (hard frontier) |
| `ap3_n200` | 3-AP-Free in `{0..199}` | `AdditiveComb/AP3_200.lean` | 32 | 42+ (open/hard frontier) |
| `ap3_n300` | 3-AP-Free in `{0..299}` | `AdditiveComb/AP3_300.lean` | 44 | 54+ (open frontier) |
| `sidon_n100` | Sidon Set in `{0..99}` | `AdditiveComb/Sidon100.lean` | 10 | 12 (exact, OGR-12=85) |
| `sidon_n150` | Sidon Set in `{0..149}` | `AdditiveComb/Sidon150.lean` | 12 | 14 (exact, OGR-14=127) |
| `sidon_n200` | Sidon Set in `{0..199}` | `AdditiveComb/Sidon200.lean` | 14 | 16 (exact, OGR-16=177) |
| `sidon_n300` | Sidon Set in `{0..299}` | `AdditiveComb/Sidon300.lean` | 16 | 20 (exact, OGR-20=283) |
| `sidon_n500` | Sidon Set in `{0..499}` | `AdditiveComb/Sidon500.lean` | 19 | 25 (hard frontier, OGR-25=480) |

## Witness Format

- **Cap Sets (`capset_f3_n`)**: each element is a `Nat` packing `n` ternary coordinates in 2-bit lanes (`00 = 0`, `01 = 1`, `10 = 2`; `11` forbidden).
- **3-AP-Free & Sidon Sets**: strictly increasing `List Nat` with all elements `< N`.

## Formal Specification & Verification

`AdditiveComb/Spec.lean` is frozen and proves end-to-end soundness with zero `sorry` and zero Mathlib (`validCapSet_of_check`, `validAP3Free_of_check`, `validSidonSet_of_check`).
