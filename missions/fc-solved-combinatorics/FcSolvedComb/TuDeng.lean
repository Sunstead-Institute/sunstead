/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Paper/TuDengConjecture.lean#L66-L70
Upstream category: research solved | AMS: 5, 11, 94
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.TuDeng

theorem tu_deng_conjecture (k : ℕ) (hk : 2 ≤ k) (t : ZMod (2 ^ k - 1)) (ht : t ≠ 0) :
    {p : ZMod (2 ^ k - 1) × ZMod (2 ^ k - 1) |
        p.1 + p.2 = t ∧ binaryWeight p.1.val + binaryWeight p.2.val ≤ k - 1}.ncard
      ≤ 2 ^ (k - 1) := by
  sorry

end FcSolvedComb.TuDeng
