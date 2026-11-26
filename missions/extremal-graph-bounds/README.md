# Extremal Graphs: Ramsey `R(s, t)` & `C4`-Free Turán `ex(n, C_4)` Witness Frontiers

Maximize graph order `N` for classical two-color Ramsey lower bounds `R(s, t) ≥ N + 1` and edge count `e` for `C_4`-free extremal graphs `ex(n, C_4) ≥ e` across 16 open and benchmark frontiers, certified purely inside the Lean 4.36.0 kernel (zero Mathlib, standard axioms only).

## Tracks & Benchmarks

Anchored to [`chrispbsmolen/ramsey-witnesses@d21fda5`](https://github.com/chrispbsmolen/ramsey-witnesses/tree/d21fda594c86657be87e425f19f5fc02a27986e6) (MIT, Radziszowski's *Small Ramsey Numbers* survey rev. 18):

| Task ID | Problem | Editable File | Seed Score | Literature Frontier |
| :--- | :--- | :--- | :---: | :--- |
| `ramsey_3_8` | `R(3, 8)` (max vertices `N`) | `ExtremalGraphs/Ramsey3_8.lean` | 21 | 27 (R(3,8)=28 exact) |
| `ramsey_3_9` | `R(3, 9)` (max vertices `N`) | `ExtremalGraphs/Ramsey3_9.lean` | 22 | 35 (R(3,9)=36 exact) |
| `ramsey_3_10` | `R(3, 10)` (max vertices `N`) | `ExtremalGraphs/Ramsey3_10.lean` | 31 | 39 (R(3,10) ∈ [40,42] open) |
| `ramsey_3_11` | `R(3, 11)` (max vertices `N`) | `ExtremalGraphs/Ramsey3_11.lean` | 35 | 46 (R(3,11) ∈ [47,50] open) |
| `ramsey_4_5` | `R(4, 5)` (max vertices `N`) | `ExtremalGraphs/Ramsey4_5.lean` | 19 | 24 (R(4,5)=25 exact) |
| `ramsey_4_6` | `R(4, 6)` (max vertices `N`) | `ExtremalGraphs/Ramsey4_6.lean` | 26 | 35 (R(4,6) ∈ [36,40] open) |
| `ramsey_4_7` | `R(4, 7)` (max vertices `N`) | `ExtremalGraphs/Ramsey4_7.lean` | 31 | 48 (R(4,7) ∈ [49,58] open) |
| `ramsey_5_5` | `R(5, 5)` (max vertices `N`) | `ExtremalGraphs/Ramsey5_5.lean` | 37 | 42 (R(5,5) ∈ [43,46] open) |
| `c4free_n25` | `ex(25, C_4)` (max edges `e`) | `ExtremalGraphs/C4Free25.lean` | 52 | 66 (exact) |
| `c4free_n27` | `ex(27, C_4)` (max edges `e`) | `ExtremalGraphs/C4Free27.lean` | 59 | 74 (exact) |
| `c4free_n29` | `ex(29, C_4)` (max edges `e`) | `ExtremalGraphs/C4Free29.lean` | 69 | 83 (exact) |
| `c4free_n32` | `ex(32, C_4)` (max edges `e`) | `ExtremalGraphs/C4Free32.lean` | 78 | 92 (exact) |
| `c4free_n34` | `ex(34, C_4)` (max edges `e`) | `ExtremalGraphs/C4Free34.lean` | 83 | 100 (hard frontier) |
| `c4free_n36` | `ex(36, C_4)` (max edges `e`) | `ExtremalGraphs/C4Free36.lean` | 92 | 110 (open/hard frontier) |
| `c4free_n38` | `ex(38, C_4)` (max edges `e`) | `ExtremalGraphs/C4Free38.lean` | 99 | 120 (open/hard frontier) |
| `c4free_n40` | `ex(40, C_4)` (max edges `e`) | `ExtremalGraphs/C4Free40.lean` | 106 | 130 (open/hard frontier) |

## Witness Format

Each editable file `ExtremalGraphs/<Tag>.lean` contains two literal definitions:
- `score_<id> : Nat` — vertex count `N` (Ramsey) or edge count `e` (`C_4`-free).
- `rows_<id> : List Nat` — list of `N` adjacency row bitmasks (`(rows[u] >>> v) &&& 1 == 1` iff `{u, v}` is an edge).

## Formal Specification & Verification

`ExtremalGraphs/Spec.lean` is frozen and proves end-to-end soundness with zero `sorry` and zero Mathlib:
1. `SimpleGraph n`: symmetric, loopless adjacency relation enforced by `checkSimpleGraph`.
2. `ValidRamseyGraph s t N`: absence of both `K_s` and `I_t` proved sound via an active-filtered Tomita greedy-coloring branch-and-bound clique checker (`noClique_sound`).
3. `ValidC4FreeGraph n e`: exact undirected edge count and absence of 4-cycles proved sound via per-pair bitwise common-neighbor counting (`(m &&& (m - 1)) == 0`, `checkC4Free_sound`).
