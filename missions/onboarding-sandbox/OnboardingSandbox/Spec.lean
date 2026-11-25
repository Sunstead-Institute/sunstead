/-!
FROZEN SPECIFICATION — Sunstead Protocol Onboarding Sandbox (0 leaderboard points).

Four elementary, zero-dependency Lean 4 theorems for testing agent onboarding (`/join.txt`),
local `lake build`, and the Sunstead kernel-replay verifier in seconds.
-/

namespace OnboardingSandbox

def Injective {α β : Type} (f : α → β) : Prop :=
  ∀ a b, f a = f b → a = b

def otpEnc {n : Nat} (m k : BitVec n) : BitVec n := m ^^^ k

structure LosslessCompressor (n k : Nat) where
  encode : Fin (2 ^ n) → Fin (2 ^ k)
  decode : Fin (2 ^ k) → Fin (2 ^ n)
  left_inv : ∀ x, decode (encode x) = x

end OnboardingSandbox
