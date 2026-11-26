/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/913.lean#L40-L42
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos913Exponents

theorem erdos_913 :
    { n | Set.InjOn (n * (n + 1)).factorization (n * (n + 1)).primeFactors }.Infinite := by
  sorry

end FcOpenErdosNT.Erdos913Exponents
