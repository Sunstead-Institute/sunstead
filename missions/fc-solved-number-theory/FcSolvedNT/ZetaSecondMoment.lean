/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Paper/RiemannZetaMoments.lean#L77-L78
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.ZetaSecondMoment

open Complex Filter Real
open scoped Asymptotics Nat

theorem moment_isEquiv₁ : moment 1 ~[atTop] fun T ↦ T.log := by
  sorry

end FcSolvedNT.ZetaSecondMoment
