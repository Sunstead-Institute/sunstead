import FateHFieldsGroups.Spec

open Polynomial

theorem cyclotomic_two_mul_eq_cyclotomic_comp_neg {n : ℕ} (hn : Odd n) (hn' : 1 < n) :
    Polynomial.cyclotomic (2 * n) ℚ = (Polynomial.cyclotomic n ℚ).comp (-X) := by
  sorry
