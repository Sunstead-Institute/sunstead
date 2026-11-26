/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/ErdosUlamProblem.lean#L97-L108
Upstream category: research solved | AMS: 51, 52
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.ErdosUlamSolymosi

open EuclideanSpace

theorem erdos_ulam_problem.variants.solymosi_de_zeeuw
    (S : Set (EuclideanSpace ℝ (Fin 2))) (hd : PairwiseRationalDistances S)
    (hstructure :
      (∃ a b : EuclideanSpace ℝ (Fin 2), a ≠ b ∧
        {x ∈ S | ∃ t : ℝ, x = a + t • (b - a)}.Infinite) ∨
      (∃ (c : EuclideanSpace ℝ (Fin 2)) (ρ : ℝ), 0 < ρ ∧
        {x ∈ S | dist x c = ρ}.Infinite)) :
    (∃ a b : EuclideanSpace ℝ (Fin 2), a ≠ b ∧
        {x ∈ S | ¬ ∃ t : ℝ, x = a + t • (b - a)}.Finite) ∨
    (∃ (c : EuclideanSpace ℝ (Fin 2)) (ρ : ℝ), 0 < ρ ∧
        {x ∈ S | dist x c ≠ ρ}.Finite) := by
  sorry

end FcSolvedAlgAnal.ErdosUlamSolymosi
