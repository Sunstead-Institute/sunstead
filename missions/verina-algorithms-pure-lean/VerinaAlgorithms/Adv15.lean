import VerinaAlgorithms.Spec

namespace VerinaAdv15

theorem increasingTriplet_spec_satisfied (nums: List Int) (h_precond : increasingTriplet_precond (nums)) :
    increasingTriplet_postcond (nums) (increasingTriplet (nums) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv15
