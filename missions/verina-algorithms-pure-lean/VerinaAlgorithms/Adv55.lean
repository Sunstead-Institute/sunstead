import VerinaAlgorithms.Spec

namespace VerinaAdv55

theorem mostFrequent_spec_satisfied (xs: List Int) (h_precond : mostFrequent_precond (xs)) :
    mostFrequent_postcond (xs) (mostFrequent (xs) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv55
