/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/61.lean#L42-L47
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Green61SquaresBasis

open scoped Pointwise Topology
open Filter

theorem green_61 :
    ∃ f : ℕ → ℝ, Tendsto f atTop (𝓝 0) ∧
      ∀ n : ℕ, n ≥ 1 → ∀ (A : Finset ℕ),
        (Finset.Icc 1 n).image (· ^ 2) ⊆ A + A →
          (n : ℝ) ^ (1 - f n) ≤ A.card := by
  sorry

end FcOpenErdosComb.Green61SquaresBasis
