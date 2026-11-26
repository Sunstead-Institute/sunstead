import FateXIdealTheory.Spec

namespace Problem43

open IsLocalRing

theorem IsRegularLocalRing.frobenius_flat {A : Type} [CommRing A] [IsNoetherianRing A]
    [IsLocalRing A] [IsReduced A] (p : ℕ) [Fact p.Prime] [CharP A p] :
    (frobenius A p).Flat ↔ IsRegularLocalRing A := by
  sorry

end Problem43
