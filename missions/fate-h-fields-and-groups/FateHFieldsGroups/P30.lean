import FateHFieldsGroups.Spec

open Polynomial
open scoped IntermediateField

theorem nonempty_ringEquiv_adjoin_pow_two_add_seven {E : Type} [Field E] [Algebra ℚ E]
    [IsCyclotomicExtension {7} ℚ E] (ζ : E)
    (h : IsPrimitiveRoot ζ 7) (β : E) (hb : β = ζ + ζ ^ 2 + ζ ^ 4) :
    Nonempty (ℚ⟮β⟯ ≃+* AdjoinRoot (X ^ 2 + 7 : ℚ[X])) := by
  sorry
