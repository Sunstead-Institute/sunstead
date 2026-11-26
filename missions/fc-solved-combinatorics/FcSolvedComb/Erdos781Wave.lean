/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/781.lean#L77-L79
Upstream category: research solved | AMS: 5, 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos781Wave

open Filter Asymptotics

theorem erdos_781.variants.brown_erdos_freedman (k : ℕ) (hk : 1 ≤ k) :
    k ^ 2 - k + 1 ≤ f k ∧ (f k : ℚ) ≤ (k ^ 3 - 4 * k + 9) / 3 := by
  sorry

end FcSolvedComb.Erdos781Wave
