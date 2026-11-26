import FateXFieldsRingsGroups.Spec

namespace Problem54

theorem not_zero_divisor_of_hausdorff_of_der_eq_one (A : Type) [CommRing A] [Algebra ℚ A]
    (x : A) (D : Derivation ℤ A A) (h_dx : D x = 1) (h_hausdorff : IsHausdorff (Ideal.span {x}) A) :
    x ∈ nonZeroDivisors A := by
  sorry

end Problem54
