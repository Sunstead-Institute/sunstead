import FateXIdealTheory.Spec

namespace Problem90

theorem not_finiteType_inf_algebraMap_range (k : Type) [Field k] :
    ∃ (n : ℕ) (K : IntermediateField k (FractionRing (MvPolynomial (Fin n) k))),
    ¬ Algebra.FiniteType k (K.toSubalgebra ⊓ (Algebra.algHom k (MvPolynomial (Fin n) k)
    (FractionRing (MvPolynomial (Fin n) k))).range :
    Subalgebra k (FractionRing (MvPolynomial (Fin n) k))) := by
  sorry

end Problem90
