import MetaComplexity.Spec
import MetaComplexity.IncompressibleDensity
import MetaComplexity.CountComplement

namespace MetaComplexity

/-- TODO (Task: exponential_incompressibility):
Prove the exponential `c`-bit incompressibility theorem:
for any `c ≤ n` and any decoder `U : Fin (2 ^ (n - c)) → Fin (2 ^ n)`,
1. At least `(2 ^ c - 1) * 2 ^ (n - c)` of the `2 ^ n` strings lie outside the image of `U`, and
2. At most `2 ^ (n - c)` strings lie inside the image of `U`.
Combine `count_not_in_image_ge` and `count_add_complement`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem exp_incompressible_bound {n c : Nat} (hc : c ≤ n)
    (U : Fin (2 ^ (n - c)) → Fin (2 ^ n)) :
    (2 ^ c - 1) * 2 ^ (n - c) ≤ countFin (2 ^ n) (fun x => !inImage U x) ∧
    countFin (2 ^ n) (inImage U) ≤ 2 ^ (n - c) := by
  sorry

end MetaComplexity
