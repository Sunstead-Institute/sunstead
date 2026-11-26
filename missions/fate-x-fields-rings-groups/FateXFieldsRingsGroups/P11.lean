import FateXFieldsRingsGroups.Spec

namespace Problem11

theorem not_isomorphic_euclideanDomain : IsEmpty <| EuclideanNormNat (((MvPolynomial (Fin 2) ℝ) ⧸
    Ideal.span {(.X 0 ^ 2 + .X 1 ^ 2 + .C 1: MvPolynomial (Fin 2) ℝ)})) := by
  sorry

end Problem11
