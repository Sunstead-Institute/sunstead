/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Paper/ConjugacyClassSizes.lean#L147-L151
Upstream category: research solved | AMS: 20
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.ConjClassSizesS3

open ConjClasses

theorem conjClassSizes_iff_sym_three_solvable
    (G : Type) [Group G] [Fintype G] [Group.IsSolvable G] [Nontrivial G]
    (h : HasDistinctConjClassSizes (G := G)) :
    Nonempty (G ≃* Equiv.Perm (Fin 3)) := by
  sorry

end FcSolvedAlgAnal.ConjClassSizesS3
