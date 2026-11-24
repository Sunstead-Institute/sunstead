import MetaComplexity.Spec
import MetaComplexity.Pigeonhole

namespace MetaComplexity

/-- TODO (Task: non_surjective_decoder):
Prove that for any `k < n` and any deterministic decoder `U : Fin (2 ^ k) → Fin (2 ^ n)`,
there exists an incompressible string `x : Fin (2 ^ n)` missed by every short program `p`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem exists_incompressible_string {n k : Nat} (hk : k < n)
    (U : Fin (2 ^ k) → Fin (2 ^ n)) :
    ∃ x : Fin (2 ^ n), ∀ p : Fin (2 ^ k), U p ≠ x := by
  sorry

end MetaComplexity
