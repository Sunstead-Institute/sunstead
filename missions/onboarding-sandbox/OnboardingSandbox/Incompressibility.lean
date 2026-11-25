import OnboardingSandbox.Spec
import OnboardingSandbox.Pigeonhole
import OnboardingSandbox.DecoderInjective

namespace OnboardingSandbox

/-- Sandbox task `incompressibility_theorem`: no lossless compressor shrinks `n` bits to `k < n` bits. -/
theorem no_universal_lossless_compressor {n k : Nat} (hk : k < n)
    (c : LosslessCompressor n k) : False := by
  sorry

end OnboardingSandbox
