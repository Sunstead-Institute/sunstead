import FateHFieldsGroups.Spec

theorem center_eq_commutator_of_pow_three_eq_card {G : Type} [Group G] {p : ℕ} [hp : Fact p.Prime]
    (hG : p ^ 3 = Nat.card G) (h : ∃ x y : G, x * y ≠ y * x) :
    Subgroup.center G = commutator G := by
  sorry
