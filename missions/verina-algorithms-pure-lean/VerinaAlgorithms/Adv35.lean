import VerinaAlgorithms.Spec

namespace VerinaAdv35

theorem majorityElement_spec_satisfied (nums: List Int) (h_precond : majorityElement_precond (nums)) :
    majorityElement_postcond (nums) (majorityElement (nums) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv35
