import VerinaAlgorithms.Spec

namespace VerinaAdv47

theorem mergeIntervals_spec_satisfied (intervals: List (Prod Int Int)) (h_precond : mergeIntervals_precond (intervals)) :
    mergeIntervals_postcond (intervals) (mergeIntervals (intervals) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv47
