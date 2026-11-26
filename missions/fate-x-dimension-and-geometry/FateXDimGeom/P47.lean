import FateXDimGeom.Spec

namespace Problem47

theorem isEmpty_isomorphism_UFD_of_quotient (k : Type) [Field k] (h_char : ¬ CharP k 2)
    (n : ℕ) (h_ge : n ≥ 3) (h_odd : Odd n) (t : (Fin n) → k) (h_inj : Function.Injective t) :
    ∃ _ : IsDedekindDomain (A t), Nontrivial (ClassGroup (A t)) := by
  sorry

end Problem47
