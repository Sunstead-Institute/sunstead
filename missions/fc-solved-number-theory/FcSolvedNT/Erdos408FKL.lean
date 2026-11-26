/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/408.lean#L165-L169
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.Erdos408FKL

open Filter
open scoped Topology

theorem erdos_408.variants.ford_konyagin_luca (ε δ : ℝ) (hε : 0 < ε) (hδ : 0 < δ) :
    ∃ k : ℕ, ∀ᶠ x : ℝ in atTop, (1 - ε) * x ≤
      ((Finset.Icc 1 ⌊x⌋₊).filter fun n ↦
        ((Nat.totient^[k] n).maxPrimeFac : ℝ) ≤ x ^ δ).card := by
  sorry

end FcSolvedNT.Erdos408FKL
