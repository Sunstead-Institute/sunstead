/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/ClassNumberProblem.lean#L50-L53
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.ImaginaryClassNumberOne

open Polynomial

theorem class_number_problem.variants.imaginary :
    { d : ℤ | Squarefree d ∧ d < 0 ∧ IsClassNumberOne d } =
    {-1, -2, -3, -7, -11, -19, -43, -67, -163} := by
  sorry

end FcSolvedNT.ImaginaryClassNumberOne
