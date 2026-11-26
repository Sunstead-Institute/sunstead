import VerinaAlgorithms.Spec

namespace VerinaAdv39

theorem maxOfList_spec_satisfied (lst: List Nat) (h_precond : maxOfList_precond (lst)) :
    maxOfList_postcond (lst) (maxOfList (lst) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv39
