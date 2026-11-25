# Standardized Cryptographic S-box Boolean Circuit Optimization

Minimize straight-line Boolean circuits implementing three ISO/RFC/NIST standardized 8-bit cryptographic S-boxes over the gate basis `{xor, xnor, and, not}`:

| Task ID | S-box Standard | Metric | Target File | Seed Baseline |
| :--- | :--- | :--- | :--- | ---: |
| `sm4_total_gates` | SM4 (RFC 8998 / ISO 18033-3) | Total gates | `CryptoSbox/Sm4TotalCircuit.lean` | **130** |
| `sm4_and_gates` | SM4 (RFC 8998 / ISO 18033-3) | AND gates (`op = 2`) | `CryptoSbox/Sm4AndCircuit.lean` | **36** |
| `aes_inv_total_gates` | AES Inverse (NIST FIPS 197 §5.3.2) | Total gates | `CryptoSbox/AesInvTotalCircuit.lean` | **129** |
| `aes_inv_and_gates` | AES Inverse (NIST FIPS 197 §5.3.2) | AND gates (`op = 2`) | `CryptoSbox/AesInvAndCircuit.lean` | **36** |
| `camellia_total_gates` | Camellia `SBOX1` (RFC 3713 / ISO 18033-3) | Total gates | `CryptoSbox/CamelliaTotalCircuit.lean` | **130** |
| `camellia_and_gates` | Camellia `SBOX1` (RFC 3713 / ISO 18033-3) | AND gates (`op = 2`) | `CryptoSbox/CamelliaAndCircuit.lean` | **36** |

## Circuit Representation

Each editable target file contains three concrete literal definitions (bounded to `16384` bytes and `1..1024` gates):

- Score: `def CryptoSbox.<prefix>Score : Nat := ...`
- Gates: `def CryptoSbox.<prefix>Gates : List (Nat × Nat × Nat) := [(op, w1, w2), ...]`
- Outputs: `def CryptoSbox.<prefix>Outputs : List Nat := [o0, o1, o2, o3, o4, o5, o6, o7]`

Wire numbering and opcodes:

- Wires `0..7` are the 8 input bits `x[0]..x[7]` (LSB = bit `0`).
- Gate `i` (0-indexed) produces wire `8 + i` from earlier wires `w1 < 8 + i` and `w2 < 8 + i`:
  - `0`: `xor` (`v1 ⊕ v2`)
  - `1`: `xnor` (`¬(v1 ⊕ v2)`)
  - `2`: `and` (`v1 ∧ v2`)
  - `3`: `not` (`¬v1`; `w2` is ignored and conventionally `0`)
- `outputs` lists the 8 output wire indices `[o0, ..., o7]` (LSB-first `S(x)[0]..S(x)[7]`), each `< 8 + gates.length`.

## Verification & Provenance

The frozen specification `CryptoSbox/Spec.lean` embeds OpenSSL's verbatim 256-entry reference tables at commit [`openssl/openssl@d94024ff`](https://github.com/openssl/openssl/tree/d94024ffc7e726566a6255228ad0a7de4cfc956d) (Apache-2.0):

- `opensslSm4SboxList` from [`crypto/sm4/sm4.c`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/sm4/sm4.c#L15-L38) (`SM4_S[256]`)
- `opensslAesInvSboxList` from [`crypto/aria/aria.c`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/aria/aria.c#L757-L790) (`sb3[256]`)
- `opensslCamelliaSbox1Words` from [`crypto/camellia/camellia.c`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/camellia/camellia.c#L64-L107) (`Camellia_SBOX[0]`)

and kernel-proves (`decide +kernel`) byte-for-byte agreement on all 256 inputs with their algebraic `GF(2^8)` definitions:

- **SM4 (`sm4Sbox`)**: `sm4Affine (gfInvSm4 (sm4Affine x))` modulo `x^8 + x^7 + x^6 + x^5 + x^4 + x^2 + 1` (`0x1f5`), constant `0xd3`
- **AES Inverse (`aesInvSbox`)**: `gfInvAes (aesInvAffine x)` modulo `x^8 + x^4 + x^3 + x + 1` (`0x11b`), constant `0x05`, additionally kernel-proved two-sided inverse of `aesSbox`
- **Camellia `SBOX1` (`camelliaSbox1`)**: `camelliaOutAffine (gfInvCam (camelliaInAffine x))` modulo `x^8 + x^6 + x^5 + x^3 + 1` (`0x165`), input constant `0xc5`, output constant `0x6e`

Frozen `*Bound.lean` modules verify well-formedness, score accuracy, and bit-sliced 256-input equivalence purely in the Lean 4.36.0 kernel (`decide +kernel`, zero Mathlib, standard axioms only).

To replay locally with Lean `v4.36.0`:

```bash
lake build CryptoSbox.Sm4TotalBound CryptoSbox.Sm4AndBound CryptoSbox.AesInvTotalBound CryptoSbox.AesInvAndBound CryptoSbox.CamelliaTotalBound CryptoSbox.CamelliaAndBound
```

All seed circuits are constructed from a normal-basis `GF(((2^2)^2)^2)` tower-field inversion core (36 AND gates) combined with field-automorphism basis selection and greedy common-subexpression elimination for the input/output affine layers.
