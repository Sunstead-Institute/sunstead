/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/76.lean#L64-L66
Upstream category: research open | AMS: 5, 52
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Green76HittingSet

open scoped Finset

theorem green_76 :
    ∀ A : Finset (ℝ × ℝ), ∃ A', #A' ≤ #A / 2 ∧ HitsRichRectangles 1000 A A' := by
  sorry

end FcOpenErdosComb.Green76HittingSet
