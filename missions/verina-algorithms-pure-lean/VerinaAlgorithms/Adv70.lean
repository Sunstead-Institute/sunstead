import VerinaAlgorithms.Spec

namespace VerinaAdv70

theorem semiOrderedPermutation_spec_satisfied (nums: List Int) (h_precond : semiOrderedPermutation_precond (nums)) :
    semiOrderedPermutation_postcond (nums) (semiOrderedPermutation (nums) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv70
