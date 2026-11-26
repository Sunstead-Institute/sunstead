import VerinaAlgorithms.Spec

namespace VerinaAdv16

theorem insertionSort_spec_satisfied (xs: List Int) (h_precond : insertionSort_precond (xs)) :
    insertionSort_postcond (xs) (insertionSort (xs) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv16
