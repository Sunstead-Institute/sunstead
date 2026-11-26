/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/3.lean#L41-L45
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.Green3MultTriple

open Set MeasureTheory

theorem green_3 :
    ∀ A : Set ℝ,
      IsOpen A → A ⊆ Icc 0 1 → volume A > 1/3 →
        ∃ x y z, x ∈ A ∧ y ∈ A ∧ z ∈ A ∧ x * y = z := by
  sorry

end FcSolvedNT.Green3MultTriple
