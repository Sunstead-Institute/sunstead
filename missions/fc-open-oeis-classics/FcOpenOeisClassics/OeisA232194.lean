/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/232194.lean#L102-L104
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA232194

theorem conjecture_6 (n : ℕ) (hn : n > 5) :
    ∃ p q : ℕ, 0 < q ∧ p + q = n ∧ p.Prime ∧ (n * q ^ 2 + 1).Prime := by
  sorry

end FcOpenOeisClassics.OeisA232194
