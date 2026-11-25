# Optimal Sorting Networks (`n = 9..16`)

Minimize the number of compare-exchange elements (`S(n)`, OEIS A003075) in oblivious sorting networks on `n = 9..16` wires, certified purely inside the Lean 4.36.0 kernel (zero Mathlib, standard axioms only).

## Tracks & Benchmarks

Each track is seeded with textbook **Batcher odd-even merge-exchange sort** (Knuth, *TAOCP* Vol. 3, Algorithm 5.2.2M) and pinned to [`bertdobbelaere/SorterHunter@3d8b345`](https://github.com/bertdobbelaere/SorterHunter/tree/3d8b3454bad15062f4b0030052f12d6550f8d89d) (MIT):

| Task ID | Wires (`n`) | Editable File | Seed (Batcher 5.2.2M) | Best Known (`S(n)`) | Lower Bound / Status |
| :--- | :---: | :--- | :---: | :---: | :--- |
| `sort_n9` | 9 | `SortNet/Net9.lean` | 26 | **25** | Proven optimal (Codish et al. 2016) |
| `sort_n10` | 10 | `SortNet/Net10.lean` | 31 | **29** | Proven optimal (Codish et al. 2016) |
| `sort_n11` | 11 | `SortNet/Net11.lean` | 37 | **35** | Proven optimal (Harder 2019) |
| `sort_n12` | 12 | `SortNet/Net12.lean` | 41 | **39** | Proven optimal (Harder 2019) |
| `sort_n13` | 13 | `SortNet/Net13.lean` | 48 | **45** | Open frontier (LB 43–44) |
| `sort_n14` | 14 | `SortNet/Net14.lean` | 53 | **51** | Open frontier (LB 47–48) |
| `sort_n15` | 15 | `SortNet/Net15.lean` | 59 | **56** | Open frontier (LB 51–52) |
| `sort_n16` | 16 | `SortNet/Net16.lean` | 63 | **60** | Open frontier (LB 55–56) |

*(SorterHunter records `Sort_10_29_8.json`, `Sort_13_45_10.json`, `Sort_16_60_10.json`, and `sorting_networks.html` are anchored in `UPSTREAM.json` and checked by `scripts/check-upstream.py`.)*

## Network Format

Each editable file `SortNet/Net{N}.lean` contains exactly two concrete literal definitions (bounded to `16384` bytes and `1..256` comparators):

```lean
def SortNet.score9 : Nat := 26
def SortNet.net9 : List (Nat × Nat) := [
  (0, 8), (0, 4), ...
]
```

Each pair `(i, j)` compares wires `i` and `j` with `0 ≤ i < j < n`, replacing `(v[i], v[j])` with `(min(v[i], v[j]), max(v[i], v[j]))`.

## Formal Specification & Verification

`SortNet/Spec.lean` is frozen and proves end-to-end soundness with zero `sorry` and zero Mathlib:

1. **General linear-order semantics (`applyNet`, `IsSorted`)**: defined for any type `α` equipped with a reflexive, transitive, total comparator `le : α → α → Bool`.
2. **Knuth's Zero-One Principle (`SortNet.zero_one_principle`)**: formally proved inside `SortNet/Spec.lean`, lifting Boolean sorting (`∀ v : Fin n → Bool, IsSortedBool (applyNetBool net v)`) directly to every linear order (`SortNet.validSortingNetwork_sorts_all_linear_orders`).
3. **Bit-sliced kernel evaluator (`SortNet.checkSortNet` + `SortNet.checkSortNet_sound`)**: evaluates all `2^n` Boolean inputs simultaneously in a single pass over `net` using `2^n`-bit natural-number truth tables (`&&&`, `|||`) and verifies `(w_i ||| w_{i+1}) == w_{i+1}` for all adjacent wires.

Each frozen wrapper `SortNet/Bound{N}.lean` checks `wellFormed`, comparator count, and `checkSortNet` purely via `decide +kernel`, certifying `SortNet.ValidSortingNetwork {N} score{N}`.

To replay locally with Lean `v4.36.0`:

```bash
lake build SortNet.Bound9 SortNet.Bound10 SortNet.Bound11 SortNet.Bound12 SortNet.Bound13 SortNet.Bound14 SortNet.Bound15 SortNet.Bound16
```
