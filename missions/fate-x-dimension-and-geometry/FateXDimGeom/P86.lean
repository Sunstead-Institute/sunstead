import FateXDimGeom.Spec

namespace Problem86

theorem dimension_convex (A : Type) [CommRing A] :
    ringKrullDim (MvPolynomial (Fin 2) A) + ringKrullDim A ≤ 2 * ringKrullDim (Polynomial A) := by
  sorry

end Problem86
