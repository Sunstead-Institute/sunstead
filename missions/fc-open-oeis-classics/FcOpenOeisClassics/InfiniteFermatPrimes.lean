/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/Fermat.lean#L41-L42
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.InfiniteFermatPrimes

theorem infinite_fermat_primes : Infinite {n : ℕ | Prime n.fermatNumber} := by
  sorry

end FcOpenOeisClassics.InfiniteFermatPrimes
