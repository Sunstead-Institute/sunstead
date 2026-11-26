import FateHFieldsGroups.Spec

open Polynomial

theorem eval₂_algebraMap_ne_two_pow_one_dvd_four {n : ℕ} (hn : 1 ≤ n) (f : ℚ[X]) (ξ : ℂˣ)
    (h : ξ ∈ rootsOfUnity n ℂ) : f.eval₂ (algebraMap ℚ ℂ) ξ ≠ (2 : ℂ) ^ ((1 : ℂ) / 4) := by
  sorry
