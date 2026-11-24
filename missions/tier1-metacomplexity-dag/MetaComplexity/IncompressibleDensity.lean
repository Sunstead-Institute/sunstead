import MetaComplexity.Spec
import MetaComplexity.NonSurjective
import MetaComplexity.BijectionCard

namespace MetaComplexity

/-- TODO (Task: incompressible_density):
Prove the quantitative incompressibility counting bound:
for any finite decoder `U : Fin m → Fin n`, at least `n - m` elements of `Fin n`
lie outside the image of `U` (giving >= 50% incompressible density when `m = 2^(L-1), n = 2^L`).
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem count_not_in_image_ge {m n : Nat} (U : Fin m → Fin n) :
    n - m ≤ countFin n (fun x => !inImage U x) := by
  sorry

end MetaComplexity
