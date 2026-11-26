/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/SixStandardDeviations.lean#L63-L67
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.SixStdDev

theorem six_standard_deviations :
    ∀ (n : ℕ) (S : Fin n → Finset (Fin n)),
      ∃ χ : Fin n → ℝ, (∀ j, χ j = 1 ∨ χ j = -1) ∧
        ∀ i, |∑ j ∈ S i, χ j| ≤ 6 * Real.sqrt n := by
  sorry

end FcSolvedComb.SixStdDev
