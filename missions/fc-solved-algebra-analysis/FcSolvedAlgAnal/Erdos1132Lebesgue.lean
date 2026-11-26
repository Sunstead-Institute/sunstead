/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1132.lean#L133-L137
Upstream category: research solved | AMS: 41
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Erdos1132Lebesgue

open Filter MeasureTheory

theorem erdos_1132.variants.erdos_max :
    ∃ C : ℝ, ∀ n : ℕ, 1 ≤ n → ∀ x : ℕ → ℝ, (∀ k < n, x k ∈ Set.Icc (-1 : ℝ) 1) →
      Set.InjOn x (Set.Iio n) →
        ∃ t ∈ Set.Icc (-1 : ℝ) 1, 2 / Real.pi * Real.log n - C < lebesgueFunction n x t := by
  sorry

end FcSolvedAlgAnal.Erdos1132Lebesgue
