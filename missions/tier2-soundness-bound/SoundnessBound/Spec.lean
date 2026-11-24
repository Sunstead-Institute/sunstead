/-!
FROZEN SPECIFICATION — Concrete cryptographic reduction & polynomial folding error models.

Track 1 (`multiUserLoss`):
  Concrete advantage numerator over `u >= 1` users and `q >= 1` oracle queries combining
  birthday collisions `q*(q-1)/2`, cross-user simulation `u*q`, reprogramming `q^2/4`,
  and linear key/query overhead `3*u + 2*q`.

Track 2 (`foldingError`):
  Concrete error numerator for an `r >= 1` round degree-`d >= 1` interactive polynomial
  folding protocol (FRI/WHIR-style soundness loss).
-/

namespace SoundnessBound

def multiUserLoss (u q : Nat) : Nat :=
  (q * (q - 1)) / 2 + u * q + (q * q) / 4 + 3 * u + 2 * q

def foldingError (d r : Nat) : Nat :=
  3 * (d * r) + (d * (d - 1)) / 2 + 2 * (r * r) + 5 * d + 4 * r

end SoundnessBound
