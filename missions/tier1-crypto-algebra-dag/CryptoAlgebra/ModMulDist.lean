import CryptoAlgebra.Spec

namespace CryptoAlgebra

/-- TODO (Task: mod_mul_dist):
Prove commutativity, associativity, and left distributivity of modular multiplication `modMul q`
over `modAdd q` for all `q a b c : Nat`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem modMul_comm_assoc_dist (q a b c : Nat) :
    modMul q a b = modMul q b a ∧
    modMul q (modMul q a b) c = modMul q a (modMul q b c) ∧
    modMul q a (modAdd q b c) = modAdd q (modMul q a b) (modMul q a c) := by
  sorry

end CryptoAlgebra
