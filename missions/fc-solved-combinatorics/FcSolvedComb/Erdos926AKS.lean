/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/926.lean#L88-L90
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos926AKS

open Filter Asymptotics SimpleGraph

theorem erdos_926.variants.aks : ∃ C : ℝ, ∀ k : ℕ, 4 ≤ k → ∀ n : ℕ,
    (extremalNumber n (H k) : ℝ) ≤ C * k * (n : ℝ) ^ (3 / 2 : ℝ) := by
  sorry

end FcSolvedComb.Erdos926AKS
