import VerinaAlgorithms.Spec

namespace VerinaAdv65

theorem reverseString_spec_satisfied (s: String) (h_precond : reverseString_precond (s)) :
    reverseString_postcond (s) (reverseString (s) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv65
