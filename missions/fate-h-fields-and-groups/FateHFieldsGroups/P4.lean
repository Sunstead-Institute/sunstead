import FateHFieldsGroups.Spec

theorem nonempty_mulEquiv_zMod_prod_zMod {p : ℕ} [Fact p.Prime] {P : Type} [Group P] (hp : Nat.card P = p ^ 3)
    (h : ∃ (a b : P), a * b ≠ b * a) : Nat.card (Subgroup.center P) = p ∧
    Nonempty ((P ⧸ Subgroup.center P) ≃* Multiplicative ((ZMod p) × (ZMod p))) := by
  sorry
