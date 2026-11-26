import VerinaAlgorithms.Spec

namespace VerinaAdv24

theorem lengthOfLIS_spec_satisfied (nums: List Int) (h_precond : lengthOfLIS_precond (nums)) :
    lengthOfLIS_postcond (nums) (lengthOfLIS (nums) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv24
