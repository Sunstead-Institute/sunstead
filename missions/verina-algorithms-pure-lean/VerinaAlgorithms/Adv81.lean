import VerinaAlgorithms.Spec

namespace VerinaAdv81

theorem uniqueSorted_spec_satisfied (arr: List Int) (h_precond : uniqueSorted_precond (arr)) :
    uniqueSorted_postcond (arr) (uniqueSorted (arr) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv81
