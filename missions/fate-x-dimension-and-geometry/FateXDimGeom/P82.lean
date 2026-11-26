import FateXDimGeom.Spec

namespace Problem82

open IsLocalRing

theorem subring_iso_mvPowerSeries_over_DVR (d : ℕ) (A : Type) [CommRing A] [IsLocalRing A]
    [IsNoetherianRing A] [IsAdicComplete (maximalIdeal A) A] (dim : ringKrullDim A = d)
    {p : ℕ} (hp : p.Prime) [CharZero A] [CharP (ResidueField A) p]
    (ht : (Ideal.span {(p : A)}).height = 1) :
    ∃ B : Subring A, Module.Finite B A ∧
    ∃ (C : Type) (_ : CommRing C) (_ : IsDomain C), IsDiscreteValuationRing C ∧
    Nonempty (B ≃+* MvPowerSeries (Fin (d - 1)) C) := by
  sorry

end Problem82
