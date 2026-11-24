import MetaComplexity.Spec

namespace MetaComplexity

/-- TODO (Task: count_complement_sum):
Prove that for any boolean predicate `P` on `Fin n`, the count of elements satisfying `P`
plus the count of elements satisfying `!P` equals `n`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem count_add_complement (n : Nat) (P : Fin n → Bool) :
    countFin n P + countFin n (fun x => !P x) = n := by
  sorry

end MetaComplexity
