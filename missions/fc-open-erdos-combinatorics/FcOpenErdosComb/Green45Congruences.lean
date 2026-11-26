/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/45.lean#L47-L50
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Green45Congruences

theorem green_45 :
    ∀ᶠ N in .atTop, ∃ a : ℕ → ℕ, ∀ m ∈ Finset.Icc 1 N,
      10 ≤ (Finset.Icc 1 N |>.filter fun p => p.Prime ∧ a p ≡ m [MOD p]).card := by
  sorry

end FcOpenErdosComb.Green45Congruences
