/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/60.lean#L36-L42
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Green60SquaresSumset

open scoped Pointwise

theorem green_60 :
    ∃ c > (0 : ℝ),
      ∀ (A : Finset ℕ),
        (∀ a ∈ A, IsSquare a) →
        2 ≤ A.card →
          ((A + A).card : ℝ) ≥ (A.card : ℝ) ^ (1 + c) := by
  sorry

end FcOpenErdosComb.Green60SquaresSumset
