import VerinaAlgorithms.Spec

namespace VerinaAdv14

theorem ifPowerOfFour_spec_satisfied (n: Nat) (h_precond : ifPowerOfFour_precond (n)) :
    ifPowerOfFour_postcond (n) (ifPowerOfFour (n) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv14
