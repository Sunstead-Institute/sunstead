import FateXFieldsRingsGroups.Spec

namespace Problem80

open MvPolynomial

theorem isCohenMacaulayRing_of_dimension_three (k : Type) [Field k] :
    IsCohenMacaulayRing (target_ring_aux k) ∧ (ringKrullDim (target_ring_aux k) = 3) := by
  sorry

end Problem80
