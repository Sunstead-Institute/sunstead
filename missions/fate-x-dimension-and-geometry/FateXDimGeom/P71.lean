import FateXDimGeom.Spec

namespace Problem71

theorem fixedPoints_isCohenMacaulayRing {R : Type} [CommRing R] (k : Type) [Field k]
    [CharZero k] [Algebra k R] [IsNoetherianRing R] [IsCohenMacaulayRing R]
    (G : Subgroup (R ≃ₐ[k] R)) [Finite G] :
    IsCohenMacaulayRing (FixedPoints.subalgebra k R G) := by
  sorry

end Problem71
