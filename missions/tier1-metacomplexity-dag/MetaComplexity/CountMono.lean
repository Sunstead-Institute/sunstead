import MetaComplexity.Spec

namespace MetaComplexity

/-- TODO (Task: count_mono):
Prove monotonicity of `countFin`: if `P x = true → Q x = true` for all `x : Fin n`,
then `countFin n P ≤ countFin n Q`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem count_le_of_imp {n : Nat} {P Q : Fin n → Bool}
    (h : ∀ x : Fin n, P x = true → Q x = true) :
    countFin n P ≤ countFin n Q := by
  sorry

end MetaComplexity
