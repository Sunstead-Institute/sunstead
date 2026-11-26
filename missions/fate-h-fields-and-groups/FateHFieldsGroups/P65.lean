import FateHFieldsGroups.Spec

open Polynomial

theorem isSquare_discriminant_of_irreducible {p n : ℕ} [Fact p.Prime] (a b : GaloisField p n)
    (h_irr : Irreducible (X ^ 3 + C a * X + C b)) :
    IsSquare (- 4 * a ^ 3 - 27 * b ^ 2) := by
  sorry
