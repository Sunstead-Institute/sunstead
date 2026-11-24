import MetaComplexity.Spec
import MetaComplexity.Pigeonhole

namespace MetaComplexity

/-- TODO (Task: bijection_card_eq):
Prove that any bijection (mutual inverse pair `f, g`) between `Fin n` and `Fin m`
implies `n = m`. Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem bij_card_eq {n m : Nat}
    (f : Fin n → Fin m) (g : Fin m → Fin n)
    (hfg : ∀ x, g (f x) = x) (hgf : ∀ y, f (g y) = y) : n = m := by
  sorry

end MetaComplexity
