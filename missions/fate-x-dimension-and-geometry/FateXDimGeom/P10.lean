import FateXDimGeom.Spec

namespace Problem10

theorem isPrincipalIdealRing_quot_X_pow_two_plus_Y_pow_two_plus_one :
    IsPrincipalIdealRing ((MvPolynomial (Fin 2) ℝ) ⧸
    Ideal.span {(.X 0 ^ 2 + .X 1 ^ 2 + .C 1 : (MvPolynomial (Fin 2) ℝ))}) := by
  sorry

end Problem10
