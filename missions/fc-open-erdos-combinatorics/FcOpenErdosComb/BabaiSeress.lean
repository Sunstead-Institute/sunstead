/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/DiameterSimpleFiniteGroups.lean#L168-L173
Upstream category: research open | AMS: 5, 20, 68
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.BabaiSeress

theorem babai_seress_conjecture :
    ∃ C : ℕ,
    ∀ (G : Type) [Group G] [Fintype G] [IsSimpleGroup G],
    (∃ a b : G, a * b ≠ b * a) →
    (groupDiam G : ℝ) ≤ (Real.log (Fintype.card G : ℝ)) ^ C := by
  sorry

end FcOpenErdosComb.BabaiSeress
