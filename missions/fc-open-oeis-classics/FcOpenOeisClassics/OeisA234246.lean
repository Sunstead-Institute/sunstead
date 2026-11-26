/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/234246.lean#L80-L82
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA234246

open ArithmeticFunction
open scoped ArithmeticFunction.sigma

theorem conjecture_3 (n : ℕ) (hn : 60 ≤ n) :
    ∃ k, 0 < k ∧ k < n ∧ IsSquare (k + (n - k).totient) := by
  sorry

end FcOpenOeisClassics.OeisA234246
