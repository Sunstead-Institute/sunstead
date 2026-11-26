# Optimal Median Selection Networks (`n = 7..16`)

Minimize the number of compare-exchange elements in oblivious median selection networks on `n = 7..16` wires, certified purely inside the Lean 4.36.0 kernel (zero Mathlib, standard axioms only).

## Tracks & Benchmarks

Each track starts from textbook **Batcher odd-even merge-exchange sort** and targets Bert Dobbelaere's [`bertdobbelaere/SorterHunter@3d8b345`](https://github.com/bertdobbelaere/SorterHunter/tree/3d8b3454bad15062f4b0030052f12d6550f8d89d) (MIT) median selection network records:

| Task ID | Wires (`n`) | Editable File | Seed (Batcher) | Best Known | Status |
| :--- | :---: | :--- | :---: | :---: | :--- |
| `median_n7` | 7 | `SelectNet/Net7.lean` | 16 | **13** | Proven optimal (13) |
| `median_n8` | 8 | `SelectNet/Net8.lean` | 19 | **16** | Proven optimal (16) |
| `median_n9` | 9 | `SelectNet/Net9.lean` | 26 | **19** | Proven optimal (19) |
| `median_n10` | 10 | `SelectNet/Net10.lean` | 31 | **22** | Proven optimal (22) |
| `median_n11` | 11 | `SelectNet/Net11.lean` | 37 | **25** | Known optimal / tight (25) |
| `median_n12` | 12 | `SelectNet/Net12.lean` | 41 | **29** | Open research frontier (best known 29) |
| `median_n13` | 13 | `SelectNet/Net13.lean` | 48 | **32** | Open research frontier (best known 32) |
| `median_n14` | 14 | `SelectNet/Net14.lean` | 53 | **38** | Open research frontier (best known 38) |
| `median_n15` | 15 | `SelectNet/Net15.lean` | 59 | **41** | Open research frontier (best known 41) |
| `median_n16` | 16 | `SelectNet/Net16.lean` | 63 | **46** | Open research frontier (best known 46) |

## Formal Specification & Verification

`SelectNet/Spec.lean` is frozen and proves end-to-end soundness with zero `sorry` and zero Mathlib:
1. Order-statistic semantics (`IsOrderStat`, `IsMedianOutput`) over every decidable linear order `(α, le)` (exact median on wire `(n-1)/2` for odd `n`; unordered central pair on wires `(n-1)/2` and `(n-1)/2 + 1` for even `n`, matching SorterHunter's `median_networks.html`).
2. **Knuth's Zero-One Principle for Median Selection Networks** (`SelectNet.zero_one_principle_median`).
3. An `O(n^2)` bit-sliced threshold-DP mask generator (`popGeTable`) and parallel `2^n`-bit evaluator (`checkMedianNet`, `validMedianNetwork_of_check`).
