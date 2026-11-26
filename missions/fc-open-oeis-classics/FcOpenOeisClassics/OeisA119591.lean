/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/119591.lean#L131-L132
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA119591

theorem conjecture (n : ℕ) (hn : 2 ≤ n) : ∃ k > 0, (2 * n ^ k - 1).Prime := by
  sorry

end FcOpenOeisClassics.OeisA119591
