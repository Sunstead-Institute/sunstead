import CryptoAlgebra.Spec
import CryptoAlgebra.ModMulDist

namespace CryptoAlgebra

/-- TODO (Task: diffie_hellman_soundness):
Prove Diffie-Hellman key agreement soundness over `Nat` modulo `p`:
`powMod (powMod g a p) b p = powMod (powMod g b p) a p` for all `g a b p : Nat`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem dh_shared_secret_eq (g a b p : Nat) :
    powMod (powMod g a p) b p = powMod (powMod g b p) a p := by
  sorry

end CryptoAlgebra
