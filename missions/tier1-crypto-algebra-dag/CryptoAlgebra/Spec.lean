/-!
FROZEN SPECIFICATION — Algebraic Foundations of Cryptography & Secret Sharing.

Defines one-time pad encryption on `BitVec n`, bijections, modular arithmetic over `Nat`,
modular exponentiation (Diffie-Hellman), and 2-of-n Shamir linear secret sharing
with Lagrange interpolation at x = 0.
-/

namespace CryptoAlgebra

def Injective {α β : Type} (f : α → β) : Prop :=
  ∀ a b, f a = f b → a = b

def Surjective {α β : Type} (f : α → β) : Prop :=
  ∀ y, ∃ x, f x = y

def Bijective {α β : Type} (f : α → β) : Prop :=
  Injective f ∧ Surjective f

/-- One-time pad encryption on `n`-bit vectors. -/
def otpEnc {n : Nat} (m k : BitVec n) : BitVec n := m ^^^ k

/-- Modular addition modulo `q`. -/
def modAdd (q a b : Nat) : Nat := (a + b) % q

/-- Modular multiplication modulo `q`. -/
def modMul (q a b : Nat) : Nat := (a * b) % q

/-- Modular exponentiation `g ^ e mod p`. -/
def powMod (g e p : Nat) : Nat := (g ^ e) % p

/-- 2-of-n Shamir linear share evaluation `f(x) = (s + a * x) mod q`. -/
def shamirEval (q s a x : Nat) : Nat := (s + a * x) % q

/-- Lagrange interpolation at x = 0 from two shares `(x1, y1), (x2, y2)` with `inv_d = (x2 - x1)^(-1) mod q`. -/
def lagrangeRecover (q x1 y1 x2 y2 inv_d : Nat) : Nat :=
  ((x2 * y1 + (q - (x1 * y2) % q)) * inv_d) % q

end CryptoAlgebra
