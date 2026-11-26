import VerinaAlgorithms.Spec

namespace VerinaAdv60

theorem partitionEvensOdds_spec_satisfied (nums: List Nat) (h_precond : partitionEvensOdds_precond (nums)) :
    partitionEvensOdds_postcond (nums) (partitionEvensOdds (nums) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv60
