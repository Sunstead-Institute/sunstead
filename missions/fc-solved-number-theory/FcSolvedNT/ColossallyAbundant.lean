/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/ColossallyAbundantNumber.lean#L210-L213
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.ColossallyAbundant

open scoped ArithmeticFunction.sigma

theorem encard_colossallyAbundant_maximizers_le_four (ε : ℝ) (hε : 0 < ε) :
    Set.encard {n : ℕ | 1 < n ∧ ∀ k : ℕ, 1 < k →
      (σ 1 k : ℝ) / (k : ℝ) ^ (1 + ε) ≤ (σ 1 n : ℝ) / (n : ℝ) ^ (1 + ε)} ≤ 4 := by
  sorry

end FcSolvedNT.ColossallyAbundant
