import CryptoAlgebra.Spec

namespace CryptoAlgebra

/-- TODO (Task: xor_involution):
Prove that one-time pad encryption is self-inverse on every `n`-bit vector:
`otpEnc (otpEnc m k) k = m`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem otp_dec_enc {n : Nat} (m k : BitVec n) :
    otpEnc (otpEnc m k) k = m := by
  sorry

end CryptoAlgebra
