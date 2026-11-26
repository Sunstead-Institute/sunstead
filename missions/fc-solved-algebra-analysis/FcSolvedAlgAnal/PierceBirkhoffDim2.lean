/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/PierceBirkhoff.lean#L112-L116
Upstream category: research solved | AMS: 13
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.PierceBirkhoffDim2

open scoped Polynomial

theorem pierce_birkhoff_conjecture_dim_two
    (f : (Fin 2 → ℝ) → ℝ) (hf : IsPiecewiseMvPolynomial f) :
    ∃ (ι κ : Type) (g : ι → κ → MvPolynomial (Fin 2) ℝ), Finite ι ∧ Finite κ ∧
      ∀ x, f x = ⨆ i, ⨅ j, MvPolynomial.eval x (g i j) := by
  sorry

end FcSolvedAlgAnal.PierceBirkhoffDim2
