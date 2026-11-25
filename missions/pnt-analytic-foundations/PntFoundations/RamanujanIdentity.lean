import PntFoundations.Spec

open PntFoundations

namespace PntFoundations

/-- Open `sorry` from `PrimeNumberTheoremAnd/IwaniecKowalskiCh1.lean:647` (Ramanujan / IK (1.28)):
`ζ(s) ζ(s - α) ζ(s - β) ζ(s - α - β) = ζ(2s - α - β) * L(σ_α · σ_β, s)`. -/
theorem zeta_mul_zeta_mul_zeta_mul_zeta_eq (α β s : ℂ) (h1 : 1 < s.re) (h2 : 1 < (s - α).re)
    (h3 : 1 < (s - β).re) (h4 : 1 < (s - α - β).re) :
    riemannZeta s * riemannZeta (s - α) * riemannZeta (s - β) * riemannZeta (s - α - β) =
      riemannZeta (2 * s - α - β) *
      LSeries (fun n ↦ σᴿ α n * σᴿ β n) s := by
  sorry

end PntFoundations
