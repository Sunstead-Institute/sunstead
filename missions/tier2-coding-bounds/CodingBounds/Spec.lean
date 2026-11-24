/-!
FROZEN SPECIFICATION — Concrete error bounds for Reed-Solomon list decoding,
hardware probing masking, cryptographic sponge capacity, and Merkle/SLH-DSA soundness.

Track 1 (`rsListLoss`):
  Reed-Solomon proximity-gap & Johnson list-decoding soundness numerator over
  domain size `n >= 1` and polynomial degree `k >= 1`.

Track 2 (`maskingLeakage`):
  ISW t-probing hardware masking circuit leakage numerator over `s >= 1` secret shares
  and `g >= 1` nonlinear multiplication gadgets.

Track 3 (`spongeBirthdayLoss`):
  Cryptographic sponge (SHA-3 / Keccak) indifferentiability multi-collision numerator
  over `q >= 1` permutation queries and `b >= 1` absorbed message blocks.

Track 4 (`merkleSoundnessLoss`):
  SLH-DSA / SPHINCS+ Merkle-tree multi-target second-preimage & WOTS+ loss numerator
  over tree height `h >= 1` and `q >= 1` hash oracle queries.
-/

namespace CodingBounds

def rsListLoss (n k : Nat) : Nat :=
  7 * (n * k) + n * (n - 1) + (k * (k - 1)) / 2 + n + k

def maskingLeakage (s g : Nat) : Nat :=
  3 * (s * (s - 1)) + 5 * (s * g) + g * (g - 1) + 2 * s + g

def spongeBirthdayLoss (q b : Nat) : Nat :=
  (q * (q - 1)) / 2 + 6 * (q * b) + (b * (b - 1)) / 2 + q + 2 * b

def merkleSoundnessLoss (h q : Nat) : Nat :=
  4 * (h * h) + 3 * (h * q) + (q * (q - 1)) / 2 + 3 * h + 5 * q

end CodingBounds
