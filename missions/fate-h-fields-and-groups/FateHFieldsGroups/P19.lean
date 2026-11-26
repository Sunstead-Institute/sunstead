import FateHFieldsGroups.Spec

theorem exists_subgroup_alternatingGroup_mulEquiv {G : Type} [Group G] [Finite G] :
    ∃ (n : ℕ) (H : Subgroup (alternatingGroup (Fin n))), Nonempty (G ≃* H) := by
  sorry
