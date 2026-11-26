import VerinaAlgorithms.Spec

namespace VerinaAdv1

theorem FindSingleNumber_spec_satisfied (nums: List Int) (h_precond : FindSingleNumber_precond (nums)) :
    FindSingleNumber_postcond (nums) (FindSingleNumber (nums) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv1
