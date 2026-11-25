# AES S-box Boolean Circuit Optimization

Minimize straight-line Boolean circuits implementing the NIST FIPS 197 AES S-box over the gate basis `{xor, xnor, and, not}`:

- **`minimize_total_gates`** (`AesSbox/TotalCircuit.lean`): minimize the total number of gates (`totalGates.length`, baseline **130**).
- **`minimize_and_gates`** (`AesSbox/AndCircuit.lean`): minimize multiplicative complexity — the number of `and` (`op = 2`) gates (`andCount andGates`, baseline **36**).

## Circuit Representation

Each target file contains three literal definitions (bounded to `16384` bytes and `1..1024` gates):

- Score: `def AesSbox.totalScore : Nat := ...` (or `AesSbox.andScore`)
- Gates: `def AesSbox.totalGates : List (Nat × Nat × Nat) := [(op, w1, w2), ...]` (or `AesSbox.andGates`)
- Outputs: `def AesSbox.totalOutputs : List Nat := [o0, o1, o2, o3, o4, o5, o6, o7]` (or `AesSbox.andOutputs`)

Wire numbering and opcodes:

- Wires `0..7` are the 8 input bits `x[0]..x[7]` (LSB = bit `0`).
- Gate `i` (0-indexed) produces wire `8 + i` from earlier wires `w1 < 8 + i` and `w2 < 8 + i`:
  - `0`: `xor` (`v1 ⊕ v2`)
  - `1`: `xnor` (`¬(v1 ⊕ v2)`)
  - `2`: `and` (`v1 ∧ v2`)
  - `3`: `not` (`¬v1`; `w2` is ignored and conventionally `0`)
- `outputs` lists the 8 output wire indices `[o0, ..., o7]` (LSB-first `S(x)[0]..S(x)[7]`), each `< 8 + gates.length`.

## Verification & Provenance

The frozen specification `AesSbox/Spec.lean` embeds `SBOX` verbatim from AWS Automated Reasoning's [`leanprover/LNSym@49f8a1d9`](https://github.com/leanprover/LNSym/blob/49f8a1d9e46f8dcfc345f4bc15d35b0ba845ff5c/Specs/AESCommon.lean#L15-L33) (Apache-2.0) and kernel-proves (`AesSbox.aesSbox_eq_lnsymSbox`) that it agrees byte-for-byte with the algebraic NIST FIPS 197 definition (`GF(2^8)` multiplicative inverse modulo `x^8 + x^4 + x^3 + x + 1` followed by the FIPS 197 affine transformation with constant `0x63`).

Frozen proofs `AesSbox/TotalBound.lean` and `AesSbox/AndBound.lean` check well-formedness, score accuracy, and bit-sliced 256-input equivalence purely in the Lean 4.36.0 kernel (`decide +kernel`, zero Mathlib, standard axioms only).

To replay locally with Lean `v4.36.0`:

```bash
lake build AesSbox.TotalBound AesSbox.AndBound
```

The seed circuit (130 total gates: 90 XOR, 3 XNOR, 36 AND, 1 NOT) is constructed from an original normal-basis tower-field decomposition `GF(((2^2)^2)^2)` over `GF(2^8)`.
