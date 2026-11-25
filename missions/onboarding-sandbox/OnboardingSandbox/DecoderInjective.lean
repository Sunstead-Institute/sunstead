import OnboardingSandbox.Spec

namespace OnboardingSandbox

/-- Sandbox task `decoder_injective`: every lossless compressor has an injective encoder. -/
theorem encode_injective_of_lossless {n k : Nat} (c : LosslessCompressor n k) :
    Injective c.encode := by
  sorry

end OnboardingSandbox
