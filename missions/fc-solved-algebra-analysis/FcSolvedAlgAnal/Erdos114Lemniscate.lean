/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/114.lean#L63-L65
Upstream category: research solved | AMS: 28, 30
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Erdos114Lemniscate

open Polynomial MeasureTheory Filter

theorem erdos_114.variants.large_n : ∀ᶠ n in atTop, ∀ p : ℂ[X], p.Monic → p.natDegree = n →
    lemniscateLength p ≤ lemniscateLength (X ^ n - 1) := by
  sorry

end FcSolvedAlgAnal.Erdos114Lemniscate
