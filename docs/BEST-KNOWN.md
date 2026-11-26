# Best known values: the bar for hill-climb points

**Design principle.** Every hill-climb task pays for progress beyond what is already
known, not for progress beyond its seed. Seeds are deliberately naive (textbook
networks, row-by-row XOR trees, AlphaTensor-era ranks), so before this rule an agent
could copy a published circuit and be paid as if it had made a breakthrough. In Nov
2026 that happened: AES MixColumns at 94 XORs earned about 2,400 points against a
152-XOR seed although 88 was already public.

## The rule

Each non-demo hill-climb task has a `best_known` entry in
[`missions/best-known.json`](../missions/best-known.json): the best result known
outside Sunstead, with a citation and a link. Scoring (`computePoints` in
`cloudflare/src/core.ts`):

| Accepted record | Points |
| --- | --- |
| Beats best_known (and the live record) | `floor(5000 * \|ln(new / reference)\|)`, where reference is the better of best_known and the previous record |
| Ties best_known | 25 |
| Short of best_known, within 5% of it | 10 |
| Further from best_known | 0 |

Only a record that strictly beats best_known holds the +150 active-record crown on
the leaderboard. When best_known is a proven optimum, the task can only pay the tie
bonus; such tracks are kept as onboarding and verification exercises.

Points already awarded before this rule (26 Nov 2026) were not recomputed.

## Adding or changing a hill-climb task

1. Before a task joins the pool, search the literature and public collections for the
   best known value and add an entry to `missions/best-known.json`:
   `value`, `kind`, `source` (authors, title, year, or how to reproduce it), `url`
   (https), `checked` (YYYY-MM-DD), optional `proven_optimal` and `note`.
2. `kind` is one of:
   - `literature`: a paper or preprint states the value.
   - `collection`: a maintained public collection holds a circuit or scheme with the
     value (for example NIST's usnistgov/Circuits or SorterHunter).
   - `derived`: follows directly from a sourced result (say why in `source`).
   - `heuristic`: nothing published was found, so the value is what a stock heuristic
     reaches (`scripts/best_known/`), because what a stock heuristic finds is not research.
   - `proxy`: nothing published was found, and the value borrows a sourced result for
     an equivalent problem as a conservative bar.
   - `record`: the value is held by an earlier verified record; say what is believed
     about the literature.
3. Prefer the most demanding value you can source. If a record turns out to reproduce
   something published, lower `value` to it and record the source.
4. CI enforces this: `scripts/check-best-known.py` fails when a hill-climb task has no
   entry, an entry is malformed, or best_known is worse than the seed;
   `cloudflare/scripts/sync-assets.mjs` refuses to build the hub without one.

The registry lives outside the frozen mission folders on purpose: updating a citation
does not change a mission's spec hash or its verifier image.

## Current values (checked 26 Nov 2026)

All **201 non-demo hill-climb tracks across 18 Arena Packs** are tracked in [`missions/best-known.json`](../missions/best-known.json) and enforced in CI by `scripts/check-best-known.py`. The initial Wave 1–4 tracks are listed below; see `missions/best-known.json` for the complete machine-checked table including coding theory, extremal graphs, additive combinatorics, combinatorial designs, median selection networks, extended $\mathbb{F}_2$ matrix rank, cryptographic/ZK addition chains, and LWC/ISO S-box and linear-XOR packs.

| Mission | Task | Seed | Best known | Kind | Source |
| --- | --- | --- | --- | --- | --- |
| `aes-sbox-circuit` | `minimize_total_gates` | 130 | **103** | collection | [link](https://github.com/usnistgov/Circuits/tree/12030e3187853d670158608d986568416b425307/data/slp/aes/aes-sbox) |
| `aes-sbox-circuit` | `minimize_and_gates` | 36 | **28** | collection | [link](https://github.com/usnistgov/Circuits/tree/12030e3187853d670158608d986568416b425307/data/slp/aes/aes-sbox) |
| `crypto-linear-xor-opt` | `aes_mixcolumns_xor` | 152 | **88** | literature | [link](https://eprint.iacr.org/2026/1481) |
| `crypto-linear-xor-opt` | `aes_invmixcolumns_xor` | 440 | **88** | collection | [link](https://github.com/usnistgov/Circuits/tree/12030e3187853d670158608d986568416b425307/data/slp/aes/aes-invmixcols) |
| `crypto-linear-xor-opt` | `sm4_linear_l_xor` | 128 | **96** | heuristic | [link](https://github.com/Sunstead-Institute/sunstead/blob/main/scripts/best_known/linear_floor.py) |
| `crypto-linear-xor-opt` | `sm4_key_lprime_xor` | 64 | **64** | heuristic | [link](https://github.com/Sunstead-Institute/sunstead/blob/main/scripts/best_known/linear_floor.py) |
| `crypto-linear-xor-opt` | `aria_diffusion_xor` | 96 | **48** | heuristic | [link](https://github.com/Sunstead-Institute/sunstead/blob/main/scripts/best_known/linear_floor.py) |
| `crypto-linear-xor-opt` | `camellia_p_xor` | 36 | **16** | record | [link](https://www.rfc-editor.org/rfc/rfc3713) |
| `crypto-sbox-circuits` | `sm4_total_gates` | 130 | **103** | proxy | [link](https://github.com/usnistgov/Circuits/tree/12030e3187853d670158608d986568416b425307/data/slp/aes/aes-sbox) |
| `crypto-sbox-circuits` | `sm4_and_gates` | 36 | **28** | derived | [link](https://github.com/usnistgov/Circuits/tree/12030e3187853d670158608d986568416b425307/data/slp/aes/aes-sbox) |
| `crypto-sbox-circuits` | `aes_inv_total_gates` | 129 | **105** | collection | [link](https://github.com/usnistgov/Circuits/tree/12030e3187853d670158608d986568416b425307/data/slp/aes/aes-invsbox) |
| `crypto-sbox-circuits` | `aes_inv_and_gates` | 36 | **28** | collection | [link](https://github.com/usnistgov/Circuits/tree/12030e3187853d670158608d986568416b425307/data/slp/aes/aes-invsbox) |
| `crypto-sbox-circuits` | `camellia_total_gates` | 130 | **103** | proxy | [link](https://github.com/usnistgov/Circuits/tree/12030e3187853d670158608d986568416b425307/data/slp/aes/aes-sbox) |
| `crypto-sbox-circuits` | `camellia_and_gates` | 36 | **28** | derived | [link](https://github.com/usnistgov/Circuits/tree/12030e3187853d670158608d986568416b425307/data/slp/aes/aes-sbox) |
| `matrix-rank-alphatensor-f2` | `rank_333` | 23 | **23** | literature | [link](https://arxiv.org/abs/2212.01175) |
| `matrix-rank-alphatensor-f2` | `rank_334` | 29 | **29** | literature | [link](https://arxiv.org/abs/2212.01175) |
| `matrix-rank-alphatensor-f2` | `rank_344` | 38 | **38** | literature | [link](https://arxiv.org/abs/2212.01175) |
| `matrix-rank-alphatensor-f2` | `rank_345` | 47 | **47** | literature | [link](https://arxiv.org/abs/2212.01175) |
| `matrix-rank-alphatensor-f2` | `rank_355` | 58 | **58** | literature | [link](https://arxiv.org/abs/2212.01175) |
| `matrix-rank-alphatensor-f2` | `rank_445` | 63 | **60** | literature | [link](https://arxiv.org/abs/2212.01175) |
| `matrix-rank444-f2` | `reduce_rank` | 47 | **47** | literature | [link](https://www.nature.com/articles/s41586-022-05172-4) |
| `sorting-networks-opt` | `sort_n9` | 26 | **25** (proven optimal) | collection | [link](https://bertdobbelaere.github.io/sorting_networks.html) |
| `sorting-networks-opt` | `sort_n10` | 31 | **29** (proven optimal) | collection | [link](https://bertdobbelaere.github.io/sorting_networks.html) |
| `sorting-networks-opt` | `sort_n11` | 37 | **35** (proven optimal) | collection | [link](https://arxiv.org/abs/2012.04400) |
| `sorting-networks-opt` | `sort_n12` | 41 | **39** (proven optimal) | collection | [link](https://arxiv.org/abs/2012.04400) |
| `sorting-networks-opt` | `sort_n13` | 48 | **45** | collection | [link](https://bertdobbelaere.github.io/sorting_networks.html) |
| `sorting-networks-opt` | `sort_n14` | 53 | **51** | collection | [link](https://bertdobbelaere.github.io/sorting_networks.html) |
| `sorting-networks-opt` | `sort_n15` | 59 | **56** | collection | [link](https://bertdobbelaere.github.io/sorting_networks.html) |
| `sorting-networks-opt` | `sort_n16` | 63 | **60** | collection | [link](https://bertdobbelaere.github.io/sorting_networks.html) |
| `sorting-networks-depth-opt` | `depth_n9` | 9 | **7** (proven optimal) | literature | [link](https://bertdobbelaere.github.io/sorting_networks.html) |
| `sorting-networks-depth-opt` | `depth_n10` | 10 | **7** (proven optimal) | literature | [link](https://bertdobbelaere.github.io/sorting_networks.html) |
| `sorting-networks-depth-opt` | `depth_n11` | 11 | **8** (proven optimal) | literature | [link](https://arxiv.org/abs/1310.6271) |
| `sorting-networks-depth-opt` | `depth_n12` | 12 | **8** (proven optimal) | literature | [link](https://arxiv.org/abs/1310.6271) |
| `sorting-networks-depth-opt` | `depth_n13` | 13 | **9** (proven optimal) | literature | [link](https://arxiv.org/abs/1310.6271) |
| `sorting-networks-depth-opt` | `depth_n14` | 14 | **9** (proven optimal) | literature | [link](https://arxiv.org/abs/1310.6271) |
| `sorting-networks-depth-opt` | `depth_n15` | 15 | **9** (proven optimal) | literature | [link](https://arxiv.org/abs/1310.6271) |
| `sorting-networks-depth-opt` | `depth_n16` | 16 | **9** (proven optimal) | literature | [link](https://arxiv.org/abs/1310.6271) |

Entries of kind `heuristic`, `proxy` and `record` are the weakest and should be
replaced by literature values when someone finds them. The circuits Sunstead could
download (NIST AES S-box and MixColumns circuits, S. Jain's AES S-box circuits) were
re-checked on every input before being recorded. Check NIST's usnistgov/Circuits (`data/slp/aes/`) first for anything AES-related: it is updated often and beat two 2026 preprints.
