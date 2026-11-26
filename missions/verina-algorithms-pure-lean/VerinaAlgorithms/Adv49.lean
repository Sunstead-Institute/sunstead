import VerinaAlgorithms.Spec

namespace VerinaAdv49

theorem mergeSortedLists_spec_satisfied (arr1: List Int) (arr2: List Int) (h_precond : mergeSortedLists_precond (arr1) (arr2)) :
    mergeSortedLists_postcond (arr1) (arr2) (mergeSortedLists (arr1) (arr2) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv49
