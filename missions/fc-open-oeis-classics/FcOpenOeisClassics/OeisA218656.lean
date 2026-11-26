/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/218656.lean#L122-L124
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA218656

theorem conjecture_2 (n : ℕ) (hn : 1 ≤ n) :
    ∃ x : ℕ, 1 ≤ x ∧ x ≤ n ∧ Nat.Prime (x ^ 2 + (2 * n + 1 - x) ^ 2) := by
  sorry

end FcOpenOeisClassics.OeisA218656
