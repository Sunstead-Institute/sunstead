/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/159829.lean#L111-L113
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA159829

theorem conjecture2 (k : ℕ) (hk : 3 ≤ k) :
    Set.Infinite {p : ℕ | ∃ n m : ℕ, 1 ≤ n ∧ 1 ≤ m ∧ p.Prime ∧ p = n ^ k + m ^ k + 1} := by
  sorry

end FcOpenOeisClassics.OeisA159829
