/-!
# Cryptographic Diffusion Layers and Straight-Line `GF(2)`-Linear XOR Circuit Semantics

This module pins OpenSSL's verbatim C diffusion layer implementations at commit
`d94024ffc7e726566a6255228ad0a7de4cfc956d` (Apache-2.0) for six standardized
cryptographic linear layers:

1. **AES `MixColumns`** (NIST FIPS 197 §5.1.3, `32×32` over `GF(2)`), from `crypto/aes/aes_core.c`.
2. **AES `InvMixColumns`** (NIST FIPS 197 §5.3.3, `32×32` over `GF(2)`), from `crypto/aes/aes_core.c`.
3. **SM4 round diffusion `L`** (RFC 8998 / ISO 18033-3, `32×32` over `GF(2)`), from `crypto/sm4/sm4.c`.
4. **SM4 key-schedule diffusion `L'`** (RFC 8998 / ISO 18033-3, `32×32` over `GF(2)`), from `crypto/sm4/sm4.c`.
5. **ARIA involutory diffusion `A`** (RFC 5794 / ISO 18033-3, `16×16` over `GF(2)`), from `crypto/aria/aria.c`.
6. **Camellia `P`-function** (RFC 3713 §2.3 / ISO 18033-3, `8×8` over `GF(2)`), from `crypto/camellia/camellia.c`.

All algebraic equivalences, invertibility/involution theorems, and the Fundamental
Linearity Soundness Theorem (lifting a single-pass basis-mask check to all `2^n` inputs)
are formally proved inside the Lean 4.36.0 kernel with zero Mathlib and zero `sorry`.
-/

namespace CryptoLinearXor

/-! ## Verbatim OpenSSL Reference Sources (`openssl/openssl@d94024ff`, Apache-2.0)

### 1. AES `XtimeLong`, `MixColumns`, and `InvMixColumns` (`crypto/aes/aes_core.c`)

```c
static void XtimeLong(uint64_t *w)
{
    uint64_t a, b;

    a = *w;
    b = a & U64(0x8080808080808080);
    a ^= b;
    b -= b >> 7;
    b &= U64(0x1B1B1B1B1B1B1B1B);
    b ^= a << 1;
    *w = b;
}
```

```c
static void MixColumns(uint64_t *state)
{
    uni s1;
    uni s;
    int c;

    for (c = 0; c < 2; c++) {
        s1.d = state[c];
        s.d = s1.d;
        s.d ^= ((s.d & U64(0xFFFF0000FFFF0000)) >> 16)
            | ((s.d & U64(0x0000FFFF0000FFFF)) << 16);
        s.d ^= ((s.d & U64(0xFF00FF00FF00FF00)) >> 8)
            | ((s.d & U64(0x00FF00FF00FF00FF)) << 8);
        s.d ^= s1.d;
        XtimeLong(&s1.d);
        s.d ^= s1.d;
        s.b[0] ^= s1.b[1];
        s.b[1] ^= s1.b[2];
        s.b[2] ^= s1.b[3];
        s.b[3] ^= s1.b[0];
        s.b[4] ^= s1.b[5];
        s.b[5] ^= s1.b[6];
        s.b[6] ^= s1.b[7];
        s.b[7] ^= s1.b[4];
        state[c] = s.d;
    }
}

static void InvMixColumns(uint64_t *state)
{
    uni s1;
    uni s;
    int c;

    for (c = 0; c < 2; c++) {
        s1.d = state[c];
        s.d = s1.d;
        s.d ^= ((s.d & U64(0xFFFF0000FFFF0000)) >> 16)
            | ((s.d & U64(0x0000FFFF0000FFFF)) << 16);
        s.d ^= ((s.d & U64(0xFF00FF00FF00FF00)) >> 8)
            | ((s.d & U64(0x00FF00FF00FF00FF)) << 8);
        s.d ^= s1.d;
        XtimeLong(&s1.d);
        s.d ^= s1.d;
        s.b[0] ^= s1.b[1];
        s.b[1] ^= s1.b[2];
        s.b[2] ^= s1.b[3];
        s.b[3] ^= s1.b[0];
        s.b[4] ^= s1.b[5];
        s.b[5] ^= s1.b[6];
        s.b[6] ^= s1.b[7];
        s.b[7] ^= s1.b[4];
        XtimeLong(&s1.d);
        s1.d ^= ((s1.d & U64(0xFFFF0000FFFF0000)) >> 16)
            | ((s1.d & U64(0x0000FFFF0000FFFF)) << 16);
        s.d ^= s1.d;
        XtimeLong(&s1.d);
        s1.d ^= ((s1.d & U64(0xFF00FF00FF00FF00)) >> 8)
            | ((s1.d & U64(0x00FF00FF00FF00FF)) << 8);
        s.d ^= s1.d;
        state[c] = s.d;
    }
}
```

### 2. SM4 `rotl`, `SM4_T_slow` (`L`), and `SM4_key_sub` (`L'`) (`crypto/sm4/sm4.c`)

```c
static ossl_inline uint32_t rotl(uint32_t a, uint8_t n)
{
    return (a << n) | (a >> (32 - n));
}
```

```c
static ossl_inline uint32_t SM4_T_slow(uint32_t X)
{
    uint32_t t = SM4_T_non_lin_sub(X);

    /*
     * L linear transform
     */
    return t ^ rotl(t, 2) ^ rotl(t, 10) ^ rotl(t, 18) ^ rotl(t, 24);
}

static ossl_inline uint32_t SM4_T(uint32_t X)
{
    return SM4_SBOX_T0[(uint8_t)(X >> 24)] ^ SM4_SBOX_T1[(uint8_t)(X >> 16)] ^ SM4_SBOX_T2[(uint8_t)(X >> 8)] ^ SM4_SBOX_T3[(uint8_t)X];
}

static ossl_inline uint32_t SM4_key_sub(uint32_t X)
{
    uint32_t t = SM4_T_non_lin_sub(X);

    return t ^ rotl(t, 13) ^ rotl(t, 23);
}
```

### 3. ARIA Diffusion Layer `a()` (`crypto/aria/aria.c`)

```c
static void a(ARIA_u128 *y, const ARIA_u128 *x)
{
    y->c[0] = x->c[3] ^ x->c[4] ^ x->c[6] ^ x->c[8] ^ x->c[9] ^ x->c[13] ^ x->c[14];
    y->c[1] = x->c[2] ^ x->c[5] ^ x->c[7] ^ x->c[8] ^ x->c[9] ^ x->c[12] ^ x->c[15];
    y->c[2] = x->c[1] ^ x->c[4] ^ x->c[6] ^ x->c[10] ^ x->c[11] ^ x->c[12] ^ x->c[15];
    y->c[3] = x->c[0] ^ x->c[5] ^ x->c[7] ^ x->c[10] ^ x->c[11] ^ x->c[13] ^ x->c[14];
    y->c[4] = x->c[0] ^ x->c[2] ^ x->c[5] ^ x->c[8] ^ x->c[11] ^ x->c[14] ^ x->c[15];
    y->c[5] = x->c[1] ^ x->c[3] ^ x->c[4] ^ x->c[9] ^ x->c[10] ^ x->c[14] ^ x->c[15];
    y->c[6] = x->c[0] ^ x->c[2] ^ x->c[7] ^ x->c[9] ^ x->c[10] ^ x->c[12] ^ x->c[13];
    y->c[7] = x->c[1] ^ x->c[3] ^ x->c[6] ^ x->c[8] ^ x->c[11] ^ x->c[12] ^ x->c[13];
    y->c[8] = x->c[0] ^ x->c[1] ^ x->c[4] ^ x->c[7] ^ x->c[10] ^ x->c[13] ^ x->c[15];
    y->c[9] = x->c[0] ^ x->c[1] ^ x->c[5] ^ x->c[6] ^ x->c[11] ^ x->c[12] ^ x->c[14];
    y->c[10] = x->c[2] ^ x->c[3] ^ x->c[5] ^ x->c[6] ^ x->c[8] ^ x->c[13] ^ x->c[15];
    y->c[11] = x->c[2] ^ x->c[3] ^ x->c[4] ^ x->c[7] ^ x->c[9] ^ x->c[12] ^ x->c[14];
    y->c[12] = x->c[1] ^ x->c[2] ^ x->c[6] ^ x->c[7] ^ x->c[9] ^ x->c[11] ^ x->c[12];
    y->c[13] = x->c[0] ^ x->c[3] ^ x->c[6] ^ x->c[7] ^ x->c[8] ^ x->c[10] ^ x->c[13];
    y->c[14] = x->c[0] ^ x->c[3] ^ x->c[4] ^ x->c[5] ^ x->c[9] ^ x->c[11] ^ x->c[14];
    y->c[15] = x->c[1] ^ x->c[2] ^ x->c[4] ^ x->c[5] ^ x->c[8] ^ x->c[10] ^ x->c[15];
}
```

### 4. Camellia `SBOX1_1110`..`SBOX3_3033` and `Camellia_Feistel` (`crypto/camellia/camellia.c`)

```c
#define SBOX1_1110 Camellia_SBOX[0]
#define SBOX4_4404 Camellia_SBOX[1]
#define SBOX2_0222 Camellia_SBOX[2]
#define SBOX3_3033 Camellia_SBOX[3]
```

```c
#define Camellia_Feistel(_s0, _s1, _s2, _s3, _key) \
    do {                                           \
        register uint32_t _t0, _t1, _t2, _t3;      \
                                                   \
        _t0 = _s0 ^ (_key)[0];                     \
        _t3 = SBOX4_4404[_t0 & 0xff];              \
        _t1 = _s1 ^ (_key)[1];                     \
        _t3 ^= SBOX3_3033[(_t0 >> 8) & 0xff];      \
        _t2 = SBOX1_1110[_t1 & 0xff];              \
        _t3 ^= SBOX2_0222[(_t0 >> 16) & 0xff];     \
        _t2 ^= SBOX4_4404[(_t1 >> 8) & 0xff];      \
        _t3 ^= SBOX1_1110[(_t0 >> 24)];            \
        _t2 ^= _t3;                                \
        _t3 = RightRotate(_t3, 8);                 \
        _t2 ^= SBOX3_3033[(_t1 >> 16) & 0xff];     \
        _s3 ^= _t3;                                \
        _t2 ^= SBOX2_0222[(_t1 >> 24)];            \
        _s2 ^= _t2;                                \
        _s3 ^= _t2;                                \
    } while (0)
```
-/

/-! ## `GF(2)` Linear Algebra over `BitVec n` -/

/-- `j`-th standard basis vector `e_j = 1 <<< j` in `GF(2)^n`. -/
def basisVec (n j : Nat) : BitVec n :=
  (1#n) <<< j

theorem basisVec_getLsbD (n j i : Nat) :
    (basisVec n j).getLsbD i = (decide (i < n) && decide (i = j)) := by
  unfold basisVec
  rw [BitVec.getLsbD_shiftLeft]
  by_cases hi : i < n
  · by_cases hij : i = j
    · subst hij
      have h0 : 0 < n := by omega
      simp [hi, h0]
    · by_cases hlt : i < j
      · simp [hi, hij, hlt]
      · have hpos : i - j ≠ 0 := by omega
        have htb : Nat.testBit 1 (i - j) = false := by
          cases hm : i - j with
          | zero => omega
          | succ m => simp [Nat.testBit_succ]
        simp [hi, hij, hlt, BitVec.getLsbD_ofNat, htb]
  · simp [hi]

/-- Pack bits `f 0, ..., f (k - 1)` into a `BitVec n` via basis XOR-sum. -/
def packBitsAux (n : Nat) (f : Nat → Bool) : Nat → BitVec n
  | 0 => 0#n
  | k + 1 => packBitsAux n f k ^^^ (if f k then basisVec n k else 0#n)

/-- Pack `n` LSB-first bits `f 0, ..., f (n - 1)` into a `BitVec n`. -/
def packBits (n : Nat) (f : Nat → Bool) : BitVec n :=
  packBitsAux n f n

theorem packBitsAux_getLsbD (n : Nat) (f : Nat → Bool) (i : Nat) :
    ∀ k, (packBitsAux n f k).getLsbD i = if i < k ∧ i < n then f i else false
  | 0 => by simp [packBitsAux]
  | k + 1 => by
    simp only [packBitsAux, BitVec.getLsbD_xor, packBitsAux_getLsbD n f i k]
    by_cases hlt : i < k
    · have hne : i ≠ k := by omega
      have hlt' : i < k + 1 := by omega
      cases f k <;> simp [hlt, hlt', hne, basisVec_getLsbD]
    · by_cases heq : i = k
      · subst heq
        by_cases hn : i < n
        · cases f i <;> simp [hn, basisVec_getLsbD]
        · cases f i <;> simp [hn, basisVec_getLsbD]
      · have hgt : ¬ (i < k + 1) := by omega
        cases f k <;> simp [hlt, hgt, heq, basisVec_getLsbD]

theorem packBits_getLsbD (n : Nat) (f : Nat → Bool) (i : Nat) :
    (packBits n f).getLsbD i = if i < n then f i else false := by
  simpa [packBits] using packBitsAux_getLsbD n f i n

theorem packBits_getLsbD_self {n : Nat} (x : BitVec n) :
    packBits n (fun j => x.getLsbD j) = x := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  simp only [packBits_getLsbD, hi, ite_true]

/-- Inner product `⨁_{j < k} (m[j] ∧ x[j])` over `GF(2)`. -/
def dotParityAux {n : Nat} (m x : BitVec n) : Nat → Bool
  | 0 => false
  | j + 1 => xor (dotParityAux m x j) (m.getLsbD j && x.getLsbD j)

/-- Inner product `⟨m, x⟩ = ⨁_{j < n} (m[j] ∧ x[j])` over `GF(2)`. -/
def dotParity (n : Nat) (m x : BitVec n) : Bool :=
  dotParityAux m x n

theorem dotParityAux_zero_left {n : Nat} (x : BitVec n) :
    ∀ k, dotParityAux (0#n) x k = false
  | 0 => rfl
  | k + 1 => by simp [dotParityAux, dotParityAux_zero_left x k]

theorem dotParityAux_zero_right {n : Nat} (m : BitVec n) :
    ∀ k, dotParityAux m (0#n) k = false
  | 0 => rfl
  | k + 1 => by simp [dotParityAux, dotParityAux_zero_right m k]

private theorem xor_and_distrib (a b c : Bool) :
    (xor a b && c) = xor (a && c) (b && c) := by
  cases a <;> cases b <;> cases c <;> rfl

private theorem and_xor_distrib (a b c : Bool) :
    (a && xor b c) = xor (a && b) (a && c) := by
  cases a <;> cases b <;> cases c <;> rfl

private theorem xor_four_swap (a b c d : Bool) :
    xor (xor a b) (xor c d) = xor (xor a c) (xor b d) := by
  cases a <;> cases b <;> cases c <;> cases d <;> rfl

theorem dotParityAux_xor_left {n : Nat} (u v x : BitVec n) :
    ∀ k, dotParityAux (u ^^^ v) x k = xor (dotParityAux u x k) (dotParityAux v x k)
  | 0 => rfl
  | k + 1 => by
    simp only [dotParityAux, dotParityAux_xor_left u v x k, BitVec.getLsbD_xor, xor_and_distrib]
    exact xor_four_swap _ _ _ _

theorem dotParityAux_xor_right {n : Nat} (m x y : BitVec n) :
    ∀ k, dotParityAux m (x ^^^ y) k = xor (dotParityAux m x k) (dotParityAux m y k)
  | 0 => rfl
  | k + 1 => by
    simp only [dotParityAux, dotParityAux_xor_right m x y k, BitVec.getLsbD_xor, and_xor_distrib]
    exact xor_four_swap _ _ _ _

theorem dotParity_zero_left (n : Nat) (x : BitVec n) : dotParity n 0#n x = false :=
  dotParityAux_zero_left x n

theorem dotParity_zero_right (n : Nat) (m : BitVec n) : dotParity n m 0#n = false :=
  dotParityAux_zero_right m n

theorem dotParity_xor_left (n : Nat) (u v x : BitVec n) :
    dotParity n (u ^^^ v) x = xor (dotParity n u x) (dotParity n v x) :=
  dotParityAux_xor_left u v x n

theorem dotParity_xor_right (n : Nat) (m x y : BitVec n) :
    dotParity n m (x ^^^ y) = xor (dotParity n m x) (dotParity n m y) :=
  dotParityAux_xor_right m x y n

theorem dotParityAux_basisVec_left {n : Nat} (j : Nat) (hj : j < n) (x : BitVec n) :
    ∀ k, dotParityAux (basisVec n j) x k = if j < k then x.getLsbD j else false
  | 0 => rfl
  | k + 1 => by
    simp only [dotParityAux, dotParityAux_basisVec_left j hj x k, basisVec_getLsbD]
    by_cases hlt : j < k
    · have hne : k ≠ j := by omega
      have hlt' : j < k + 1 := by omega
      simp [hlt, hlt', hne]
    · by_cases heq : k = j
      · subst heq
        simp [hj]
      · have hgt : ¬ (j < k + 1) := by omega
        simp [hlt, hgt, heq]

theorem dotParity_basisVec_left (n j : Nat) (hj : j < n) (x : BitVec n) :
    dotParity n (basisVec n j) x = x.getLsbD j := by
  simpa [dotParity, hj] using dotParityAux_basisVec_left j hj x n

theorem dotParityAux_basisVec_right {n : Nat} (m : BitVec n) (j : Nat) (hj : j < n) :
    ∀ k, dotParityAux m (basisVec n j) k = if j < k then m.getLsbD j else false
  | 0 => rfl
  | k + 1 => by
    simp only [dotParityAux, dotParityAux_basisVec_right m j hj k, basisVec_getLsbD]
    by_cases hlt : j < k
    · have hne : k ≠ j := by omega
      have hlt' : j < k + 1 := by omega
      simp [hlt, hlt', hne]
    · by_cases heq : k = j
      · subst heq
        simp [hj]
      · have hgt : ¬ (j < k + 1) := by omega
        simp [hlt, hgt, heq]

theorem dotParity_basisVec_right (n : Nat) (m : BitVec n) (j : Nat) (hj : j < n) :
    dotParity n m (basisVec n j) = m.getLsbD j := by
  simpa [dotParity, hj] using dotParityAux_basisVec_right m j hj n

/-- A function `f : BitVec n → BitVec n` is `GF(2)`-linear iff `f 0 = 0` and
`f (x ^^^ y) = f x ^^^ f y`. -/
structure IsF2Linear (n : Nat) (f : BitVec n → BitVec n) : Prop where
  map_zero : f 0#n = 0#n
  map_xor : ∀ x y : BitVec n, f (x ^^^ y) = f x ^^^ f y

theorem IsF2Linear.id (n : Nat) : IsF2Linear n (fun x => x) :=
  ⟨rfl, fun _ _ => rfl⟩

theorem IsF2Linear.comp {n : Nat} {f g : BitVec n → BitVec n}
    (hf : IsF2Linear n f) (hg : IsF2Linear n g) : IsF2Linear n (fun x => f (g x)) :=
  ⟨by rw [hg.map_zero, hf.map_zero], fun x y => by rw [hg.map_xor, hf.map_xor]⟩

theorem IsF2Linear.xor {n : Nat} {f g : BitVec n → BitVec n}
    (hf : IsF2Linear n f) (hg : IsF2Linear n g) : IsF2Linear n (fun x => f x ^^^ g x) :=
  ⟨by simp [hf.map_zero, hg.map_zero], fun x y => by
    rw [hf.map_xor, hg.map_xor]
    apply BitVec.eq_of_getLsbD_eq
    intro i _
    simp only [BitVec.getLsbD_xor]
    exact xor_four_swap _ _ _ _⟩

/-- Extract row `i` of the `n×n` binary matrix representing `f` from its action on basis vectors. -/
def rowOfLinearMap (n : Nat) (f : BitVec n → BitVec n) (i : Nat) : BitVec n :=
  packBits n (fun j => (f (basisVec n j)).getLsbD i)

/-- Extract all `n` matrix rows of a `GF(2)`-linear map `f : BitVec n → BitVec n`. -/
def rowsOfLinearMap (n : Nat) (f : BitVec n → BitVec n) : List (BitVec n) :=
  List.ofFn (fun i : Fin n => rowOfLinearMap n f i.val)

/-- Matrix-vector product `M · x` over `GF(2)` for a row-major list of `n` `BitVec n` rows. -/
def matMul (n : Nat) (rows : List (BitVec n)) (x : BitVec n) : BitVec n :=
  packBits n (fun i => dotParity n (rows.getD i 0#n) x)

/-- Extract column `j` of a row-major matrix `rows` in `O(n)` bit lookups (fast kernel evaluation). -/
def colOfRowsAux {n : Nat} (j : Nat) : List (BitVec n) → Nat → Nat → Nat
  | [], _, acc => acc
  | r :: rs, bit, acc =>
    let acc' := if r.getLsbD j then acc ||| bit else acc
    colOfRowsAux j rs (bit <<< 1) acc'

/-- Extract column `j` of a row-major `n×n` matrix `rows` as a `BitVec n`. -/
def colOfRows (n : Nat) (rows : List (BitVec n)) (j : Nat) : BitVec n :=
  BitVec.ofNat n (colOfRowsAux j rows 1 0)

theorem IsF2Linear.matMul (n : Nat) (rows : List (BitVec n)) : IsF2Linear n (matMul n rows) :=
  ⟨by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [CryptoLinearXor.matMul, packBits_getLsbD, hi, ite_true,
      dotParity_zero_right, BitVec.getLsbD_zero],
   fun x y => by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [CryptoLinearXor.matMul, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true,
      dotParity_xor_right]⟩

private theorem f_packBitsAux_getLsbD {n : Nat} (f : BitVec n → BitVec n)
    (hf : IsF2Linear n f) (x : BitVec n) (i : Nat) :
    ∀ k, k ≤ n →
      (f (packBitsAux n (fun j => x.getLsbD j) k)).getLsbD i =
        dotParityAux (rowOfLinearMap n f i) x k
  | 0, _ => by simp [packBitsAux, hf.map_zero, dotParityAux]
  | k + 1, hk => by
    have hklt : k < n := by omega
    have hkle : k ≤ n := by omega
    simp only [packBitsAux, hf.map_xor, BitVec.getLsbD_xor, dotParityAux,
      f_packBitsAux_getLsbD f hf x i k hkle]
    congr 1
    by_cases hx : x.getLsbD k = true
    · simp only [hx, ite_true, rowOfLinearMap, packBits_getLsbD, hklt, Bool.and_true]
    · have hxf : x.getLsbD k = false := by
        cases hb : x.getLsbD k
        · rfl
        · exact absurd hb hx
      simp only [hxf, Bool.false_eq_true, ite_false, hf.map_zero, BitVec.getLsbD_zero, Bool.and_false]

/-- Any `GF(2)`-linear map `f : BitVec n → BitVec n` equals `matMul n (rowsOfLinearMap n f)`
on all `2^n` inputs. -/
theorem matMul_rowsOfLinearMap (n : Nat) (f : BitVec n → BitVec n) (hf : IsF2Linear n f) :
    ∀ x : BitVec n, matMul n (rowsOfLinearMap n f) x = f x := by
  intro x
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  have hrow : (rowsOfLinearMap n f).getD i 0#n = rowOfLinearMap n f i := by
    simp [rowsOfLinearMap, List.getD, hi]
  simp only [matMul, packBits_getLsbD, hi, ite_true, hrow, dotParity]
  rw [← f_packBitsAux_getLsbD f hf x i n (Nat.le_refl n)]
  have hself : packBitsAux n (fun j => x.getLsbD j) n = x := packBits_getLsbD_self x
  rw [hself]

/-- Two `GF(2)`-linear maps that agree on all `n` standard basis vectors agree on all `2^n` inputs. -/
theorem linear_ext {n : Nat} {f g : BitVec n → BitVec n}
    (hf : IsF2Linear n f) (hg : IsF2Linear n g)
    (hbasis : ∀ j : Fin n, f (basisVec n j.val) = g (basisVec n j.val)) :
    ∀ x : BitVec n, f x = g x := by
  have hrows : rowsOfLinearMap n f = rowsOfLinearMap n g := by
    unfold rowsOfLinearMap
    congr 1
    funext i
    apply BitVec.eq_of_getLsbD_eq
    intro j hj
    simp only [rowOfLinearMap, packBits_getLsbD, hj, ite_true]
    rw [hbasis ⟨j, hj⟩]
  intro x
  rw [← matMul_rowsOfLinearMap n f hf x, hrows, matMul_rowsOfLinearMap n g hg x]

/-- Fast `O(n)` check that `matMul n rows` matches `f` on basis vectors `0 .. k-1`. -/
def checkRowsBasisAux (n : Nat) (rows : List (BitVec n)) (f : BitVec n → BitVec n) : Nat → Bool
  | 0 => true
  | k + 1 => ((colOfRows n rows k).toNat == (f (basisVec n k)).toNat) && checkRowsBasisAux n rows f k

/-- Fast `O(n)` check that `matMul n rows` matches `f` on all `n` basis vectors. -/
def checkRowsBasis (n : Nat) (rows : List (BitVec n)) (f : BitVec n → BitVec n) : Bool :=
  checkRowsBasisAux n rows f n

private theorem checkRowsBasisAux_sound (n : Nat) (rows : List (BitVec n))
    (f : BitVec n → BitVec n) :
    ∀ k, checkRowsBasisAux n rows f k = true →
      ∀ j, j < k → colOfRows n rows j = f (basisVec n j)
  | 0, _, _, hj => by omega
  | k + 1, h, j, hj => by
    simp only [checkRowsBasisAux, Bool.and_eq_true, beq_iff_eq] at h
    by_cases hlt : j < k
    · exact checkRowsBasisAux_sound n rows f k h.2 j hlt
    · have heq : j = k := by omega
      subst heq
      exact BitVec.eq_of_toNat_eq h.1

private theorem colOfRowsAux_testBit {n : Nat} (j : Nat) :
    ∀ (rs : List (BitVec n)) (k acc i : Nat),
      (∀ m, k ≤ m → acc.testBit m = false) →
      (colOfRowsAux j rs (1 <<< k) acc).testBit i =
        if i < k then acc.testBit i
        else if i - k < rs.length then (rs.getD (i - k) 0#n).getLsbD j
        else false
  | [], k, acc, i, hacc => by
    simp only [colOfRowsAux, List.length_nil, Nat.not_lt_zero, ite_false]
    by_cases hi : i < k
    · simp [hi]
    · have hge : k ≤ i := by omega
      simp [hi, hacc i hge]
  | r :: rs, k, acc, i, hacc => by
    have hsh : (1 <<< k) <<< 1 = 1 <<< (k + 1) := by
      simp [Nat.shiftLeft_eq, Nat.pow_succ]
    simp only [colOfRowsAux, hsh]
    have hacc' : ∀ m, k + 1 ≤ m →
        (if r.getLsbD j then acc ||| (1 <<< k) else acc).testBit m = false := by
      intro m hm
      have hkm : k ≤ m := by omega
      cases r.getLsbD j
      · simpa using hacc m hkm
      · simp only [ite_true, Nat.testBit_or, hacc m hkm, Bool.false_or, Nat.testBit_shiftLeft]
        have hpos : m - k ≠ 0 := by omega
        have htb : Nat.testBit 1 (m - k) = false := by
          cases hd : m - k with | zero => omega | succ p => simp [Nat.testBit_succ]
        simp [htb]
    rw [colOfRowsAux_testBit j rs (k + 1) _ i hacc']
    by_cases hik : i < k
    · have hik1 : i < k + 1 := by omega
      have hmk : ¬ (k ≤ i) := by omega
      simp only [hik, hik1, ite_true]
      cases r.getLsbD j
      · rfl
      · simp [Nat.testBit_or, Nat.testBit_shiftLeft, hmk]
    · by_cases hieq : i = k
      · subst hieq
        have hik1 : i < i + 1 := by omega
        have hsub : i - i = 0 := Nat.sub_self i
        simp only [hik, hik1, ite_true, ite_false, hsub, List.length_cons, Nat.zero_lt_succ,
          List.getD_cons_zero]
        cases hr : r.getLsbD j
        · simp [hacc i (Nat.le_refl i)]
        · simp [Nat.testBit_or, Nat.testBit_shiftLeft]
      · have hgt : ¬ (i < k + 1) := by omega
        have hsub : i - k = (i - (k + 1)) + 1 := by omega
        simp only [hik, hgt, ite_false, hsub, List.getD_cons_succ]
        by_cases hlt : i - (k + 1) < rs.length
        · simp [hlt]
        · simp [hlt]

theorem matMul_basisVec_eq_colOfRows (n : Nat) (rows : List (BitVec n)) (j : Nat) (hj : j < n) :
    matMul n rows (basisVec n j) = colOfRows n rows j := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  simp only [matMul, packBits_getLsbD, hi, ite_true, dotParity_basisVec_right n _ j hj,
    colOfRows, BitVec.getLsbD_ofNat, decide_true, Bool.true_and]
  have h0 : (1 : Nat) = 1 <<< 0 := rfl
  rw [h0, colOfRowsAux_testBit j rows 0 0 i (fun _ _ => by simp)]
  simp only [Nat.not_lt_zero, ite_false, Nat.sub_zero]
  by_cases hlt : i < rows.length
  · simp [hlt]
  · simp [List.getD, hlt]

/-- Fast soundness lemma: if `checkRowsBasis n rows f = true` and `f` is `GF(2)`-linear, then
`matMul n rows x = f x` on all `2^n` inputs. -/
theorem matMul_eq_of_checkRowsBasis {n : Nat} (f : BitVec n → BitVec n) (hf : IsF2Linear n f)
    (rows : List (BitVec n)) (hcheck : checkRowsBasis n rows f = true) :
    ∀ x : BitVec n, matMul n rows x = f x := by
  apply linear_ext (IsF2Linear.matMul n rows) hf
  intro j
  rw [matMul_basisVec_eq_colOfRows n rows j.val j.isLt]
  exact checkRowsBasisAux_sound n rows f n hcheck j.val j.isLt

/-! ## Straight-Line XOR Circuit Semantics and Bit-Parallel Soundness -/

/-- Push bits `x[0] .. x[k-1]` into an `Array Bool` (constructive, zero `Classical.choice`). -/
def initXorWiresAux {n : Nat} (x : BitVec n) : Nat → Array Bool
  | 0 => #[]
  | k + 1 => (initXorWiresAux x k).push (x.getLsbD k)

/-- Input wires `0 .. n-1` hold input bits `x[0] .. x[n-1]` (LSB-first). -/
def initXorWires (n : Nat) (x : BitVec n) : Array Bool :=
  initXorWiresAux x n

/-- Evaluate 2-input XOR gates in order; gate `k` (`0`-indexed) produces wire `n + k`. -/
def evalXorWiresAux (wires : Array Bool) : List (Nat × Nat) → Array Bool
  | [] => wires
  | (a, b) :: rest =>
    let v := xor (wires.getD a false) (wires.getD b false)
    evalXorWiresAux (wires.push v) rest

/-- Evaluate a straight-line XOR circuit `(gates, outputs)` on `x : BitVec n`. -/
def evalXorCircuit (n : Nat) (gates : List (Nat × Nat)) (outputs : List Nat)
    (x : BitVec n) : BitVec n :=
  let wires := evalXorWiresAux (initXorWires n x) gates
  packBits n (fun i => wires.getD (outputs.getD i 0) false)

/-- Check that every gate `k` (`0`-indexed) references strictly earlier wires `< n + k`. -/
def wellFormedXorGates (numWires : Nat) : List (Nat × Nat) → Bool
  | [] => true
  | (a, b) :: rest => (a < numWires && b < numWires) && wellFormedXorGates (numWires + 1) rest

/-- Check `outputs.length == n`, every gate input `< n + k`, and every output `< n + gates.length`. -/
def wellFormedXor (n : Nat) (gates : List (Nat × Nat)) (outputs : List Nat) : Bool :=
  let totalWires := n + gates.length
  outputs.length == n && wellFormedXorGates n gates && outputs.all (fun w => w < totalWires)

/-- Existence of a well-formed straight-line XOR circuit computing `target` on all `2^n` inputs
using exactly `k` 2-input XOR gates. -/
def ValidXorCircuit (n : Nat) (target : BitVec n → BitVec n) (k : Nat) : Prop :=
  ∃ gates outputs,
    wellFormedXor n gates outputs = true ∧
    gates.length = k ∧
    ∀ x : BitVec n, evalXorCircuit n gates outputs x = target x

/-! ### Bit-Parallel Symbolic Basis-Mask Evaluator -/

/-- Lookup wire `w` in a reversed wire-mask list of length `len`. -/
def getRevMask {n : Nat} (len : Nat) (revMasks : List (BitVec n)) (w : Nat) : BitVec n :=
  if w < len then revMasks.getD (len - 1 - w) 0#n else 0#n

/-- Build reversed basis masks `[e_{k-1}, ..., e_0]` in `O(k)` (constructive). -/
def initRevMasksAux (n : Nat) : Nat → List (BitVec n)
  | 0 => []
  | k + 1 => basisVec n k :: initRevMasksAux n k

/-- Initial reversed basis masks `[e_{n-1}, ..., e_1, e_0]`. -/
def initRevMasks (n : Nat) : List (BitVec n) :=
  initRevMasksAux n n

/-- Execute all XOR gates once on symbolic `BitVec n` basis masks. -/
def evalMasksAux {n : Nat} (len : Nat) (revMasks : List (BitVec n)) :
    List (Nat × Nat) → Nat × List (BitVec n)
  | [] => (len, revMasks)
  | (a, b) :: rest =>
    let v := getRevMask len revMasks a ^^^ getRevMask len revMasks b
    evalMasksAux (len + 1) (v :: revMasks) rest

/-- Symbolically extract the `n` output row masks computed by a straight-line XOR circuit. -/
def evalCircuitMasks (n : Nat) (gates : List (Nat × Nat)) (outputs : List Nat) : List (BitVec n) :=
  let res := evalMasksAux n (initRevMasks n) gates
  List.ofFn (fun i : Fin n => getRevMask res.1 res.2 (outputs.getD i.val 0))

/-- Compare each output wire's computed symbolic mask against the corresponding target row. -/
def checkOutputsAux {n : Nat} (len : Nat) (revMasks : List (BitVec n)) :
    List (BitVec n) → List Nat → Bool
  | [], [] => true
  | r :: rs, o :: os =>
    ((getRevMask len revMasks o).toNat == r.toNat) && checkOutputsAux len revMasks rs os
  | _, _ => false

/-- Single-pass kernel check verifying a straight-line XOR circuit against `n` target matrix rows. -/
def checkLinearCircuit (n : Nat) (rows : List (BitVec n))
    (gates : List (Nat × Nat)) (outputs : List Nat) : Bool :=
  let (len, revMasks) := evalMasksAux n (initRevMasks n) gates
  checkOutputsAux len revMasks rows outputs

private theorem array_getD_push_eq {α : Type} (a : Array α) (v d : α) (i : Nat) :
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

private theorem getRevMask_cons {n : Nat} (len : Nat) (revMasks : List (BitVec n))
    (v : BitVec n) (w : Nat) :
    getRevMask (len + 1) (v :: revMasks) w =
      if w < len then getRevMask len revMasks w else if w = len then v else 0#n := by
  unfold getRevMask
  by_cases h1 : w < len
  · have hlt : w < len + 1 := by omega
    have hidx : len + 1 - 1 - w = (len - 1 - w) + 1 := by omega
    simp only [h1, hlt, ite_true, hidx, List.getD_cons_succ]
  · by_cases h2 : w = len
    · subst h2
      have hlt : w < w + 1 := by omega
      have hidx : w + 1 - 1 - w = 0 := by omega
      simp only [h1, hlt, ite_false, ite_true, hidx, List.getD_cons_zero]
    · have hge : ¬ (w < len + 1) := by omega
      simp only [h1, h2, hge, ite_false]

private theorem evalMasksAux_dotParity {n : Nat} (gates : List (Nat × Nat))
    (len : Nat) (revMasks : List (BitVec n)) (wires : Array Bool) (x : BitVec n)
    (hsz : len = wires.size)
    (hinv : ∀ i, dotParity n (getRevMask len revMasks i) x = wires.getD i false) :
    let res := evalMasksAux len revMasks gates
    ∀ i, dotParity n (getRevMask res.1 res.2 i) x =
      (evalXorWiresAux wires gates).getD i false := by
  induction gates generalizing len revMasks wires with
  | nil => exact hinv
  | cons g rest ih =>
    rcases g with ⟨a, b⟩
    simp only [evalMasksAux, evalXorWiresAux]
    apply ih
    · simp [hsz]
    · intro i
      rw [getRevMask_cons, array_getD_push_eq, hsz]
      by_cases h1 : i < wires.size
      · simp only [h1, ite_true]; rw [← hsz]; exact hinv i
      · by_cases h2 : i = wires.size
        · subst h2
          simp only [Nat.lt_irrefl, ite_false, ite_true]
          rw [dotParity_xor_left, ← hsz, hinv a, hinv b]
        · simp only [h1, h2, ite_false, dotParity_zero_left]

private theorem initXorWiresAux_size {n : Nat} (x : BitVec n) :
    ∀ k, (initXorWiresAux x k).size = k
  | 0 => rfl
  | k + 1 => by simp [initXorWiresAux, Array.size_push, initXorWiresAux_size x k]

private theorem initXorWiresAux_getD {n : Nat} (x : BitVec n) (i : Nat) :
    ∀ k, (initXorWiresAux x k).getD i false = if i < k then x.getLsbD i else false
  | 0 => by simp [initXorWiresAux, Array.getD]
  | k + 1 => by
    rw [initXorWiresAux, array_getD_push_eq, initXorWiresAux_size x k, initXorWiresAux_getD x i k]
    by_cases h1 : i < k
    · have hlt : i < k + 1 := by omega
      simp [h1, hlt]
    · by_cases h2 : i = k
      · subst h2; simp
      · have hgt : ¬ (i < k + 1) := by omega
        simp [h1, h2, hgt]

private theorem getRevMask_initRevMasksAux (n i : Nat) :
    ∀ k, getRevMask k (initRevMasksAux n k) i = if i < k then basisVec n i else 0#n
  | 0 => by simp [getRevMask]
  | k + 1 => by
    rw [initRevMasksAux, getRevMask_cons, getRevMask_initRevMasksAux n i k]
    by_cases h1 : i < k
    · have hlt : i < k + 1 := by omega
      simp [h1, hlt]
    · by_cases h2 : i = k
      · subst h2; simp
      · have hgt : ¬ (i < k + 1) := by omega
        simp [h1, h2, hgt]

private theorem initRevMasks_dotParity (n : Nat) (x : BitVec n) (i : Nat) :
    dotParity n (getRevMask n (initRevMasks n) i) x = (initXorWires n x).getD i false := by
  rw [initRevMasks, getRevMask_initRevMasksAux n i n, initXorWires, initXorWiresAux_getD x i n]
  by_cases hi : i < n
  · simp [hi, dotParity_basisVec_left n i hi x]
  · simp [hi, dotParity_zero_left]

/-- Every straight-line XOR circuit evaluates as a `GF(2)`-linear matrix multiplication by its
symbolically computed output wire masks. -/
theorem evalXorCircuit_eq_matMul_masks (n : Nat) (gates : List (Nat × Nat)) (outputs : List Nat) :
    ∀ x : BitVec n, evalXorCircuit n gates outputs x =
      matMul n (evalCircuitMasks n gates outputs) x := by
  intro x
  have hsz : n = (initXorWires n x).size := (initXorWiresAux_size x n).symm
  have hw := evalMasksAux_dotParity gates n (initRevMasks n) (initXorWires n x) x hsz
    (initRevMasks_dotParity n x)
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  simp only [evalXorCircuit, matMul, packBits_getLsbD, hi, ite_true]
  have hrow : (evalCircuitMasks n gates outputs).getD i 0#n =
      getRevMask (evalMasksAux n (initRevMasks n) gates).1
        (evalMasksAux n (initRevMasks n) gates).2 (outputs.getD i 0) := by
    simp [evalCircuitMasks, List.getD, hi]
  rw [hrow]
  exact (hw (outputs.getD i 0)).symm

/-- Every straight-line XOR circuit is `GF(2)`-linear (`eval 0 = 0` and
`eval (x ^^^ y) = eval x ^^^ eval y`). -/
theorem evalXorCircuit_isF2Linear (n : Nat) (gates : List (Nat × Nat)) (outputs : List Nat) :
    IsF2Linear n (evalXorCircuit n gates outputs) := by
  have heq := evalXorCircuit_eq_matMul_masks n gates outputs
  have hlin := IsF2Linear.matMul n (evalCircuitMasks n gates outputs)
  exact ⟨by rw [heq 0#n, hlin.map_zero], fun x y => by rw [heq (x ^^^ y), heq x, heq y, hlin.map_xor]⟩

private theorem checkOutputsAux_sound {n : Nat} (len : Nat) (revMasks : List (BitVec n)) :
    ∀ (rows : List (BitVec n)) (outputs : List Nat),
      checkOutputsAux len revMasks rows outputs = true →
      ∀ i, i < rows.length →
        getRevMask len revMasks (outputs.getD i 0) = rows.getD i 0#n
  | [], [], _, _, hi => by simp at hi
  | [], _ :: _, h, _, _ => by simp [checkOutputsAux] at h
  | _ :: _, [], h, _, _ => by simp [checkOutputsAux] at h
  | r :: rs, o :: os, h, 0, _ => by
    simp only [checkOutputsAux, Bool.and_eq_true, beq_iff_eq] at h
    simpa [List.getD] using BitVec.eq_of_toNat_eq h.1
  | r :: rs, o :: os, h, i + 1, hi => by
    simp only [checkOutputsAux, Bool.and_eq_true, beq_iff_eq] at h
    have hi' : i < rs.length := by simpa using hi
    simpa [List.getD] using checkOutputsAux_sound len revMasks rs os h.2 i hi'

/-- **Fundamental Linearity Soundness Theorem (Matrix Form)**:
If the single-pass symbolic basis-mask check passes, the XOR circuit agrees with `matMul n rows`
on all `2^n` inputs. -/
theorem evalXorCircuit_eq_matMul_of_check (n : Nat) (rows : List (BitVec n))
    (hlen : rows.length = n)
    (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit n rows gates outputs = true) :
    ∀ x : BitVec n, evalXorCircuit n gates outputs x = matMul n rows x := by
  intro x
  have hsz : n = (initXorWires n x).size := (initXorWiresAux_size x n).symm
  have hw := evalMasksAux_dotParity gates n (initRevMasks n) (initXorWires n x) x hsz
    (initRevMasks_dotParity n x)
  unfold checkLinearCircuit at hcheck
  have hmatch := checkOutputsAux_sound (evalMasksAux n (initRevMasks n) gates).1
    (evalMasksAux n (initRevMasks n) gates).2 rows outputs hcheck
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  have hi' : i < rows.length := by omega
  simp only [evalXorCircuit, matMul, packBits_getLsbD, hi, ite_true]
  rw [← hw (outputs.getD i 0), hmatch i hi']

/-- **Fundamental Linearity Soundness Theorem (Reference-Map Form)**:
For any `GF(2)`-linear reference function `f : BitVec n → BitVec n` matching `rows` on the `n`
standard basis vectors, a passing `checkLinearCircuit` proves `evalXorCircuit = f` on all `2^n` inputs. -/
theorem evalXorCircuit_eq_of_check (n : Nat) (f : BitVec n → BitVec n)
    (hf : IsF2Linear n f) (rows : List (BitVec n))
    (hlen : rows.length = n)
    (hbasis : checkRowsBasis n rows f = true)
    (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit n rows gates outputs = true) :
    ∀ x : BitVec n, evalXorCircuit n gates outputs x = f x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check n rows hlen gates outputs hcheck x,
      matMul_eq_of_checkRowsBasis f hf rows hbasis x]

/-! ## Reference Specifications for the Six OpenSSL Diffusion Layers -/

/-! ### 1 & 2. AES `MixColumns` and `InvMixColumns` (NIST FIPS 197 & `crypto/aes/aes_core.c`) -/

/-- Extract byte `k` (`0 ≤ k < 4`, little-endian: byte `0` = bits `0..7`) of a 32-bit word. -/
def byteOf32 (w : BitVec 32) (k : Nat) : BitVec 8 :=
  BitVec.ofNat 8 (w.toNat >>> (8 * k))

/-- Pack 4 bytes `(b0, b1, b2, b3)` little-endian into a 32-bit word (`b0` in bits `0..7`). -/
def packBytes4 (b0 b1 b2 b3 : BitVec 8) : BitVec 32 :=
  BitVec.ofNat 32
    (b0.toNat ||| (b1.toNat <<< 8) ||| (b2.toNat <<< 16) ||| (b3.toNat <<< 24))

private theorem byteOf32_getLsbD (w : BitVec 32) (k i : Nat) :
    (byteOf32 w k).getLsbD i = if i < 8 then w.getLsbD (8 * k + i) else false := by
  unfold byteOf32
  rw [BitVec.getLsbD_ofNat]
  by_cases hi : i < 8
  · simp [hi, Nat.testBit_shiftRight, BitVec.getLsbD]
  · simp [hi]

private theorem byte_testBit_ge8 (b : BitVec 8) (j : Nat) (hj : 8 ≤ j) :
    b.toNat.testBit j = false :=
  Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le b.isLt (Nat.pow_le_pow_right (by omega) hj))

private theorem packBytes4_getLsbD (b0 b1 b2 b3 : BitVec 8) (i : Nat) (hi : i < 32) :
    (packBytes4 b0 b1 b2 b3).getLsbD i =
      if i < 8 then b0.getLsbD i
      else if i < 16 then b1.getLsbD (i - 8)
      else if i < 24 then b2.getLsbD (i - 16)
      else b3.getLsbD (i - 24) := by
  unfold packBytes4
  rw [BitVec.getLsbD_ofNat, decide_eq_true hi, Bool.true_and]
  simp only [Nat.testBit_or, Nat.testBit_shiftLeft, BitVec.getLsbD]
  by_cases h8 : i < 8
  · have hge8 : ¬ (8 ≤ i) := by omega
    have hge16 : ¬ (16 ≤ i) := by omega
    have hge24 : ¬ (24 ≤ i) := by omega
    simp [h8, hge8, hge16, hge24]
  · by_cases h16 : i < 16
    · have hge8 : 8 ≤ i := by omega
      have hge16 : ¬ (16 ≤ i) := by omega
      have hge24 : ¬ (24 ≤ i) := by omega
      simp [h8, h16, hge8, hge16, hge24, byte_testBit_ge8 b0 i hge8]
    · by_cases h24 : i < 24
      · have hge8 : 8 ≤ i := by omega
        have hge16 : 16 ≤ i := by omega
        have hge24 : ¬ (24 ≤ i) := by omega
        have hge8b : 8 ≤ i - 8 := by omega
        simp [h8, h16, h24, hge8, hge16, hge24,
              byte_testBit_ge8 b0 i hge8, byte_testBit_ge8 b1 (i - 8) hge8b]
      · have hge8 : 8 ≤ i := by omega
        have hge16 : 16 ≤ i := by omega
        have hge24 : 24 ≤ i := by omega
        have hge8b : 8 ≤ i - 8 := by omega
        have hge8c : 8 ≤ i - 16 := by omega
        simp [h8, h16, h24, hge8, hge16, hge24,
              byte_testBit_ge8 b0 i hge8, byte_testBit_ge8 b1 (i - 8) hge8b,
              byte_testBit_ge8 b2 (i - 16) hge8c]

private theorem byteOf32_zero (k : Nat) : byteOf32 0#32 k = 0#8 := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  simp only [byteOf32_getLsbD, hi, ite_true, BitVec.getLsbD_zero]

private theorem byteOf32_xor (x y : BitVec 32) (k : Nat) :
    byteOf32 (x ^^^ y) k = byteOf32 x k ^^^ byteOf32 y k := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  simp only [BitVec.getLsbD_xor, byteOf32_getLsbD, hi, ite_true]

private theorem packBytes4_zero : packBytes4 0#8 0#8 0#8 0#8 = 0#32 := rfl

private theorem packBytes4_xor (a0 a1 a2 a3 b0 b1 b2 b3 : BitVec 8) :
    packBytes4 (a0 ^^^ b0) (a1 ^^^ b1) (a2 ^^^ b2) (a3 ^^^ b3) =
      packBytes4 a0 a1 a2 a3 ^^^ packBytes4 b0 b1 b2 b3 := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  simp only [BitVec.getLsbD_xor, packBytes4_getLsbD _ _ _ _ i hi]
  by_cases h8 : i < 8
  · simp [h8]
  · by_cases h16 : i < 16
    · simp [h8, h16]
    · by_cases h24 : i < 24
      · simp [h8, h16, h24]
      · simp [h8, h16, h24]

/-- Multiplication by `x` in AES `GF(2^8) = GF(2)[x] / (x^8 + x^4 + x^3 + x + 1)` (`0x11b`). -/
def gfXtime (a : BitVec 8) : BitVec 8 :=
  if a.getLsbD 7 then (a <<< 1) ^^^ 0x1b#8 else a <<< 1

private theorem gfXtime_zero : gfXtime 0#8 = 0#8 := rfl

private theorem gfXtime_xor (a b : BitVec 8) :
    gfXtime (a ^^^ b) = gfXtime a ^^^ gfXtime b := by
  unfold gfXtime
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  rw [BitVec.getLsbD_xor, BitVec.getLsbD_xor]
  by_cases ha : a.getLsbD 7 = true <;> by_cases hb : b.getLsbD 7 = true
  · simp only [ha, hb, Bool.xor_self, Bool.false_eq_true, ite_true, ite_false,
      BitVec.getLsbD_xor, BitVec.getLsbD_shiftLeft, decide_eq_true hi, Bool.true_and]
    cases decide (i < 1) <;> cases a.getLsbD (i - 1) <;> cases b.getLsbD (i - 1) <;>
      cases (0x1b#8).getLsbD i <;> rfl
  · have hbf : b.getLsbD 7 = false := by cases h : b.getLsbD 7; rfl; exact absurd h hb
    simp only [ha, hbf, Bool.xor_false, Bool.false_eq_true, ite_true, ite_false,
      BitVec.getLsbD_xor, BitVec.getLsbD_shiftLeft, decide_eq_true hi, Bool.true_and]
    cases decide (i < 1) <;> cases a.getLsbD (i - 1) <;> cases b.getLsbD (i - 1) <;>
      cases (0x1b#8).getLsbD i <;> rfl
  · have haf : a.getLsbD 7 = false := by cases h : a.getLsbD 7; rfl; exact absurd h ha
    simp only [haf, hb, Bool.false_xor, Bool.false_eq_true, ite_true, ite_false,
      BitVec.getLsbD_xor, BitVec.getLsbD_shiftLeft, decide_eq_true hi, Bool.true_and]
    cases decide (i < 1) <;> cases a.getLsbD (i - 1) <;> cases b.getLsbD (i - 1) <;>
      cases (0x1b#8).getLsbD i <;> rfl
  · have haf : a.getLsbD 7 = false := by cases h : a.getLsbD 7; rfl; exact absurd h ha
    have hbf : b.getLsbD 7 = false := by cases h : b.getLsbD 7; rfl; exact absurd h hb
    simp only [haf, hbf, Bool.false_xor, Bool.false_eq_true, ite_false,
      BitVec.getLsbD_xor, BitVec.getLsbD_shiftLeft, decide_eq_true hi, Bool.true_and]
    cases decide (i < 1) <;> cases a.getLsbD (i - 1) <;> cases b.getLsbD (i - 1) <;> rfl

/-- Shift-and-add multiplication in `GF(2^8) = GF(2)[x] / (0x11b)`. -/
def gfMulAux : Nat → BitVec 8 → BitVec 8 → BitVec 8 → BitVec 8
  | 0, _, _, acc => acc
  | k + 1, a, b, acc =>
    let acc' := if b.getLsbD 0 then acc ^^^ a else acc
    gfMulAux k (gfXtime a) (b >>> 1) acc'

/-- Multiplication `a · b` in AES `GF(2^8) = GF(2)[x] / (0x11b)`. -/
def gfMul (a b : BitVec 8) : BitVec 8 :=
  gfMulAux 8 a b 0#8

private theorem gfMulAux_zero_left :
    ∀ k b, gfMulAux k 0#8 b 0#8 = 0#8
  | 0, _ => rfl
  | k + 1, b => by
    simp only [gfMulAux, gfXtime_zero]
    cases b.getLsbD 0 <;> simp [gfMulAux_zero_left k (b >>> 1)]

private theorem gfMulAux_xor_left :
    ∀ k x y b acc1 acc2,
      gfMulAux k (x ^^^ y) b (acc1 ^^^ acc2) =
        gfMulAux k x b acc1 ^^^ gfMulAux k y b acc2
  | 0, _, _, _, _, _ => rfl
  | k + 1, x, y, b, acc1, acc2 => by
    simp only [gfMulAux, gfXtime_xor]
    cases b.getLsbD 0
    · simpa using gfMulAux_xor_left k (gfXtime x) (gfXtime y) (b >>> 1) acc1 acc2
    · have hacc : (acc1 ^^^ acc2) ^^^ (x ^^^ y) = (acc1 ^^^ x) ^^^ (acc2 ^^^ y) := by
        apply BitVec.eq_of_getLsbD_eq
        intro i _; simp only [BitVec.getLsbD_xor]; exact xor_four_swap _ _ _ _
      simp only [ite_true, hacc]
      exact gfMulAux_xor_left k (gfXtime x) (gfXtime y) (b >>> 1) (acc1 ^^^ x) (acc2 ^^^ y)

private theorem gfMul_zero_left (c : BitVec 8) : gfMul 0#8 c = 0#8 :=
  gfMulAux_zero_left 8 c

private theorem gfMul_xor_left (x y c : BitVec 8) :
    gfMul (x ^^^ y) c = gfMul x c ^^^ gfMul y c := by
  simpa [gfMul] using gfMulAux_xor_left 8 x y c 0#8 0#8

/-- Algebraic NIST FIPS 197 §5.1.3 AES `MixColumns` on a 32-bit column `[b0, b1, b2, b3]`:
column multiplication by `[02, 03, 01, 01]` over `GF(2)[x] / (0x11b)`. -/
def aesMixColumns32 (x : BitVec 32) : BitVec 32 :=
  let b0 := byteOf32 x 0
  let b1 := byteOf32 x 1
  let b2 := byteOf32 x 2
  let b3 := byteOf32 x 3
  let y0 := gfMul b0 0x02#8 ^^^ gfMul b1 0x03#8 ^^^ b2 ^^^ b3
  let y1 := b0 ^^^ gfMul b1 0x02#8 ^^^ gfMul b2 0x03#8 ^^^ b3
  let y2 := b0 ^^^ b1 ^^^ gfMul b2 0x02#8 ^^^ gfMul b3 0x03#8
  let y3 := gfMul b0 0x03#8 ^^^ b1 ^^^ b2 ^^^ gfMul b3 0x02#8
  packBytes4 y0 y1 y2 y3

/-- Algebraic NIST FIPS 197 §5.3.3 AES `InvMixColumns` on a 32-bit column `[b0, b1, b2, b3]`:
column multiplication by `[0e, 0b, 0d, 09]` over `GF(2)[x] / (0x11b)`. -/
def aesInvMixColumns32 (x : BitVec 32) : BitVec 32 :=
  let b0 := byteOf32 x 0
  let b1 := byteOf32 x 1
  let b2 := byteOf32 x 2
  let b3 := byteOf32 x 3
  let y0 := gfMul b0 0x0e#8 ^^^ gfMul b1 0x0b#8 ^^^ gfMul b2 0x0d#8 ^^^ gfMul b3 0x09#8
  let y1 := gfMul b0 0x09#8 ^^^ gfMul b1 0x0e#8 ^^^ gfMul b2 0x0b#8 ^^^ gfMul b3 0x0d#8
  let y2 := gfMul b0 0x0d#8 ^^^ gfMul b1 0x09#8 ^^^ gfMul b2 0x0e#8 ^^^ gfMul b3 0x0b#8
  let y3 := gfMul b0 0x0b#8 ^^^ gfMul b1 0x0d#8 ^^^ gfMul b2 0x09#8 ^^^ gfMul b3 0x0e#8
  packBytes4 y0 y1 y2 y3

private theorem xor4_distrib (a1 a2 a3 a4 b1 b2 b3 b4 : BitVec 8) :
    (a1 ^^^ b1) ^^^ (a2 ^^^ b2) ^^^ (a3 ^^^ b3) ^^^ (a4 ^^^ b4) =
      (a1 ^^^ a2 ^^^ a3 ^^^ a4) ^^^ (b1 ^^^ b2 ^^^ b3 ^^^ b4) := by
  apply BitVec.eq_of_getLsbD_eq
  intro i _
  simp only [BitVec.getLsbD_xor]
  rw [xor_four_swap (a1.getLsbD i) (b1.getLsbD i) (a2.getLsbD i) (b2.getLsbD i),
      xor_four_swap (xor (a1.getLsbD i) (a2.getLsbD i)) (xor (b1.getLsbD i) (b2.getLsbD i))
        (a3.getLsbD i) (b3.getLsbD i),
      xor_four_swap (xor (xor (a1.getLsbD i) (a2.getLsbD i)) (a3.getLsbD i))
        (xor (xor (b1.getLsbD i) (b2.getLsbD i)) (b3.getLsbD i))
        (a4.getLsbD i) (b4.getLsbD i)]

theorem aesMixColumns32_linear : IsF2Linear 32 aesMixColumns32 :=
  ⟨by simp [aesMixColumns32, byteOf32_zero, gfMul_zero_left, packBytes4_zero],
   fun x y => by
    simp only [aesMixColumns32, byteOf32_xor, gfMul_xor_left]
    rw [← packBytes4_xor]
    congr 1 <;> exact xor4_distrib _ _ _ _ _ _ _ _⟩

theorem aesInvMixColumns32_linear : IsF2Linear 32 aesInvMixColumns32 :=
  ⟨by simp [aesInvMixColumns32, byteOf32_zero, gfMul_zero_left, packBytes4_zero],
   fun x y => by
    simp only [aesInvMixColumns32, byteOf32_xor, gfMul_xor_left]
    rw [← packBytes4_xor]
    congr 1 <;> exact xor4_distrib _ _ _ _ _ _ _ _⟩

/-- Direct OpenSSL 32-bit `XtimeWord` / `XtimeLong` lane from `crypto/aes/aes_core.c`. -/
def xtimeWord32 (w : BitVec 32) : BitVec 32 :=
  let b := w &&& 0x80808080#32
  let a := w ^^^ b
  let b := b - (b >>> 7)
  let b := b &&& 0x1B1B1B1B#32
  b ^^^ (a <<< 1)

private def hiBits32 (b0 b1 b2 b3 : Bool) : BitVec 32 :=
  (if b0 then 0x00000080#32 else 0#32) |||
  (if b1 then 0x00008000#32 else 0#32) |||
  (if b2 then 0x00800000#32 else 0#32) |||
  (if b3 then 0x80000000#32 else 0#32)

private theorem mask80_bits :
    ∀ i : Fin 32,
      (0x80808080#32).getLsbD i.val =
        (decide (i.val = 7) || decide (i.val = 15) || decide (i.val = 23) || decide (i.val = 31)) := by
  decide +kernel

private theorem hiBits32_sub_and :
    ∀ b0 b1 b2 b3 : Bool,
      let h := hiBits32 b0 b1 b2 b3
      ((h - (h >>> 7)) &&& 0x1B1B1B1B#32) =
        packBytes4 (if b0 then 0x1b#8 else 0#8)
                   (if b1 then 0x1b#8 else 0#8)
                   (if b2 then 0x1b#8 else 0#8)
                   (if b3 then 0x1b#8 else 0#8) := by
  decide +kernel

private theorem and_mask80_eq_hiBits (w : BitVec 32) :
    w &&& 0x80808080#32 = hiBits32 (w.getLsbD 7) (w.getLsbD 15) (w.getLsbD 23) (w.getLsbD 31) := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  rw [BitVec.getLsbD_and, mask80_bits ⟨i, hi⟩]
  have hcheck : ∀ b0 b1 b2 b3 : Bool, ∀ j : Fin 32,
      (hiBits32 b0 b1 b2 b3).getLsbD j.val =
        if j.val = 7 then b0 else if j.val = 15 then b1 else if j.val = 23 then b2
        else if j.val = 31 then b3 else false := by
    decide +kernel
  rw [hcheck _ _ _ _ ⟨i, hi⟩]
  by_cases h7 : i = 7
  · subst h7; simp
  · by_cases h15 : i = 15
    · subst h15; simp
    · by_cases h23 : i = 23
      · subst h23; simp
      · by_cases h31 : i = 31
        · subst h31; simp
        · simp [h7, h15, h23, h31]

private theorem masked_shl1_eq_pack (w : BitVec 32) :
    (w ^^^ (w &&& 0x80808080#32)) <<< 1 =
      packBytes4 (byteOf32 w 0 <<< 1) (byteOf32 w 1 <<< 1)
                 (byteOf32 w 2 <<< 1) (byteOf32 w 3 <<< 1) := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  rw [BitVec.getLsbD_shiftLeft, packBytes4_getLsbD _ _ _ _ i hi]
  by_cases h0 : i = 0
  · subst h0; simp
  · have hge1 : ¬ (i < 1) := by omega
    have hm1 : i - 1 < 32 := by omega
    rw [decide_eq_true hi, Bool.true_and, decide_eq_false hge1, Bool.not_false, Bool.true_and,
        BitVec.getLsbD_xor, BitVec.getLsbD_and, mask80_bits ⟨i - 1, hm1⟩]
    by_cases h8 : i < 8
    · have ha : i - 1 ≠ 7 ∧ i - 1 ≠ 15 ∧ i - 1 ≠ 23 ∧ i - 1 ≠ 31 := by omega
      have hsublt : i - 1 < 8 := by omega
      simp only [h8, ite_true, BitVec.getLsbD_shiftLeft,
        decide_eq_false hge1, Bool.not_false, byteOf32_getLsbD, hsublt, Nat.mul_zero, Nat.zero_add]
      simp [ha]
    · by_cases h16 : i < 16
      · by_cases heq8 : i = 8
        · subst heq8; simp
        · have ha : i - 1 ≠ 7 ∧ i - 1 ≠ 15 ∧ i - 1 ≠ 23 ∧ i - 1 ≠ 31 := by omega
          have hsub : 8 * 1 + (i - 8 - 1) = i - 1 := by omega
          have hsublt : i - 8 < 8 := by omega
          have hsublt1 : i - 8 - 1 < 8 := by omega
          have hsubpos : ¬ (i - 8 < 1) := by omega
          simp only [h8, h16, ite_false, ite_true, BitVec.getLsbD_shiftLeft,
            decide_eq_true hsublt, Bool.true_and, decide_eq_false hsubpos, Bool.not_false,
            byteOf32_getLsbD, hsublt1, hsub]
          simp [ha]
      · by_cases h24 : i < 24
        · by_cases heq16 : i = 16
          · subst heq16; simp
          · have ha : i - 1 ≠ 7 ∧ i - 1 ≠ 15 ∧ i - 1 ≠ 23 ∧ i - 1 ≠ 31 := by omega
            have hsub : 8 * 2 + (i - 16 - 1) = i - 1 := by omega
            have hsublt : i - 16 < 8 := by omega
            have hsublt1 : i - 16 - 1 < 8 := by omega
            have hsubpos : ¬ (i - 16 < 1) := by omega
            simp only [h8, h16, h24, ite_false, ite_true, BitVec.getLsbD_shiftLeft,
              decide_eq_true hsublt, Bool.true_and, decide_eq_false hsubpos, Bool.not_false,
              byteOf32_getLsbD, hsublt1, hsub]
            simp [ha]
        · by_cases heq24 : i = 24
          · subst heq24; simp
          · have ha : i - 1 ≠ 7 ∧ i - 1 ≠ 15 ∧ i - 1 ≠ 23 ∧ i - 1 ≠ 31 := by omega
            have hsub : 8 * 3 + (i - 24 - 1) = i - 1 := by omega
            have hsublt : i - 24 < 8 := by omega
            have hsublt1 : i - 24 - 1 < 8 := by omega
            have hsubpos : ¬ (i - 24 < 1) := by omega
            simp only [h8, h16, h24, ite_false, BitVec.getLsbD_shiftLeft,
              decide_eq_true hsublt, Bool.true_and, decide_eq_false hsubpos, Bool.not_false,
              byteOf32_getLsbD, hsublt1, hsub]
            simp [ha]

/-- OpenSSL's branchless `XtimeWord` / `XtimeLong` 32-bit lane matches per-byte `gfXtime` on all
`2^32` 32-bit words. -/
theorem xtimeWord32_eq_bytes (w : BitVec 32) :
    xtimeWord32 w =
      packBytes4 (gfXtime (byteOf32 w 0)) (gfXtime (byteOf32 w 1))
                 (gfXtime (byteOf32 w 2)) (gfXtime (byteOf32 w 3)) := by
  simp only [xtimeWord32]
  rw [masked_shl1_eq_pack w, and_mask80_eq_hiBits w, hiBits32_sub_and, ← packBytes4_xor]
  have hb0 : (byteOf32 w 0).getLsbD 7 = w.getLsbD 7 := by rw [byteOf32_getLsbD]; rfl
  have hb1 : (byteOf32 w 1).getLsbD 7 = w.getLsbD 15 := by rw [byteOf32_getLsbD]; rfl
  have hb2 : (byteOf32 w 2).getLsbD 7 = w.getLsbD 23 := by rw [byteOf32_getLsbD]; rfl
  have hb3 : (byteOf32 w 3).getLsbD 7 = w.getLsbD 31 := by rw [byteOf32_getLsbD]; rfl
  have hbyte : ∀ c : BitVec 8, (if c.getLsbD 7 then 0x1b#8 else 0#8) ^^^ (c <<< 1) = gfXtime c := by
    intro c
    unfold gfXtime
    cases c.getLsbD 7
    · simp
    · simp [BitVec.xor_comm]
  rw [← hb0, ← hb1, ← hb2, ← hb3, hbyte, hbyte, hbyte, hbyte]

private theorem xtimeWord32_linear : IsF2Linear 32 xtimeWord32 :=
  ⟨by simp [xtimeWord32_eq_bytes, byteOf32_zero, gfXtime_zero, packBytes4_zero],
   fun x y => by simp [xtimeWord32_eq_bytes, byteOf32_xor, gfXtime_xor, packBytes4_xor]⟩

/-- 16-bit half-word swap inside a 32-bit AES column (from OpenSSL `MixColumns`). -/
def swap16_32 (s : BitVec 32) : BitVec 32 :=
  ((s &&& 0xFFFF0000#32) >>> 16) ||| ((s &&& 0x0000FFFF#32) <<< 16)

/-- Adjacent byte swap inside a 32-bit AES column (from OpenSSL `MixColumns`). -/
def swap8_32 (s : BitVec 32) : BitVec 32 :=
  ((s &&& 0xFF00FF00#32) >>> 8) ||| ((s &&& 0x00FF00FF#32) <<< 8)

/-- Cyclic byte rotation `b[0..3] ↦ (b[1], b[2], b[3], b[0])` (from OpenSSL `MixColumns`). -/
def rotBytesRight32 (s : BitVec 32) : BitVec 32 :=
  packBytes4 (byteOf32 s 1) (byteOf32 s 2) (byteOf32 s 3) (byteOf32 s 0)

private theorem swap16_32_linear : IsF2Linear 32 swap16_32 :=
  ⟨by decide +kernel, fun x y => by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    have hdisj : ∀ j : Fin 32,
        ((0xFFFF0000#32).getLsbD (16 + j.val) &&
          (!decide (j.val < 16) && (0x0000FFFF#32).getLsbD (j.val - 16))) = false := by
      decide +kernel
    have hm := hdisj ⟨i, hi⟩
    simp only [swap16_32, BitVec.getLsbD_or, BitVec.getLsbD_xor, BitVec.getLsbD_ushiftRight,
      BitVec.getLsbD_shiftLeft, BitVec.getLsbD_and, decide_eq_true hi, Bool.true_and]
    generalize (0xFFFF0000#32).getLsbD (16 + i) = m1 at hm ⊢
    generalize decide (i < 16) = d at hm ⊢
    generalize (0x0000FFFF#32).getLsbD (i - 16) = m2 at hm ⊢
    cases m1 <;> cases d <;> cases m2 <;> simp at hm ⊢ <;>
      cases x.getLsbD (16 + i) <;> cases y.getLsbD (16 + i) <;>
      cases x.getLsbD (i - 16) <;> cases y.getLsbD (i - 16) <;> rfl⟩

private theorem swap8_32_linear : IsF2Linear 32 swap8_32 :=
  ⟨by decide +kernel, fun x y => by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    have hdisj : ∀ j : Fin 32,
        ((0xFF00FF00#32).getLsbD (8 + j.val) &&
          (!decide (j.val < 8) && (0x00FF00FF#32).getLsbD (j.val - 8))) = false := by
      decide +kernel
    have hm := hdisj ⟨i, hi⟩
    simp only [swap8_32, BitVec.getLsbD_or, BitVec.getLsbD_xor, BitVec.getLsbD_ushiftRight,
      BitVec.getLsbD_shiftLeft, BitVec.getLsbD_and, decide_eq_true hi, Bool.true_and]
    generalize (0xFF00FF00#32).getLsbD (8 + i) = m1 at hm ⊢
    generalize decide (i < 8) = d at hm ⊢
    generalize (0x00FF00FF#32).getLsbD (i - 8) = m2 at hm ⊢
    cases m1 <;> cases d <;> cases m2 <;> simp at hm ⊢ <;>
      cases x.getLsbD (8 + i) <;> cases y.getLsbD (8 + i) <;>
      cases x.getLsbD (i - 8) <;> cases y.getLsbD (i - 8) <;> rfl⟩

private theorem rotBytesRight32_linear : IsF2Linear 32 rotBytesRight32 :=
  ⟨by simp [rotBytesRight32, byteOf32_zero, packBytes4_zero],
   fun x y => by simp [rotBytesRight32, byteOf32_xor, packBytes4_xor]⟩

/-- Direct OpenSSL `MixColumns` column transform from `crypto/aes/aes_core.c`. -/
def opensslMixColumns32 (w : BitVec 32) : BitVec 32 :=
  let s1 := w
  let s := s1
  let s := s ^^^ swap16_32 s
  let s := s ^^^ swap8_32 s
  let s := s ^^^ s1
  let s1 := xtimeWord32 s1
  let s := s ^^^ s1
  s ^^^ rotBytesRight32 s1

/-- Direct OpenSSL `InvMixColumns` column transform from `crypto/aes/aes_core.c`. -/
def opensslInvMixColumns32 (w : BitVec 32) : BitVec 32 :=
  let s1 := w
  let s := s1
  let s := s ^^^ swap16_32 s
  let s := s ^^^ swap8_32 s
  let s := s ^^^ s1
  let s1 := xtimeWord32 s1
  let s := s ^^^ s1
  let s := s ^^^ rotBytesRight32 s1
  let s1 := xtimeWord32 s1
  let s1 := s1 ^^^ swap16_32 s1
  let s := s ^^^ s1
  let s1 := xtimeWord32 s1
  let s1 := s1 ^^^ swap8_32 s1
  s ^^^ s1

private theorem opensslMixColumns32_linear : IsF2Linear 32 opensslMixColumns32 := by
  have h1 : IsF2Linear 32 (fun w => w ^^^ swap16_32 w) := (IsF2Linear.id 32).xor swap16_32_linear
  have h2 : IsF2Linear 32 (fun w => (w ^^^ swap16_32 w) ^^^ swap8_32 (w ^^^ swap16_32 w)) :=
    h1.xor (swap8_32_linear.comp h1)
  have h3 : IsF2Linear 32 (fun w => ((w ^^^ swap16_32 w) ^^^ swap8_32 (w ^^^ swap16_32 w)) ^^^ w) :=
    h2.xor (IsF2Linear.id 32)
  have h4 := h3.xor xtimeWord32_linear
  have h5 := h4.xor (rotBytesRight32_linear.comp xtimeWord32_linear)
  exact h5

private theorem opensslInvMixColumns32_linear : IsF2Linear 32 opensslInvMixColumns32 := by
  have hmc := opensslMixColumns32_linear
  have hx2 := xtimeWord32_linear.comp xtimeWord32_linear
  have ha := hx2.xor (swap16_32_linear.comp hx2)
  have hs1 := hmc.xor ha
  have hx3 := xtimeWord32_linear.comp ha
  have hb := hx3.xor (swap8_32_linear.comp hx3)
  exact hs1.xor hb

/-- NIST FIPS 197 `aesMixColumns32` agrees with OpenSSL's `MixColumns` on all `2^32` inputs. -/
theorem aesMixColumns32_eq_openssl :
    ∀ x : BitVec 32, aesMixColumns32 x = opensslMixColumns32 x :=
  linear_ext aesMixColumns32_linear opensslMixColumns32_linear (by decide +kernel)

/-- NIST FIPS 197 `aesInvMixColumns32` agrees with OpenSSL's `InvMixColumns` on all `2^32` inputs. -/
theorem aesInvMixColumns32_eq_openssl :
    ∀ x : BitVec 32, aesInvMixColumns32 x = opensslInvMixColumns32 x :=
  linear_ext aesInvMixColumns32_linear opensslInvMixColumns32_linear (by decide +kernel)

/-- `aesInvMixColumns32` is the exact left inverse of `aesMixColumns32` on all `2^32` inputs. -/
theorem aesInvMixColumns32_aesMixColumns32 :
    ∀ x : BitVec 32, aesInvMixColumns32 (aesMixColumns32 x) = x :=
  linear_ext (aesInvMixColumns32_linear.comp aesMixColumns32_linear) (IsF2Linear.id 32)
    (by decide +kernel)

/-- `aesInvMixColumns32` is the exact right inverse of `aesMixColumns32` on all `2^32` inputs. -/
theorem aesMixColumns32_aesInvMixColumns32 :
    ∀ x : BitVec 32, aesMixColumns32 (aesInvMixColumns32 x) = x :=
  linear_ext (aesMixColumns32_linear.comp aesInvMixColumns32_linear) (IsF2Linear.id 32)
    (by decide +kernel)

/-! ### 3 & 4. SM4 Round `L` and Key-Schedule `L'` (RFC 8998 & `crypto/sm4/sm4.c`) -/

/-- 32-bit left rotation mirroring OpenSSL `rotl(a, n)` (`crypto/sm4/sm4.c`). -/
def rotl32 (a : BitVec 32) (n : Nat) : BitVec 32 :=
  (a <<< n) ||| (a >>> (32 - n))

private theorem bv32_getLsbD_ge (v : BitVec 32) (k : Nat) (hk : 32 ≤ k) :
    v.getLsbD k = false := by
  rw [BitVec.getLsbD]
  exact Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le v.isLt (Nat.pow_le_pow_right (by omega) hk))

private theorem rotl32_linear (n : Nat) (hn0 : 0 < n) (hn32 : n < 32) :
    IsF2Linear 32 (fun a => rotl32 a n) :=
  ⟨by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp [rotl32, hi],
   fun x y => by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [rotl32, BitVec.getLsbD_or, BitVec.getLsbD_xor, BitVec.getLsbD_shiftLeft,
      BitVec.getLsbD_ushiftRight, decide_eq_true hi, Bool.true_and]
    by_cases hlt : i < n
    · simp [hlt]
    · have hge : 32 ≤ 32 - n + i := by omega
      simp [hlt, bv32_getLsbD_ge x (32 - n + i) hge, bv32_getLsbD_ge y (32 - n + i) hge]⟩

/-- SM4 round linear diffusion `L(t) = t ^ rotl(t, 2) ^ rotl(t, 10) ^ rotl(t, 18) ^ rotl(t, 24)`
(`crypto/sm4/sm4.c` `SM4_T_slow`). -/
def sm4LinearL32 (t : BitVec 32) : BitVec 32 :=
  t ^^^ rotl32 t 2 ^^^ rotl32 t 10 ^^^ rotl32 t 18 ^^^ rotl32 t 24

/-- SM4 key-schedule linear diffusion `L'(t) = t ^ rotl(t, 13) ^ rotl(t, 23)`
(`crypto/sm4/sm4.c` `SM4_key_sub`). -/
def sm4KeyLPrime32 (t : BitVec 32) : BitVec 32 :=
  t ^^^ rotl32 t 13 ^^^ rotl32 t 23

theorem sm4LinearL32_linear : IsF2Linear 32 sm4LinearL32 :=
  ((((IsF2Linear.id 32).xor (rotl32_linear 2 (by omega) (by omega))).xor
      (rotl32_linear 10 (by omega) (by omega))).xor
      (rotl32_linear 18 (by omega) (by omega))).xor
      (rotl32_linear 24 (by omega) (by omega))

theorem sm4KeyLPrime32_linear : IsF2Linear 32 sm4KeyLPrime32 :=
  ((IsF2Linear.id 32).xor (rotl32_linear 13 (by omega) (by omega))).xor
    (rotl32_linear 23 (by omega) (by omega))

/-! ### 5. ARIA Involutory Diffusion `A` (RFC 5794 & `crypto/aria/aria.c`) -/

/-- XOR parity of selected bit indices of a `BitVec n`. -/
def xorBits {n : Nat} (x : BitVec n) : List Nat → Bool
  | [] => false
  | j :: rest => xor (x.getLsbD j) (xorBits x rest)

private theorem xorBits_zero {n : Nat} : ∀ idxs, xorBits (0#n) idxs = false
  | [] => rfl
  | _ :: rest => by simp [xorBits, xorBits_zero rest]

private theorem xorBits_xor {n : Nat} (x y : BitVec n) :
    ∀ idxs, xorBits (x ^^^ y) idxs = xor (xorBits x idxs) (xorBits y idxs)
  | [] => rfl
  | j :: rest => by
    simp only [xorBits, BitVec.getLsbD_xor, xorBits_xor x y rest]
    exact xor_four_swap _ _ _ _

/-- ARIA 16×16 binary diffusion layer `A` matching OpenSSL `crypto/aria/aria.c` `a()`
(applied identically to each of the 8 bit positions of the 16 state bytes). -/
def ariaDiffusion16 (x : BitVec 16) : BitVec 16 :=
  packBits 16 (fun i =>
    match i with
    | 0  => xorBits x [3, 4, 6, 8, 9, 13, 14]
    | 1  => xorBits x [2, 5, 7, 8, 9, 12, 15]
    | 2  => xorBits x [1, 4, 6, 10, 11, 12, 15]
    | 3  => xorBits x [0, 5, 7, 10, 11, 13, 14]
    | 4  => xorBits x [0, 2, 5, 8, 11, 14, 15]
    | 5  => xorBits x [1, 3, 4, 9, 10, 14, 15]
    | 6  => xorBits x [0, 2, 7, 9, 10, 12, 13]
    | 7  => xorBits x [1, 3, 6, 8, 11, 12, 13]
    | 8  => xorBits x [0, 1, 4, 7, 10, 13, 15]
    | 9  => xorBits x [0, 1, 5, 6, 11, 12, 14]
    | 10 => xorBits x [2, 3, 5, 6, 8, 13, 15]
    | 11 => xorBits x [2, 3, 4, 7, 9, 12, 14]
    | 12 => xorBits x [1, 2, 6, 7, 9, 11, 12]
    | 13 => xorBits x [0, 3, 6, 7, 8, 10, 13]
    | 14 => xorBits x [0, 3, 4, 5, 9, 11, 14]
    | 15 => xorBits x [1, 2, 4, 5, 8, 10, 15]
    | _  => false)

theorem ariaDiffusion16_linear : IsF2Linear 16 ariaDiffusion16 :=
  ⟨by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [ariaDiffusion16, packBits_getLsbD, hi, ite_true, BitVec.getLsbD_zero]
    match i with
    | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 => exact xorBits_zero _
    | _ + 16 => omega,
   fun x y => by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [ariaDiffusion16, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true]
    match i with
    | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 => exact xorBits_xor x y _
    | _ + 16 => omega⟩

/-- ARIA diffusion `A` is an exact involution (`A(A(x)) = x`) on all `2^16` inputs. -/
theorem ariaDiffusion16_involutory :
    ∀ x : BitVec 16, ariaDiffusion16 (ariaDiffusion16 x) = x :=
  linear_ext (ariaDiffusion16_linear.comp ariaDiffusion16_linear) (IsF2Linear.id 16)
    (by decide +kernel)

/-! ### 6. Camellia `P`-function (RFC 3713 §2.3 & `crypto/camellia/camellia.c`) -/

/-- Camellia 8×8 binary diffusion layer `P` (RFC 3713 §2.3, 0-indexed `z1..z8 ↦ z1'..z8'`,
applied identically to each of the 8 bit positions per byte). -/
def camelliaP8 (x : BitVec 8) : BitVec 8 :=
  packBits 8 (fun i =>
    match i with
    | 0 => xorBits x [0, 2, 3, 5, 6, 7]
    | 1 => xorBits x [0, 1, 3, 4, 6, 7]
    | 2 => xorBits x [0, 1, 2, 4, 5, 7]
    | 3 => xorBits x [1, 2, 3, 4, 5, 6]
    | 4 => xorBits x [0, 1, 5, 6, 7]
    | 5 => xorBits x [1, 2, 4, 6, 7]
    | 6 => xorBits x [2, 3, 4, 5, 7]
    | 7 => xorBits x [0, 3, 4, 5, 6]
    | _ => false)

private def camT3 (x : BitVec 8) : BitVec 4 :=
  (if x.getLsbD 3 then 0xd#4 else 0#4) ^^^
  (if x.getLsbD 2 then 0xb#4 else 0#4) ^^^
  (if x.getLsbD 1 then 0x7#4 else 0#4) ^^^
  (if x.getLsbD 0 then 0xe#4 else 0#4)

private def camT2 (x : BitVec 8) : BitVec 4 :=
  (if x.getLsbD 7 then 0xe#4 else 0#4) ^^^
  (if x.getLsbD 6 then 0xd#4 else 0#4) ^^^
  camT3 x ^^^
  (if x.getLsbD 5 then 0xb#4 else 0#4) ^^^
  (if x.getLsbD 4 then 0x7#4 else 0#4)

private def camRrot1 (w : BitVec 4) : BitVec 4 :=
  (w >>> 1) ||| (w <<< 3)

/-- Direct 1-bit-lane model of OpenSSL `Camellia_Feistel` (`crypto/camellia/camellia.c`),
mirroring the `SBOX1_1110`, `SBOX4_4404`, `SBOX2_0222`, `SBOX3_3033` T-table byte replication
patterns (`0xe`, `0xd`, `0x7`, `0xb`) and `RightRotate(_t3, 8)` XOR schedule. -/
def opensslCamelliaFeistelP8 (x : BitVec 8) : BitVec 8 :=
  let outHi := camT2 x
  let outLo := camRrot1 (camT3 x) ^^^ camT2 x
  packBits 8 (fun i =>
    match i with
    | 0 => outHi.getLsbD 3
    | 1 => outHi.getLsbD 2
    | 2 => outHi.getLsbD 1
    | 3 => outHi.getLsbD 0
    | 4 => outLo.getLsbD 3
    | 5 => outLo.getLsbD 2
    | 6 => outLo.getLsbD 1
    | 7 => outLo.getLsbD 0
    | _ => false)

theorem camelliaP8_linear : IsF2Linear 8 camelliaP8 :=
  ⟨by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [camelliaP8, packBits_getLsbD, hi, ite_true, BitVec.getLsbD_zero]
    match i with
    | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 => exact xorBits_zero _
    | _ + 8 => omega,
   fun x y => by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [camelliaP8, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true]
    match i with
    | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 => exact xorBits_xor x y _
    | _ + 8 => omega⟩

private theorem ite_xor_bv4 (a b : Bool) (c : BitVec 4) :
    (if xor a b then c else 0#4) = (if a then c else 0#4) ^^^ (if b then c else 0#4) := by
  cases a <;> cases b <;> simp

private theorem xor2_bv4_swap (a b c d : BitVec 4) :
    (a ^^^ b) ^^^ (c ^^^ d) = (a ^^^ c) ^^^ (b ^^^ d) := by
  apply BitVec.eq_of_getLsbD_eq
  intro i _
  simp only [BitVec.getLsbD_xor]
  exact xor_four_swap _ _ _ _

private theorem camT3_xor (x y : BitVec 8) : camT3 (x ^^^ y) = camT3 x ^^^ camT3 y := by
  unfold camT3
  simp only [BitVec.getLsbD_xor, ite_xor_bv4]
  have step (a1 a2 a3 a4 b1 b2 b3 b4 : BitVec 4) :
      (((a1 ^^^ b1) ^^^ (a2 ^^^ b2)) ^^^ (a3 ^^^ b3)) ^^^ (a4 ^^^ b4) =
        (((a1 ^^^ a2) ^^^ a3) ^^^ a4) ^^^ (((b1 ^^^ b2) ^^^ b3) ^^^ b4) := by
    rw [xor2_bv4_swap a1 b1 a2 b2, xor2_bv4_swap (a1 ^^^ a2) (b1 ^^^ b2) a3 b3,
        xor2_bv4_swap ((a1 ^^^ a2) ^^^ a3) ((b1 ^^^ b2) ^^^ b3) a4 b4]
  exact step _ _ _ _ _ _ _ _

private theorem camT2_xor (x y : BitVec 8) : camT2 (x ^^^ y) = camT2 x ^^^ camT2 y := by
  unfold camT2
  simp only [BitVec.getLsbD_xor, ite_xor_bv4, camT3_xor]
  have step (a1 a2 a3 a4 a5 b1 b2 b3 b4 b5 : BitVec 4) :
      ((((a1 ^^^ b1) ^^^ (a2 ^^^ b2)) ^^^ (a3 ^^^ b3)) ^^^ (a4 ^^^ b4)) ^^^ (a5 ^^^ b5) =
        ((((a1 ^^^ a2) ^^^ a3) ^^^ a4) ^^^ a5) ^^^ ((((b1 ^^^ b2) ^^^ b3) ^^^ b4) ^^^ b5) := by
    rw [xor2_bv4_swap a1 b1 a2 b2, xor2_bv4_swap (a1 ^^^ a2) (b1 ^^^ b2) a3 b3,
        xor2_bv4_swap ((a1 ^^^ a2) ^^^ a3) ((b1 ^^^ b2) ^^^ b3) a4 b4,
        xor2_bv4_swap (((a1 ^^^ a2) ^^^ a3) ^^^ a4) (((b1 ^^^ b2) ^^^ b3) ^^^ b4) a5 b5]
  exact step _ _ _ _ _ _ _ _ _ _

private theorem camRrot1_xor (u v : BitVec 4) :
    camRrot1 (u ^^^ v) = camRrot1 u ^^^ camRrot1 v := by
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  simp only [camRrot1, BitVec.getLsbD_or, BitVec.getLsbD_xor, BitVec.getLsbD_ushiftRight,
    BitVec.getLsbD_shiftLeft, decide_eq_true hi, Bool.true_and]
  match i with
  | 0 | 1 | 2 | 3 => simp
  | _ + 4 => omega

private theorem opensslCamelliaFeistelP8_linear : IsF2Linear 8 opensslCamelliaFeistelP8 :=
  ⟨by decide +kernel, fun x y => by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [opensslCamelliaFeistelP8, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true,
      camT2_xor, camT3_xor, camRrot1_xor]
    match i with
    | 0 | 1 | 2 | 3 => simp
    | 4 | 5 | 6 | 7 => exact xor_four_swap _ _ _ _
    | _ + 8 => omega⟩

/-- RFC 3713 `camelliaP8` agrees with OpenSSL's `Camellia_Feistel` P-function on all 256 inputs. -/
theorem camelliaP8_eq_opensslFeistel :
    ∀ x : BitVec 8, camelliaP8 x = opensslCamelliaFeistelP8 x :=
  linear_ext camelliaP8_linear opensslCamelliaFeistelP8_linear (by decide +kernel)

/-! ## Precomputed Basis-Derived Matrix Rows and Invertibility Proofs -/

def aesMixColumnsRows : List (BitVec 32) := [
  0x01018180#32, 0x02028381#32, 0x04040602#32, 0x08088c84#32,
  0x10109888#32, 0x20203010#32, 0x40406020#32, 0x8080c040#32,
  0x01818001#32, 0x02838102#32, 0x04060204#32, 0x088c8408#32,
  0x10988810#32, 0x20301020#32, 0x40602040#32, 0x80c04080#32,
  0x81800101#32, 0x83810202#32, 0x06020404#32, 0x8c840808#32,
  0x98881010#32, 0x30102020#32, 0x60204040#32, 0xc0408080#32,
  0x80010181#32, 0x81020283#32, 0x02040406#32, 0x8408088c#32,
  0x88101098#32, 0x10202030#32, 0x20404060#32, 0x408080c0#32
]

def aesInvMixColumnsRows : List (BitVec 32) := [
  0x2161a1e0#32, 0x62a2e321#32, 0xc445c643#32, 0xa9eb2d67#32,
  0x72b6fa2e#32, 0xe46cf45c#32, 0xc8d8e8b8#32, 0x90b0d070#32,
  0x61a1e021#32, 0xa2e32162#32, 0x45c643c4#32, 0xeb2d67a9#32,
  0xb6fa2e72#32, 0x6cf45ce4#32, 0xd8e8b8c8#32, 0xb0d07090#32,
  0xa1e02161#32, 0xe32162a2#32, 0xc643c445#32, 0x2d67a9eb#32,
  0xfa2e72b6#32, 0xf45ce46c#32, 0xe8b8c8d8#32, 0xd07090b0#32,
  0xe02161a1#32, 0x2162a2e3#32, 0x43c445c6#32, 0x67a9eb2d#32,
  0x2e72b6fa#32, 0x5ce46cf4#32, 0xb8c8d8e8#32, 0x7090b0d0#32
]

def sm4LinearLRows : List (BitVec 32) := [
  0x40404101#32, 0x80808202#32, 0x01010405#32, 0x0202080a#32,
  0x04041014#32, 0x08082028#32, 0x10104050#32, 0x202080a0#32,
  0x40410140#32, 0x80820280#32, 0x01040501#32, 0x02080a02#32,
  0x04101404#32, 0x08202808#32, 0x10405010#32, 0x2080a020#32,
  0x41014040#32, 0x82028080#32, 0x04050101#32, 0x080a0202#32,
  0x10140404#32, 0x20280808#32, 0x40501010#32, 0x80a02020#32,
  0x01404041#32, 0x02808082#32, 0x05010104#32, 0x0a020208#32,
  0x14040410#32, 0x28080820#32, 0x50101040#32, 0xa0202080#32
]

def sm4KeyLPrimeRows : List (BitVec 32) := [
  0x00080201#32, 0x00100402#32, 0x00200804#32, 0x00401008#32,
  0x00802010#32, 0x01004020#32, 0x02008040#32, 0x04010080#32,
  0x08020100#32, 0x10040200#32, 0x20080400#32, 0x40100800#32,
  0x80201000#32, 0x00402001#32, 0x00804002#32, 0x01008004#32,
  0x02010008#32, 0x04020010#32, 0x08040020#32, 0x10080040#32,
  0x20100080#32, 0x40200100#32, 0x80400200#32, 0x00800401#32,
  0x01000802#32, 0x02001004#32, 0x04002008#32, 0x08004010#32,
  0x10008020#32, 0x20010040#32, 0x40020080#32, 0x80040100#32
]

def ariaDiffusionRows : List (BitVec 16) := [
  0x6358#16, 0x93a4#16, 0x9c52#16, 0x6ca1#16, 0xc925#16, 0xc61a#16, 0x3685#16, 0x394a#16,
  0xa493#16, 0x5863#16, 0xa16c#16, 0x529c#16, 0x1ac6#16, 0x25c9#16, 0x4a39#16, 0x8536#16
]

def camelliaPRows : List (BitVec 8) := [
  0xed#8, 0xdb#8, 0xb7#8, 0x7e#8, 0xe3#8, 0xd6#8, 0xbc#8, 0x79#8
]

def camelliaPInvRows : List (BitVec 8) := [
  0xee#8, 0xdd#8, 0xbb#8, 0x77#8, 0xd3#8, 0xb6#8, 0x7c#8, 0xe9#8
]

theorem aesMixColumnsRows_basis :
    checkRowsBasis 32 aesMixColumnsRows aesMixColumns32 = true := by
  decide +kernel

theorem aesInvMixColumnsRows_basis :
    checkRowsBasis 32 aesInvMixColumnsRows aesInvMixColumns32 = true := by
  decide +kernel

theorem sm4LinearLRows_basis :
    checkRowsBasis 32 sm4LinearLRows sm4LinearL32 = true := by
  decide +kernel

theorem sm4KeyLPrimeRows_basis :
    checkRowsBasis 32 sm4KeyLPrimeRows sm4KeyLPrime32 = true := by
  decide +kernel

theorem ariaDiffusionRows_basis :
    checkRowsBasis 16 ariaDiffusionRows ariaDiffusion16 = true := by
  decide +kernel

theorem camelliaPRows_basis :
    checkRowsBasis 8 camelliaPRows camelliaP8 = true := by
  decide +kernel

/-- Exact circulant inverse of SM4 round diffusion `L`. -/
def sm4LinearLInv32 (t : BitVec 32) : BitVec 32 :=
  t ^^^ rotl32 t 2 ^^^ rotl32 t 4 ^^^ rotl32 t 8 ^^^ rotl32 t 12 ^^^
  rotl32 t 14 ^^^ rotl32 t 16 ^^^ rotl32 t 18 ^^^ rotl32 t 22 ^^^
  rotl32 t 24 ^^^ rotl32 t 30

/-- Exact circulant inverse of SM4 key-schedule diffusion `L'`. -/
def sm4KeyLPrimeInv32 (t : BitVec 32) : BitVec 32 :=
  t ^^^ rotl32 t 2 ^^^ rotl32 t 4 ^^^ rotl32 t 8 ^^^ rotl32 t 11 ^^^
  rotl32 t 12 ^^^ rotl32 t 14 ^^^ rotl32 t 17 ^^^ rotl32 t 22 ^^^
  rotl32 t 23 ^^^ rotl32 t 24 ^^^ rotl32 t 30 ^^^ rotl32 t 31

private theorem sm4LinearLInv32_linear : IsF2Linear 32 sm4LinearLInv32 :=
  ((((((((((IsF2Linear.id 32).xor (rotl32_linear 2 (by omega) (by omega))).xor
      (rotl32_linear 4 (by omega) (by omega))).xor
      (rotl32_linear 8 (by omega) (by omega))).xor
      (rotl32_linear 12 (by omega) (by omega))).xor
      (rotl32_linear 14 (by omega) (by omega))).xor
      (rotl32_linear 16 (by omega) (by omega))).xor
      (rotl32_linear 18 (by omega) (by omega))).xor
      (rotl32_linear 22 (by omega) (by omega))).xor
      (rotl32_linear 24 (by omega) (by omega))).xor
      (rotl32_linear 30 (by omega) (by omega))

private theorem sm4KeyLPrimeInv32_linear : IsF2Linear 32 sm4KeyLPrimeInv32 :=
  ((((((((((((IsF2Linear.id 32).xor (rotl32_linear 2 (by omega) (by omega))).xor
      (rotl32_linear 4 (by omega) (by omega))).xor
      (rotl32_linear 8 (by omega) (by omega))).xor
      (rotl32_linear 11 (by omega) (by omega))).xor
      (rotl32_linear 12 (by omega) (by omega))).xor
      (rotl32_linear 14 (by omega) (by omega))).xor
      (rotl32_linear 17 (by omega) (by omega))).xor
      (rotl32_linear 22 (by omega) (by omega))).xor
      (rotl32_linear 23 (by omega) (by omega))).xor
      (rotl32_linear 24 (by omega) (by omega))).xor
      (rotl32_linear 30 (by omega) (by omega))).xor
      (rotl32_linear 31 (by omega) (by omega))

/-- SM4 round linear diffusion `L` is bijective on all `2^32` inputs. -/
theorem sm4LinearL32_invertible :
    ∃ inv : BitVec 32 → BitVec 32,
      ∀ x : BitVec 32, inv (sm4LinearL32 x) = x ∧ sm4LinearL32 (inv x) = x :=
  ⟨sm4LinearLInv32, fun x =>
    ⟨linear_ext (sm4LinearLInv32_linear.comp sm4LinearL32_linear) (IsF2Linear.id 32)
       (by decide +kernel) x,
     linear_ext (sm4LinearL32_linear.comp sm4LinearLInv32_linear) (IsF2Linear.id 32)
       (by decide +kernel) x⟩⟩

/-- SM4 key-schedule linear diffusion `L'` is bijective on all `2^32` inputs. -/
theorem sm4KeyLPrime32_invertible :
    ∃ inv : BitVec 32 → BitVec 32,
      ∀ x : BitVec 32, inv (sm4KeyLPrime32 x) = x ∧ sm4KeyLPrime32 (inv x) = x :=
  ⟨sm4KeyLPrimeInv32, fun x =>
    ⟨linear_ext (sm4KeyLPrimeInv32_linear.comp sm4KeyLPrime32_linear) (IsF2Linear.id 32)
       (by decide +kernel) x,
     linear_ext (sm4KeyLPrime32_linear.comp sm4KeyLPrimeInv32_linear) (IsF2Linear.id 32)
       (by decide +kernel) x⟩⟩

/-- Camellia `P`-function is bijective on all `2^8` inputs. -/
theorem camelliaP8_invertible :
    ∃ inv : BitVec 8 → BitVec 8,
      ∀ x : BitVec 8, inv (camelliaP8 x) = x ∧ camelliaP8 (inv x) = x := by
  refine ⟨matMul 8 camelliaPInvRows, fun x => ⟨?_, ?_⟩⟩
  · exact linear_ext ((IsF2Linear.matMul 8 camelliaPInvRows).comp camelliaP8_linear)
      (IsF2Linear.id 8) (by decide +kernel) x
  · exact linear_ext (camelliaP8_linear.comp (IsF2Linear.matMul 8 camelliaPInvRows))
      (IsF2Linear.id 8) (by decide +kernel) x

/-! ## Track-Specific Soundness Corollaries -/

theorem evalXorCircuit_eq_aesMixColumns32_of_check
    (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 aesMixColumnsRows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = aesMixColumns32 x :=
  evalXorCircuit_eq_of_check 32 aesMixColumns32 aesMixColumns32_linear
    aesMixColumnsRows rfl aesMixColumnsRows_basis gates outputs hcheck

theorem evalXorCircuit_eq_aesInvMixColumns32_of_check
    (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 aesInvMixColumnsRows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = aesInvMixColumns32 x :=
  evalXorCircuit_eq_of_check 32 aesInvMixColumns32 aesInvMixColumns32_linear
    aesInvMixColumnsRows rfl aesInvMixColumnsRows_basis gates outputs hcheck

theorem evalXorCircuit_eq_sm4LinearL32_of_check
    (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 sm4LinearLRows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = sm4LinearL32 x :=
  evalXorCircuit_eq_of_check 32 sm4LinearL32 sm4LinearL32_linear
    sm4LinearLRows rfl sm4LinearLRows_basis gates outputs hcheck

theorem evalXorCircuit_eq_sm4KeyLPrime32_of_check
    (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 sm4KeyLPrimeRows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = sm4KeyLPrime32 x :=
  evalXorCircuit_eq_of_check 32 sm4KeyLPrime32 sm4KeyLPrime32_linear
    sm4KeyLPrimeRows rfl sm4KeyLPrimeRows_basis gates outputs hcheck

theorem evalXorCircuit_eq_ariaDiffusion16_of_check
    (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 16 ariaDiffusionRows gates outputs = true) :
    ∀ x : BitVec 16, evalXorCircuit 16 gates outputs x = ariaDiffusion16 x :=
  evalXorCircuit_eq_of_check 16 ariaDiffusion16 ariaDiffusion16_linear
    ariaDiffusionRows rfl ariaDiffusionRows_basis gates outputs hcheck

theorem evalXorCircuit_eq_camelliaP8_of_check
    (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 8 camelliaPRows gates outputs = true) :
    ∀ x : BitVec 8, evalXorCircuit 8 gates outputs x = camelliaP8 x :=
  evalXorCircuit_eq_of_check 8 camelliaP8 camelliaP8_linear
    camelliaPRows rfl camelliaPRows_basis gates outputs hcheck

end CryptoLinearXor
