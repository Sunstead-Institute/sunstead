/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1057.lean#L95-L97
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.Erdos1057AGP

open Nat Real Filter Set
open scoped Topology Asymptotics

theorem erdos_1057.variants.agp_lower_bound :
    ∀ᶠ x in atTop, carmichaelCounting x > x ^ (2 / 7 : ℝ) := by
  sorry

end FcSolvedNT.Erdos1057AGP
