/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/62.lean#L41-L46
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Green62PrimeProd

open Filter

theorem green_62 :
    ∀ᶠ p in atTop, p.Prime →
      let A := (Finset.range p).filter Nat.Prime
      ∀ x : ℕ, 1 ≤ x ∧ x < p →
        ∃ a₁ ∈ A, ∃ a₂ ∈ A, (x : ZMod p) = (a₁ * a₂ : ZMod p) := by
  sorry

end FcOpenErdosComb.Green62PrimeProd
