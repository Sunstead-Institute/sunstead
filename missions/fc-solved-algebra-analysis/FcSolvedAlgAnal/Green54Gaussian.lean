/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/54.lean#L57-L61
Upstream category: research solved | AMS: 46, 52, 60
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Green54Gaussian

open MeasureTheory ProbabilityTheory
open scoped Pointwise ENNReal

theorem green_54 :
    ∀ K : Set (ℕ → ℝ), IsCompact K → Balanced ℝ K → (0.99 : ℝ≥0∞) ≤
    gaussianMeasureInf K → ∃ C : Set (ℕ → ℝ), IsCompact C ∧ Convex ℝ C ∧ C ⊆ (10 : ℕ) • K ∧
    (0.01 : ℝ≥0∞) ≤ gaussianMeasureInf C := by
  sorry

end FcSolvedAlgAnal.Green54Gaussian
