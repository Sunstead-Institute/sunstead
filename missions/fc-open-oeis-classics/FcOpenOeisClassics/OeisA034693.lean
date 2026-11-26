/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/34693.lean#L61-L62
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA034693

open Filter

theorem exists_k {n : ℕ} (hn : 1 < n) : ∃ k < n, (n * k + 1).Prime := by
  sorry

end FcOpenOeisClassics.OeisA034693
