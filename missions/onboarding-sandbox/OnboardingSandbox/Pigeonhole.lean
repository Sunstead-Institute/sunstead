import OnboardingSandbox.Spec

namespace OnboardingSandbox

/-- Sandbox task `pigeonhole_fin`: no injection `Fin n → Fin m` exists when `m < n`. -/
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  sorry

end OnboardingSandbox
