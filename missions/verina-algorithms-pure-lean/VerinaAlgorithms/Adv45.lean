import VerinaAlgorithms.Spec

namespace VerinaAdv45

theorem maxSubarraySum_spec_satisfied (xs: List Int) (h_precond : maxSubarraySum_precond (xs)) :
    maxSubarraySum_postcond (xs) (maxSubarraySum (xs) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv45
