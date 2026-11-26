/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/599.lean#L47-L56
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos599Menger

open SimpleGraph

theorem erdos_599 :
    ∀ (V : Type) (G : SimpleGraph V) (A B : Set V),
      Disjoint A B → G.IsIndepSet A → G.IsIndepSet B →
      ∃ (ι : Type) (a b : ι → V) (p : ∀ i, G.Walk (a i) (b i)) (S : Set V),
        (∀ i, a i ∈ A) ∧ (∀ i, b i ∈ B) ∧ (∀ i, (p i).IsPath) ∧
        (Pairwise fun i j => Disjoint {v | v ∈ (p i).support} {v | v ∈ (p j).support}) ∧
        S ⊆ {v | ∃ i, v ∈ (p i).support} ∧
        (∀ i, ∃! v, v ∈ S ∧ v ∈ (p i).support) ∧
        (∀ a' ∈ A, ∀ b' ∈ B, ∀ q : G.Walk a' b', q.IsPath → ∃ v ∈ q.support, v ∈ S) := by
  sorry

end FcSolvedComb.Erdos599Menger
