import VerinaAlgorithms.Spec

namespace VerinaAdv11

theorem findMajorityElement_spec_satisfied (lst: List Int) (h_precond : findMajorityElement_precond (lst)) :
    findMajorityElement_postcond (lst) (findMajorityElement (lst) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv11
