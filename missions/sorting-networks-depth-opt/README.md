# Optimal-Depth Sorting Networks (`n = 9..16`)

Minimize the parallel depth `D(n)` (OEIS A067782) — the number of disjoint parallel compare-exchange layers — in oblivious sorting networks on `n = 9..16` wires, certified purely inside the Lean 4.36.0 kernel (zero Mathlib, standard axioms only).

Pinned to [`bertdobbelaere/SorterHunter@3d8b345`](https://github.com/bertdobbelaere/SorterHunter/tree/3d8b3454bad15062f4b0030052f12d6550f8d89d) (MIT), which tracks sorting networks by both comparator count and the *"number of parallel operation steps - a.k.a. "depth""* (`README.md`) — defined in `sorting_networks.html` as:

> Number of parallel operation steps (layers), determining processing latency - metric below called "depth"

## Tracks & Benchmarks

Each track is seeded with textbook **Odd-Even Transposition Sort** (Habermann 1972; Knuth, *TAOCP* Vol. 3, Ex. 5.3.4.37), which alternates even layers `[(0, 1), (2, 3), ...]` and odd layers `[(1, 2), (3, 4), ...]` for `n` disjoint parallel layers:

| Task ID | Wires (`n`) | Editable File | Seed Depth (Odd-Even) | Optimal Depth (`D(n)`) | Optimality Proof / Reference |
| :--- | :---: | :--- | :---: | :---: | :--- |
| `depth_n9` | 9 | `SortDepth/Layers9.lean` | 9 | **7** | Proven optimal (Parberry 1989; `Sort_9_25_7.json`) |
| `depth_n10` | 10 | `SortDepth/Layers10.lean` | 10 | **7** | Proven optimal (Parberry 1989; `Sort_10_31_7.json`) |
| `depth_n11` | 11 | `SortDepth/Layers11.lean` | 11 | **8** | Proven optimal (Bundala–Závodný 2014; `Sort_11_35_8.json`) |
| `depth_n12` | 12 | `SortDepth/Layers12.lean` | 12 | **8** | Proven optimal (Bundala–Závodný 2014; `Sort_12_40_8.json`) |
| `depth_n13` | 13 | `SortDepth/Layers13.lean` | 13 | **9** | Proven optimal (Bundala–Závodný 2014; `Sort_13_46_9.json`) |
| `depth_n14` | 14 | `SortDepth/Layers14.lean` | 14 | **9** | Proven optimal (Bundala–Závodný 2014; `Sort_14_52_9.json`) |
| `depth_n15` | 15 | `SortDepth/Layers15.lean` | 15 | **9** | Proven optimal (Bundala–Závodný 2014; `Sort_15_57_9.json`) |
| `depth_n16` | 16 | `SortDepth/Layers16.lean` | 16 | **9** | Proven optimal (Bundala–Závodný 2014; `Sort_16_61_9.json`) |

*(SorterHunter depth definitions and benchmark files `Sort_10_31_7.json`, `Sort_12_40_8.json`, `Sort_16_61_9.json`, `SorterHunter.cpp`, `README.md`, and `sorting_networks.html` are anchored in `UPSTREAM.json` and checked by `scripts/check-upstream.py`.)*

## Layer Format

Each editable file `SortDepth/Layers{N}.lean` contains exactly two concrete literal definitions (bounded to `16384` bytes, `1..32` non-empty layers, and `1..256` total comparators):

```lean
def SortDepth.depth9 : Nat := 9
def SortDepth.layers9 : List (List (Nat × Nat)) := [
  [(0, 1), (2, 3), (4, 5), (6, 7)],
  [(1, 2), (3, 4), (5, 6), (7, 8)],
  ...
]
```

Within every parallel layer:
1. Every comparator `(i, j)` must satisfy `0 ≤ i < j < n`.
2. **Pairwise wire disjointness**: no wire index may appear in more than one comparator within the same layer, so all comparators in the layer execute simultaneously in 1 clock cycle.

## Formal Specification & Verification

`SortDepth/Spec.lean` is frozen and proves end-to-end soundness with zero `sorry` and zero Mathlib:

1. **General linear-order semantics (`applyLayer`, `applyLayers`, `IsSorted`)**: defined for any type `α` equipped with a reflexive, transitive, total comparator `le : α → α → Bool`.
2. **Pairwise wire disjointness & simultaneous parallel semantics (`layerDisjoint_sound`, `wellFormedLayers_sound`, `applyComp_comm`, `applyLayer_parallel_spec`)**: formally proves that `wellFormedLayers n layers = true` implies every layer has in-bounds ordered comparators on pairwise disjoint wires, that disjoint comparators commute, and that `applyLayer` computes exact simultaneous 1-clock-cycle parallel compare-exchange updates.
3. **Knuth's Zero-One Principle (`SortDepth.zero_one_principle`, `SortDepth.zero_one_principle_layers`)**: formally proved inside `SortDepth/Spec.lean`, lifting Boolean sorting on all `2^n` inputs directly to every decidable linear order `(α, le)` (and explicitly specialized to `Nat` in `validParallelSortingNetwork_sorts_nat`).
4. **Bit-sliced kernel evaluator (`SortDepth.checkSortLayers` + `SortDepth.checkSortLayers_sound`)**: evaluates all `2^n` Boolean inputs simultaneously in a single pass over `layers` using `2^n`-bit natural-number truth tables (`&&&`, `|||`) and verifies `(w_i ||| w_{i+1}) == w_{i+1}` for all adjacent wires.

Each frozen wrapper `SortDepth/Bound{N}.lean` checks `wellFormedLayers`, layer count (`layers{N}.length = depth{N}`), and `checkSortLayers` purely via `decide +kernel`, certifying `SortDepth.ValidParallelSortingNetwork {N} depth{N}` with standard axioms only.

To replay locally with Lean `v4.36.0`:

```bash
lake build SortDepth.Bound9 SortDepth.Bound10 SortDepth.Bound11 SortDepth.Bound12 SortDepth.Bound13 SortDepth.Bound14 SortDepth.Bound15 SortDepth.Bound16
```
