import FateXDimGeom.Spec

namespace Problem70

theorem exists_minimalPrime_map_zero (R S : Type) [CommRing R] [IsDomain R] [IsNoetherianRing R]
    [CommRing S] [IsNoetherianRing S] [IsLocalRing S] [Algebra R S] [NoZeroSMulDivisors R S] :
    ∃ (p : minimalPrimes S), Ideal.comap (algebraMap R S) p.1 = ⊥ := by
  sorry

end Problem70
