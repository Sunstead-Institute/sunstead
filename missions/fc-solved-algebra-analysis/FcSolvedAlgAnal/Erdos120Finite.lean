/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/120.lean#L55-L56
Upstream category: research solved | AMS: 5, 28
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Erdos120Finite

open Set MeasureTheory

theorem erdos_120.variants.finite_set {A : Set ℝ} (h : A.Finite) : ¬ Erdos120For A := by
  sorry

end FcSolvedAlgAnal.Erdos120Finite
