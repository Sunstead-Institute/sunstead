import FateHFieldsGroups.Spec

open Module

theorem exists_basis_primitiveRoots_iff_squarefree {n : ℕ+} :
    (∃ b : Basis (primitiveRoots n (CyclotomicField n ℚ)) ℚ (CyclotomicField n ℚ),
    (b : _ → _) = (↑)) ↔ Squarefree n := by
  sorry
