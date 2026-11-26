/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/TwinPrimes.lean#L37-L39
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.TwinPrimes

theorem twin_primes :
    {p : ℕ | Prime p ∧ Prime (p + 2)}.Infinite := by
  sorry

end FcOpenOeisClassics.TwinPrimes
