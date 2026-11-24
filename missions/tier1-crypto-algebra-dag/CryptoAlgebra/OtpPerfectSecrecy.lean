import CryptoAlgebra.Spec
import CryptoAlgebra.XorBijection

namespace CryptoAlgebra

/-- TODO (Task: otp_perfect_secrecy):
Prove Shannon's unique-key property for the one-time pad: for any plaintext `m`
and ciphertext `c` in `BitVec n`, there exists a unique key `k` such that `otpEnc m k = c`.
(Hence every plaintext maps uniformly onto every ciphertext under a uniform random key.)
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem otp_unique_key {n : Nat} (m c : BitVec n) :
    ∃ k : BitVec n, otpEnc m k = c ∧ ∀ k', otpEnc m k' = c → k' = k := by
  sorry

end CryptoAlgebra
