import PntFoundations.Spec
import PntFoundations.WienerDecay2

open Real MeasureTheory FourierTransform

namespace PntFoundations

/-- Open `sorry` from `PrimeNumberTheoremAnd/Wiener.lean:350` (PNT+ Discussion #563):
If `ψ : ℝ → ℂ` is integrable, absolutely continuous, and `deriv ψ` is of bounded variation,
then `‖𝓕 ψ u‖ ≤ ‖ψ'‖_TV / (2 π ‖u‖)^2` for `u ≠ 0`. -/
theorem prelim_decay_3 (ψ : ℝ → ℂ) (hψ : Integrable ψ)
    (habscont : AbsolutelyContinuous ψ)
    (hvar : BoundedVariationOn (deriv ψ) Set.univ) (u : ℝ) (hu : u ≠ 0) :
    ‖𝓕 (ψ : ℝ → ℂ) u‖ ≤ (eVariationOn (deriv ψ) Set.univ).toReal / (2 * π * ‖u‖) ^ 2 := by
  sorry

end PntFoundations
