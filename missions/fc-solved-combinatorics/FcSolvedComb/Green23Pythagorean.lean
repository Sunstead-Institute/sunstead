/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/23.lean#L39-L48
Upstream category: research solved | AMS: 5, 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Green23Pythagorean

theorem green_23 :
    -- For every finite colouring of the natural numbers
    ∀ (k : ℕ) (c : ℕ → Fin k),
    -- there exist two numbers of the same colour whose squares sum to a square
    ∃ x y : ℕ,
      0 < x ∧ 0 < y ∧  -- Exclude trivial x^2 + 0^2 = x^2 solution
      c x = c y ∧      -- Same colour
      IsSquare (x^2 + y^2)
    := by
  sorry

end FcSolvedComb.Green23Pythagorean
