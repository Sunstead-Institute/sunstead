import FateHFieldsGroups.Spec

theorem exists_index_two_of_sylow_two_isCyclic {G : Type} [Group G] [Finite G] (P : Sylow 2 G)
    (h1 : P.toSubgroup ≠ ⊥) [IsCyclic P] : ∃ H : Subgroup G, H.index = 2 := by
  sorry
