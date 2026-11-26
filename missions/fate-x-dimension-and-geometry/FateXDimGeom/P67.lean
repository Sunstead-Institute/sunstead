import FateXDimGeom.Spec

namespace Problem67

open scoped TensorProduct

theorem isEmpty_mvPowerSeries_tensor_mvPowerSeries_algEquiv
    {k : Type} [Field k] (n : ℕ) (hn : n ≠ 0) :
    IsEmpty ((MvPowerSeries (Fin n) k) ⊗[k] (MvPowerSeries (Fin n) k) ≃ₐ[k]
    (MvPowerSeries (Fin (n + n)) k)) := by
  sorry

end Problem67
