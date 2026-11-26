/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/85.lean#L45-L54
Upstream category: research open | AMS: 28, 52
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Green85Rectangle

open Filter MeasureTheory Set Topology

theorem green_85 :
  ∃ c > 0, ∀ A : Set (ℝ × ℝ),
    IsOpen A →
    A ⊆ Icc 0 1 ×ˢ Icc 0 1 →
    A.Nonempty →
    let α := (volume A).toReal
    ∃ x₁ x₂ y₁ y₂,
      {(x₁, y₁), (x₂, y₁), (x₂, y₂), (x₁, y₂)} ⊆ A ∧
      c * α ^ 2 ≤ |x₁ - x₂| * |y₁ - y₂| := by
  sorry

end FcOpenErdosComb.Green85Rectangle
