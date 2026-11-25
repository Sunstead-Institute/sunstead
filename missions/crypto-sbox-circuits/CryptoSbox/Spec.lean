/-!
# Standardized Cryptographic S-box Specifications and Boolean Circuit Semantics

This module pins OpenSSL's verbatim 256-entry reference tables at commit
`d94024ffc7e726566a6255228ad0a7de4cfc956d` (Apache-2.0) for three ISO/RFC/NIST
standardized 8-bit cryptographic S-boxes:

1. **SM4 S-box** (RFC 8998 / ISO 18033-3 / GB/T 32907), from `crypto/sm4/sm4.c` (`SM4_S[256]`).
2. **AES Inverse S-box** (NIST FIPS 197 §5.3.2), from `crypto/aria/aria.c` (`sb3[256]`).
3. **Camellia `SBOX1`** (RFC 3713 §2.4 / ISO 18033-3), from `crypto/camellia/camellia.c` (`Camellia_SBOX[0]`).

Each S-box is defined algebraically over its defining finite field `GF(2^8)` and
kernel-proved (`decide +kernel`) to agree byte-for-byte with OpenSSL's verbatim table
on all 256 inputs (and `aesInvSbox` is additionally kernel-proved to be the exact
two-sided inverse of the NIST FIPS 197 `aesSbox`).
-/

namespace CryptoSbox

/-! ## Verbatim OpenSSL Reference Tables (`openssl/openssl@d94024ff`, Apache-2.0) -/

/-- Verbatim SM4 S-box table `SM4_S[256]` from OpenSSL `crypto/sm4/sm4.c`. -/
def opensslSm4SboxList : List Nat := [
    0xD6, 0x90, 0xE9, 0xFE, 0xCC, 0xE1, 0x3D, 0xB7, 0x16, 0xB6, 0x14, 0xC2,
    0x28, 0xFB, 0x2C, 0x05, 0x2B, 0x67, 0x9A, 0x76, 0x2A, 0xBE, 0x04, 0xC3,
    0xAA, 0x44, 0x13, 0x26, 0x49, 0x86, 0x06, 0x99, 0x9C, 0x42, 0x50, 0xF4,
    0x91, 0xEF, 0x98, 0x7A, 0x33, 0x54, 0x0B, 0x43, 0xED, 0xCF, 0xAC, 0x62,
    0xE4, 0xB3, 0x1C, 0xA9, 0xC9, 0x08, 0xE8, 0x95, 0x80, 0xDF, 0x94, 0xFA,
    0x75, 0x8F, 0x3F, 0xA6, 0x47, 0x07, 0xA7, 0xFC, 0xF3, 0x73, 0x17, 0xBA,
    0x83, 0x59, 0x3C, 0x19, 0xE6, 0x85, 0x4F, 0xA8, 0x68, 0x6B, 0x81, 0xB2,
    0x71, 0x64, 0xDA, 0x8B, 0xF8, 0xEB, 0x0F, 0x4B, 0x70, 0x56, 0x9D, 0x35,
    0x1E, 0x24, 0x0E, 0x5E, 0x63, 0x58, 0xD1, 0xA2, 0x25, 0x22, 0x7C, 0x3B,
    0x01, 0x21, 0x78, 0x87, 0xD4, 0x00, 0x46, 0x57, 0x9F, 0xD3, 0x27, 0x52,
    0x4C, 0x36, 0x02, 0xE7, 0xA0, 0xC4, 0xC8, 0x9E, 0xEA, 0xBF, 0x8A, 0xD2,
    0x40, 0xC7, 0x38, 0xB5, 0xA3, 0xF7, 0xF2, 0xCE, 0xF9, 0x61, 0x15, 0xA1,
    0xE0, 0xAE, 0x5D, 0xA4, 0x9B, 0x34, 0x1A, 0x55, 0xAD, 0x93, 0x32, 0x30,
    0xF5, 0x8C, 0xB1, 0xE3, 0x1D, 0xF6, 0xE2, 0x2E, 0x82, 0x66, 0xCA, 0x60,
    0xC0, 0x29, 0x23, 0xAB, 0x0D, 0x53, 0x4E, 0x6F, 0xD5, 0xDB, 0x37, 0x45,
    0xDE, 0xFD, 0x8E, 0x2F, 0x03, 0xFF, 0x6A, 0x72, 0x6D, 0x6C, 0x5B, 0x51,
    0x8D, 0x1B, 0xAF, 0x92, 0xBB, 0xDD, 0xBC, 0x7F, 0x11, 0xD9, 0x5C, 0x41,
    0x1F, 0x10, 0x5A, 0xD8, 0x0A, 0xC1, 0x31, 0x88, 0xA5, 0xCD, 0x7B, 0xBD,
    0x2D, 0x74, 0xD0, 0x12, 0xB8, 0xE5, 0xB4, 0xB0, 0x89, 0x69, 0x97, 0x4A,
    0x0C, 0x96, 0x77, 0x7E, 0x65, 0xB9, 0xF1, 0x09, 0xC5, 0x6E, 0xC6, 0x84,
    0x18, 0xF0, 0x7D, 0xEC, 0x3A, 0xDC, 0x4D, 0x20, 0x79, 0xEE, 0x5F, 0x3E,
    0xD7, 0xCB, 0x39, 0x48
]

/-- Verbatim NIST FIPS 197 AES Inverse S-box table `sb3[256]` from OpenSSL `crypto/aria/aria.c`. -/
def opensslAesInvSboxList : List Nat := [
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38,
    0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
    0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87,
    0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
    0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d,
    0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2,
    0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
    0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16,
    0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
    0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda,
    0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a,
    0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
    0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02,
    0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
    0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea,
    0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85,
    0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
    0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89,
    0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
    0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20,
    0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31,
    0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
    0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d,
    0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
    0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0,
    0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26,
    0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d
]

/-- Verbatim Camellia `SBOX1_1110` T-table `Camellia_SBOX[0]` from OpenSSL `crypto/camellia/camellia.c`.
Each 32-bit word replicates the `SBOX1` byte `s` as `(s <<< 24) ||| (s <<< 16) ||| (s <<< 8)`. -/
def opensslCamelliaSbox1Words : List Nat := [
    0x70707000, 0x82828200, 0x2c2c2c00, 0xececec00, 0xb3b3b300, 0x27272700,
        0xc0c0c000, 0xe5e5e500, 0xe4e4e400, 0x85858500, 0x57575700, 0x35353500,
        0xeaeaea00, 0x0c0c0c00, 0xaeaeae00, 0x41414100, 0x23232300, 0xefefef00,
        0x6b6b6b00, 0x93939300, 0x45454500, 0x19191900, 0xa5a5a500, 0x21212100,
        0xededed00, 0x0e0e0e00, 0x4f4f4f00, 0x4e4e4e00, 0x1d1d1d00, 0x65656500,
        0x92929200, 0xbdbdbd00, 0x86868600, 0xb8b8b800, 0xafafaf00, 0x8f8f8f00,
        0x7c7c7c00, 0xebebeb00, 0x1f1f1f00, 0xcecece00, 0x3e3e3e00, 0x30303000,
        0xdcdcdc00, 0x5f5f5f00, 0x5e5e5e00, 0xc5c5c500, 0x0b0b0b00, 0x1a1a1a00,
        0xa6a6a600, 0xe1e1e100, 0x39393900, 0xcacaca00, 0xd5d5d500, 0x47474700,
        0x5d5d5d00, 0x3d3d3d00, 0xd9d9d900, 0x01010100, 0x5a5a5a00, 0xd6d6d600,
        0x51515100, 0x56565600, 0x6c6c6c00, 0x4d4d4d00, 0x8b8b8b00, 0x0d0d0d00,
        0x9a9a9a00, 0x66666600, 0xfbfbfb00, 0xcccccc00, 0xb0b0b000, 0x2d2d2d00,
        0x74747400, 0x12121200, 0x2b2b2b00, 0x20202000, 0xf0f0f000, 0xb1b1b100,
        0x84848400, 0x99999900, 0xdfdfdf00, 0x4c4c4c00, 0xcbcbcb00, 0xc2c2c200,
        0x34343400, 0x7e7e7e00, 0x76767600, 0x05050500, 0x6d6d6d00, 0xb7b7b700,
        0xa9a9a900, 0x31313100, 0xd1d1d100, 0x17171700, 0x04040400, 0xd7d7d700,
        0x14141400, 0x58585800, 0x3a3a3a00, 0x61616100, 0xdedede00, 0x1b1b1b00,
        0x11111100, 0x1c1c1c00, 0x32323200, 0x0f0f0f00, 0x9c9c9c00, 0x16161600,
        0x53535300, 0x18181800, 0xf2f2f200, 0x22222200, 0xfefefe00, 0x44444400,
        0xcfcfcf00, 0xb2b2b200, 0xc3c3c300, 0xb5b5b500, 0x7a7a7a00, 0x91919100,
        0x24242400, 0x08080800, 0xe8e8e800, 0xa8a8a800, 0x60606000, 0xfcfcfc00,
        0x69696900, 0x50505000, 0xaaaaaa00, 0xd0d0d000, 0xa0a0a000, 0x7d7d7d00,
        0xa1a1a100, 0x89898900, 0x62626200, 0x97979700, 0x54545400, 0x5b5b5b00,
        0x1e1e1e00, 0x95959500, 0xe0e0e000, 0xffffff00, 0x64646400, 0xd2d2d200,
        0x10101000, 0xc4c4c400, 0x00000000, 0x48484800, 0xa3a3a300, 0xf7f7f700,
        0x75757500, 0xdbdbdb00, 0x8a8a8a00, 0x03030300, 0xe6e6e600, 0xdadada00,
        0x09090900, 0x3f3f3f00, 0xdddddd00, 0x94949400, 0x87878700, 0x5c5c5c00,
        0x83838300, 0x02020200, 0xcdcdcd00, 0x4a4a4a00, 0x90909000, 0x33333300,
        0x73737300, 0x67676700, 0xf6f6f600, 0xf3f3f300, 0x9d9d9d00, 0x7f7f7f00,
        0xbfbfbf00, 0xe2e2e200, 0x52525200, 0x9b9b9b00, 0xd8d8d800, 0x26262600,
        0xc8c8c800, 0x37373700, 0xc6c6c600, 0x3b3b3b00, 0x81818100, 0x96969600,
        0x6f6f6f00, 0x4b4b4b00, 0x13131300, 0xbebebe00, 0x63636300, 0x2e2e2e00,
        0xe9e9e900, 0x79797900, 0xa7a7a700, 0x8c8c8c00, 0x9f9f9f00, 0x6e6e6e00,
        0xbcbcbc00, 0x8e8e8e00, 0x29292900, 0xf5f5f500, 0xf9f9f900, 0xb6b6b600,
        0x2f2f2f00, 0xfdfdfd00, 0xb4b4b400, 0x59595900, 0x78787800, 0x98989800,
        0x06060600, 0x6a6a6a00, 0xe7e7e700, 0x46464600, 0x71717100, 0xbababa00,
        0xd4d4d400, 0x25252500, 0xababab00, 0x42424200, 0x88888800, 0xa2a2a200,
        0x8d8d8d00, 0xfafafa00, 0x72727200, 0x07070700, 0xb9b9b900, 0x55555500,
        0xf8f8f800, 0xeeeeee00, 0xacacac00, 0x0a0a0a00, 0x36363600, 0x49494900,
        0x2a2a2a00, 0x68686800, 0x3c3c3c00, 0x38383800, 0xf1f1f100, 0xa4a4a400,
        0x40404000, 0x28282800, 0xd3d3d300, 0x7b7b7b00, 0xbbbbbb00, 0xc9c9c900,
        0x43434300, 0xc1c1c100, 0x15151500, 0xe3e3e300, 0xadadad00, 0xf4f4f400,
        0x77777700, 0xc7c7c700, 0x80808000, 0x9e9e9e00
]

/-- Lookup byte in OpenSSL's verbatim SM4 S-box table. -/
def opensslSm4Sbox (x : BitVec 8) : BitVec 8 :=
  BitVec.ofNat 8 (opensslSm4SboxList.getD x.toNat 0)

/-- Lookup byte in OpenSSL's verbatim AES Inverse S-box table. -/
def opensslAesInvSbox (x : BitVec 8) : BitVec 8 :=
  BitVec.ofNat 8 (opensslAesInvSboxList.getD x.toNat 0)

/-- Lookup byte in OpenSSL's verbatim Camellia `SBOX1` table (`Camellia_SBOX[0]`). -/
def opensslCamelliaSbox1 (x : BitVec 8) : BitVec 8 :=
  BitVec.ofNat 8 ((opensslCamelliaSbox1Words.getD x.toNat 0) >>> 24)

/-! ## Finite Field `GF(2^8)` Arithmetic and Algebraic S-box Definitions -/

/-- Pack 8 LSB-first bits into a `BitVec 8`. -/
def packByte (b0 b1 b2 b3 b4 b5 b6 b7 : Bool) : BitVec 8 :=
  BitVec.ofNat 8
    ((if b0 then 1 else 0) + (if b1 then 2 else 0) +
     (if b2 then 4 else 0) + (if b3 then 8 else 0) +
     (if b4 then 16 else 0) + (if b5 then 32 else 0) +
     (if b6 then 64 else 0) + (if b7 then 128 else 0))

/-- Parity (XOR-sum) of all 8 bits of a byte. -/
def parity8 (v : BitVec 8) : Bool :=
  xor (v.getLsbD 0)
    (xor (v.getLsbD 1)
      (xor (v.getLsbD 2)
        (xor (v.getLsbD 3)
          (xor (v.getLsbD 4)
            (xor (v.getLsbD 5)
              (xor (v.getLsbD 6) (v.getLsbD 7)))))))

/-- Apply an 8×8 GF(2)-linear matrix (specified by 8 LSB-first row masks) to a byte. -/
def linMap8 (r0 r1 r2 r3 r4 r5 r6 r7 : BitVec 8) (x : BitVec 8) : BitVec 8 :=
  packByte
    (parity8 (x &&& r0)) (parity8 (x &&& r1))
    (parity8 (x &&& r2)) (parity8 (x &&& r3))
    (parity8 (x &&& r4)) (parity8 (x &&& r5))
    (parity8 (x &&& r6)) (parity8 (x &&& r7))

/-- Multiplication by `x` in `GF(2)[x] / (x^8 + red)`. -/
def gfXtime (red a : BitVec 8) : BitVec 8 :=
  if a.getLsbD 7 then (a <<< 1) ^^^ red else a <<< 1

/-- Shift-and-add multiplication in `GF(2)[x] / (x^8 + red)`. -/
def gfMulAux (red : BitVec 8) : Nat → BitVec 8 → BitVec 8 → BitVec 8 → BitVec 8
  | 0, _, _, acc => acc
  | n + 1, a, b, acc =>
    let acc' := if b.getLsbD 0 then acc ^^^ a else acc
    gfMulAux red n (gfXtime red a) (b >>> 1) acc'

/-- Multiplication in `GF(2^8) = GF(2)[x] / (x^8 + red)`. -/
def gfMul (red a b : BitVec 8) : BitVec 8 :=
  gfMulAux red 8 a b 0#8

/-- Multiplicative inverse in `GF(2^8) = GF(2)[x] / (x^8 + red)` (`x ↦ x^254`, sending `0 ↦ 0`). -/
def gfInv (red x : BitVec 8) : BitVec 8 :=
  let x2 := gfMul red x x
  let x3 := gfMul red x2 x
  let x6 := gfMul red x3 x3
  let x12 := gfMul red x6 x6
  let x15 := gfMul red x12 x3
  let x30 := gfMul red x15 x15
  let x60 := gfMul red x30 x30
  let x120 := gfMul red x60 x60
  let x126 := gfMul red x120 x6
  let x127 := gfMul red x126 x
  gfMul red x127 x127

/-! ### 1. SM4 S-box (RFC 8998 / ISO 18033-3 / GB/T 32907) -/

/-- Multiplicative inverse in `GF(2^8) = GF(2)[x] / (x^8 + x^7 + x^6 + x^5 + x^4 + x^2 + 1)` (`0x1f5`). -/
def gfInvSm4 (x : BitVec 8) : BitVec 8 :=
  gfInv 0xf5#8 x

/-- SM4 affine transformation `A(b)` over GF(2) with constant `0xd3`:
`b'_k = b_k ⊕ b_{(k+1)%8} ⊕ b_{(k+2)%8} ⊕ b_{(k+5)%8} ⊕ b_{(k+7)%8} ⊕ (0xd3)_k`. -/
def sm4Affine (b : BitVec 8) : BitVec 8 :=
  let bit (k : Nat) : Bool :=
    xor (b.getLsbD k)
      (xor (b.getLsbD ((k + 1) % 8))
        (xor (b.getLsbD ((k + 2) % 8))
          (xor (b.getLsbD ((k + 5) % 8))
            (xor (b.getLsbD ((k + 7) % 8)) ((0xd3#8).getLsbD k)))))
  packByte (bit 0) (bit 1) (bit 2) (bit 3) (bit 4) (bit 5) (bit 6) (bit 7)

/-- Algebraic SM4 S-box: `S(x) = A(I(A(x)))` over `GF(2)[x] / (0x1f5)`. -/
def sm4Sbox (x : BitVec 8) : BitVec 8 :=
  sm4Affine (gfInvSm4 (sm4Affine x))

/-! ### 2. AES Inverse S-box (NIST FIPS 197 §5.3.2) -/

/-- Multiplicative inverse in `GF(2^8) = GF(2)[x] / (x^8 + x^4 + x^3 + x + 1)` (`0x11b`). -/
def gfInvAes (x : BitVec 8) : BitVec 8 :=
  gfInv 0x1b#8 x

/-- NIST FIPS 197 forward AES affine transformation with constant `0x63`. -/
def aesAffine (b : BitVec 8) : BitVec 8 :=
  let bit (k : Nat) : Bool :=
    xor (b.getLsbD k)
      (xor (b.getLsbD ((k + 4) % 8))
        (xor (b.getLsbD ((k + 5) % 8))
          (xor (b.getLsbD ((k + 6) % 8))
            (xor (b.getLsbD ((k + 7) % 8)) ((0x63#8).getLsbD k)))))
  packByte (bit 0) (bit 1) (bit 2) (bit 3) (bit 4) (bit 5) (bit 6) (bit 7)

/-- Algebraic NIST FIPS 197 forward AES S-box. -/
def aesSbox (x : BitVec 8) : BitVec 8 :=
  aesAffine (gfInvAes x)

/-- NIST FIPS 197 inverse AES affine transformation over GF(2) with constant `0x05`:
`b'_k = b_{(k+2)%8} ⊕ b_{(k+5)%8} ⊕ b_{(k+7)%8} ⊕ (0x05)_k`. -/
def aesInvAffine (b : BitVec 8) : BitVec 8 :=
  let bit (k : Nat) : Bool :=
    xor (b.getLsbD ((k + 2) % 8))
      (xor (b.getLsbD ((k + 5) % 8))
        (xor (b.getLsbD ((k + 7) % 8)) ((0x05#8).getLsbD k)))
  packByte (bit 0) (bit 1) (bit 2) (bit 3) (bit 4) (bit 5) (bit 6) (bit 7)

/-- Algebraic NIST FIPS 197 AES Inverse S-box: `InvSbox(x) = I(InvAffine(x))` over `GF(2)[x] / (0x11b)`. -/
def aesInvSbox (x : BitVec 8) : BitVec 8 :=
  gfInvAes (aesInvAffine x)

/-! ### 3. Camellia `SBOX1` (RFC 3713 §2.4 / ISO 18033-3) -/

/-- Multiplicative inverse in `GF(2^8) = GF(2)[x] / (x^8 + x^6 + x^5 + x^3 + 1)` (`0x165`). -/
def gfInvCam (x : BitVec 8) : BitVec 8 :=
  gfInv 0x65#8 x

/-- Camellia `SBOX1` input affine map `g(x) = G · (x ⊕ 0xc5)` into `GF(2)[x] / (0x165)`. -/
def camelliaInAffine (x : BitVec 8) : BitVec 8 :=
  linMap8 0x55#8 0x58#8 0x86#8 0x09#8 0x23#8 0x31#8 0x4f#8 0x02#8 (x ^^^ 0xc5#8)

/-- Camellia `SBOX1` output affine map `h(y) = (H · y) ⊕ 0x6e` from `GF(2)[x] / (0x165)`. -/
def camelliaOutAffine (y : BitVec 8) : BitVec 8 :=
  (linMap8 0x9c#8 0x08#8 0x4a#8 0xf4#8 0x09#8 0x5c#8 0x11#8 0x14#8 y) ^^^ 0x6e#8

/-- Algebraic Camellia `SBOX1`: `SBOX1(x) = h(gfInvCam(g(x)))` over `GF(2)[x] / (0x165)`. -/
def camelliaSbox1 (x : BitVec 8) : BitVec 8 :=
  camelliaOutAffine (gfInvCam (camelliaInAffine x))

/-! ## Bit-Sliced `GF(2^8)` Kernel Verification (All 256 Bytes in Parallel) -/

/-- 256 bytes stored bit-sliced as 8 lanes of `BitVec 256`. -/
structure Byte256 where
  b0 : BitVec 256
  b1 : BitVec 256
  b2 : BitVec 256
  b3 : BitVec 256
  b4 : BitVec 256
  b5 : BitVec 256
  b6 : BitVec 256
  b7 : BitVec 256
deriving DecidableEq

def Byte256.at (v : Byte256) (x : BitVec 8) : BitVec 8 :=
  packByte
    (v.b0.getLsbD x.toNat) (v.b1.getLsbD x.toNat)
    (v.b2.getLsbD x.toNat) (v.b3.getLsbD x.toNat)
    (v.b4.getLsbD x.toNat) (v.b5.getLsbD x.toNat)
    (v.b6.getLsbD x.toNat) (v.b7.getLsbD x.toNat)

def Byte256.toList (v : Byte256) : List (BitVec 256) :=
  [v.b0, v.b1, v.b2, v.b3, v.b4, v.b5, v.b6, v.b7]

def Byte256.zero : Byte256 :=
  ⟨0#256, 0#256, 0#256, 0#256, 0#256, 0#256, 0#256, 0#256⟩

def Byte256.xor (a b : Byte256) : Byte256 :=
  ⟨a.b0 ^^^ b.b0, a.b1 ^^^ b.b1, a.b2 ^^^ b.b2, a.b3 ^^^ b.b3,
   a.b4 ^^^ b.b4, a.b5 ^^^ b.b5, a.b6 ^^^ b.b6, a.b7 ^^^ b.b7⟩

def Byte256.mask (m : BitVec 256) (a : Byte256) : Byte256 :=
  ⟨m &&& a.b0, m &&& a.b1, m &&& a.b2, m &&& a.b3,
   m &&& a.b4, m &&& a.b5, m &&& a.b6, m &&& a.b7⟩

def Byte256.const (c : BitVec 8) : Byte256 :=
  let f (b : Bool) : BitVec 256 := if b then BitVec.allOnes 256 else 0#256
  ⟨f (c.getLsbD 0), f (c.getLsbD 1), f (c.getLsbD 2), f (c.getLsbD 3),
   f (c.getLsbD 4), f (c.getLsbD 5), f (c.getLsbD 6), f (c.getLsbD 7)⟩

def Byte256.shl1 (a : Byte256) : Byte256 :=
  ⟨0#256, a.b0, a.b1, a.b2, a.b3, a.b4, a.b5, a.b6⟩

def Byte256.shr1 (a : Byte256) : Byte256 :=
  ⟨a.b1, a.b2, a.b3, a.b4, a.b5, a.b6, a.b7, 0#256⟩

def Byte256.gfXtime (red : BitVec 8) (a : Byte256) : Byte256 :=
  Byte256.xor a.shl1 (Byte256.mask a.b7 (Byte256.const red))

def Byte256.gfMulAux (red : BitVec 8) : Nat → Byte256 → Byte256 → Byte256 → Byte256
  | 0, _, _, acc => acc
  | n + 1, a, b, acc =>
    let acc' := Byte256.xor acc (Byte256.mask b.b0 a)
    Byte256.gfMulAux red n (Byte256.gfXtime red a) b.shr1 acc'

def Byte256.gfMul (red : BitVec 8) (a b : Byte256) : Byte256 :=
  Byte256.gfMulAux red 8 a b Byte256.zero

def Byte256.gfInv (red : BitVec 8) (x : Byte256) : Byte256 :=
  let x2 := Byte256.gfMul red x x
  let x3 := Byte256.gfMul red x2 x
  let x6 := Byte256.gfMul red x3 x3
  let x12 := Byte256.gfMul red x6 x6
  let x15 := Byte256.gfMul red x12 x3
  let x30 := Byte256.gfMul red x15 x15
  let x60 := Byte256.gfMul red x30 x30
  let x120 := Byte256.gfMul red x60 x60
  let x126 := Byte256.gfMul red x120 x6
  let x127 := Byte256.gfMul red x126 x
  Byte256.gfMul red x127 x127

def Byte256.parityMask (r : BitVec 8) (a : Byte256) : BitVec 256 :=
  let s (b : Bool) (v : BitVec 256) : BitVec 256 := if b then v else 0#256
  s (r.getLsbD 0) a.b0 ^^^
    (s (r.getLsbD 1) a.b1 ^^^
      (s (r.getLsbD 2) a.b2 ^^^
        (s (r.getLsbD 3) a.b3 ^^^
          (s (r.getLsbD 4) a.b4 ^^^
            (s (r.getLsbD 5) a.b5 ^^^
              (s (r.getLsbD 6) a.b6 ^^^ s (r.getLsbD 7) a.b7))))))

def Byte256.linMap8 (r0 r1 r2 r3 r4 r5 r6 r7 : BitVec 8) (a : Byte256) : Byte256 :=
  ⟨a.parityMask r0, a.parityMask r1, a.parityMask r2, a.parityMask r3,
   a.parityMask r4, a.parityMask r5, a.parityMask r6, a.parityMask r7⟩

def Byte256.sm4Affine (a : Byte256) : Byte256 :=
  let ones := BitVec.allOnes 256
  ⟨a.b0 ^^^ a.b1 ^^^ a.b2 ^^^ a.b5 ^^^ a.b7 ^^^ ones,
   a.b1 ^^^ a.b2 ^^^ a.b3 ^^^ a.b6 ^^^ a.b0 ^^^ ones,
   a.b2 ^^^ a.b3 ^^^ a.b4 ^^^ a.b7 ^^^ a.b1,
   a.b3 ^^^ a.b4 ^^^ a.b5 ^^^ a.b0 ^^^ a.b2,
   a.b4 ^^^ a.b5 ^^^ a.b6 ^^^ a.b1 ^^^ a.b3 ^^^ ones,
   a.b5 ^^^ a.b6 ^^^ a.b7 ^^^ a.b2 ^^^ a.b4,
   a.b6 ^^^ a.b7 ^^^ a.b0 ^^^ a.b3 ^^^ a.b5 ^^^ ones,
   a.b7 ^^^ a.b0 ^^^ a.b1 ^^^ a.b4 ^^^ a.b6 ^^^ ones⟩

def Byte256.aesAffine (a : Byte256) : Byte256 :=
  let ones := BitVec.allOnes 256
  ⟨a.b0 ^^^ a.b4 ^^^ a.b5 ^^^ a.b6 ^^^ a.b7 ^^^ ones,
   a.b1 ^^^ a.b5 ^^^ a.b6 ^^^ a.b7 ^^^ a.b0 ^^^ ones,
   a.b2 ^^^ a.b6 ^^^ a.b7 ^^^ a.b0 ^^^ a.b1,
   a.b3 ^^^ a.b7 ^^^ a.b0 ^^^ a.b1 ^^^ a.b2,
   a.b4 ^^^ a.b0 ^^^ a.b1 ^^^ a.b2 ^^^ a.b3,
   a.b5 ^^^ a.b1 ^^^ a.b2 ^^^ a.b3 ^^^ a.b4 ^^^ ones,
   a.b6 ^^^ a.b2 ^^^ a.b3 ^^^ a.b4 ^^^ a.b5 ^^^ ones,
   a.b7 ^^^ a.b3 ^^^ a.b4 ^^^ a.b5 ^^^ a.b6⟩

def Byte256.aesInvAffine (a : Byte256) : Byte256 :=
  let ones := BitVec.allOnes 256
  ⟨a.b2 ^^^ a.b5 ^^^ a.b7 ^^^ ones,
   a.b3 ^^^ a.b6 ^^^ a.b0,
   a.b4 ^^^ a.b7 ^^^ a.b1 ^^^ ones,
   a.b5 ^^^ a.b0 ^^^ a.b2,
   a.b6 ^^^ a.b1 ^^^ a.b3,
   a.b7 ^^^ a.b2 ^^^ a.b4,
   a.b0 ^^^ a.b3 ^^^ a.b5,
   a.b1 ^^^ a.b4 ^^^ a.b6⟩

def Byte256.camelliaInAffine (a : Byte256) : Byte256 :=
  Byte256.linMap8 0x55#8 0x58#8 0x86#8 0x09#8 0x23#8 0x31#8 0x4f#8 0x02#8
    (Byte256.xor a (Byte256.const 0xc5#8))

def Byte256.camelliaOutAffine (a : Byte256) : Byte256 :=
  Byte256.xor
    (Byte256.linMap8 0x9c#8 0x08#8 0x4a#8 0xf4#8 0x09#8 0x5c#8 0x11#8 0x14#8 a)
    (Byte256.const 0x6e#8)

def id256 : Byte256 :=
  ⟨0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa#256,
   0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc#256,
   0xf0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0#256,
   0xff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00#256,
   0xffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000#256,
   0xffffffff00000000ffffffff00000000ffffffff00000000ffffffff00000000#256,
   0xffffffffffffffff0000000000000000ffffffffffffffff0000000000000000#256,
   0xffffffffffffffffffffffffffffffff00000000000000000000000000000000#256⟩

def sm4Byte256 : Byte256 :=
  ⟨ 0x75441f4721f61bb7d3afbe01d394f3a20878b950ce966b77729a3d309483a0e4#256,
    0x3e1060ec0841509e4fd6ec7e86520f2f8efc8a9d2eca51f7ea02ada26dbf2b89#256,
    0x1e6cf1f463b014e532fdd02b31ae4aa2ab5d850fe420744ff68572296a6ac7d9#256,
    0xef7d2a9b11e9d6f776f2da4921561847c1104c2d4fc3ce886a7c74e19135705c#256,
    0x5d3706e4dec4f7faca3720035ef456ca82b94c69f1580ef85e8603dd842c27cb#256,
    0x4b9e27c2f3d400d43ea48eaedd2bb7c31a406f92933b94bcd84bd1a8093b72ec#256,
    0xb76e75ca2662cea0fe3be1e690853e3969ad44783b7352391a51baae128a283d#256,
    0x322ad625f4ba827d02730956f31b9faff83180c043ccb19cafdb7079a1a42abf#256 ⟩

def aesInvByte256 : Byte256 :=
  ⟨ 0xbb23f64cbbbe99eb224883fb66f0853ebf6869447a703000fa244cc2c4f6f54a#256,
    0x08fb36349c4492694b3edf05c519cfb1eafca1c41d80c095278af97aa6faed25#256,
    0xd4ed0858cba4d063a8174b51f4f76d70066ecb30ff317f9c914a87953be14968#256,
    0xc21a4f3ceddcc8177b4df9b4da220cd1c67e14b661f51c623a33ab82e2758986#256,
    0x94796cc45c368f8bdb67e21e7645b347242535634bdad5c743a0248f2155e9b9#256,
    0xabba8ef7872d518c98c5572aaf7ef2a1862233241073622f95de21da4167a5f4#256,
    0x9b68a34aa647c842fe7b054beb14def8811147420dbf3d2f5b28f323fc43e20d#256,
    0x015057d3fa286156af3152c24bb37fc247193377f0f0cb5664a46534f2dafd48#256 ⟩

def camelliaByte256 : Byte256 :=
  ⟨ 0x37fc420e4650b7175da27b9572f02ab840b41268bf85a49393f6686cb5ff8eb0#256,
    0xb25c05a3acbc18b4feebefad2fb0a6c1005ddb34a26d061d2c29d9ed4e0f5432#256,
    0xbd00916a43347afca6687613e4626d8821270e91e3f341aae8f13dddbf526fac#256,
    0x843a3ef4d48bb5fbac967032798826296e4526b6052784b7c5ccddfe9f26700c#256,
    0x991c711d81c3ee5232a77dc2e8e1af8aa0e97df7ba71b3543dd49f52d0280c11#256,
    0x1e1afd75a6d97f67e4a8ef802470705d7d69c10c0f703dd840870336a1c759bd#256,
    0x3aed4a398979a6234c55af324ceaf34af457501a916f1138fd7a3cb02d1695c9#256,
    0xeeb4c074f5926edd2356dc55cdb2b8b72cbd4410960df075091b24afc14a53da#256 ⟩

private theorem packByte_nat_bit (b0 b1 b2 b3 b4 b5 b6 b7 : Bool) :
    let n :=
      (if b0 then 1 else 0) + (if b1 then 2 else 0) +
      (if b2 then 4 else 0) + (if b3 then 8 else 0) +
      (if b4 then 16 else 0) + (if b5 then 32 else 0) +
      (if b6 then 64 else 0) + (if b7 then 128 else 0)
    n < 256 ∧
    (n % 2 == 1) = b0 ∧ ((n / 2) % 2 == 1) = b1 ∧
    ((n / 4) % 2 == 1) = b2 ∧ ((n / 8) % 2 == 1) = b3 ∧
    ((n / 16) % 2 == 1) = b4 ∧ ((n / 32) % 2 == 1) = b5 ∧
    ((n / 64) % 2 == 1) = b6 ∧ ((n / 128) % 2 == 1) = b7 := by
  have h0 : (if b0 then 1 else 0) = b0.toNat := by cases b0 <;> rfl
  have h1 : (if b1 then 2 else 0) = 2 * b1.toNat := by cases b1 <;> rfl
  have h2 : (if b2 then 4 else 0) = 4 * b2.toNat := by cases b2 <;> rfl
  have h3 : (if b3 then 8 else 0) = 8 * b3.toNat := by cases b3 <;> rfl
  have h4 : (if b4 then 16 else 0) = 16 * b4.toNat := by cases b4 <;> rfl
  have h5 : (if b5 then 32 else 0) = 32 * b5.toNat := by cases b5 <;> rfl
  have h6 : (if b6 then 64 else 0) = 64 * b6.toNat := by cases b6 <;> rfl
  have h7 : (if b7 then 128 else 0) = 128 * b7.toNat := by cases b7 <;> rfl
  have hb0 : b0.toNat ≤ 1 := by cases b0 <;> decide
  have hb1 : b1.toNat ≤ 1 := by cases b1 <;> decide
  have hb2 : b2.toNat ≤ 1 := by cases b2 <;> decide
  have hb3 : b3.toNat ≤ 1 := by cases b3 <;> decide
  have hb4 : b4.toNat ≤ 1 := by cases b4 <;> decide
  have hb5 : b5.toNat ≤ 1 := by cases b5 <;> decide
  have hb6 : b6.toNat ≤ 1 := by cases b6 <;> decide
  have hb7 : b7.toNat ≤ 1 := by cases b7 <;> decide
  dsimp only
  rw [h0, h1, h2, h3, h4, h5, h6, h7]
  refine ⟨by omega, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · cases b0 <;> simp <;> omega
  · cases b1 <;> simp <;> omega
  · cases b2 <;> simp <;> omega
  · cases b3 <;> simp <;> omega
  · cases b4 <;> simp <;> omega
  · cases b5 <;> simp <;> omega
  · cases b6 <;> simp <;> omega
  · cases b7 <;> simp <;> omega

private theorem packByte_getLsbD_0 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    (packByte a0 a1 a2 a3 a4 a5 a6 a7).getLsbD 0 = a0 := by
  have h := packByte_nat_bit a0 a1 a2 a3 a4 a5 a6 a7
  simpa [packByte, BitVec.getLsbD, Nat.testBit, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt h.1] using h.2.1

private theorem packByte_getLsbD_1 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    (packByte a0 a1 a2 a3 a4 a5 a6 a7).getLsbD 1 = a1 := by
  have h := packByte_nat_bit a0 a1 a2 a3 a4 a5 a6 a7
  simpa [packByte, BitVec.getLsbD, Nat.testBit, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt h.1] using h.2.2.1

private theorem packByte_getLsbD_2 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    (packByte a0 a1 a2 a3 a4 a5 a6 a7).getLsbD 2 = a2 := by
  have h := packByte_nat_bit a0 a1 a2 a3 a4 a5 a6 a7
  simpa [packByte, BitVec.getLsbD, Nat.testBit, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt h.1] using h.2.2.2.1

private theorem packByte_getLsbD_3 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    (packByte a0 a1 a2 a3 a4 a5 a6 a7).getLsbD 3 = a3 := by
  have h := packByte_nat_bit a0 a1 a2 a3 a4 a5 a6 a7
  simpa [packByte, BitVec.getLsbD, Nat.testBit, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt h.1] using h.2.2.2.2.1

private theorem packByte_getLsbD_4 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    (packByte a0 a1 a2 a3 a4 a5 a6 a7).getLsbD 4 = a4 := by
  have h := packByte_nat_bit a0 a1 a2 a3 a4 a5 a6 a7
  simpa [packByte, BitVec.getLsbD, Nat.testBit, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt h.1] using h.2.2.2.2.2.1

private theorem packByte_getLsbD_5 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    (packByte a0 a1 a2 a3 a4 a5 a6 a7).getLsbD 5 = a5 := by
  have h := packByte_nat_bit a0 a1 a2 a3 a4 a5 a6 a7
  simpa [packByte, BitVec.getLsbD, Nat.testBit, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt h.1] using h.2.2.2.2.2.2.1

private theorem packByte_getLsbD_6 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    (packByte a0 a1 a2 a3 a4 a5 a6 a7).getLsbD 6 = a6 := by
  have h := packByte_nat_bit a0 a1 a2 a3 a4 a5 a6 a7
  simpa [packByte, BitVec.getLsbD, Nat.testBit, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt h.1] using h.2.2.2.2.2.2.2.1

private theorem packByte_getLsbD_7 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    (packByte a0 a1 a2 a3 a4 a5 a6 a7).getLsbD 7 = a7 := by
  have h := packByte_nat_bit a0 a1 a2 a3 a4 a5 a6 a7
  simpa [packByte, BitVec.getLsbD, Nat.testBit, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt h.1] using h.2.2.2.2.2.2.2.2

private theorem bv8_ext (a b : BitVec 8)
    (h0 : a.getLsbD 0 = b.getLsbD 0) (h1 : a.getLsbD 1 = b.getLsbD 1)
    (h2 : a.getLsbD 2 = b.getLsbD 2) (h3 : a.getLsbD 3 = b.getLsbD 3)
    (h4 : a.getLsbD 4 = b.getLsbD 4) (h5 : a.getLsbD 5 = b.getLsbD 5)
    (h6 : a.getLsbD 6 = b.getLsbD 6) (h7 : a.getLsbD 7 = b.getLsbD 7) : a = b := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  match i with
  | 0 => exact h0
  | 1 => exact h1
  | 2 => exact h2
  | 3 => exact h3
  | 4 => exact h4
  | 5 => exact h5
  | 6 => exact h6
  | 7 => exact h7
  | _ + 8 => omega

private theorem packByte_xor (a0 a1 a2 a3 a4 a5 a6 a7 b0 b1 b2 b3 b4 b5 b6 b7 : Bool) :
    packByte (xor a0 b0) (xor a1 b1) (xor a2 b2) (xor a3 b3)
             (xor a4 b4) (xor a5 b5) (xor a6 b6) (xor a7 b7) =
      packByte a0 a1 a2 a3 a4 a5 a6 a7 ^^^ packByte b0 b1 b2 b3 b4 b5 b6 b7 := by
  refine bv8_ext _ _ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_
  · rw [BitVec.getLsbD_xor, packByte_getLsbD_0, packByte_getLsbD_0, packByte_getLsbD_0]
  · rw [BitVec.getLsbD_xor, packByte_getLsbD_1, packByte_getLsbD_1, packByte_getLsbD_1]
  · rw [BitVec.getLsbD_xor, packByte_getLsbD_2, packByte_getLsbD_2, packByte_getLsbD_2]
  · rw [BitVec.getLsbD_xor, packByte_getLsbD_3, packByte_getLsbD_3, packByte_getLsbD_3]
  · rw [BitVec.getLsbD_xor, packByte_getLsbD_4, packByte_getLsbD_4, packByte_getLsbD_4]
  · rw [BitVec.getLsbD_xor, packByte_getLsbD_5, packByte_getLsbD_5, packByte_getLsbD_5]
  · rw [BitVec.getLsbD_xor, packByte_getLsbD_6, packByte_getLsbD_6, packByte_getLsbD_6]
  · rw [BitVec.getLsbD_xor, packByte_getLsbD_7, packByte_getLsbD_7, packByte_getLsbD_7]

private theorem packByte_and_mask (m a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    packByte (m && a0) (m && a1) (m && a2) (m && a3)
             (m && a4) (m && a5) (m && a6) (m && a7) =
      if m then packByte a0 a1 a2 a3 a4 a5 a6 a7 else 0#8 := by
  cases m <;> simp [packByte]

private theorem packByte_shl1 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    packByte false a0 a1 a2 a3 a4 a5 a6 = packByte a0 a1 a2 a3 a4 a5 a6 a7 <<< 1 := by
  refine bv8_ext _ _ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_
  · rw [BitVec.getLsbD_shiftLeft, packByte_getLsbD_0]; rfl
  · rw [BitVec.getLsbD_shiftLeft, packByte_getLsbD_1]; simpa using (packByte_getLsbD_0 a0 a1 a2 a3 a4 a5 a6 a7).symm
  · rw [BitVec.getLsbD_shiftLeft, packByte_getLsbD_2]; simpa using (packByte_getLsbD_1 a0 a1 a2 a3 a4 a5 a6 a7).symm
  · rw [BitVec.getLsbD_shiftLeft, packByte_getLsbD_3]; simpa using (packByte_getLsbD_2 a0 a1 a2 a3 a4 a5 a6 a7).symm
  · rw [BitVec.getLsbD_shiftLeft, packByte_getLsbD_4]; simpa using (packByte_getLsbD_3 a0 a1 a2 a3 a4 a5 a6 a7).symm
  · rw [BitVec.getLsbD_shiftLeft, packByte_getLsbD_5]; simpa using (packByte_getLsbD_4 a0 a1 a2 a3 a4 a5 a6 a7).symm
  · rw [BitVec.getLsbD_shiftLeft, packByte_getLsbD_6]; simpa using (packByte_getLsbD_5 a0 a1 a2 a3 a4 a5 a6 a7).symm
  · rw [BitVec.getLsbD_shiftLeft, packByte_getLsbD_7]; simpa using (packByte_getLsbD_6 a0 a1 a2 a3 a4 a5 a6 a7).symm

private theorem packByte_shr1 (a0 a1 a2 a3 a4 a5 a6 a7 : Bool) :
    packByte a1 a2 a3 a4 a5 a6 a7 false = packByte a0 a1 a2 a3 a4 a5 a6 a7 >>> 1 := by
  refine bv8_ext _ _ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_
  · rw [BitVec.getLsbD_ushiftRight, packByte_getLsbD_0, packByte_getLsbD_1]
  · rw [BitVec.getLsbD_ushiftRight, packByte_getLsbD_1, packByte_getLsbD_2]
  · rw [BitVec.getLsbD_ushiftRight, packByte_getLsbD_2, packByte_getLsbD_3]
  · rw [BitVec.getLsbD_ushiftRight, packByte_getLsbD_3, packByte_getLsbD_4]
  · rw [BitVec.getLsbD_ushiftRight, packByte_getLsbD_4, packByte_getLsbD_5]
  · rw [BitVec.getLsbD_ushiftRight, packByte_getLsbD_5, packByte_getLsbD_6]
  · rw [BitVec.getLsbD_ushiftRight, packByte_getLsbD_6, packByte_getLsbD_7]
  · rw [BitVec.getLsbD_ushiftRight, packByte_getLsbD_7]; simp

private theorem packByte_self (c : BitVec 8) :
    packByte (c.getLsbD 0) (c.getLsbD 1) (c.getLsbD 2) (c.getLsbD 3)
             (c.getLsbD 4) (c.getLsbD 5) (c.getLsbD 6) (c.getLsbD 7) = c := by
  refine bv8_ext _ _ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_
  · exact packByte_getLsbD_0 ..
  · exact packByte_getLsbD_1 ..
  · exact packByte_getLsbD_2 ..
  · exact packByte_getLsbD_3 ..
  · exact packByte_getLsbD_4 ..
  · exact packByte_getLsbD_5 ..
  · exact packByte_getLsbD_6 ..
  · exact packByte_getLsbD_7 ..

private theorem Byte256.at_zero (x : BitVec 8) : Byte256.zero.at x = 0#8 := by
  simp [Byte256.zero, Byte256.at, packByte]

private theorem Byte256.at_xor (a b : Byte256) (x : BitVec 8) :
    (a.xor b).at x = a.at x ^^^ b.at x := by
  simp only [Byte256.xor, Byte256.at, BitVec.getLsbD_xor]
  exact packByte_xor ..

private theorem Byte256.at_mask (m : BitVec 256) (a : Byte256) (x : BitVec 8) :
    (a.mask m).at x = if m.getLsbD x.toNat then a.at x else 0#8 := by
  simp only [Byte256.mask, Byte256.at, BitVec.getLsbD_and]
  exact packByte_and_mask ..

private theorem Byte256.at_const (c x : BitVec 8) :
    (Byte256.const c).at x = c := by
  have hx : x.toNat < 256 := x.isLt
  have hbit : ∀ b : Bool, (if b then BitVec.allOnes 256 else 0#256).getLsbD x.toNat = b := by
    intro b
    cases b
    · simp
    · simp only [ite_true, BitVec.getLsbD_allOnes, decide_eq_true_eq]
      exact hx
  simp only [Byte256.const, Byte256.at, hbit]
  exact packByte_self c

private theorem Byte256.at_shl1 (a : Byte256) (x : BitVec 8) :
    a.shl1.at x = a.at x <<< 1 := by
  simp only [Byte256.shl1, Byte256.at, BitVec.getLsbD_zero]
  exact packByte_shl1 ..

private theorem Byte256.at_shr1 (a : Byte256) (x : BitVec 8) :
    a.shr1.at x = a.at x >>> 1 := by
  simp only [Byte256.shr1, Byte256.at, BitVec.getLsbD_zero]
  exact packByte_shr1 ..

private theorem byte256_at_gfXtime (red : BitVec 8) (a : Byte256) (x : BitVec 8) :
    (a.gfXtime red).at x = gfXtime red (a.at x) := by
  simp only [Byte256.gfXtime, Byte256.at_xor, Byte256.at_shl1, Byte256.at_mask, Byte256.at_const, gfXtime]
  have h7 : (a.at x).getLsbD 7 = a.b7.getLsbD x.toNat := packByte_getLsbD_7 ..
  rw [h7]
  cases a.b7.getLsbD x.toNat <;> simp

private theorem byte256_at_gfMulAux (red : BitVec 8) (n : Nat) (a b acc : Byte256) (x : BitVec 8) :
    (Byte256.gfMulAux red n a b acc).at x = gfMulAux red n (a.at x) (b.at x) (acc.at x) := by
  induction n generalizing a b acc with
  | zero => rfl
  | succ n ih =>
    simp only [Byte256.gfMulAux, gfMulAux]
    rw [ih, byte256_at_gfXtime, Byte256.at_shr1, Byte256.at_xor, Byte256.at_mask]
    have h0 : (b.at x).getLsbD 0 = b.b0.getLsbD x.toNat := packByte_getLsbD_0 ..
    rw [h0]
    cases b.b0.getLsbD x.toNat <;> simp

private theorem byte256_at_gfMul (red : BitVec 8) (a b : Byte256) (x : BitVec 8) :
    (Byte256.gfMul red a b).at x = gfMul red (a.at x) (b.at x) := by
  simp [Byte256.gfMul, gfMul, byte256_at_gfMulAux, Byte256.at_zero]

private theorem byte256_at_gfInv (red : BitVec 8) (a : Byte256) (x : BitVec 8) :
    (Byte256.gfInv red a).at x = gfInv red (a.at x) := by
  simp [Byte256.gfInv, gfInv, byte256_at_gfMul]

private theorem byte256_at_parityMask (r : BitVec 8) (a : Byte256) (x : BitVec 8) :
    (a.parityMask r).getLsbD x.toNat = parity8 (a.at x &&& r) := by
  have hsel : ∀ (b : Bool) (v : BitVec 256),
      (if b then v else 0#256).getLsbD x.toNat = (v.getLsbD x.toNat && b) := by
    intro b v; cases b <;> simp
  simp only [Byte256.parityMask, parity8, Byte256.at, BitVec.getLsbD_xor, BitVec.getLsbD_and,
    hsel, packByte_getLsbD_0, packByte_getLsbD_1, packByte_getLsbD_2, packByte_getLsbD_3,
    packByte_getLsbD_4, packByte_getLsbD_5, packByte_getLsbD_6, packByte_getLsbD_7]

private theorem byte256_at_linMap8 (r0 r1 r2 r3 r4 r5 r6 r7 : BitVec 8) (a : Byte256) (x : BitVec 8) :
    (a.linMap8 r0 r1 r2 r3 r4 r5 r6 r7).at x = linMap8 r0 r1 r2 r3 r4 r5 r6 r7 (a.at x) := by
  simp only [Byte256.linMap8, Byte256.at, linMap8, byte256_at_parityMask]

private theorem bool_xor_assoc_5 (a b c d e f : Bool) :
    xor (xor (xor (xor (xor a b) c) d) e) f =
      xor a (xor b (xor c (xor d (xor e f)))) := by
  cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases f <;> rfl

private theorem bool_xor_assoc_5_false (a b c d e : Bool) :
    xor (xor (xor (xor a b) c) d) e =
      xor a (xor b (xor c (xor d (xor e false)))) := by
  cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> rfl

private theorem bool_xor_assoc_3 (a b c d : Bool) :
    xor (xor (xor a b) c) d = xor a (xor b (xor c d)) := by
  cases a <;> cases b <;> cases c <;> cases d <;> rfl

private theorem bool_xor_assoc_3_false (a b c : Bool) :
    xor (xor a b) c = xor a (xor b (xor c false)) := by
  cases a <;> cases b <;> cases c <;> rfl

private theorem packByte_congr {a0 a1 a2 a3 a4 a5 a6 a7 b0 b1 b2 b3 b4 b5 b6 b7 : Bool}
    (h0 : a0 = b0) (h1 : a1 = b1) (h2 : a2 = b2) (h3 : a3 = b3)
    (h4 : a4 = b4) (h5 : a5 = b5) (h6 : a6 = b6) (h7 : a7 = b7) :
    packByte a0 a1 a2 a3 a4 a5 a6 a7 = packByte b0 b1 b2 b3 b4 b5 b6 b7 := by
  subst h0 h1 h2 h3 h4 h5 h6 h7; rfl

private theorem allOnes256_getLsbD (x : BitVec 8) :
    (BitVec.allOnes 256).getLsbD x.toNat = true := by
  rw [BitVec.getLsbD_allOnes]; exact decide_eq_true x.isLt

private theorem byte256_at_sm4Affine (a : Byte256) (x : BitVec 8) :
    a.sm4Affine.at x = sm4Affine (a.at x) := by
  have hx := allOnes256_getLsbD x
  have hc0 : (0xd3#8 : BitVec 8).getLsbD 0 = true := rfl
  have hc1 : (0xd3#8 : BitVec 8).getLsbD 1 = true := rfl
  have hc2 : (0xd3#8 : BitVec 8).getLsbD 2 = false := rfl
  have hc3 : (0xd3#8 : BitVec 8).getLsbD 3 = false := rfl
  have hc4 : (0xd3#8 : BitVec 8).getLsbD 4 = true := rfl
  have hc5 : (0xd3#8 : BitVec 8).getLsbD 5 = false := rfl
  have hc6 : (0xd3#8 : BitVec 8).getLsbD 6 = true := rfl
  have hc7 : (0xd3#8 : BitVec 8).getLsbD 7 = true := rfl
  simp only [Byte256.sm4Affine, sm4Affine, Byte256.at, BitVec.getLsbD_xor, hx,
    Nat.reduceAdd, Nat.reduceMod, hc0, hc1, hc2, hc3, hc4, hc5, hc6, hc7,
    packByte_getLsbD_0, packByte_getLsbD_1, packByte_getLsbD_2, packByte_getLsbD_3,
    packByte_getLsbD_4, packByte_getLsbD_5, packByte_getLsbD_6, packByte_getLsbD_7]
  exact packByte_congr
    (bool_xor_assoc_5 ..) (bool_xor_assoc_5 ..) (bool_xor_assoc_5_false ..) (bool_xor_assoc_5_false ..)
    (bool_xor_assoc_5 ..) (bool_xor_assoc_5_false ..) (bool_xor_assoc_5 ..) (bool_xor_assoc_5 ..)

private theorem byte256_at_aesAffine (a : Byte256) (x : BitVec 8) :
    a.aesAffine.at x = aesAffine (a.at x) := by
  have hx := allOnes256_getLsbD x
  have hc0 : (0x63#8 : BitVec 8).getLsbD 0 = true := rfl
  have hc1 : (0x63#8 : BitVec 8).getLsbD 1 = true := rfl
  have hc2 : (0x63#8 : BitVec 8).getLsbD 2 = false := rfl
  have hc3 : (0x63#8 : BitVec 8).getLsbD 3 = false := rfl
  have hc4 : (0x63#8 : BitVec 8).getLsbD 4 = false := rfl
  have hc5 : (0x63#8 : BitVec 8).getLsbD 5 = true := rfl
  have hc6 : (0x63#8 : BitVec 8).getLsbD 6 = true := rfl
  have hc7 : (0x63#8 : BitVec 8).getLsbD 7 = false := rfl
  simp only [Byte256.aesAffine, aesAffine, Byte256.at, BitVec.getLsbD_xor, hx,
    Nat.reduceAdd, Nat.reduceMod, hc0, hc1, hc2, hc3, hc4, hc5, hc6, hc7,
    packByte_getLsbD_0, packByte_getLsbD_1, packByte_getLsbD_2, packByte_getLsbD_3,
    packByte_getLsbD_4, packByte_getLsbD_5, packByte_getLsbD_6, packByte_getLsbD_7]
  exact packByte_congr
    (bool_xor_assoc_5 ..) (bool_xor_assoc_5 ..) (bool_xor_assoc_5_false ..) (bool_xor_assoc_5_false ..)
    (bool_xor_assoc_5_false ..) (bool_xor_assoc_5 ..) (bool_xor_assoc_5 ..) (bool_xor_assoc_5_false ..)

private theorem byte256_at_aesInvAffine (a : Byte256) (x : BitVec 8) :
    a.aesInvAffine.at x = aesInvAffine (a.at x) := by
  have hx := allOnes256_getLsbD x
  have hc0 : (0x05#8 : BitVec 8).getLsbD 0 = true := rfl
  have hc1 : (0x05#8 : BitVec 8).getLsbD 1 = false := rfl
  have hc2 : (0x05#8 : BitVec 8).getLsbD 2 = true := rfl
  have hc3 : (0x05#8 : BitVec 8).getLsbD 3 = false := rfl
  have hc4 : (0x05#8 : BitVec 8).getLsbD 4 = false := rfl
  have hc5 : (0x05#8 : BitVec 8).getLsbD 5 = false := rfl
  have hc6 : (0x05#8 : BitVec 8).getLsbD 6 = false := rfl
  have hc7 : (0x05#8 : BitVec 8).getLsbD 7 = false := rfl
  simp only [Byte256.aesInvAffine, aesInvAffine, Byte256.at, BitVec.getLsbD_xor, hx,
    Nat.reduceAdd, Nat.reduceMod, hc0, hc1, hc2, hc3, hc4, hc5, hc6, hc7,
    packByte_getLsbD_0, packByte_getLsbD_1, packByte_getLsbD_2, packByte_getLsbD_3,
    packByte_getLsbD_4, packByte_getLsbD_5, packByte_getLsbD_6, packByte_getLsbD_7]
  exact packByte_congr
    (bool_xor_assoc_3 ..) (bool_xor_assoc_3_false ..) (bool_xor_assoc_3 ..) (bool_xor_assoc_3_false ..)
    (bool_xor_assoc_3_false ..) (bool_xor_assoc_3_false ..) (bool_xor_assoc_3_false ..) (bool_xor_assoc_3_false ..)

private theorem byte256_at_camelliaInAffine (a : Byte256) (x : BitVec 8) :
    a.camelliaInAffine.at x = camelliaInAffine (a.at x) := by
  simp [Byte256.camelliaInAffine, camelliaInAffine, byte256_at_linMap8, Byte256.at_xor, Byte256.at_const]

private theorem byte256_at_camelliaOutAffine (a : Byte256) (x : BitVec 8) :
    a.camelliaOutAffine.at x = camelliaOutAffine (a.at x) := by
  simp [Byte256.camelliaOutAffine, camelliaOutAffine, byte256_at_linMap8, Byte256.at_xor, Byte256.at_const]

/-- Fast `O(256)` bit-by-bit check that `id256` encodes the identity map on `0..255`. -/
private def checkId256Aux : Nat → Bool
  | 0 => true
  | n + 1 =>
    let b :=
      (id256.b0.getLsbD n == n.testBit 0) && (id256.b1.getLsbD n == n.testBit 1) &&
      (id256.b2.getLsbD n == n.testBit 2) && (id256.b3.getLsbD n == n.testBit 3) &&
      (id256.b4.getLsbD n == n.testBit 4) && (id256.b5.getLsbD n == n.testBit 5) &&
      (id256.b6.getLsbD n == n.testBit 6) && (id256.b7.getLsbD n == n.testBit 7)
    b && checkId256Aux n

private theorem checkId256_ok : checkId256Aux 256 = true := by
  decide +kernel

private theorem checkId256Aux_sound :
    ∀ (m k : Nat), k < m → checkId256Aux m = true →
      id256.b0.getLsbD k = k.testBit 0 ∧ id256.b1.getLsbD k = k.testBit 1 ∧
      id256.b2.getLsbD k = k.testBit 2 ∧ id256.b3.getLsbD k = k.testBit 3 ∧
      id256.b4.getLsbD k = k.testBit 4 ∧ id256.b5.getLsbD k = k.testBit 5 ∧
      id256.b6.getLsbD k = k.testBit 6 ∧ id256.b7.getLsbD k = k.testBit 7
  | 0, _, hk, _ => by omega
  | m + 1, k, hk, h => by
    simp only [checkId256Aux, Bool.and_eq_true, beq_iff_eq] at h
    by_cases hkm : k = m
    · subst hkm
      rcases h.1 with ⟨⟨⟨⟨⟨⟨⟨h0, h1⟩, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩, h7⟩
      exact ⟨h0, h1, h2, h3, h4, h5, h6, h7⟩
    · exact checkId256Aux_sound m k (by omega) h.2

private theorem id256_bits (x : BitVec 8) :
    id256.b0.getLsbD x.toNat = x.getLsbD 0 ∧ id256.b1.getLsbD x.toNat = x.getLsbD 1 ∧
    id256.b2.getLsbD x.toNat = x.getLsbD 2 ∧ id256.b3.getLsbD x.toNat = x.getLsbD 3 ∧
    id256.b4.getLsbD x.toNat = x.getLsbD 4 ∧ id256.b5.getLsbD x.toNat = x.getLsbD 5 ∧
    id256.b6.getLsbD x.toNat = x.getLsbD 6 ∧ id256.b7.getLsbD x.toNat = x.getLsbD 7 :=
  checkId256Aux_sound 256 x.toNat x.isLt checkId256_ok

private theorem id256_at (x : BitVec 8) : id256.at x = x := by
  have ⟨h0, h1, h2, h3, h4, h5, h6, h7⟩ := id256_bits x
  simp only [Byte256.at, h0, h1, h2, h3, h4, h5, h6, h7]
  exact packByte_self x

private def nonzeroOne256 : Byte256 :=
  ⟨0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe#256,
   0#256, 0#256, 0#256, 0#256, 0#256, 0#256, 0#256⟩

private theorem nonzeroOne256_at (x : BitVec 8) (hx : x ≠ 0#8) : nonzeroOne256.at x = 1#8 := by
  have hne : x.toNat ≠ 0 := by
    intro h0; apply hx; apply BitVec.eq_of_toNat_eq; exact h0
  have hlt : x.toNat < 256 := x.isLt
  have hb0 : (0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe#256).getLsbD x.toNat = true := by
    have heq : (0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe#256 : BitVec 256) =
        BitVec.allOnes 256 ^^^ 1#256 := by decide +kernel
    rw [heq, BitVec.getLsbD_xor, BitVec.getLsbD_allOnes]
    simp [hlt, hne]
  simp [nonzeroOne256, Byte256.at, hb0, packByte]

private theorem gfMul_sm4_inv_eq :
    Byte256.gfMul 0xf5#8 id256 (Byte256.gfInv 0xf5#8 id256) = nonzeroOne256 := by
  decide +kernel

private theorem gfMul_aes_inv_eq :
    Byte256.gfMul 0x1b#8 id256 (Byte256.gfInv 0x1b#8 id256) = nonzeroOne256 := by
  decide +kernel

private theorem gfMul_cam_inv_eq :
    Byte256.gfMul 0x65#8 id256 (Byte256.gfInv 0x65#8 id256) = nonzeroOne256 := by
  decide +kernel

theorem gfInvSm4_mul_self : ∀ x : BitVec 8, x ≠ 0#8 → gfMul 0xf5#8 x (gfInvSm4 x) = 1#8 := by
  intro x hx
  have h := byte256_at_gfMul 0xf5#8 id256 (Byte256.gfInv 0xf5#8 id256) x
  rw [gfMul_sm4_inv_eq, byte256_at_gfInv, id256_at] at h
  rw [gfInvSm4, ← h]
  exact nonzeroOne256_at x hx

theorem gfInvSm4_zero : gfInvSm4 0#8 = 0#8 := by
  decide +kernel

theorem gfInvAes_mul_self : ∀ x : BitVec 8, x ≠ 0#8 → gfMul 0x1b#8 x (gfInvAes x) = 1#8 := by
  intro x hx
  have h := byte256_at_gfMul 0x1b#8 id256 (Byte256.gfInv 0x1b#8 id256) x
  rw [gfMul_aes_inv_eq, byte256_at_gfInv, id256_at] at h
  rw [gfInvAes, ← h]
  exact nonzeroOne256_at x hx

theorem gfInvAes_zero : gfInvAes 0#8 = 0#8 := by
  decide +kernel

theorem gfInvCam_mul_self : ∀ x : BitVec 8, x ≠ 0#8 → gfMul 0x65#8 x (gfInvCam x) = 1#8 := by
  intro x hx
  have h := byte256_at_gfMul 0x65#8 id256 (Byte256.gfInv 0x65#8 id256) x
  rw [gfMul_cam_inv_eq, byte256_at_gfInv, id256_at] at h
  rw [gfInvCam, ← h]
  exact nonzeroOne256_at x hx

theorem gfInvCam_zero : gfInvCam 0#8 = 0#8 := by
  decide +kernel

private theorem sm4_byte256_eq :
    Byte256.sm4Affine (Byte256.gfInv 0xf5#8 (Byte256.sm4Affine id256)) = sm4Byte256 := by
  decide +kernel

private theorem aesInv_byte256_eq :
    Byte256.gfInv 0x1b#8 (Byte256.aesInvAffine id256) = aesInvByte256 := by
  decide +kernel

private theorem camellia_byte256_eq :
    Byte256.camelliaOutAffine (Byte256.gfInv 0x65#8 (Byte256.camelliaInAffine id256)) = camelliaByte256 := by
  decide +kernel

private theorem aesInvAffine_aesAffine_256 :
    Byte256.aesInvAffine (Byte256.aesAffine id256) = id256 := by
  decide +kernel

private theorem aesAffine_aesInvAffine_256 :
    Byte256.aesAffine (Byte256.aesInvAffine id256) = id256 := by
  decide +kernel

private theorem gfInvAes_involution_256 :
    Byte256.gfInv 0x1b#8 (Byte256.gfInv 0x1b#8 id256) = id256 := by
  decide +kernel

/-- `aesInvSbox` is the left inverse of `aesSbox` on all 256 bytes. -/
theorem aesInvSbox_aesSbox : ∀ x : BitVec 8, aesInvSbox (aesSbox x) = x := by
  intro x
  have haff : ∀ b : BitVec 8, aesInvAffine (aesAffine b) = b := by
    intro b
    have h := congrArg (fun v => v.at b) aesInvAffine_aesAffine_256
    simpa [byte256_at_aesInvAffine, byte256_at_aesAffine, id256_at] using h
  have hinv : ∀ b : BitVec 8, gfInvAes (gfInvAes b) = b := by
    intro b
    have h := congrArg (fun v => v.at b) gfInvAes_involution_256
    simpa [gfInvAes, byte256_at_gfInv, id256_at] using h
  simp [aesInvSbox, aesSbox, haff, hinv]

/-- `aesInvSbox` is the right inverse of `aesSbox` on all 256 bytes. -/
theorem aesSbox_aesInvSbox : ∀ x : BitVec 8, aesSbox (aesInvSbox x) = x := by
  intro x
  have haff : ∀ b : BitVec 8, aesAffine (aesInvAffine b) = b := by
    intro b
    have h := congrArg (fun v => v.at b) aesAffine_aesInvAffine_256
    simpa [byte256_at_aesAffine, byte256_at_aesInvAffine, id256_at] using h
  have hinv : ∀ b : BitVec 8, gfInvAes (gfInvAes b) = b := by
    intro b
    have h := congrArg (fun v => v.at b) gfInvAes_involution_256
    simpa [gfInvAes, byte256_at_gfInv, id256_at] using h
  simp [aesSbox, aesInvSbox, hinv, haff]

/-- Linear-time `O(256)` kernel check that a verbatim OpenSSL table list matches a `Byte256`. -/
def checkListEqByte256 (extract : Nat → BitVec 8) (t : Byte256) : Nat → List Nat → Bool
  | _, [] => true
  | i, w :: rest =>
    (extract w == t.at (BitVec.ofNat 8 i)) && checkListEqByte256 extract t (i + 1) rest

private theorem checkListEqByte256_sound (extract : Nat → BitVec 8) (t : Byte256) :
    ∀ (xs : List Nat) (i k : Nat),
      k < xs.length →
      checkListEqByte256 extract t i xs = true →
      extract (xs.getD k 0) = t.at (BitVec.ofNat 8 (i + k))
  | [], _, _, hk, _ => by simp at hk
  | w :: rest, i, 0, _, h => by
    simp only [checkListEqByte256, Bool.and_eq_true, beq_iff_eq] at h
    simpa [List.getD] using h.1
  | w :: rest, i, k + 1, hk, h => by
    simp only [checkListEqByte256, Bool.and_eq_true, beq_iff_eq] at h
    have hk' : k < rest.length := by simpa using hk
    have ih := checkListEqByte256_sound extract t rest (i + 1) k hk' h.2
    have hidx : i + 1 + k = i + (k + 1) := by omega
    simpa [List.getD, hidx] using ih

private theorem opensslSm4_check :
    opensslSm4SboxList.length = 256 ∧
    checkListEqByte256 (BitVec.ofNat 8) sm4Byte256 0 opensslSm4SboxList = true := by
  decide +kernel

private theorem opensslAesInv_check :
    opensslAesInvSboxList.length = 256 ∧
    checkListEqByte256 (BitVec.ofNat 8) aesInvByte256 0 opensslAesInvSboxList = true := by
  decide +kernel

private theorem opensslCamellia_check :
    opensslCamelliaSbox1Words.length = 256 ∧
    checkListEqByte256 (fun w => BitVec.ofNat 8 (w >>> 24)) camelliaByte256 0 opensslCamelliaSbox1Words = true := by
  decide +kernel

/-- Kernel check that every 32-bit word in `opensslCamelliaSbox1Words` has exact `SBOX1_1110` layout. -/
theorem opensslCamelliaSbox1Words_layout :
    opensslCamelliaSbox1Words.all (fun w =>
      let s := w >>> 24
      w == ((s <<< 24) ||| (s <<< 16) ||| (s <<< 8))) = true := by
  decide +kernel

theorem sm4Byte256_eq_opensslSm4Sbox (x : BitVec 8) :
    sm4Byte256.at x = opensslSm4Sbox x := by
  have hk : x.toNat < opensslSm4SboxList.length := by rw [opensslSm4_check.1]; exact x.isLt
  have h := checkListEqByte256_sound (BitVec.ofNat 8) sm4Byte256 opensslSm4SboxList 0 x.toNat hk opensslSm4_check.2
  simpa [opensslSm4Sbox, BitVec.ofNat_toNat] using h.symm

theorem aesInvByte256_eq_opensslAesInvSbox (x : BitVec 8) :
    aesInvByte256.at x = opensslAesInvSbox x := by
  have hk : x.toNat < opensslAesInvSboxList.length := by rw [opensslAesInv_check.1]; exact x.isLt
  have h := checkListEqByte256_sound (BitVec.ofNat 8) aesInvByte256 opensslAesInvSboxList 0 x.toNat hk opensslAesInv_check.2
  simpa [opensslAesInvSbox, BitVec.ofNat_toNat] using h.symm

theorem camelliaByte256_eq_opensslCamelliaSbox1 (x : BitVec 8) :
    camelliaByte256.at x = opensslCamelliaSbox1 x := by
  have hk : x.toNat < opensslCamelliaSbox1Words.length := by rw [opensslCamellia_check.1]; exact x.isLt
  have h := checkListEqByte256_sound (fun w => BitVec.ofNat 8 (w >>> 24)) camelliaByte256 opensslCamelliaSbox1Words 0 x.toNat hk opensslCamellia_check.2
  simpa [opensslCamelliaSbox1, BitVec.ofNat_toNat] using h.symm

/-- The algebraic SM4 S-box agrees with OpenSSL's verbatim `SM4_S[256]` on all 256 bytes. -/
theorem sm4Sbox_eq_opensslSm4Sbox : ∀ x : BitVec 8, sm4Sbox x = opensslSm4Sbox x := by
  intro x
  have h := congrArg (fun v => v.at x) sm4_byte256_eq
  simp only [byte256_at_sm4Affine, byte256_at_gfInv, id256_at] at h
  rw [sm4Sbox, gfInvSm4, h, sm4Byte256_eq_opensslSm4Sbox]

/-- The algebraic AES Inverse S-box agrees with OpenSSL's verbatim `sb3[256]` on all 256 bytes. -/
theorem aesInvSbox_eq_opensslAesInvSbox : ∀ x : BitVec 8, aesInvSbox x = opensslAesInvSbox x := by
  intro x
  have h := congrArg (fun v => v.at x) aesInv_byte256_eq
  simp only [byte256_at_gfInv, byte256_at_aesInvAffine, id256_at] at h
  rw [aesInvSbox, gfInvAes, h, aesInvByte256_eq_opensslAesInvSbox]

/-- The algebraic Camellia `SBOX1` agrees with OpenSSL's verbatim `Camellia_SBOX[0]` on all 256 bytes. -/
theorem camelliaSbox1_eq_opensslCamelliaSbox1 :
    ∀ x : BitVec 8, camelliaSbox1 x = opensslCamelliaSbox1 x := by
  intro x
  have h := congrArg (fun v => v.at x) camellia_byte256_eq
  simp only [byte256_at_camelliaOutAffine, byte256_at_gfInv, byte256_at_camelliaInAffine, id256_at] at h
  rw [camelliaSbox1, gfInvCam, h, camelliaByte256_eq_opensslCamelliaSbox1]

/-! ## Straight-line Boolean circuit AST and semantics -/

/-- Gate semantics over `{0 = xor, 1 = xnor, 2 = and, 3 = not}`. -/
def evalGate (op : Nat) (v1 v2 : Bool) : Bool :=
  match op with
  | 0 => xor v1 v2
  | 1 => !(xor v1 v2)
  | 2 => v1 && v2
  | 3 => !v1
  | _ => false

/-- Evaluate gates in order; gate `i` (0-indexed) produces wire `8 + i`. -/
def evalWiresAux (wires : Array Bool) : List (Nat × Nat × Nat) → Array Bool
  | [] => wires
  | (op, w1, w2) :: rest =>
    let v := evalGate op (wires.getD w1 false) (wires.getD w2 false)
    evalWiresAux (wires.push v) rest

/-- Input wires `0..7` hold input bits `x[0]..x[7]` (LSB-first). -/
def initWires (x : BitVec 8) : Array Bool :=
  #[x.getLsbD 0, x.getLsbD 1, x.getLsbD 2, x.getLsbD 3,
    x.getLsbD 4, x.getLsbD 5, x.getLsbD 6, x.getLsbD 7]

/-- Evaluate a straight-line Boolean circuit `(gates, outputs)` on input byte `x`. -/
def evalCircuit (gates : List (Nat × Nat × Nat)) (outputs : List Nat) (x : BitVec 8) : BitVec 8 :=
  let wires := evalWiresAux (initWires x) gates
  let outBit (i : Nat) : Bool := wires.getD (outputs.getD i 0) false
  packByte (outBit 0) (outBit 1) (outBit 2) (outBit 3)
           (outBit 4) (outBit 5) (outBit 6) (outBit 7)

/-- Check that every gate `i` has `op < 4` and causal wire inputs `< 8 + i`. -/
def wellFormedGates (n : Nat) : List (Nat × Nat × Nat) → Bool
  | [] => true
  | (op, w1, w2) :: rest =>
    (op < 4 && w1 < n && w2 < n) && wellFormedGates (n + 1) rest

/-- Check `outputs.length == 8`, every gate op `< 4`, every gate input `< 8 + i`,
and every output wire `< 8 + gates.length`. -/
def wellFormed (gates : List (Nat × Nat × Nat)) (outputs : List Nat) : Bool :=
  let numWires := 8 + gates.length
  outputs.length == 8 && wellFormedGates 8 gates && outputs.all (fun w => w < numWires)

/-- Count the number of AND (`op == 2`) gates in a circuit. -/
def andCount : List (Nat × Nat × Nat) → Nat
  | [] => 0
  | (op, _, _) :: rest => (if op == 2 then 1 else 0) + andCount rest

/-- Existence of a well-formed circuit computing `target` with exactly `n` total gates. -/
def ValidTotalCircuit (target : BitVec 8 → BitVec 8) (n : Nat) : Prop :=
  ∃ gates outputs,
    wellFormed gates outputs = true ∧
    gates.length = n ∧
    ∀ x : BitVec 8, evalCircuit gates outputs x = target x

/-- Existence of a well-formed circuit computing `target` with exactly `n` AND gates. -/
def ValidAndCircuit (target : BitVec 8 → BitVec 8) (n : Nat) : Prop :=
  ∃ gates outputs,
    wellFormed gates outputs = true ∧
    andCount gates = n ∧
    ∀ x : BitVec 8, evalCircuit gates outputs x = target x

/-! ## Bit-sliced 256-input circuit kernel evaluator -/

def evalGate256 (op : Nat) (v1 v2 : BitVec 256) : BitVec 256 :=
  match op with
  | 0 => v1 ^^^ v2
  | 1 => ~~~(v1 ^^^ v2)
  | 2 => v1 &&& v2
  | 3 => ~~~v1
  | _ => 0#256

/-- Lookup wire `w` in a reversed wire list of length `n` (`O(1)` cons during evaluation). -/
def getRevWire (n : Nat) (revWires : List (BitVec 256)) (w : Nat) : BitVec 256 :=
  if w < n then revWires.getD (n - 1 - w) 0#256 else 0#256

def evalWires256Aux (n : Nat) (revWires : List (BitVec 256)) :
    List (Nat × Nat × Nat) → Nat × List (BitVec 256)
  | [] => (n, revWires)
  | (op, w1, w2) :: rest =>
    let v := evalGate256 op (getRevWire n revWires w1) (getRevWire n revWires w2)
    evalWires256Aux (n + 1) (v :: revWires) rest

/-- Reversed list of the 8 input bit truth tables (wire 7 at head, wire 0 at tail). -/
def initRevWires256 : List (BitVec 256) :=
  [ id256.b7, id256.b6, id256.b5, id256.b4, id256.b3, id256.b2, id256.b1, id256.b0 ]

def sm4Table256 : List (BitVec 256) := sm4Byte256.toList
def aesInvTable256 : List (BitVec 256) := aesInvByte256.toList
def camelliaTable256 : List (BitVec 256) := camelliaByte256.toList

/-- Evaluate all 256 inputs simultaneously as 256-bit truth tables and compare to `table`. -/
def checkCircuit256 (table : List (BitVec 256))
    (gates : List (Nat × Nat × Nat)) (outputs : List Nat) : Bool :=
  let (n, wires) := evalWires256Aux 8 initRevWires256 gates
  (getRevWire n wires (outputs.getD 0 0) == table.getD 0 0#256) &&
  (getRevWire n wires (outputs.getD 1 0) == table.getD 1 0#256) &&
  (getRevWire n wires (outputs.getD 2 0) == table.getD 2 0#256) &&
  (getRevWire n wires (outputs.getD 3 0) == table.getD 3 0#256) &&
  (getRevWire n wires (outputs.getD 4 0) == table.getD 4 0#256) &&
  (getRevWire n wires (outputs.getD 5 0) == table.getD 5 0#256) &&
  (getRevWire n wires (outputs.getD 6 0) == table.getD 6 0#256) &&
  (getRevWire n wires (outputs.getD 7 0) == table.getD 7 0#256)

theorem evalGate256_getLsbD (op : Nat) (v1 v2 : BitVec 256) (x : BitVec 8) :
    (evalGate256 op v1 v2).getLsbD x.toNat =
      evalGate op (v1.getLsbD x.toNat) (v2.getLsbD x.toNat) := by
  have hx : x.toNat < 256 := x.isLt
  match op with
  | 0 => simp [evalGate256, evalGate]
  | 1 => simp [evalGate256, evalGate, hx]
  | 2 => simp [evalGate256, evalGate]
  | 3 => simp [evalGate256, evalGate, hx]
  | _ + 4 => simp [evalGate256, evalGate]

theorem array_getD_push_eq {α : Type} (a : Array α) (v d : α) (i : Nat) :
    (a.push v).getD i d = if i < a.size then a.getD i d else if i = a.size then v else d := by
  by_cases h1 : i < a.size
  · have hlt : i < (a.push v).size := by rw [Array.size_push]; omega
    simp only [Array.getD, h1, hlt, dite_true, ite_true]
    exact Array.getElem_push_lt h1
  · by_cases h2 : i = a.size
    · subst h2
      have hlt : a.size < (a.push v).size := by rw [Array.size_push]; omega
      simp only [Array.getD, h1, hlt, dite_true, ite_false, ite_true]
      exact Array.getElem_push_eq
    · have hge : ¬ (i < (a.push v).size) := by rw [Array.size_push]; omega
      simp only [Array.getD, h1, h2, hge, dite_false, ite_false]

theorem getRevWire_cons (n : Nat) (revWires : List (BitVec 256)) (v : BitVec 256) (w : Nat) :
    getRevWire (n + 1) (v :: revWires) w =
      if w < n then getRevWire n revWires w else if w = n then v else 0#256 := by
  unfold getRevWire
  by_cases h1 : w < n
  · have hlt : w < n + 1 := by omega
    have hidx : n + 1 - 1 - w = (n - 1 - w) + 1 := by omega
    simp only [h1, hlt, ite_true, hidx, List.getD_cons_succ]
  · by_cases h2 : w = n
    · subst h2
      have hlt : w < w + 1 := by omega
      have hidx : w + 1 - 1 - w = 0 := by omega
      simp only [h1, hlt, ite_false, ite_true, hidx, List.getD_cons_zero]
    · have hge : ¬ (w < n + 1) := by omega
      simp only [h1, h2, hge, ite_false]

theorem evalWires256Aux_getLsbD (gates : List (Nat × Nat × Nat))
    (n : Nat) (revWires : List (BitVec 256)) (w1 : Array Bool) (x : BitVec 8)
    (hsz : n = w1.size)
    (hinv : ∀ i, (getRevWire n revWires i).getLsbD x.toNat = w1.getD i false) :
    let res := evalWires256Aux n revWires gates
    ∀ i, (getRevWire res.1 res.2 i).getLsbD x.toNat =
      (evalWiresAux w1 gates).getD i false := by
  induction gates generalizing n revWires w1 with
  | nil => exact hinv
  | cons g rest ih =>
    rcases g with ⟨op, a, b⟩
    simp only [evalWires256Aux, evalWiresAux]
    apply ih
    · simp [hsz]
    · intro i
      rw [getRevWire_cons, array_getD_push_eq, hsz]
      by_cases h1 : i < w1.size
      · simp only [h1, ite_true]; rw [← hsz]; exact hinv i
      · by_cases h2 : i = w1.size
        · simp only [h1, ite_false]
          simp only [h2, ite_true]
          rw [evalGate256_getLsbD, ← hsz, hinv a, hinv b]
        · simp only [h1, h2, ite_false]; simp

theorem initRevWires256_correct (x : BitVec 8) (i : Fin 8) :
    (getRevWire 8 initRevWires256 i.val).getLsbD x.toNat = (initWires x).getD i.val false := by
  have ⟨h0, h1, h2, h3, h4, h5, h6, h7⟩ := id256_bits x
  rcases i with ⟨k, hk⟩
  match k with
  | 0 => simpa [getRevWire, initRevWires256, initWires, Array.getD] using h0
  | 1 => simpa [getRevWire, initRevWires256, initWires, Array.getD] using h1
  | 2 => simpa [getRevWire, initRevWires256, initWires, Array.getD] using h2
  | 3 => simpa [getRevWire, initRevWires256, initWires, Array.getD] using h3
  | 4 => simpa [getRevWire, initRevWires256, initWires, Array.getD] using h4
  | 5 => simpa [getRevWire, initRevWires256, initWires, Array.getD] using h5
  | 6 => simpa [getRevWire, initRevWires256, initWires, Array.getD] using h6
  | 7 => simpa [getRevWire, initRevWires256, initWires, Array.getD] using h7
  | _ + 8 => omega

/-- Generic soundness of bit-sliced verification: a passing `checkCircuit256 table.toList`
proves exact pointwise agreement with `target` on all 256 input bytes. -/
theorem evalCircuit_eq_of_checkCircuit256
    (target : BitVec 8 → BitVec 8) (table : Byte256)
    (htable : ∀ x : BitVec 8, table.at x = target x)
    (gates : List (Nat × Nat × Nat)) (outputs : List Nat)
    (hcheck : checkCircuit256 table.toList gates outputs = true) :
    ∀ x : BitVec 8, evalCircuit gates outputs x = target x := by
  intro x
  have hinv0 : ∀ i, (getRevWire 8 initRevWires256 i).getLsbD x.toNat = (initWires x).getD i false := by
    intro i
    by_cases hi : i < 8
    · exact initRevWires256_correct x ⟨i, hi⟩
    · simp [getRevWire, Array.getD, initWires, hi]
  have hwires := evalWires256Aux_getLsbD gates 8 initRevWires256 (initWires x) x rfl hinv0
  simp only [checkCircuit256, Byte256.toList, List.getD, Bool.and_eq_true, beq_iff_eq] at hcheck
  rcases hcheck with ⟨⟨⟨⟨⟨⟨⟨h0, h1⟩, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩, h7⟩
  have hb : ∀ k v,
      getRevWire (evalWires256Aux 8 initRevWires256 gates).1
        (evalWires256Aux 8 initRevWires256 gates).2 (outputs.getD k 0) = v →
      (evalWiresAux (initWires x) gates).getD (outputs.getD k 0) false = v.getLsbD x.toNat := by
    intro k v heq
    rw [← hwires (outputs.getD k 0), heq]
  simp only [evalCircuit]
  rw [hb 0 _ h0, hb 1 _ h1, hb 2 _ h2, hb 3 _ h3, hb 4 _ h4, hb 5 _ h5, hb 6 _ h6, hb 7 _ h7]
  exact htable x

theorem evalCircuit_eq_sm4Sbox_of_checkCircuit256 (gates : List (Nat × Nat × Nat)) (outputs : List Nat)
    (hcheck : checkCircuit256 sm4Table256 gates outputs = true) :
    ∀ x : BitVec 8, evalCircuit gates outputs x = sm4Sbox x :=
  evalCircuit_eq_of_checkCircuit256 sm4Sbox sm4Byte256
    (fun x => by rw [sm4Byte256_eq_opensslSm4Sbox x, sm4Sbox_eq_opensslSm4Sbox x])
    gates outputs hcheck

theorem evalCircuit_eq_aesInvSbox_of_checkCircuit256 (gates : List (Nat × Nat × Nat)) (outputs : List Nat)
    (hcheck : checkCircuit256 aesInvTable256 gates outputs = true) :
    ∀ x : BitVec 8, evalCircuit gates outputs x = aesInvSbox x :=
  evalCircuit_eq_of_checkCircuit256 aesInvSbox aesInvByte256
    (fun x => by rw [aesInvByte256_eq_opensslAesInvSbox x, aesInvSbox_eq_opensslAesInvSbox x])
    gates outputs hcheck

theorem evalCircuit_eq_camelliaSbox1_of_checkCircuit256 (gates : List (Nat × Nat × Nat)) (outputs : List Nat)
    (hcheck : checkCircuit256 camelliaTable256 gates outputs = true) :
    ∀ x : BitVec 8, evalCircuit gates outputs x = camelliaSbox1 x :=
  evalCircuit_eq_of_checkCircuit256 camelliaSbox1 camelliaByte256
    (fun x => by rw [camelliaByte256_eq_opensslCamelliaSbox1 x, camelliaSbox1_eq_opensslCamelliaSbox1 x])
    gates outputs hcheck

end CryptoSbox
