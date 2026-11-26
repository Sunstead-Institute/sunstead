/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1159.lean#L43-L48
Upstream category: research open | AMS: 5, 51
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Erdos1159Blocking

open Configuration

theorem erdos_1159 :
    ∃ C : ℕ, 1 < C ∧
      ∀ (P L : Type) (_ : Membership P L) (_ : Fintype P) (_ : Fintype L),
        ∀ _ : ProjectivePlane P L, ∃ S : Set P, ∀ l : L,
          1 ≤ (S ∩ {p : P | p ∈ l}).ncard ∧ (S ∩ {p : P | p ∈ l}).ncard ≤ C := by
  sorry

end FcOpenErdosComb.Erdos1159Blocking
