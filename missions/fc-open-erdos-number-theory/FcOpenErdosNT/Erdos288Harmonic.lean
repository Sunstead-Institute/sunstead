/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/288.lean#L63-L67
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos288Harmonic

theorem erdos_288.variants.exists_k_gt_2 :
    ∃ k > 2, Set.Finite { I : Fin k → ℕ+ × ℕ+ |
      ∀ j, (I j).1 ≤ (I j).2 ∧
        ∃ n : ℕ+, (∑ j : Fin k, ∑ nⱼ ∈ Set.Icc (I j).1 (I j).2, (nⱼ⁻¹ : ℚ)) = n } := by
  sorry

end FcOpenErdosNT.Erdos288Harmonic
