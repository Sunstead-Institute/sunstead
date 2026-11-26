import FateXIdealTheory.Spec

namespace Problem95

open Polynomial Bivariate

theorem p_map_ne_p (p : ℂ[X]) (h : p.natDegree > 1) {a : ℂ} (ha : a ≠ 0)
    (𝔭 : Ideal ℂ[X][Y]) (h𝔭 : 𝔭.IsPrime) (h : 𝔭.height = 1) :
    𝔭.map (f a p) ≠ 𝔭 := by
  sorry

end Problem95
