/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/695.lean#L39-L45
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos695PrimeChain

open Filter Finset Real

theorem erdos_695 :
    ∀ {q : ℕ → ℕ},
      StrictMono q →
      (∀ i, (q i).Prime) →
      (∀ i, q (i + 1) % q i = 1) →
      Tendsto (fun k => (q k : ℝ) ^ (1 / k : ℝ)) atTop atTop := by
  sorry

end FcOpenErdosNT.Erdos695PrimeChain
