import VerinaAlgorithms.Spec

namespace VerinaAdv48

theorem mergeSort_spec_satisfied (list: List Int) (h_precond : mergeSort_precond (list)) :
    mergeSort_postcond (list) (mergeSort (list) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv48
