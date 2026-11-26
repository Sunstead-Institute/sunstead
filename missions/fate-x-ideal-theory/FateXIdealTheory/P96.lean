import FateXIdealTheory.Spec

namespace Problem96

open RatFunc

theorem ratFunc_square_is_poly_of_orbit_contain_infinite_integer
    {f : RatFunc ℚ} (hf : f.num.natDegree ≥ 2 ∨ f.denom.natDegree ≥ 2) {a : ℚ}
    (h : ∀ n : ℕ, (f.eval (RingHom.id ℚ))^[n] a ≠ 0) -- exclude the case that the `denom` is zero
    (ha : {m : ℤ | ∃ n : ℕ, m = (f.eval (RingHom.id ℚ))^[n] a}.Infinite) :
    ∃ g : Polynomial ℚ, g = f.eval C f := by
  sorry

end Problem96
