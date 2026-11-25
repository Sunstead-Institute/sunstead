import ArkLibNearCapacity.Spec

open scoped NNReal

namespace ArkLibNearCapacity

/-- Open solicited proof from `Verified-zkEVM/ArkLib` Issue #1352
(`ArkLib/Data/CodingTheory/ProximityGap/CapacityBounds.lean:314-321`).

Proving this theorem with `0 sorry` and standard Lean axioms (`propext`, `Classical.choice`,
`Quot.sound`) closes the only remaining `sorry` in ArkLib's
`CodingTheory.ReedSolomon.exists_rs_epsCa_large_near_capacity` (failure of Reed–Solomon
correlated agreement near capacity, Krachun–Kazanin–Haböck ePrint 2026/782).
-/
theorem near_capacity_prime_supply (c : ℝ≥0) (hc : 0 < c) :
    NearCapacityPrimeSupply c := by
  sorry

end ArkLibNearCapacity
