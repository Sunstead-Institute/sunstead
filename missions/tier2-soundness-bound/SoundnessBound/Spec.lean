/-!
FROZEN SPECIFICATION — Concrete cryptographic reduction & polynomial folding error models.

Track 1 (`multiUserLoss`):
  Concrete advantage numerator over `u >= 1` users and `q >= 1` oracle queries combining
  birthday collisions `q*(q-1)/2`, cross-user simulation `u*q`, reprogramming `q^2/4`,
  and linear key/query overhead `3*u + 2*q`.

Track 2 (`foldingError`):
  Concrete error numerator for an `r >= 1` round degree-`d >= 1` interactive polynomial
  folding protocol (FRI/WHIR-style soundness loss).

Track 3 (`hybridKemLoss`):
  Concrete multi-target IND-CCA reduction numerator for a hybrid PQ+Classical KEM combiner
  (e.g. X-Wing) over `n >= 1` encapsulations and `q >= 1` decapsulation oracle queries.

Track 4 (`frostForkingLoss`):
  Concrete forking-lemma & nonce-binding soundness numerator for threshold Schnorr (FROST)
  over `t >= 1` threshold signers and `q >= 1` signing oracle queries.
-/

namespace SoundnessBound

def multiUserLoss (u q : Nat) : Nat :=
  (q * (q - 1)) / 2 + u * q + (q * q) / 4 + 3 * u + 2 * q

def foldingError (d r : Nat) : Nat :=
  3 * (d * r) + (d * (d - 1)) / 2 + 2 * (r * r) + 5 * d + 4 * r

def hybridKemLoss (n q : Nat) : Nat :=
  2 * (n * q) + (n * (n - 1)) / 2 + (q * q) / 3 + 4 * n + 3 * q

def frostForkingLoss (t q : Nat) : Nat :=
  4 * (t * q) + 2 * (t * (t - 1)) + (q * (q - 1)) / 2 + 6 * t + 5 * q

end SoundnessBound
