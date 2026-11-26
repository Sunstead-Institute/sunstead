/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/494.lean#L156-L159
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos494ProdMultiset

open Filter

theorem erdos_494.variants.product :
    ∃ (A B : Finset ℂ), 3 < A.card ∧ A.card = B.card ∧ (0 : ℂ) ∉ A ∧ (0 : ℂ) ∉ B ∧
      prodMultiset A 3 = prodMultiset B 3 ∧ A ≠ B := by
  sorry

end FcSolvedComb.Erdos494ProdMultiset
