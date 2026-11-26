import VerinaAlgorithms.Spec

namespace VerinaAdv20

theorem isItEight_spec_satisfied (n: Int) (h_precond : isItEight_precond (n)) :
    isItEight_postcond (n) (isItEight (n) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv20
