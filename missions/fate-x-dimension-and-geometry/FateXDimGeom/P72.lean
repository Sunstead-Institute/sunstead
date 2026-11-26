import FateXDimGeom.Spec

namespace Problem72

open TensorProduct

theorem isCohenMacaulay_extendScalars_over_mvPolynomial_of_isCohenMacaulay
    (R : Type) [CommRing R] (M : Type) [AddCommGroup M] [Module R M]
    [IsNoetherianRing R] [Module.IsCohenMacaulay R M] (n : ℕ) :
    Module.IsCohenMacaulay (MvPolynomial (Fin n) R) ((MvPolynomial (Fin n) R) ⊗[R] M) := by
  sorry

end Problem72
