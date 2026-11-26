/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/915.lean#L81-L86
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos915Paths

open SimpleGraph

theorem erdos_915.variants.edge_disjoint :
    ∀ m n : ℕ, 2 ≤ m → 1 ≤ n → ∀ (V : Type) [Fintype V] (G : SimpleGraph V),
      Fintype.card V = 1 + n * (m - 1) → G.edgeSet.ncard = 1 + n * m.choose 2 →
        ∃ u v : V, u ≠ v ∧ ∃ P : Finset (G.Walk u v), P.card = m ∧ (∀ p ∈ P, p.IsPath) ∧
          (P : Set (G.Walk u v)).Pairwise fun p q => List.Disjoint p.edges q.edges := by
  sorry

end FcSolvedComb.Erdos915Paths
