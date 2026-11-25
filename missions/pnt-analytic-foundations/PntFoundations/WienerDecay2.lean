import PntFoundations.Spec

open Real MeasureTheory FourierTransform

namespace PntFoundations

/-- Open `sorry` from `PrimeNumberTheoremAnd/Wiener.lean:331` (PNT+ Discussion #562):
If `ψ : ℝ → ℂ` is integrable and of bounded variation, then
`‖𝓕 ψ u‖ ≤ ‖ψ‖_TV / (2 π ‖u‖)` for `u ≠ 0`. -/
theorem prelim_decay_2 (ψ : ℝ → ℂ) (hψ : Integrable ψ) (hvar : BoundedVariationOn ψ Set.univ)
    (u : ℝ) (hu : u ≠ 0) :
    ‖𝓕 (ψ : ℝ → ℂ) u‖ ≤ (eVariationOn ψ Set.univ).toReal / (2 * π * ‖u‖) := by
  sorry

end PntFoundations
