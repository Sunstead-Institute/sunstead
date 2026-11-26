import FateHFieldsGroups.Spec

open Polynomial

theorem not_irreducible_iff_finrank_lt {E E': Type} [Field E] [CharZero E] [Field E'] [Algebra E E'] {q : ℕ}
    [Fact q.Prime] {b : E} (hb : b ≠ 0) (not_pow : ∀ c : E, c ^ q ≠ b) {a : E'}
    (ha : a ^ q = algebraMap E E' b) (haE : ⊤ = IntermediateField.adjoin E {a}) :
    ¬ Irreducible (X ^ q - C b) ↔ Module.finrank E E' < q := by
  sorry
