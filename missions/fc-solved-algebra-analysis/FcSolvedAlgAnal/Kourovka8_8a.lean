/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Kourovka/8_8.lean#L44-L47
Upstream category: research solved | AMS: 20
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Kourovka8_8a

theorem kourovka_8_8a :
    ∃ (G : Type) (_ : Group G), ¬ IsCyclic G ∧ Group.FG G ∧
      ∃ a : G, ∀ g : G, ∃ n : ℤ, IsConj g (a ^ n) := by
  sorry

end FcSolvedAlgAnal.Kourovka8_8a
