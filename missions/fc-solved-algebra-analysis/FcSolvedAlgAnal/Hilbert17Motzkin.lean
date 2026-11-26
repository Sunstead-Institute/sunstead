/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/HilbertProblems/17.lean#L73-L75
Upstream category: textbook | AMS: 12
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Hilbert17Motzkin

open Real MvPolynomial

theorem f_not_sum_of_squares :
    ¬∃ (n : ℕ) (hn : 0 < n) (S : Fin n → MvPolynomial (Fin 2) ℝ), f = ∑ i, S i ^ 2 := by
  sorry

end FcSolvedAlgAnal.Hilbert17Motzkin
