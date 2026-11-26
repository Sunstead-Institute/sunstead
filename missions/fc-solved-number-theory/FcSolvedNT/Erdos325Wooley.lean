/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/325.lean#L65-L68
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.Erdos325Wooley

open Asymptotics Filter

theorem erdos_325.variants.wooley :
    (fun x : ℕ => (x : ℝ) ^ (0.91709477 : ℝ)) =O[atTop]
      (fun x => (cardIsSumThreePowerBelow 3 x : ℝ)) := by
  sorry

end FcSolvedNT.Erdos325Wooley
