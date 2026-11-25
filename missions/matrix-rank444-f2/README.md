# Reduce the 4×4 matrix multiplication rank bound over F₂

Edit the score literal and coefficient table in `Rank444/Certificate.lean`. Each triple contains three decimal 16-bit masks for one rank-one term. Bit positions count from zero. In the left factor, bit 4i+j selects input A[i,j]. In the right factor, bit 4j+k selects B[j,k]. In the third factor, bit 4k+i contributes to output C[i,k]. All coefficient arithmetic is modulo two.

The frozen proof checks the sum of the terms against all 4,096 tensor entries. Lean checks that the score equals the length of that same table by definitional equality. A submission must improve on the current bound. The 47-term seed reproduces a published result. A smaller valid table certifies an upper bound on bilinear products; optimality and practical speed require separate evidence.

For independent replay from this directory, use Lean v4.36.0 and the pinned Mathlib, then run `lake build Rank444.Bound`. The table is also sufficient to check the result using ordinary elementary-matrix multiplication without Lean.

The tensor definitions and proof techniques come from [B334](https://github.com/tejasvi/rank444-f2/tree/22f87dd705718246e3256f4cb5b5bc47311eb53d/lean/B334), including Statement, MethodK/Cert and Lem/SanityL. The seed table comes from [Greg Sidebottom’s published scheme](https://github.com/gsidebottom/mat_mul/tree/d6cdc88585e1cdbaaba46a8752f99140d7c14b25/schemes/4x4x4_47_mod_2_166), with its output index transposed for B334. Both sources use Apache-2.0.
