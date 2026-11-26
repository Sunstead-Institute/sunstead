import FateHFieldsGroups.Spec

open Polynomial

theorem isSolvable_X_pow_six_add_gal {a : ℤ} (ha : a > 0) : IsSolvable
    (X ^ 6 + C (3 * a : ℚ) * X ^ 4 + C 3 * X ^ 3 + C (3 * a : ℚ) * X ^ 2 + C 1 : ℚ[X]).Gal:= by
  sorry
