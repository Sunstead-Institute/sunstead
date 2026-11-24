import CryptoAlgebra.Spec
import CryptoAlgebra.ModAddLaws

namespace CryptoAlgebra

/-- TODO (Task: crt_uniqueness):
Prove the uniqueness half of the Chinese Remainder Theorem (fundamental to RSA-CRT):
if `Nat.gcd m n = 1`, `x % m = y % m`, and `x % n = y % n`, then `x % (m * n) = y % (m * n)`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem crt_unique_mod_mul {m n x y : Nat}
    (hcop : Nat.gcd m n = 1)
    (hm : x % m = y % m)
    (hn : x % n = y % n) :
    x % (m * n) = y % (m * n) := by
  sorry

end CryptoAlgebra
