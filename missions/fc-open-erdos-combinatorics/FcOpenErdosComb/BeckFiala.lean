/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/BeckFialaConjecture.lean#L88-L93
Upstream category: research open | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.BeckFiala

theorem beck_fiala_conjecture :
    ∃ C : ℝ, 0 < C ∧ ∀ (n m t : ℕ) (S : Fin m → Finset (Fin n)),
      (∀ j, (Finset.univ.filter fun i => j ∈ S i).card ≤ t) →
      ∃ χ : Fin n → ℝ, (∀ j, χ j = 1 ∨ χ j = -1) ∧
        ∀ i, |∑ j ∈ S i, χ j| ≤ C * Real.sqrt t := by
  sorry

end FcOpenErdosComb.BeckFiala
