/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/LonelyRunnerConjecture.lean#L73-L80
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.LonelyRunnerTao2017

theorem lonely_runner_conjecture.variants.tao_2017 :
    ∃ c : ℝ, 0 < c ∧
      (∀ᶠ n : ℕ in Filter.atTop,
        deltaGap n ≥
          ((1 : ℝ) / (2 * (n : ℝ))
            + c * Real.log (n : ℝ) /
                ((n : ℝ) ^ 2 * (Real.log (Real.log (n : ℝ))) ^ 2))) := by
  sorry

end FcSolvedNT.LonelyRunnerTao2017
