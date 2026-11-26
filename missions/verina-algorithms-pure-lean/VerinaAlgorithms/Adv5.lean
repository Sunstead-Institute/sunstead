import VerinaAlgorithms.Spec

namespace VerinaAdv5

theorem addTwoNumbers_spec_satisfied (l1: List Nat) (l2: List Nat) (h_precond : addTwoNumbers_precond (l1) (l2)) :
    addTwoNumbers_postcond (l1) (l2) (addTwoNumbers (l1) (l2) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv5
