import FateXFieldsRingsGroups.Spec

namespace Problem8

open Quaternion

theorem quaternionAlgebra_isomorphic_to_matrix_ring_or_quaternion_ring
    (A B : ℚ) (ha : A ≠ 0) (hb : B ≠ 0) :
    ((Nonempty (ℍ[ℝ, A, B] ≃ₐ[ℝ] ℍ[ℝ, -1, -1])) ∨ (Nonempty (ℍ[ℝ, A, B] ≃ₐ[ℝ] Matrix (Fin 2) (Fin 2) ℝ)))
    ∧ IsEmpty (Matrix (Fin 2) (Fin 2) ℝ ≃ₐ[ℝ] ℍ[ℝ, -1, -1]) := by
  sorry

end Problem8
