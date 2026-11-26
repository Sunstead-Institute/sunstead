import VerinaAlgorithms.Spec

namespace VerinaAdv72

theorem singleDigitPrimeFactor_spec_satisfied (n: Nat) (h_precond : singleDigitPrimeFactor_precond (n)) :
    singleDigitPrimeFactor_postcond (n) (singleDigitPrimeFactor (n) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv72
