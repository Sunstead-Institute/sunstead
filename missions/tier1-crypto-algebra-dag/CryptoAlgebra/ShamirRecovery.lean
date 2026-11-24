import CryptoAlgebra.Spec
import CryptoAlgebra.ModAddLaws
import CryptoAlgebra.ModMulDist

namespace CryptoAlgebra

/-- TODO (Task: shamir_linear_recovery):
Prove exact recovery for 2-of-n Shamir linear secret sharing over `Z_q`:
for any secret `s < q`, random slope `a`, evaluation points `x1 < x2`, and modular inverse
`inv_d` satisfying `((x2 - x1) * inv_d) % q = 1 % q`, Lagrange interpolation at `x = 0`
recovers `s` exactly from `shamirEval q s a x1` and `shamirEval q s a x2`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem shamir_recover_secret {q s a x1 x2 inv_d : Nat}
    (hs : s < q) (hx : x1 < x2) (hinv : ((x2 - x1) * inv_d) % q = 1 % q) :
    lagrangeRecover q x1 (shamirEval q s a x1) x2 (shamirEval q s a x2) inv_d = s := by
  sorry

end CryptoAlgebra
