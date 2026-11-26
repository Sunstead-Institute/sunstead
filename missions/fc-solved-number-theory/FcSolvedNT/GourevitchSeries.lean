/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Paper/Gourevitch.lean#L40-L43
Upstream category: research solved | AMS: 11, 33
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.GourevitchSeries

theorem gourevitch_series_identity :
    ∑' n : ℕ, ((1 + 14 * n + 76 * n ^ 2 + 168 * n ^ 3) / (2 ^ (20 * n)) : ℝ)
      * Nat.centralBinom n ^ 7 = 32 / (Real.pi ^ 3) := by
  sorry

end FcSolvedNT.GourevitchSeries
