# Cryptographic Diffusion Layer XOR Circuit Optimization

Minimize the straight-line 2-input XOR gate count of `GF(2)`-linear circuits implementing six standardized cryptographic diffusion layers pinned verbatim to OpenSSL (`openssl/openssl@d94024ff`, Apache-2.0):

| Task ID | Diffusion Layer Standard | Matrix Size | Target File | Seed Baseline |
| :--- | :--- | :---: | :--- | ---: |
| `aes_mixcolumns_xor` | AES `MixColumns` (NIST FIPS 197 §5.1.3) | `32×32` | `CryptoLinearXor/AesMixColumnsCircuit.lean` | **152** |
| `aes_invmixcolumns_xor` | AES `InvMixColumns` (NIST FIPS 197 §5.3.3) | `32×32` | `CryptoLinearXor/AesInvMixColumnsCircuit.lean` | **440** |
| `sm4_linear_l_xor` | SM4 round diffusion `L` (RFC 8998 / ISO 18033-3) | `32×32` | `CryptoLinearXor/Sm4LinearLCircuit.lean` | **128** |
| `sm4_key_lprime_xor` | SM4 key-schedule diffusion `L'` (RFC 8998 / ISO 18033-3) | `32×32` | `CryptoLinearXor/Sm4KeyLPrimeCircuit.lean` | **64** |
| `aria_diffusion_xor` | ARIA involutory diffusion `A` (RFC 5794 / ISO 18033-3) | `16×16` | `CryptoLinearXor/AriaDiffusionCircuit.lean` | **96** |
| `camellia_p_xor` | Camellia `P`-function (RFC 3713 §2.3 / ISO 18033-3) | `8×8` | `CryptoLinearXor/CamelliaPCircuit.lean` | **36** |

## Circuit Representation

Each editable target file contains three concrete literal definitions (bounded to `32768` bytes and `1..1024` XOR gates):

- Score: `def CryptoLinearXor.<prefix>Score : Nat := ...`
- Gates: `def CryptoLinearXor.<prefix>Gates : List (Nat × Nat) := [(w1, w2), ...]`
- Outputs: `def CryptoLinearXor.<prefix>Outputs : List Nat := [o0, ..., o_{n-1}]`

Wire numbering (for width `n ∈ {32, 16, 8}`):

- Wires `0 .. n-1` are the `n` input bits `x[0] .. x[n-1]` (LSB = bit `0`).
  - For AES `MixColumns` / `InvMixColumns` (`n = 32`), byte `j ∈ {0, 1, 2, 3}` occupies bits `8j .. 8j + 7` (LSB-first within each byte, matching OpenSSL's `uni.b[0..3]` column layout).
  - For SM4 `L` / `L'` (`n = 32`), bit `i` is bit `i` of the 32-bit word (`rotl(t, r) = (t <<< r) ||| (t >>> (32 - r))`).
  - For ARIA `A` (`n = 16`), bit `i` represents lane `x->c[i]` of `ARIA_u128` (applied identically to each of the 8 bit positions per byte).
  - For Camellia `P` (`n = 8`), bit `i` represents post-S-box byte lane `z_{i+1}'` (`i = 0..7`) of RFC 3713 §2.3 / OpenSSL `Camellia_Feistel`.
- Gate `k` (`0`-indexed) takes earlier wires `w1 < n + k` and `w2 < n + k` and produces wire `n + k` equal to `wire[w1] ⊕ wire[w2]`.
- `outputs` lists the `n` output wire indices `[o0, ..., o_{n-1}]`, each `< n + gates.length`.

## Verification, Formal Soundness & Provenance

The frozen specification `CryptoLinearXor/Spec.lean` pins OpenSSL's verbatim C source excerpts at commit [`openssl/openssl@d94024ff`](https://github.com/openssl/openssl/tree/d94024ffc7e726566a6255228ad0a7de4cfc956d) (Apache-2.0):

- `crypto/aes/aes_core.c`: [`XtimeLong`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/aes/aes_core.c#L86-L97), [`MixColumns`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/aes/aes_core.c#L463-L489), and [`InvMixColumns`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/aes/aes_core.c#L491-L525)
- `crypto/sm4/sm4.c`: [`rotl`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/sm4/sm4.c#L227-L230), [`SM4_T_slow`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/sm4/sm4.c#L257-L265), and [`SM4_key_sub`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/sm4/sm4.c#L272-L277)
- `crypto/aria/aria.c`: [`a()`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/aria/aria.c#L944-L962)
- `crypto/camellia/camellia.c`: [`SBOX1_1110..SBOX3_3033`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/camellia/camellia.c#L60-L63) and [`Camellia_Feistel`](https://github.com/openssl/openssl/blob/d94024ffc7e726566a6255228ad0a7de4cfc956d/crypto/camellia/camellia.c#L253-L272)

Inside `CryptoLinearXor/Spec.lean` (pure Lean 4.36.0, zero Mathlib, zero `sorry`, standard axioms only), Sunstead formally proves:

1. **Exact OpenSSL & Algebraic Identities (all `2^n` inputs)**:
   - `aesMixColumns32_eq_openssl` and `aesInvMixColumns32_eq_openssl` (FIPS 197 `GF(2^8)` matrix multiplication equals OpenSSL's `XtimeWord` + `MixColumns` / `InvMixColumns` on all `2^32` inputs).
   - `aesInvMixColumns32_aesMixColumns32` and `aesMixColumns32_aesInvMixColumns32` (two-sided inverse on all `2^32` inputs).
   - `sm4LinearL32_invertible` and `sm4KeyLPrime32_invertible` (bijectivity on all `2^32` inputs).
   - `ariaDiffusion16_involutory` (`A(A(x)) = x` on all `2^16` inputs).
   - `camelliaP8_eq_opensslFeistel` (RFC 3713 `P` equals OpenSSL's `Camellia_Feistel` T-table byte XORs on all `2^8` inputs) and `camelliaP8_invertible`.
2. **Fundamental Linearity Soundness Theorem**:
   - Every straight-line XOR circuit is `GF(2)`-linear (`evalXorCircuit_isF2Linear`).
   - Every `GF(2)`-linear reference map agrees with matrix-vector multiplication by its basis-derived rows (`matMul_rowsOfLinearMap`).
   - Passing the single-pass symbolic basis-mask check `checkLinearCircuit n rows gates outputs = true` implies exact pointwise agreement `∀ x : BitVec n, evalXorCircuit n gates outputs x = target x` across all `2^n` inputs (`2^32 = 4,294,967,296` inputs for 32-bit layers).

Frozen `*Bound.lean` modules verify well-formedness, gate count, and symbolic basis-mask equivalence purely in the Lean 4.36.0 kernel (`decide +kernel`).

To replay locally with Lean `v4.36.0`:

```bash
lake build CryptoLinearXor.AesMixColumnsBound CryptoLinearXor.AesInvMixColumnsBound CryptoLinearXor.Sm4LinearLBound CryptoLinearXor.Sm4KeyLPrimeBound CryptoLinearXor.AriaDiffusionBound CryptoLinearXor.CamelliaPBound
```

All six seed circuits are unoptimized row-by-row parity XOR trees with zero common-subexpression elimination, providing large optimization headroom toward state-of-the-art straight-line XOR circuits (e.g., Paar, Boyar-Peralta, Xiang et al., Li et al.).
