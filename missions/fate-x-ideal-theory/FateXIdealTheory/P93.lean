import FateXIdealTheory.Spec

namespace Problem93

theorem exists_integral_finiteType_not_finiteDimensional : ∃ (k A : Type) (_ : Field k)
    (_ : Ring A) (_ : Algebra k A),
    Algebra.IsIntegral k A ∧ Algebra.FiniteType k A ∧ ¬ FiniteDimensional k A := by
  sorry

end Problem93
