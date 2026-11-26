/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1033.lean#L80-L83
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos1033Fan

open Filter Finset

theorem erdos_1033.variants.fan (n : ℕ) (G : SimpleGraph (Fin n)) [DecidableRel G.Adj]
    (hG : n ^ 2 < 4 * #G.edgeFinset) :
    ∃ t, G.IsNClique 3 t ∧ 21 * n ≤ 16 * ∑ v ∈ t, G.degree v := by
  sorry

end FcSolvedComb.Erdos1033Fan
