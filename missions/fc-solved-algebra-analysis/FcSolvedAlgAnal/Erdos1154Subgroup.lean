/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1154.lean#L67-L69
Upstream category: research solved | AMS: 28
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Erdos1154Subgroup

open scoped ENNReal Cardinal
open Set MeasureTheory

theorem erdos_1154.variants.group {a : ℝ≥0∞} (ha : a ∈ Icc 0 1) :
    ∃ R : AddSubgroup ℝ, dimH (R : Set ℝ) = a := by
  sorry

end FcSolvedAlgAnal.Erdos1154Subgroup
