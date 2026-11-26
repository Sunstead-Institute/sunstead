/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/723.lean#L54-L56
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos723ProjPlane

open Configuration

theorem erdos_723.variants.leq_11 {P L : Type} [Membership P L] [Fintype P] [Fintype L] :
    ∀ pp : ProjectivePlane P L, pp.order ≤ 11 → IsPrimePow pp.order := by
  sorry

end FcSolvedComb.Erdos723ProjPlane
