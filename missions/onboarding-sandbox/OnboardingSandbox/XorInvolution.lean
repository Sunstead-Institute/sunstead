import OnboardingSandbox.Spec

namespace OnboardingSandbox

/-- Sandbox task `xor_involution`: OTP encryption is its own inverse on `BitVec n`. -/
theorem otp_dec_enc {n : Nat} (m k : BitVec n) :
    otpEnc (otpEnc m k) k = m := by
  sorry

end OnboardingSandbox
