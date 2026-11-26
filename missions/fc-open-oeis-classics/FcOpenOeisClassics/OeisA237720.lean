/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/237720.lean#L81-L83
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA237720

theorem conjecture_3 (n : ℕ) (hn : 2 < n) :
    ∃ p : ℕ, p.Prime ∧ p < n ∧ (Nat.sqrt (n + p)).Prime := by
  sorry

end FcOpenOeisClassics.OeisA237720
