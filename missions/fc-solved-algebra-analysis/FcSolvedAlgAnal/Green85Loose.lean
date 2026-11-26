/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/85.lean#L61-L71
Upstream category: research solved | AMS: 28, 52
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Green85Loose

open Filter MeasureTheory Set Topology

theorem green_85_loose :
    ∃ c > 0, ∀ᶠ α in 𝓝[>] 0,
    ∀ A : Set (ℝ × ℝ),
    IsOpen A →
    A ⊆ Icc 0 1 ×ˢ Icc 0 1 →
    A.Nonempty →
    α = (volume A).toReal →
    ∃ x₁ x₂ y₁ y₂,
      {(x₁, y₁), (x₂, y₁), (x₂, y₂), (x₁, y₂)} ⊆ A ∧
      c * α ^ 2 * (Real.log (1/α))⁻¹ ≤ |x₁ - x₂| * |y₁ - y₂| := by
  sorry

end FcSolvedAlgAnal.Green85Loose
