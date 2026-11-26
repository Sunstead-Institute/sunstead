/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/931.lean#L75-L79
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos931PrimeFac

theorem erdos_931.variants.exists_prime (k₁ k₂ n₁ n₂ : ℕ) (h₁ : k₂ ≤ k₁) (h₂ : 3 ≤ k₂)
    (h₃ : n₁ + k₁ ≤ n₂) (h₄ : (∏ i ∈ Finset.Icc 1 k₁, (n₁ + i)).primeFactors =
      (∏ j ∈ Finset.Icc 1 k₂, (n₂ + j)).primeFactors) :
    ∃ (p : ℕ), p.Prime ∧ n₁ ≤ p ∧ p ≤ n₂ := by
  sorry

end FcOpenErdosNT.Erdos931PrimeFac
