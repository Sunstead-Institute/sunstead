import FateHFieldsGroups.Spec

open MatrixGroups

theorem exists_sl_quot_center_monoidHom_alternatingGroup :
    ∃ φ : SL(2,ZMod 3) ⧸ Subgroup.center SL(2,ZMod 3) →* alternatingGroup (Fin 4),
    Function.Injective φ := by
  sorry
