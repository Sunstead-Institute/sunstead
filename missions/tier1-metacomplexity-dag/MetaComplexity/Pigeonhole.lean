import MetaComplexity.Spec

namespace MetaComplexity

/-- TODO (Task: pigeonhole_fin):
Prove the finite pigeonhole principle: no injection exists from `Fin n` into `Fin m` when `m < n`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  sorry

end MetaComplexity
