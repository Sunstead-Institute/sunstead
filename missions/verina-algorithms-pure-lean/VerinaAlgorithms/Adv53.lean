import VerinaAlgorithms.Spec

namespace VerinaAdv53

theorem minimumRightShifts_spec_satisfied (nums: List Int) (h_precond : minimumRightShifts_precond (nums)) :
    minimumRightShifts_postcond (nums) (minimumRightShifts (nums) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv53
