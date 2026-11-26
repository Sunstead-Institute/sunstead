/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1009.lean#L67-L72
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos1009Sauer

theorem erdos_1009.variants.sauer : ∀ r : ℕ, 1 ≤ r → ∃ G : SimpleGraph (Fin (2 * r + 4)),
    G.edgeSet.ncard = (2 * r + 4) ^ 2 / 4 + 2 * (2 * r + 4) - 6 ∧
      ∀ T : Finset (Finset (Fin (2 * r + 4))), (∀ t ∈ T, G.IsNClique 3 t) →
        (T : Set (Finset (Fin (2 * r + 4)))).Pairwise (fun s t => (s ∩ t).card ≤ 1) →
          T.card ≤ 2 * (2 * r + 4) - 7 := by
  sorry

end FcSolvedComb.Erdos1009Sauer
