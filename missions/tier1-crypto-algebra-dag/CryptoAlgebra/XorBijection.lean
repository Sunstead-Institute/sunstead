import CryptoAlgebra.Spec
import CryptoAlgebra.XorInvolution

namespace CryptoAlgebra

/-- TODO (Task: xor_bijection):
Prove that for any fixed plaintext `m : BitVec n`, key encryption `fun k => otpEnc m k`
is a bijection on `BitVec n`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem otp_enc_bijective {n : Nat} (m : BitVec n) :
    Bijective (otpEnc m) := by
  sorry

end CryptoAlgebra
