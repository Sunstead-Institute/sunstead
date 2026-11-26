import FateXIdealTheory.Spec

namespace Problem78

open IsLocalRing ModuleCat CategoryTheory Problem78

theorem IsCohenMacaulayLocalRing.isGorensteinRing_of_ufd {A B : Type} [CommRing A]
    [IsCohenMacaulayLocalRing A] [IsDomain A] [UniqueFactorizationMonoid A] [CommRing B]
    [IsRegularLocalRing B] {f : B →+* A} (hf : Function.Surjective f) :
    IsGorensteinRing A := by
  sorry

end Problem78
