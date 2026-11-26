/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/233566.lean#L69-L71
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA233566

theorem conjecture_2 (n : ℕ) (hn : 2 < n) :
    ∃ p < n, p.Prime ∧ Nat.Prime (p ^ 2 * (n - p).totient - 1) := by
  sorry

end FcOpenOeisClassics.OeisA233566
