import VerinaAlgorithms.Spec

namespace VerinaAdv73

theorem smallestMissing_spec_satisfied (l: List Nat) (h_precond : smallestMissing_precond (l)) :
    smallestMissing_postcond (l) (smallestMissing (l) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv73
