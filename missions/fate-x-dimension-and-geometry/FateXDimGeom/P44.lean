import FateXDimGeom.Spec

namespace Problem44

open MvPolynomial

theorem quot_x2_sub_y2_y2_sub_z2_xy_yz_zx_not_global_complete_intersection (k : Type) [Field k] :
    ¬ IsGlobalCompleteIntersection k (MvPolynomial (Fin 3) k ⧸ Ideal.span
    ({(X 0)^ 2 - (X 1)^2, (X 1)^2 - (X 2)^2, (X 0) * (X 1), (X 1) * (X 2), (X 2) * (X 0)} :
    Set (MvPolynomial (Fin 3) k))) := by
  sorry

end Problem44
