/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/59.lean#L69-L72
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Green59SmoothSum

open Filter

theorem green_59 :
    ∀ ε : ℝ, 0 < ε → ∀ᶠ N : ℕ in atTop, ∀ n ∈ Finset.Icc 2 N, ∃ a b : ℕ, 0 < a ∧ 0 < b ∧
      a + b = n ∧ IsSmooth ((N : ℝ) ^ ε) a ∧ IsSmooth ((N : ℝ) ^ ε) b := by
  sorry

end FcOpenErdosComb.Green59SmoothSum
