/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/DirichletDivisorProblem.lean#L88-L90
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.DivisorErrorHardy

open Filter Asymptotics Real

theorem divisor_error_hardy :
    ¬ (divisorError =o[atTop] fun x => x ^ ((1 : ℝ) / 4)) := by
  sorry

end FcSolvedNT.DivisorErrorHardy
