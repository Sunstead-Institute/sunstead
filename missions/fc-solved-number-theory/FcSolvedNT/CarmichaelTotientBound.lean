/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/CarmichaelTotient.lean#L66-L68
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.CarmichaelTotientBound

open Nat

theorem carchimaelTotient_bound {n : ℕ} (hn : 0 < n) (hn' : n < 10 ^ (10 ^ 10)) :
    CarmichaelTotientFor n := by
  sorry

end FcSolvedNT.CarmichaelTotientBound
