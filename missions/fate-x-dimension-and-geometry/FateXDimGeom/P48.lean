import FateXDimGeom.Spec

namespace Problem48

theorem isAbsolutelyFlat_iff_principal_ideal_idempotent (R : Type) [CommRing R] :
    IsAbsolutelyFlat R ↔ (∀ I : Ideal R, I.IsPrincipal → I ^ 2 = I) := by
  sorry

end Problem48
