import CryptoAlgebra.Spec

namespace CryptoAlgebra

/-- TODO (Task: mod_add_laws):
Prove commutativity and associativity of modular addition `modAdd q` for all `q a b c : Nat`.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem modAdd_comm_assoc (q a b c : Nat) :
    modAdd q a b = modAdd q b a ∧
    modAdd q (modAdd q a b) c = modAdd q a (modAdd q b c) := by
  sorry

end CryptoAlgebra
