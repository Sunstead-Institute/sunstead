/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/88.lean#L67-L72
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos88McKay

open Filter

theorem erdos_88.variants.erdos_mckay :
    ∀ ε > (0 : ℝ), ∃ δ > (0 : ℝ), ∀ n : ℕ, ∀ G : SimpleGraph (Fin n),
      (G.cliqueNum : ℝ) < ε * Real.log n → (G.indepNum : ℝ) < ε * Real.log n →
        ∀ m : ℕ, (m : ℝ) ≤ δ * Real.log n ^ 2 →
          ∃ S : Finset (Fin n), (G.induce (S : Set (Fin n))).edgeSet.ncard = m := by
  sorry

end FcSolvedComb.Erdos88McKay
