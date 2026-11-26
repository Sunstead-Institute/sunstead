import FateXIdealTheory.Spec

namespace Problem77

theorem infinite_intermediate_primes (R : Type) [CommRing R] [IsNoetherianRing R] (P Q : Ideal R)
    (le : P ≤ Q) [P.IsPrime] [Q.IsPrime] (h d : ℕ) (lt : 1 < d) (ht1 : P.height = h)
    (ht2 : (Q.map (Ideal.Quotient.mk P)).height = d) :
    {P' : Ideal R | P ≤ P' ∧ P' ≤ Q ∧ P'.IsPrime ∧ P'.height = h + 1 ∧
      (Q.map (Ideal.Quotient.mk P')).height = d - 1}.Infinite := by
  sorry

end Problem77
