import FateXIdealTheory.Spec

namespace Problem30

theorem integrallyClosedIn_of_complement_multiplicatively_closed (B : Type) [CommRing B] (A : Subring B)
    (h : ∀ (x y : B), x ∉ A → y ∉ A → x * y ∉ A) : IsIntegrallyClosedIn A B := by
  sorry

end Problem30
