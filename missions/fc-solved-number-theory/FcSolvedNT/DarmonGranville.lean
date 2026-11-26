/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/FermatCatalanConjecture.lean#L68-L73
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.DarmonGranville

open scoped Function

theorem fermat_catalan.variants.darmon_granville
    (m n k : ℕ) (hm : 0 < m) (hn : 0 < n) (hk : 0 < k)
    (H : (1 / m : ℝ) + 1 / n + 1 / k < 1) :
    {(a, b, c) : ℕ × ℕ × ℕ | 0 < a ∧ 0 < b ∧ 0 < c ∧ a^m + b^n = c^k ∧
      ({a, b, c} : Set _).Pairwise Nat.Coprime}.Finite := by
  sorry

end FcSolvedNT.DarmonGranville
