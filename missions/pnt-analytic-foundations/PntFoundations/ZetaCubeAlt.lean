import PntFoundations.Spec

open Finset PntFoundations

namespace PntFoundations

/-- Open `sorry` from `PrimeNumberTheoremAnd/IwaniecKowalskiCh1.lean:869` (IK between (1.30) and (1.31)):
`ζ(s)^3 = ∑_n (∑_{d^2 m = n} τ(m^2)) n^{-s}` for `Re(s) > 1`. -/
lemma zeta_pow_three_eq_alt (s : ℂ) (hs : 1 < s.re) :
    riemannZeta s ^ 3 =
    LSeries (fun n ↦
      ∑ dm ∈ n.divisors ×ˢ n.divisors with dm.1 ^ 2 * dm.2 = n, τ (dm.2 ^ 2)) s := by
  sorry

end PntFoundations
