/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Mathoverflow/486451.lean#L32-L35
Upstream category: research solved | AMS: 16
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.SemiringMaxIdeals

theorem exists_semiring_unique_left_maximal_not_unique_right_maximal :
    ∃ (R : Type) (_ : Semiring R), (∃! I : Ideal R, I.IsMaximal) ∧
      ∃ I J : Ideal Rᵐᵒᵖ, I.IsMaximal ∧ J.IsMaximal ∧ I ≠ J := by
  sorry

end FcSolvedAlgAnal.SemiringMaxIdeals
