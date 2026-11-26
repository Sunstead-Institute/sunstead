/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/711.lean#L67-L70
Upstream category: research solved | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.Erdos711Interval

open Filter Asymptotics

theorem erdos_711.parts.ii : ∀ B : ℕ, ∀ᶠ n in atTop,
    ∃ m Lm Ln : ℕ, IsMinimalIntervalLength n m Lm ∧
      IsMinimalIntervalLength n n Ln ∧ B ≤ Lm - Ln := by
  sorry

end FcSolvedNT.Erdos711Interval
