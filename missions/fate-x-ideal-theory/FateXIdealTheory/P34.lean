import FateXIdealTheory.Spec

namespace Problem34

open PowerSeries

theorem powerSeries_not_integrallyClosed_of_two_lt_ringKrullDim (R : Type) [CommRing R]
    [IsDomain R] [ValuationRing R] (two_lt : 2 ≤ ringKrullDim R) :
    ¬ (IsIntegrallyClosed R⟦X⟧) := by
  sorry

end Problem34
