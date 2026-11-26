import FateHFieldsGroups.Spec

open IntermediateField

theorem isGalois_galoisField_X_pow_iff_modEq_one (p m n : ℕ) (hn : 1 ≤ n) (hm : 1 ≤ m)
    [Fact p.Prime] :  IsGalois (GaloisField p m)⟮(RatFunc.X ^ n : RatFunc (GaloisField p m))⟯
    (RatFunc (GaloisField p m)) ↔ p ^ m ≡ 1 [MOD n] := by
  sorry
