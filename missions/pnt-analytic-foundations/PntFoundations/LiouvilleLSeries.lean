import PntFoundations.Spec
import PntFoundations.LiouvilleMult

open scoped LSeries.notation

namespace PntFoundations

/-- Open `sorry` from `PrimeNumberTheoremAnd/IwaniecKowalskiCh1.lean:1802`:
The Dirichlet series of the Liouville function is `ζ(2s) / ζ(s)` for `Re(s) > 1`. -/
lemma LSeries_liouville_eq {s : ℂ} (hs : 1 < s.re) :
    LSeries ↗liouville s = riemannZeta (2 * s) / riemannZeta s := by
  sorry

end PntFoundations
