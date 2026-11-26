/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/69.lean#L40-L41
Upstream category: textbook | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.Erdos69OmegaIrrational

open scoped ArithmeticFunction.omega

theorem erdos_69 : Irrational <| ∑' n, ω (n + 2) / 2 ^ (n + 2) := by
  sorry

end FcSolvedNT.Erdos69OmegaIrrational
