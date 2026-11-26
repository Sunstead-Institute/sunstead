/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/245.lean#L46-L52
Upstream category: research solved | AMS: 5, 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos245Sumset

open Filter Set
open scoped Pointwise Topology

theorem erdos_245 :
    ∀ (A : Set ℕ), A.Infinite →
      atTop.Tendsto (fun N ↦ (A ∩ Icc 1 ⌊N⌋₊ |>.ncard : ℝ) / N) (𝓝 0) →
      3 ≤ atTop.limsup
        fun N : ℝ ↦ ((A + A) ∩ Icc 1 ⌊N⌋₊ |>.ncard : EReal)
          / (A ∩ Icc 1 ⌊N⌋₊).ncard := by
  sorry

end FcSolvedComb.Erdos245Sumset
