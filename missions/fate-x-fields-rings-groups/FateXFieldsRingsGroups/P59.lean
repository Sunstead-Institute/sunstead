import FateXFieldsRingsGroups.Spec

namespace Problem59

theorem exists_unique_valuation_eq (α : ℝ) (h_pos : α > 0) (h_irr : Irrational α)
    (k : Type) [Field k] : ∃! (v : AddValuation (FractionRing (MvPolynomial (Fin 2) k)) (WithTop ℝ)),
    ∀ (f : MvPolynomial (Fin 2) k), v (algebraMap _ _ f) = Finset.inf (Finset.image (fun s ↦ ((s 0 + α * s 1) : WithTop ℝ)) f.support) id := by
  sorry

end Problem59
