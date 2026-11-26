/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/477.lean#L62-L65
Upstream category: research solved | AMS: 12
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Erdos477Squares

open Polynomial Set

theorem erdos_477.variants.S_sq :
    letI f := X ^ 2
    ∀ A : Set ℤ, ∃ z, ¬ ∃! a ∈ A ×ˢ (Set.range f.eval), z = a.1 + a.2 := by
  sorry

end FcSolvedAlgAnal.Erdos477Squares
