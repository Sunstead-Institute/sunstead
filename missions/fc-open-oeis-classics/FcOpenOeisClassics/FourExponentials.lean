/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/Exponentials.lean#L38-L41
Upstream category: research open | AMS: 33
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.FourExponentials

open Complex

theorem four_exponentials_conjecture (x : Fin 2 → ℂ) (y : Fin 2 → ℂ)
    (h1 : LinearIndependent ℚ x) (h2 : LinearIndependent ℚ y) :
    ∃ i j : Fin 2, Transcendental ℚ (exp (x i * y j)) := by
  sorry

end FcOpenOeisClassics.FourExponentials
