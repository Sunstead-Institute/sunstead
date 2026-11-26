/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/conjecture_1_3_to_2_3.lean#L39-L44
Upstream category: research open | AMS: 6
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.ConjectureOneThirdTwoThirds

theorem conjecture_1_3_to_2_3 : ∀ (P : Type) [Finite P] [PartialOrder P]
    (not_total : ¬ Std.Total (α := P) (· ≤ ·)) (total_ext : Set <| OrderHom P ℕ)
    (total_ext_def : ∀ σ, σ ∈ total_ext ↔ Set.range σ = Set.Icc 1 (Nat.card P)),
    ∃ x y : P, ({σ ∈ total_ext | σ x < σ y}.ncard / total_ext.ncard : ℚ)
      ∈ Set.Icc (1/3) (2/3) := by
  sorry

end FcOpenErdosComb.ConjectureOneThirdTwoThirds
