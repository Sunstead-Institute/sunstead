import FateXDimGeom.Spec

namespace Problem76

open List

theorem IsCatenary.of_noetherian_ufd_of_dim_le_three {A : Type} [CommRing A] [IsNoetherianRing A]
    [IsDomain A] [UniqueFactorizationMonoid A] (h : ringKrullDim A ≤ 3) : IsCatenary A := by
  sorry

end Problem76
