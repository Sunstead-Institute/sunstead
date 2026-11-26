import FateXDimGeom.Spec

namespace Problem64

open MvPolynomial

theorem homogeneous_coordinate_ring_not_isCohenMacaulayRing (k : Type) [Field k] :
    ¬ IsCohenMacaulayRing (Algebra.adjoin k ({(X 0) ^ 4, (X 0) ^ 3 * X 1,
      X 0 * (X 1) ^ 3, (X 1) ^ 4} : Set (MvPolynomial (Fin 2) k))) := by
  sorry

end Problem64
