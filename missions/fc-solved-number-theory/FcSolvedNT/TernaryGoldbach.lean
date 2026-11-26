/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/GoldbachConjecture.lean#L52-L54
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.TernaryGoldbach

theorem ternaryGoldbach (n : ℕ) (hn : 5 < n) (hn_odd : Odd n) :
    ∃ p q r, Nat.Prime p ∧ Nat.Prime q ∧ Nat.Prime r ∧ n = p + q + r := by
  sorry

end FcSolvedNT.TernaryGoldbach
