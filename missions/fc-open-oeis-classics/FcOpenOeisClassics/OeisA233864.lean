/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/233864.lean#L85-L87
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA233864

open ArithmeticFunction
open scoped ArithmeticFunction.sigma

theorem conjecture_2 (n : ℕ) (hn : 0 < n) :
    ∃ k, 0 < k ∧ k < 2 * n ∧ Nat.Prime (2 * n + σ 1 k) := by
  sorry

end FcOpenOeisClassics.OeisA233864
