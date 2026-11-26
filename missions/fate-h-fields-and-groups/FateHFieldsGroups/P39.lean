import FateHFieldsGroups.Spec

open Polynomial

theorem exists_isPrimitiveRoot_and_adjoin_eq_top :
    letI : Fact (Nat.Prime 7) := by decide
    ∃ ζ : (X ^ 15 - 2 : (ZMod 7)[X]).SplittingField, IsPrimitiveRoot ζ 45 ∧
    IntermediateField.adjoin (ZMod 7) {ζ} = ⊤ := by
  sorry
