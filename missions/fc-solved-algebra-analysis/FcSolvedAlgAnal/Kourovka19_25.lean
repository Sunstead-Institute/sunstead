/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Kourovka/19_25.lean#L51-L56
Upstream category: research solved | AMS: 20
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Kourovka19_25

open scoped Nat Group

theorem kourovka_19_25 :
    ¬ ∀ (G H : Type) [Group G] [Group H] [Fintype G] [Fintype H],
       Fintype.card G = Fintype.card H →
       ∑ g : G, φ (orderOf g) = ∑ h : H, φ (orderOf h) →
       IsSimpleGroup G → IsSimpleGroup H := by
  sorry

end FcSolvedAlgAnal.Kourovka19_25
