import VerinaAlgorithms.Spec

namespace VerinaAdv12

theorem firstDuplicate_spec_satisfied (lst: List Int) (h_precond : firstDuplicate_precond (lst)) :
    firstDuplicate_postcond (lst) (firstDuplicate (lst) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv12
