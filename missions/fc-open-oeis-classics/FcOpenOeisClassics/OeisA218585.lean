/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/218585.lean#L85-L87
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA218585

theorem conjecture_2 (n : ℕ) (hn : 12 < n) :
    ∃ x : ℕ, 0 < x ∧ 3 * x < n ∧ Nat.Prime (n * x + (n - x) ^ 2) := by
  sorry

end FcOpenOeisClassics.OeisA218585
