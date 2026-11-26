/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/OEIS/117545.lean#L117-L119
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.OeisA117545

theorem conjecture (n : ℕ) (hn : 0 < n) :
    ∃ k > 0, ((Polynomial.cyclotomic k ℤ).eval (n : ℤ)).natAbs.Prime := by
  sorry

end FcOpenOeisClassics.OeisA117545
