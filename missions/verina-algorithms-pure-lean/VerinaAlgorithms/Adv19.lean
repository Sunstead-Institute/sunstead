import VerinaAlgorithms.Spec

namespace VerinaAdv19

theorem isCleanPalindrome_spec_satisfied (s: String) (h_precond : isCleanPalindrome_precond (s)) :
    isCleanPalindrome_postcond (s) (isCleanPalindrome (s) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv19
