import MetaComplexity.Spec
import MetaComplexity.CountMono

namespace MetaComplexity

/-- TODO (Task: union_bound_fin):
Prove the finite counting union bound: for any boolean predicates `P, Q : Fin n → Bool`,
`countFin n (fun x => P x || Q x) ≤ countFin n P + countFin n Q`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem count_or_le_add (n : Nat) (P Q : Fin n → Bool) :
    countFin n (fun x => P x || Q x) ≤ countFin n P + countFin n Q := by
  sorry

end MetaComplexity
