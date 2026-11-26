/-!
# Lightweight Cipher Linear Diffusion Layer XOR Circuits (13 Tracks)

Pure Lean 4.36.0 (zero Mathlib) certified straight-line XOR gate minimization across thirteen
standardized lightweight cryptographic diffusion layers, pinned verbatim to
`rweather/lightweight-crypto@fa4ec9a021` (MIT):

1. **Pyjamask-128** forward `M0..M3, M_K` and inverse `InvM0..InvM3` (nine `32×32` dense circulants, `internal-pyjamask.c`):
```c
#define pyjamask_matrix_multiply_b881b9ca(y) \
    do { \
        uint32_t result; \
        result  = (y); \
        result ^= rightRotate2((y)); \
        result ^= rightRotate3((y)); \
        result ^= rightRotate4((y)); \
        result ^= rightRotate8((y)); \
        result ^= rightRotate15((y)); \
        result ^= rightRotate16((y)); \
        result ^= rightRotate18((y)); \
        result ^= rightRotate19((y)); \
        result ^= rightRotate20((y)); \
        result ^= rightRotate23((y)); \
        result ^= rightRotate24((y)); \
        result ^= rightRotate25((y)); \
        result ^= rightRotate28((y)); \
        result ^= rightRotate30((y)); \
        (y) = result; \
    } while (0)
#define pyjamask_matrix_multiply_a3861085(y) \
    do { \
        uint32_t result; \
        result  = (y); \
        result ^= rightRotate2((y)); \
        result ^= rightRotate6((y)); \
        result ^= rightRotate7((y)); \
        result ^= rightRotate8((y)); \
        result ^= rightRotate13((y)); \
        result ^= rightRotate14((y)); \
        result ^= rightRotate19((y)); \
        result ^= rightRotate24((y)); \
        result ^= rightRotate29((y)); \
        result ^= rightRotate31((y)); \
        (y) = result; \
    } while (0)
#define pyjamask_matrix_multiply_63417021(y) \
    do { \
        uint32_t result; \
        result  = rightRotate1((y)); \
        result ^= rightRotate2((y)); \
        result ^= rightRotate6((y)); \
        result ^= rightRotate7((y)); \
        result ^= rightRotate9((y)); \
        result ^= rightRotate15((y)); \
        result ^= rightRotate17((y)); \
        result ^= rightRotate18((y)); \
        result ^= rightRotate19((y)); \
        result ^= rightRotate26((y)); \
        result ^= rightRotate31((y)); \
        (y) = result; \
    } while (0)
#define pyjamask_matrix_multiply_692cf280(y) \
    do { \
        uint32_t result; \
        result  = rightRotate1((y)); \
        result ^= rightRotate2((y)); \
        result ^= rightRotate4((y)); \
        result ^= rightRotate7((y)); \
        result ^= rightRotate10((y)); \
        result ^= rightRotate12((y)); \
        result ^= rightRotate13((y)); \
        result ^= rightRotate16((y)); \
        result ^= rightRotate17((y)); \
        result ^= rightRotate18((y)); \
        result ^= rightRotate19((y)); \
        result ^= rightRotate22((y)); \
        result ^= rightRotate24((y)); \
        (y) = result; \
    } while (0)
#define pyjamask_matrix_multiply_48a54813(y) \
    do { \
        uint32_t result; \
        result  = rightRotate1((y)); \
        result ^= rightRotate4((y)); \
        result ^= rightRotate8((y)); \
        result ^= rightRotate10((y)); \
        result ^= rightRotate13((y)); \
        result ^= rightRotate15((y)); \
        result ^= rightRotate17((y)); \
        result ^= rightRotate20((y)); \
        result ^= rightRotate27((y)); \
        result ^= rightRotate30((y)); \
        result ^= rightRotate31((y)); \
        (y) = result; \
    } while (0)
#define pyjamask_matrix_multiply_2037a121(y) \
    do { \
        uint32_t result; \
        result  = rightRotate2((y)); \
        result ^= rightRotate10((y)); \
        result ^= rightRotate11((y)); \
        result ^= rightRotate13((y)); \
        result ^= rightRotate14((y)); \
        result ^= rightRotate15((y)); \
        result ^= rightRotate16((y)); \
        result ^= rightRotate18((y)); \
        result ^= rightRotate23((y)); \
        result ^= rightRotate26((y)); \
        result ^= rightRotate31((y)); \
        (y) = result; \
    } while (0)
#define pyjamask_matrix_multiply_108ff2a0(y) \
    do { \
        uint32_t result; \
        result  = rightRotate3((y)); \
        result ^= rightRotate8((y)); \
        result ^= rightRotate12((y)); \
        result ^= rightRotate13((y)); \
        result ^= rightRotate14((y)); \
        result ^= rightRotate15((y)); \
        result ^= rightRotate16((y)); \
        result ^= rightRotate17((y)); \
        result ^= rightRotate18((y)); \
        result ^= rightRotate19((y)); \
        result ^= rightRotate22((y)); \
        result ^= rightRotate24((y)); \
        result ^= rightRotate26((y)); \
        (y) = result; \
    } while (0)
#define pyjamask_matrix_multiply_9054d8c0(y) \
    do { \
        uint32_t result; \
        result  = (y); \
        result ^= rightRotate3((y)); \
        result ^= rightRotate9((y)); \
        result ^= rightRotate11((y)); \
        result ^= rightRotate13((y)); \
        result ^= rightRotate16((y)); \
        result ^= rightRotate17((y)); \
        result ^= rightRotate19((y)); \
        result ^= rightRotate20((y)); \
        result ^= rightRotate24((y)); \
        result ^= rightRotate25((y)); \
        (y) = result; \
    } while (0)
#define pyjamask_matrix_multiply_3354b117(y) \
    do { \
        uint32_t result; \
        result  = rightRotate2((y)); \
        result ^= rightRotate3((y)); \
        result ^= rightRotate6((y)); \
        result ^= rightRotate7((y)); \
        result ^= rightRotate9((y)); \
        result ^= rightRotate11((y)); \
        result ^= rightRotate13((y)); \
        result ^= rightRotate16((y)); \
        result ^= rightRotate18((y)); \
        result ^= rightRotate19((y)); \
        result ^= rightRotate23((y)); \
        result ^= rightRotate27((y)); \
        result ^= rightRotate29((y)); \
        result ^= rightRotate30((y)); \
        result ^= rightRotate31((y)); \
        (y) = result; \
    } while (0)
```
2. **PHOTON-256 MDS** (`8×8` MDS over `GF(2^4)` = `32×32` over `GF(2)`, `internal-photon256.c`):
```c
        t8 = MUL(0x02, t0) ^ MUL(0x04, t1) ^ MUL(0x02, t2) ^ MUL(0x0b, t3) ^
             MUL(0x02, t4) ^ MUL(0x08, t5) ^ MUL(0x05, t6) ^ MUL(0x06, t7);
        WRITE_ROW(0, t8);
        t8 = MUL(0x0c, t0) ^ MUL(0x09, t1) ^ MUL(0x08, t2) ^ MUL(0x0d, t3) ^
             MUL(0x07, t4) ^ MUL(0x07, t5) ^ MUL(0x05, t6) ^ MUL(0x02, t7);
        WRITE_ROW(1, t8);
        t8 = MUL(0x04, t0) ^ MUL(0x04, t1) ^ MUL(0x0d, t2) ^ MUL(0x0d, t3) ^
             MUL(0x09, t4) ^ MUL(0x04, t5) ^ MUL(0x0d, t6) ^ MUL(0x09, t7);
        WRITE_ROW(2, t8);
        t8 = MUL(0x01, t0) ^ MUL(0x06, t1) ^ MUL(0x05, t2) ^ MUL(0x01, t3) ^
             MUL(0x0c, t4) ^ MUL(0x0d, t5) ^ MUL(0x0f, t6) ^ MUL(0x0e, t7);
        WRITE_ROW(3, t8);
        t8 = MUL(0x0f, t0) ^ MUL(0x0c, t1) ^ MUL(0x09, t2) ^ MUL(0x0d, t3) ^
             MUL(0x0e, t4) ^ MUL(0x05, t5) ^ MUL(0x0e, t6) ^ MUL(0x0d, t7);
        WRITE_ROW(4, t8);
        t8 = MUL(0x09, t0) ^ MUL(0x0e, t1) ^ MUL(0x05, t2) ^ MUL(0x0f, t3) ^
             MUL(0x04, t4) ^ MUL(0x0c, t5) ^ MUL(0x09, t6) ^ MUL(0x06, t7);
        WRITE_ROW(5, t8);
        t8 = MUL(0x0c, t0) ^ MUL(0x02, t1) ^ MUL(0x02, t2) ^ MUL(0x0a, t3) ^
             MUL(0x03, t4) ^ MUL(0x01, t5) ^ MUL(0x01, t6) ^ MUL(0x0e, t7);
        WRITE_ROW(6, t8);
        t8 = MUL(0x0f, t0) ^ MUL(0x01, t1) ^ MUL(0x0d, t2) ^ MUL(0x0a, t3) ^
             MUL(0x05, t4) ^ MUL(0x0a, t5) ^ MUL(0x02, t6) ^ MUL(0x03, t7);
        WRITE_ROW(7, t8);
```
3. **Clyde-128 / Spook L-box** (`64×64` over `GF(2)`, `internal-spook.c`):
```c
        #define clyde128_lbox(x, y) \
            do { \
                c = x ^ rightRotate12(x); \
                d = y ^ rightRotate12(y); \
                c ^= rightRotate3(c); \
                d ^= rightRotate3(d); \
                x = c ^ leftRotate15(x); \
                y = d ^ leftRotate15(y); \
                c = x ^ leftRotate1(x); \
                d = y ^ leftRotate1(y); \
                x ^= leftRotate6(d); \
                y ^= leftRotate7(c); \
                x ^= rightRotate15(c); \
                y ^= rightRotate15(d); \
            } while (0)
```
4. **Ascon NIST SP 800-232** `Σ0, Σ2` (`64×64` circulant diffusion layers, `internal-ascon.c`):
```c
        /* Linear diffusion layer */
        x0 ^= rightRotate19_64(x0) ^ rightRotate28_64(x0);
        x1 ^= rightRotate61_64(x1) ^ rightRotate39_64(x1);
        x2 ^= rightRotate1_64(x2)  ^ rightRotate6_64(x2);
        x3 ^= rightRotate10_64(x3) ^ rightRotate17_64(x3);
        x4 ^= rightRotate7_64(x4)  ^ rightRotate41_64(x4);
```
-/

namespace LwcLinearXor

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
    simp only [LwcLinearXor.matMul, packBits_getLsbD, hi, ite_true,
      dotParity_zero_right, BitVec.getLsbD_zero],
   fun x y => by
    apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [LwcLinearXor.matMul, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true,
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



/-! ## Verbatim Lightweight Cipher Diffusion Layer Reference Maps & `GF(2)`-Linearity -/

private theorem bv_xor_four_swap {n : Nat} (a b c d : BitVec n) :
    (a ^^^ b) ^^^ (c ^^^ d) = (a ^^^ c) ^^^ (b ^^^ d) := by
  apply BitVec.eq_of_getLsbD_eq
  intro i _
  simp only [BitVec.getLsbD_xor]
  exact xor_four_swap _ _ _ _

private theorem bv_xor_three_lin {n : Nat} (a1 a2 b1 b2 c1 c2 : BitVec n) :
    ((a1 ^^^ a2) ^^^ (b1 ^^^ b2)) ^^^ (c1 ^^^ c2) =
      ((a1 ^^^ b1) ^^^ c1) ^^^ ((a2 ^^^ b2) ^^^ c2) := by
  rw [bv_xor_four_swap a1 a2 b1 b2, bv_xor_four_swap (a1 ^^^ b1) (a2 ^^^ b2) c1 c2]

private theorem bv_xor_four_lin {n : Nat} (a1 a2 b1 b2 c1 c2 d1 d2 : BitVec n) :
    ((a1 ^^^ a2) ^^^ (b1 ^^^ b2)) ^^^ ((c1 ^^^ c2) ^^^ (d1 ^^^ d2)) =
      ((a1 ^^^ b1) ^^^ (c1 ^^^ d1)) ^^^ ((a2 ^^^ b2) ^^^ (c2 ^^^ d2)) := by
  rw [bv_xor_four_swap a1 a2 b1 b2, bv_xor_four_swap c1 c2 d1 d2,
      bv_xor_four_swap (a1 ^^^ b1) (a2 ^^^ b2) (c1 ^^^ d1) (c2 ^^^ d2)]

private theorem bv_xor_eight_lin {n : Nat}
    (a0 b0 a1 b1 a2 b2 a3 b3 a4 b4 a5 b5 a6 b6 a7 b7 : BitVec n) :
    (((a0 ^^^ b0) ^^^ (a1 ^^^ b1)) ^^^ ((a2 ^^^ b2) ^^^ (a3 ^^^ b3))) ^^^
    (((a4 ^^^ b4) ^^^ (a5 ^^^ b5)) ^^^ ((a6 ^^^ b6) ^^^ (a7 ^^^ b7))) =
    (((a0 ^^^ a1) ^^^ (a2 ^^^ a3)) ^^^ ((a4 ^^^ a5) ^^^ (a6 ^^^ a7))) ^^^
    (((b0 ^^^ b1) ^^^ (b2 ^^^ b3)) ^^^ ((b4 ^^^ b5) ^^^ (b6 ^^^ b7))) := by
  rw [bv_xor_four_lin a0 b0 a1 b1 a2 b2 a3 b3,
      bv_xor_four_lin a4 b4 a5 b5 a6 b6 a7 b7,
      bv_xor_four_swap ((a0 ^^^ a1) ^^^ (a2 ^^^ a3)) ((b0 ^^^ b1) ^^^ (b2 ^^^ b3))
                       ((a4 ^^^ a5) ^^^ (a6 ^^^ a7)) ((b4 ^^^ b5) ^^^ (b6 ^^^ b7))]

private theorem bv_getLsbD_ge {n : Nat} (x : BitVec n) (j : Nat) (hj : n ≤ j) :
    x.getLsbD j = false := by
  show x.toNat.testBit j = false
  exact Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le x.isLt (Nat.pow_le_pow_right (by omega) hj))

/-- Right bit-rotation on `BitVec n` (for `k ≤ n`). -/
def rotrBV (n k : Nat) (x : BitVec n) : BitVec n :=
  (x >>> k) ||| (x <<< (n - k))

/-- Left bit-rotation on `BitVec n` (for `k ≤ n`). -/
def rotlBV (n k : Nat) (x : BitVec n) : BitVec n :=
  (x <<< k) ||| (x >>> (n - k))

private theorem rotrBV_isLinear (n k : Nat) (hk : k ≤ n) : IsF2Linear n (rotrBV n k) := by
  refine ⟨?_, fun x y => ?_⟩
  · apply BitVec.eq_of_getLsbD_eq
    intro i _
    simp [rotrBV]
  · apply BitVec.eq_of_getLsbD_eq
    intro i hi
    simp only [rotrBV, BitVec.getLsbD_or, BitVec.getLsbD_xor, BitVec.getLsbD_ushiftRight, BitVec.getLsbD_shiftLeft]
    by_cases hlt : i < n - k
    · simp only [hi, hlt, decide_true, Bool.not_true, Bool.and_false, Bool.false_and, Bool.or_false]
    · have h2 : n ≤ k + i := by omega
      have hx0 : x.getLsbD (k + i) = false := bv_getLsbD_ge x (k + i) h2
      have hy0 : y.getLsbD (k + i) = false := bv_getLsbD_ge y (k + i) h2
      simp only [hi, hlt, hx0, hy0, decide_true, decide_false, Bool.not_false,
        Bool.true_and, Bool.false_xor, Bool.false_or]

private theorem rotlBV_isLinear (n k : Nat) (hk : k ≤ n) : IsF2Linear n (rotlBV n k) := by
  have heq : rotlBV n k = rotrBV n (n - k) := by
    funext x
    unfold rotlBV rotrBV
    have hsub : n - (n - k) = k := by omega
    rw [hsub]
    apply BitVec.eq_of_getLsbD_eq
    intro i _
    simp [BitVec.getLsbD_or, Bool.or_comm]
  rw [heq]
  exact rotrBV_isLinear n (n - k) (by omega)

/-- Sum of right-rotations of `x : BitVec n` over rotation list `rs`. -/
def rotSum (n : Nat) : List Nat → BitVec n → BitVec n
  | [], _ => 0#n
  | r :: rs, x => rotrBV n r x ^^^ rotSum n rs x

private theorem rotSum_isLinear (n : Nat) :
    ∀ rs : List Nat, (∀ r ∈ rs, r ≤ n) → IsF2Linear n (rotSum n rs)
  | [], _ => ⟨rfl, fun _ _ => by simp [rotSum]⟩
  | r :: rs, h => by
    have hr : r ≤ n := h r (by simp)
    have hrs : ∀ r' ∈ rs, r' ≤ n := fun r' hr' => h r' (by simp [hr'])
    exact IsF2Linear.xor (rotrBV_isLinear n r hr) (rotSum_isLinear n rs hrs)

/-- Pyjamask-128 forward & inverse circulant linear layers (`internal-pyjamask.c`). -/
def pyjamaskM0_32 (y : BitVec 32) : BitVec 32 := rotSum 32 [0, 2, 6, 7, 8, 13, 14, 19, 24, 29, 31] y
def pyjamaskM1_32 (y : BitVec 32) : BitVec 32 := rotSum 32 [1, 2, 6, 7, 9, 15, 17, 18, 19, 26, 31] y
def pyjamaskM2_32 (y : BitVec 32) : BitVec 32 := rotSum 32 [1, 2, 4, 7, 10, 12, 13, 16, 17, 18, 19, 22, 24] y
def pyjamaskM3_32 (y : BitVec 32) : BitVec 32 := rotSum 32 [1, 4, 8, 10, 13, 15, 17, 20, 27, 30, 31] y
def pyjamaskMK_32 (y : BitVec 32) : BitVec 32 := rotSum 32 [0, 2, 3, 4, 8, 15, 16, 18, 19, 20, 23, 24, 25, 28, 30] y
def pyjamaskInvM0_32 (y : BitVec 32) : BitVec 32 := rotSum 32 [2, 10, 11, 13, 14, 15, 16, 18, 23, 26, 31] y
def pyjamaskInvM1_32 (y : BitVec 32) : BitVec 32 := rotSum 32 [3, 8, 12, 13, 14, 15, 16, 17, 18, 19, 22, 24, 26] y
def pyjamaskInvM2_32 (y : BitVec 32) : BitVec 32 := rotSum 32 [0, 3, 9, 11, 13, 16, 17, 19, 20, 24, 25] y
def pyjamaskInvM3_32 (y : BitVec 32) : BitVec 32 := rotSum 32 [2, 3, 6, 7, 9, 11, 13, 16, 18, 19, 23, 27, 29, 30, 31] y

theorem pyjamaskM0_32_isLinear : IsF2Linear 32 pyjamaskM0_32 := rotSum_isLinear 32 _ (by decide)
theorem pyjamaskM1_32_isLinear : IsF2Linear 32 pyjamaskM1_32 := rotSum_isLinear 32 _ (by decide)
theorem pyjamaskM2_32_isLinear : IsF2Linear 32 pyjamaskM2_32 := rotSum_isLinear 32 _ (by decide)
theorem pyjamaskM3_32_isLinear : IsF2Linear 32 pyjamaskM3_32 := rotSum_isLinear 32 _ (by decide)
theorem pyjamaskMK_32_isLinear : IsF2Linear 32 pyjamaskMK_32 := rotSum_isLinear 32 _ (by decide)
theorem pyjamaskInvM0_32_isLinear : IsF2Linear 32 pyjamaskInvM0_32 := rotSum_isLinear 32 _ (by decide)
theorem pyjamaskInvM1_32_isLinear : IsF2Linear 32 pyjamaskInvM1_32 := rotSum_isLinear 32 _ (by decide)
theorem pyjamaskInvM2_32_isLinear : IsF2Linear 32 pyjamaskInvM2_32 := rotSum_isLinear 32 _ (by decide)
theorem pyjamaskInvM3_32_isLinear : IsF2Linear 32 pyjamaskInvM3_32 := rotSum_isLinear 32 _ (by decide)

/-- Kernel-verified two-sided invertibility of Pyjamask `M0..M3` and `InvM0..InvM3` on all `2^32` inputs. -/
private def checkCompId (n : Nat) (f g : BitVec n → BitVec n) : Nat → Bool
  | 0 => true
  | k + 1 => ((f (g (basisVec n k))).toNat == (basisVec n k).toNat) && checkCompId n f g k

private theorem checkCompId_sound (n : Nat) (f g : BitVec n → BitVec n) :
    ∀ k, checkCompId n f g k = true → ∀ j, j < k → f (g (basisVec n j)) = basisVec n j
  | 0, _, _, hj => by omega
  | k + 1, h, j, hj => by
    simp only [checkCompId, Bool.and_eq_true, beq_iff_eq] at h
    by_cases hlt : j < k
    · exact checkCompId_sound n f g k h.2 j hlt
    · have heq : j = k := by omega
      subst heq; exact BitVec.eq_of_toNat_eq h.1

private theorem pyjamaskM0_inv_basis : checkCompId 32 pyjamaskInvM0_32 pyjamaskM0_32 32 = true := by decide +kernel
private theorem pyjamaskM1_inv_basis : checkCompId 32 pyjamaskInvM1_32 pyjamaskM1_32 32 = true := by decide +kernel
private theorem pyjamaskM2_inv_basis : checkCompId 32 pyjamaskInvM2_32 pyjamaskM2_32 32 = true := by decide +kernel
private theorem pyjamaskM3_inv_basis : checkCompId 32 pyjamaskInvM3_32 pyjamaskM3_32 32 = true := by decide +kernel

theorem pyjamaskInvM0_M0 : ∀ x : BitVec 32, pyjamaskInvM0_32 (pyjamaskM0_32 x) = x :=
  linear_ext (IsF2Linear.comp pyjamaskInvM0_32_isLinear pyjamaskM0_32_isLinear) (IsF2Linear.id 32)
    (fun j => checkCompId_sound 32 pyjamaskInvM0_32 pyjamaskM0_32 32 pyjamaskM0_inv_basis j.val j.isLt)
theorem pyjamaskInvM1_M1 : ∀ x : BitVec 32, pyjamaskInvM1_32 (pyjamaskM1_32 x) = x :=
  linear_ext (IsF2Linear.comp pyjamaskInvM1_32_isLinear pyjamaskM1_32_isLinear) (IsF2Linear.id 32)
    (fun j => checkCompId_sound 32 pyjamaskInvM1_32 pyjamaskM1_32 32 pyjamaskM1_inv_basis j.val j.isLt)
theorem pyjamaskInvM2_M2 : ∀ x : BitVec 32, pyjamaskInvM2_32 (pyjamaskM2_32 x) = x :=
  linear_ext (IsF2Linear.comp pyjamaskInvM2_32_isLinear pyjamaskM2_32_isLinear) (IsF2Linear.id 32)
    (fun j => checkCompId_sound 32 pyjamaskInvM2_32 pyjamaskM2_32 32 pyjamaskM2_inv_basis j.val j.isLt)
theorem pyjamaskInvM3_M3 : ∀ x : BitVec 32, pyjamaskInvM3_32 (pyjamaskM3_32 x) = x :=
  linear_ext (IsF2Linear.comp pyjamaskInvM3_32_isLinear pyjamaskM3_32_isLinear) (IsF2Linear.id 32)
    (fun j => checkCompId_sound 32 pyjamaskInvM3_32 pyjamaskM3_32 32 pyjamaskM3_inv_basis j.val j.isLt)

/-- Ascon NIST SP 800-232 64-bit linear diffusion layers `Σ0` and `Σ2` (`internal-ascon.c`). -/
def asconSigma0_64 (x : BitVec 64) : BitVec 64 := rotSum 64 [0, 19, 28] x
def asconSigma2_64 (x : BitVec 64) : BitVec 64 := rotSum 64 [0, 1, 6] x

theorem asconSigma0_64_isLinear : IsF2Linear 64 asconSigma0_64 := rotSum_isLinear 64 _ (by decide)
theorem asconSigma2_64_isLinear : IsF2Linear 64 asconSigma2_64 := rotSum_isLinear 64 _ (by decide)

/-! ### PHOTON-256 8×8 MDS Matrix over `GF(2^4) = GF(2)[x]/(x^4 + x + 1)` (`32×32` over `GF(2)`) -/

def gf4Xtime (a : BitVec 4) : BitVec 4 :=
  if a.getLsbD 3 then (a <<< 1) ^^^ 0x3#4 else a <<< 1

private theorem gf4Xtime_isLinear : IsF2Linear 4 gf4Xtime := by
  refine ⟨by decide, fun x y => ?_⟩
  apply BitVec.eq_of_getLsbD_eq
  intro i hi
  unfold gf4Xtime
  simp only [BitVec.getLsbD_xor]
  cases hx : x.getLsbD 3 <;> cases hy : y.getLsbD 3 <;>
    simp only [Bool.false_xor, Bool.true_xor, Bool.xor_self, Bool.not_false,
      Bool.false_eq_true, ite_false, ite_true, BitVec.getLsbD_xor, BitVec.getLsbD_shiftLeft,
      hi, decide_true, Bool.true_and]
  · cases decide (i < 1) <;> cases x.getLsbD (i - 1) <;> cases y.getLsbD (i - 1) <;> rfl
  · cases decide (i < 1) <;> cases x.getLsbD (i - 1) <;> cases y.getLsbD (i - 1) <;>
      cases (0x3#4 : BitVec 4).getLsbD i <;> rfl
  · cases decide (i < 1) <;> cases x.getLsbD (i - 1) <;> cases y.getLsbD (i - 1) <;>
      cases (0x3#4 : BitVec 4).getLsbD i <;> rfl
  · cases decide (i < 1) <;> cases x.getLsbD (i - 1) <;> cases y.getLsbD (i - 1) <;>
      cases (0x3#4 : BitVec 4).getLsbD i <;> rfl

def gf4MulConst (a : Nat) (v : BitVec 4) : BitVec 4 :=
  let v1 := gf4Xtime v
  let v2 := gf4Xtime v1
  let v3 := gf4Xtime v2
  (if a.testBit 0 then v else 0#4) ^^^
  (if a.testBit 1 then v1 else 0#4) ^^^
  (if a.testBit 2 then v2 else 0#4) ^^^
  (if a.testBit 3 then v3 else 0#4)

private theorem gf4MulConst_isLinear (a : Nat) : IsF2Linear 4 (gf4MulConst a) := by
  have h0 : IsF2Linear 4 (fun v => if a.testBit 0 then v else 0#4) := by
    cases a.testBit 0
    · exact ⟨rfl, fun _ _ => by simp⟩
    · exact IsF2Linear.id 4
  have h1 : IsF2Linear 4 (fun v => if a.testBit 1 then gf4Xtime v else 0#4) := by
    cases a.testBit 1
    · exact ⟨rfl, fun _ _ => by simp⟩
    · exact gf4Xtime_isLinear
  have h2 : IsF2Linear 4 (fun v => if a.testBit 2 then gf4Xtime (gf4Xtime v) else 0#4) := by
    cases a.testBit 2
    · exact ⟨rfl, fun _ _ => by simp⟩
    · exact IsF2Linear.comp gf4Xtime_isLinear gf4Xtime_isLinear
  have h3 : IsF2Linear 4 (fun v => if a.testBit 3 then gf4Xtime (gf4Xtime (gf4Xtime v)) else 0#4) := by
    cases a.testBit 3
    · exact ⟨rfl, fun _ _ => by simp⟩
    · exact IsF2Linear.comp gf4Xtime_isLinear (IsF2Linear.comp gf4Xtime_isLinear gf4Xtime_isLinear)
  exact IsF2Linear.xor (IsF2Linear.xor (IsF2Linear.xor h0 h1) h2) h3

def getNib (x : BitVec 32) (j : Nat) : BitVec 4 :=
  packBits 4 (fun b => x.getLsbD (4 * j + b))

private theorem getNib_zero (j : Nat) : getNib 0#32 j = 0#4 := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp only [getNib, packBits_getLsbD, hi, ite_true, BitVec.getLsbD_zero]

private theorem getNib_xor (x y : BitVec 32) (j : Nat) :
    getNib (x ^^^ y) j = getNib x j ^^^ getNib y j := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp only [getNib, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true]

def photonMdsRow (c0 c1 c2 c3 c4 c5 c6 c7 : Nat) (x : BitVec 32) : BitVec 4 :=
  ((gf4MulConst c0 (getNib x 0) ^^^ gf4MulConst c1 (getNib x 1)) ^^^
   (gf4MulConst c2 (getNib x 2) ^^^ gf4MulConst c3 (getNib x 3))) ^^^
  ((gf4MulConst c4 (getNib x 4) ^^^ gf4MulConst c5 (getNib x 5)) ^^^
   (gf4MulConst c6 (getNib x 6) ^^^ gf4MulConst c7 (getNib x 7)))

private theorem photonMdsRow_zero (c0 c1 c2 c3 c4 c5 c6 c7 : Nat) :
    photonMdsRow c0 c1 c2 c3 c4 c5 c6 c7 0#32 = 0#4 := by
  simp [photonMdsRow, getNib_zero, (gf4MulConst_isLinear _).map_zero]

private theorem photonMdsRow_xor (c0 c1 c2 c3 c4 c5 c6 c7 : Nat) (x y : BitVec 32) :
    photonMdsRow c0 c1 c2 c3 c4 c5 c6 c7 (x ^^^ y) =
      photonMdsRow c0 c1 c2 c3 c4 c5 c6 c7 x ^^^ photonMdsRow c0 c1 c2 c3 c4 c5 c6 c7 y := by
  simp only [photonMdsRow, getNib_xor, (gf4MulConst_isLinear _).map_xor]
  exact bv_xor_eight_lin _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

/-- PHOTON-256 8×8 MDS linear diffusion layer over `GF(2^4)` (`32×32` over `GF(2)`, `internal-photon256.c`). -/
def photon256Mds32 (x : BitVec 32) : BitVec 32 :=
  let y0 := photonMdsRow 0x02 0x04 0x02 0x0b 0x02 0x08 0x05 0x06 x
  let y1 := photonMdsRow 0x0c 0x09 0x08 0x0d 0x07 0x07 0x05 0x02 x
  let y2 := photonMdsRow 0x04 0x04 0x0d 0x0d 0x09 0x04 0x0d 0x09 x
  let y3 := photonMdsRow 0x01 0x06 0x05 0x01 0x0c 0x0d 0x0f 0x0e x
  let y4 := photonMdsRow 0x0f 0x0c 0x09 0x0d 0x0e 0x05 0x0e 0x0d x
  let y5 := photonMdsRow 0x09 0x0e 0x05 0x0f 0x04 0x0c 0x09 0x06 x
  let y6 := photonMdsRow 0x0c 0x02 0x02 0x0a 0x03 0x01 0x01 0x0e x
  let y7 := photonMdsRow 0x0f 0x01 0x0d 0x0a 0x05 0x0a 0x02 0x03 x
  packBits 32 (fun i =>
    let nib := match i / 4 with
      | 0 => y0 | 1 => y1 | 2 => y2 | 3 => y3 | 4 => y4 | 5 => y5 | 6 => y6 | _ => y7
    nib.getLsbD (i % 4))

theorem photon256Mds32_isLinear : IsF2Linear 32 photon256Mds32 := by
  refine ⟨?_, fun x y => ?_⟩
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    simp only [photon256Mds32, packBits_getLsbD, hi, ite_true, photonMdsRow_zero]
    match i / 4 with
    | 0 | 1 | 2 | 3 | 4 | 5 | 6 | _ + 7 => simp
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    simp only [photon256Mds32, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true, photonMdsRow_xor]
    match i / 4 with
    | 0 | 1 | 2 | 3 | 4 | 5 | 6 | _ + 7 => simp [BitVec.getLsbD_xor]

/-! ### Clyde-128 / Spook 64-Bit L-Box Linear Layer (`internal-spook.c`) -/

def lo32 (v : BitVec 64) : BitVec 32 := packBits 32 (fun i => v.getLsbD i)
def hi32 (v : BitVec 64) : BitVec 32 := packBits 32 (fun i => v.getLsbD (32 + i))
def join64 (x y : BitVec 32) : BitVec 64 :=
  packBits 64 (fun i => if i < 32 then x.getLsbD i else y.getLsbD (i - 32))

private theorem lo32_zero : lo32 0#64 = 0#32 := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp only [lo32, packBits_getLsbD, hi, ite_true, BitVec.getLsbD_zero]
private theorem hi32_zero : hi32 0#64 = 0#32 := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp only [hi32, packBits_getLsbD, hi, ite_true, BitVec.getLsbD_zero]
private theorem lo32_xor (u v : BitVec 64) : lo32 (u ^^^ v) = lo32 u ^^^ lo32 v := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp only [lo32, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true]
private theorem hi32_xor (u v : BitVec 64) : hi32 (u ^^^ v) = hi32 u ^^^ hi32 v := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp only [hi32, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true]
private theorem join64_zero : join64 0#32 0#32 = 0#64 := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp only [join64, packBits_getLsbD, hi, BitVec.getLsbD_zero, ite_self]
private theorem join64_xor (x1 y1 x2 y2 : BitVec 32) :
    join64 (x1 ^^^ x2) (y1 ^^^ y2) = join64 x1 y1 ^^^ join64 x2 y2 := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp only [join64, BitVec.getLsbD_xor, packBits_getLsbD, hi, ite_true]
  by_cases hlt : i < 32 <;> simp only [hlt, ite_true, ite_false]

def clydeHalf1 (w : BitVec 32) : BitVec 32 :=
  let c := w ^^^ rotrBV 32 12 w
  let c := c ^^^ rotrBV 32 3 c
  c ^^^ rotlBV 32 15 w

private theorem clydeHalf1_isLinear : IsF2Linear 32 clydeHalf1 := by
  have hc1 : IsF2Linear 32 (fun w => w ^^^ rotrBV 32 12 w) :=
    IsF2Linear.xor (IsF2Linear.id 32) (rotrBV_isLinear 32 12 (by decide))
  have hc2 : IsF2Linear 32 (fun w => (w ^^^ rotrBV 32 12 w) ^^^ rotrBV 32 3 (w ^^^ rotrBV 32 12 w)) :=
    IsF2Linear.xor hc1 (IsF2Linear.comp (rotrBV_isLinear 32 3 (by decide)) hc1)
  exact IsF2Linear.xor hc2 (rotlBV_isLinear 32 15 (by decide))

def clydeC (w : BitVec 32) : BitVec 32 := w ^^^ rotlBV 32 1 w

private theorem clydeC_isLinear : IsF2Linear 32 clydeC :=
  IsF2Linear.xor (IsF2Linear.id 32) (rotlBV_isLinear 32 1 (by decide))

/-- Clyde-128 / Spook 64-bit L-box linear diffusion layer (`internal-spook.c`: `clyde128_lbox`). -/
def clyde128Lbox64 (v : BitVec 64) : BitVec 64 :=
  let x1 := clydeHalf1 (lo32 v)
  let y1 := clydeHalf1 (hi32 v)
  let c := clydeC x1
  let d := clydeC y1
  let x2 := x1 ^^^ rotlBV 32 6 d ^^^ rotrBV 32 15 c
  let y2 := y1 ^^^ rotlBV 32 7 c ^^^ rotrBV 32 15 d
  join64 x2 y2

theorem clyde128Lbox64_isLinear : IsF2Linear 64 clyde128Lbox64 := by
  have hr6 := rotlBV_isLinear 32 6 (by decide)
  have hr7 := rotlBV_isLinear 32 7 (by decide)
  have hr15 := rotrBV_isLinear 32 15 (by decide)
  refine ⟨?_, fun u v => ?_⟩
  · simp [clyde128Lbox64, lo32_zero, hi32_zero, clydeHalf1_isLinear.map_zero, clydeC_isLinear.map_zero,
      hr6.map_zero, hr7.map_zero, hr15.map_zero, join64_zero]
  · simp only [clyde128Lbox64, lo32_xor, hi32_xor, clydeHalf1_isLinear.map_xor, clydeC_isLinear.map_xor,
      hr6.map_xor, hr7.map_xor, hr15.map_xor, ← join64_xor]
    congr 1
    · exact bv_xor_three_lin _ _ _ _ _ _
    · exact bv_xor_three_lin _ _ _ _ _ _

/-! ## Exact Target Row Matrices (Kernel-Verified Against Reference Maps) -/

def pyjamaskM0Rows : List (BitVec 32) := [
  0xa10861c5#32, 0x4210c38b#32, 0x84218716#32, 0x08430e2d#32,
  0x10861c5a#32, 0x210c38b4#32, 0x42187168#32, 0x8430e2d0#32,
  0x0861c5a1#32, 0x10c38b42#32, 0x21871684#32, 0x430e2d08#32,
  0x861c5a10#32, 0x0c38b421#32, 0x18716842#32, 0x30e2d084#32,
  0x61c5a108#32, 0xc38b4210#32, 0x87168421#32, 0x0e2d0843#32,
  0x1c5a1086#32, 0x38b4210c#32, 0x71684218#32, 0xe2d08430#32,
  0xc5a10861#32, 0x8b4210c3#32, 0x16842187#32, 0x2d08430e#32,
  0x5a10861c#32, 0xb4210c38#32, 0x68421871#32, 0xd08430e2#32
]
theorem pyjamaskM0Rows_len : pyjamaskM0Rows.length = 32 := by decide +kernel
theorem pyjamaskM0Rows_matches : checkRowsBasis 32 pyjamaskM0Rows pyjamaskM0_32 = true := by decide +kernel
theorem evalXorCircuit_eq_pyjamaskM0_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 pyjamaskM0Rows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = pyjamaskM0_32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 pyjamaskM0Rows pyjamaskM0Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis pyjamaskM0_32 pyjamaskM0_32_isLinear pyjamaskM0Rows pyjamaskM0Rows_matches x

def pyjamaskM1Rows : List (BitVec 32) := [
  0x840e82c6#32, 0x081d058d#32, 0x103a0b1a#32, 0x20741634#32,
  0x40e82c68#32, 0x81d058d0#32, 0x03a0b1a1#32, 0x07416342#32,
  0x0e82c684#32, 0x1d058d08#32, 0x3a0b1a10#32, 0x74163420#32,
  0xe82c6840#32, 0xd058d081#32, 0xa0b1a103#32, 0x41634207#32,
  0x82c6840e#32, 0x058d081d#32, 0x0b1a103a#32, 0x16342074#32,
  0x2c6840e8#32, 0x58d081d0#32, 0xb1a103a0#32, 0x63420741#32,
  0xc6840e82#32, 0x8d081d05#32, 0x1a103a0b#32, 0x34207416#32,
  0x6840e82c#32, 0xd081d058#32, 0xa103a0b1#32, 0x42074163#32
]
theorem pyjamaskM1Rows_len : pyjamaskM1Rows.length = 32 := by decide +kernel
theorem pyjamaskM1Rows_matches : checkRowsBasis 32 pyjamaskM1Rows pyjamaskM1_32 = true := by decide +kernel
theorem evalXorCircuit_eq_pyjamaskM1_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 pyjamaskM1Rows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = pyjamaskM1_32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 pyjamaskM1Rows pyjamaskM1Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis pyjamaskM1_32 pyjamaskM1_32_isLinear pyjamaskM1Rows pyjamaskM1Rows_matches x

def pyjamaskM2Rows : List (BitVec 32) := [
  0x014f3496#32, 0x029e692c#32, 0x053cd258#32, 0x0a79a4b0#32,
  0x14f34960#32, 0x29e692c0#32, 0x53cd2580#32, 0xa79a4b00#32,
  0x4f349601#32, 0x9e692c02#32, 0x3cd25805#32, 0x79a4b00a#32,
  0xf3496014#32, 0xe692c029#32, 0xcd258053#32, 0x9a4b00a7#32,
  0x3496014f#32, 0x692c029e#32, 0xd258053c#32, 0xa4b00a79#32,
  0x496014f3#32, 0x92c029e6#32, 0x258053cd#32, 0x4b00a79a#32,
  0x96014f34#32, 0x2c029e69#32, 0x58053cd2#32, 0xb00a79a4#32,
  0x6014f349#32, 0xc029e692#32, 0x8053cd25#32, 0x00a79a4b#32
]
theorem pyjamaskM2Rows_len : pyjamaskM2Rows.length = 32 := by decide +kernel
theorem pyjamaskM2Rows_matches : checkRowsBasis 32 pyjamaskM2Rows pyjamaskM2_32 = true := by decide +kernel
theorem evalXorCircuit_eq_pyjamaskM2_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 pyjamaskM2Rows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = pyjamaskM2_32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 pyjamaskM2Rows pyjamaskM2Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis pyjamaskM2_32 pyjamaskM2_32_isLinear pyjamaskM2Rows pyjamaskM2Rows_matches x

def pyjamaskM3Rows : List (BitVec 32) := [
  0xc812a512#32, 0x90254a25#32, 0x204a944b#32, 0x40952896#32,
  0x812a512c#32, 0x0254a259#32, 0x04a944b2#32, 0x09528964#32,
  0x12a512c8#32, 0x254a2590#32, 0x4a944b20#32, 0x95289640#32,
  0x2a512c81#32, 0x54a25902#32, 0xa944b204#32, 0x52896409#32,
  0xa512c812#32, 0x4a259025#32, 0x944b204a#32, 0x28964095#32,
  0x512c812a#32, 0xa2590254#32, 0x44b204a9#32, 0x89640952#32,
  0x12c812a5#32, 0x2590254a#32, 0x4b204a94#32, 0x96409528#32,
  0x2c812a51#32, 0x590254a2#32, 0xb204a944#32, 0x64095289#32
]
theorem pyjamaskM3Rows_len : pyjamaskM3Rows.length = 32 := by decide +kernel
theorem pyjamaskM3Rows_matches : checkRowsBasis 32 pyjamaskM3Rows pyjamaskM3_32 = true := by decide +kernel
theorem evalXorCircuit_eq_pyjamaskM3_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 pyjamaskM3Rows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = pyjamaskM3_32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 pyjamaskM3Rows pyjamaskM3Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis pyjamaskM3_32 pyjamaskM3_32_isLinear pyjamaskM3Rows pyjamaskM3Rows_matches x

def pyjamaskMKRows : List (BitVec 32) := [
  0x539d811d#32, 0xa73b023a#32, 0x4e760475#32, 0x9cec08ea#32,
  0x39d811d5#32, 0x73b023aa#32, 0xe7604754#32, 0xcec08ea9#32,
  0x9d811d53#32, 0x3b023aa7#32, 0x7604754e#32, 0xec08ea9c#32,
  0xd811d539#32, 0xb023aa73#32, 0x604754e7#32, 0xc08ea9ce#32,
  0x811d539d#32, 0x023aa73b#32, 0x04754e76#32, 0x08ea9cec#32,
  0x11d539d8#32, 0x23aa73b0#32, 0x4754e760#32, 0x8ea9cec0#32,
  0x1d539d81#32, 0x3aa73b02#32, 0x754e7604#32, 0xea9cec08#32,
  0xd539d811#32, 0xaa73b023#32, 0x54e76047#32, 0xa9cec08e#32
]
theorem pyjamaskMKRows_len : pyjamaskMKRows.length = 32 := by decide +kernel
theorem pyjamaskMKRows_matches : checkRowsBasis 32 pyjamaskMKRows pyjamaskMK_32 = true := by decide +kernel
theorem evalXorCircuit_eq_pyjamaskMK_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 pyjamaskMKRows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = pyjamaskMK_32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 pyjamaskMKRows pyjamaskMKRows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis pyjamaskMK_32 pyjamaskMK_32_isLinear pyjamaskMKRows pyjamaskMKRows_matches x

def pyjamaskInvM0Rows : List (BitVec 32) := [
  0x8485ec04#32, 0x090bd809#32, 0x1217b012#32, 0x242f6024#32,
  0x485ec048#32, 0x90bd8090#32, 0x217b0121#32, 0x42f60242#32,
  0x85ec0484#32, 0x0bd80909#32, 0x17b01212#32, 0x2f602424#32,
  0x5ec04848#32, 0xbd809090#32, 0x7b012121#32, 0xf6024242#32,
  0xec048485#32, 0xd809090b#32, 0xb0121217#32, 0x6024242f#32,
  0xc048485e#32, 0x809090bd#32, 0x0121217b#32, 0x024242f6#32,
  0x048485ec#32, 0x09090bd8#32, 0x121217b0#32, 0x24242f60#32,
  0x48485ec0#32, 0x9090bd80#32, 0x21217b01#32, 0x4242f602#32
]
theorem pyjamaskInvM0Rows_len : pyjamaskInvM0Rows.length = 32 := by decide +kernel
theorem pyjamaskInvM0Rows_matches : checkRowsBasis 32 pyjamaskInvM0Rows pyjamaskInvM0_32 = true := by decide +kernel
theorem evalXorCircuit_eq_pyjamaskInvM0_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 pyjamaskInvM0Rows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = pyjamaskInvM0_32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 pyjamaskInvM0Rows pyjamaskInvM0Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis pyjamaskInvM0_32 pyjamaskInvM0_32_isLinear pyjamaskInvM0Rows pyjamaskInvM0Rows_matches x

def pyjamaskInvM1Rows : List (BitVec 32) := [
  0x054ff108#32, 0x0a9fe210#32, 0x153fc420#32, 0x2a7f8840#32,
  0x54ff1080#32, 0xa9fe2100#32, 0x53fc4201#32, 0xa7f88402#32,
  0x4ff10805#32, 0x9fe2100a#32, 0x3fc42015#32, 0x7f88402a#32,
  0xff108054#32, 0xfe2100a9#32, 0xfc420153#32, 0xf88402a7#32,
  0xf108054f#32, 0xe2100a9f#32, 0xc420153f#32, 0x88402a7f#32,
  0x108054ff#32, 0x2100a9fe#32, 0x420153fc#32, 0x8402a7f8#32,
  0x08054ff1#32, 0x100a9fe2#32, 0x20153fc4#32, 0x402a7f88#32,
  0x8054ff10#32, 0x00a9fe21#32, 0x0153fc42#32, 0x02a7f884#32
]
theorem pyjamaskInvM1Rows_len : pyjamaskInvM1Rows.length = 32 := by decide +kernel
theorem pyjamaskInvM1Rows_matches : checkRowsBasis 32 pyjamaskInvM1Rows pyjamaskInvM1_32 = true := by decide +kernel
theorem evalXorCircuit_eq_pyjamaskInvM1_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 pyjamaskInvM1Rows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = pyjamaskInvM1_32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 pyjamaskInvM1Rows pyjamaskInvM1Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis pyjamaskInvM1_32 pyjamaskInvM1_32_isLinear pyjamaskInvM1Rows pyjamaskInvM1Rows_matches x

def pyjamaskInvM2Rows : List (BitVec 32) := [
  0x031b2a09#32, 0x06365412#32, 0x0c6ca824#32, 0x18d95048#32,
  0x31b2a090#32, 0x63654120#32, 0xc6ca8240#32, 0x8d950481#32,
  0x1b2a0903#32, 0x36541206#32, 0x6ca8240c#32, 0xd9504818#32,
  0xb2a09031#32, 0x65412063#32, 0xca8240c6#32, 0x9504818d#32,
  0x2a09031b#32, 0x54120636#32, 0xa8240c6c#32, 0x504818d9#32,
  0xa09031b2#32, 0x41206365#32, 0x8240c6ca#32, 0x04818d95#32,
  0x09031b2a#32, 0x12063654#32, 0x240c6ca8#32, 0x4818d950#32,
  0x9031b2a0#32, 0x20636541#32, 0x40c6ca82#32, 0x818d9504#32
]
theorem pyjamaskInvM2Rows_len : pyjamaskInvM2Rows.length = 32 := by decide +kernel
theorem pyjamaskInvM2Rows_matches : checkRowsBasis 32 pyjamaskInvM2Rows pyjamaskInvM2_32 = true := by decide +kernel
theorem evalXorCircuit_eq_pyjamaskInvM2_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 pyjamaskInvM2Rows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = pyjamaskInvM2_32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 pyjamaskInvM2Rows pyjamaskInvM2Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis pyjamaskInvM2_32 pyjamaskInvM2_32_isLinear pyjamaskInvM2Rows pyjamaskInvM2Rows_matches x

def pyjamaskInvM3Rows : List (BitVec 32) := [
  0xe88d2acc#32, 0xd11a5599#32, 0xa234ab33#32, 0x44695667#32,
  0x88d2acce#32, 0x11a5599d#32, 0x234ab33a#32, 0x46956674#32,
  0x8d2acce8#32, 0x1a5599d1#32, 0x34ab33a2#32, 0x69566744#32,
  0xd2acce88#32, 0xa5599d11#32, 0x4ab33a23#32, 0x95667446#32,
  0x2acce88d#32, 0x5599d11a#32, 0xab33a234#32, 0x56674469#32,
  0xacce88d2#32, 0x599d11a5#32, 0xb33a234a#32, 0x66744695#32,
  0xcce88d2a#32, 0x99d11a55#32, 0x33a234ab#32, 0x67446956#32,
  0xce88d2ac#32, 0x9d11a559#32, 0x3a234ab3#32, 0x74469566#32
]
theorem pyjamaskInvM3Rows_len : pyjamaskInvM3Rows.length = 32 := by decide +kernel
theorem pyjamaskInvM3Rows_matches : checkRowsBasis 32 pyjamaskInvM3Rows pyjamaskInvM3_32 = true := by decide +kernel
theorem evalXorCircuit_eq_pyjamaskInvM3_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 pyjamaskInvM3Rows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = pyjamaskInvM3_32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 pyjamaskInvM3Rows pyjamaskInvM3Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis pyjamaskInvM3_32 pyjamaskInvM3_32_isLinear pyjamaskInvM3Rows pyjamaskInvM3Rows_matches x

def photon256MdsRows : List (BitVec 32) := [
  0xc528b848#32, 0x5e69d9c9#32, 0xbdc2a292#32, 0x6a945424#32,
  0x85dd7236#32, 0x9e77864a#32, 0x2dff1c85#32, 0x4aee391b#32,
  0x37437744#32, 0x48c488cc#32, 0x81981199#32, 0x13213322#32,
  0xef7615c1#32, 0x318a2e52#32, 0x73154db4#32, 0xf73b8a68#32,
  0x7e5e736f#32, 0x83e384a1#32, 0x17d71853#32, 0x3faf31b7#32,
  0xc364f5e3#32, 0x54ac1e34#32, 0xb8593d78#32, 0x61b27af1#32,
  0xe119a886#32, 0x322bf99a#32, 0x7446e225#32, 0xf88cd44b#32,
  0x98a5a71f#32, 0xb9fef821#32, 0x62ede143#32, 0xc4dad387#32
]
theorem photon256MdsRows_len : photon256MdsRows.length = 32 := by decide +kernel
theorem photon256MdsRows_matches : checkRowsBasis 32 photon256MdsRows photon256Mds32 = true := by decide +kernel
theorem evalXorCircuit_eq_photon256Mds_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 32 photon256MdsRows gates outputs = true) :
    ∀ x : BitVec 32, evalXorCircuit 32 gates outputs x = photon256Mds32 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 32 photon256MdsRows photon256MdsRows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis photon256Mds32 photon256Mds32_isLinear photon256MdsRows photon256MdsRows_matches x

def clyde128LboxRows : List (BitVec 64) := [
  0x36000f60ec045008#64, 0x6c001ec0d808a011#64, 0xd8003d80b0114023#64, 0xb0007b0160228047#64,
  0x6000f603c045008e#64, 0xc001ec06808a011d#64, 0x8003d80d0114023b#64, 0x0007b01b02280476#64,
  0x000f6036045008ec#64, 0x001ec06c08a011d8#64, 0x003d80d8114023b0#64, 0x007b01b022804760#64,
  0x00f6036045008ec0#64, 0x01ec06c08a011d80#64, 0x03d80d8014023b01#64, 0x07b01b0028047602#64,
  0x0f6036005008ec04#64, 0x1ec06c00a011d808#64, 0x3d80d8004023b011#64, 0x7b01b00080476022#64,
  0xf6036000008ec045#64, 0xec06c001011d808a#64, 0xd80d8003023b0114#64, 0xb01b000704760228#64,
  0x6036000f08ec0450#64, 0xc06c001e11d808a0#64, 0x80d8003d23b01140#64, 0x01b0007b47602280#64,
  0x036000f68ec04500#64, 0x06c001ec1d808a01#64, 0x0d8003d83b011402#64, 0x1b0007b076022804#64,
  0xec0450081b0007b0#64, 0xd808a01136000f60#64, 0xb01140236c001ec0#64, 0x60228047d8003d80#64,
  0xc045008eb0007b01#64, 0x808a011d6000f603#64, 0x0114023bc001ec06#64, 0x022804768003d80d#64,
  0x045008ec0007b01b#64, 0x08a011d8000f6036#64, 0x114023b0001ec06c#64, 0x22804760003d80d8#64,
  0x45008ec0007b01b0#64, 0x8a011d8000f60360#64, 0x14023b0101ec06c0#64, 0x2804760203d80d80#64,
  0x5008ec0407b01b00#64, 0xa011d8080f603600#64, 0x4023b0111ec06c00#64, 0x804760223d80d800#64,
  0x008ec0457b01b000#64, 0x011d808af6036000#64, 0x023b0114ec06c001#64, 0x04760228d80d8003#64,
  0x08ec0450b01b0007#64, 0x11d808a06036000f#64, 0x23b01140c06c001e#64, 0x4760228080d8003d#64,
  0x8ec0450001b0007b#64, 0x1d808a01036000f6#64, 0x3b01140206c001ec#64, 0x760228040d8003d8#64
]
theorem clyde128LboxRows_len : clyde128LboxRows.length = 64 := by decide +kernel
theorem clyde128LboxRows_matches : checkRowsBasis 64 clyde128LboxRows clyde128Lbox64 = true := by decide +kernel
theorem evalXorCircuit_eq_clyde128Lbox_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 64 clyde128LboxRows gates outputs = true) :
    ∀ x : BitVec 64, evalXorCircuit 64 gates outputs x = clyde128Lbox64 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 64 clyde128LboxRows clyde128LboxRows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis clyde128Lbox64 clyde128Lbox64_isLinear clyde128LboxRows clyde128LboxRows_matches x

def asconSigma0Rows : List (BitVec 64) := [
  0x0000000010080001#64, 0x0000000020100002#64, 0x0000000040200004#64, 0x0000000080400008#64,
  0x0000000100800010#64, 0x0000000201000020#64, 0x0000000402000040#64, 0x0000000804000080#64,
  0x0000001008000100#64, 0x0000002010000200#64, 0x0000004020000400#64, 0x0000008040000800#64,
  0x0000010080001000#64, 0x0000020100002000#64, 0x0000040200004000#64, 0x0000080400008000#64,
  0x0000100800010000#64, 0x0000201000020000#64, 0x0000402000040000#64, 0x0000804000080000#64,
  0x0001008000100000#64, 0x0002010000200000#64, 0x0004020000400000#64, 0x0008040000800000#64,
  0x0010080001000000#64, 0x0020100002000000#64, 0x0040200004000000#64, 0x0080400008000000#64,
  0x0100800010000000#64, 0x0201000020000000#64, 0x0402000040000000#64, 0x0804000080000000#64,
  0x1008000100000000#64, 0x2010000200000000#64, 0x4020000400000000#64, 0x8040000800000000#64,
  0x0080001000000001#64, 0x0100002000000002#64, 0x0200004000000004#64, 0x0400008000000008#64,
  0x0800010000000010#64, 0x1000020000000020#64, 0x2000040000000040#64, 0x4000080000000080#64,
  0x8000100000000100#64, 0x0000200000000201#64, 0x0000400000000402#64, 0x0000800000000804#64,
  0x0001000000001008#64, 0x0002000000002010#64, 0x0004000000004020#64, 0x0008000000008040#64,
  0x0010000000010080#64, 0x0020000000020100#64, 0x0040000000040200#64, 0x0080000000080400#64,
  0x0100000000100800#64, 0x0200000000201000#64, 0x0400000000402000#64, 0x0800000000804000#64,
  0x1000000001008000#64, 0x2000000002010000#64, 0x4000000004020000#64, 0x8000000008040000#64
]
theorem asconSigma0Rows_len : asconSigma0Rows.length = 64 := by decide +kernel
theorem asconSigma0Rows_matches : checkRowsBasis 64 asconSigma0Rows asconSigma0_64 = true := by decide +kernel
theorem evalXorCircuit_eq_asconSigma0_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 64 asconSigma0Rows gates outputs = true) :
    ∀ x : BitVec 64, evalXorCircuit 64 gates outputs x = asconSigma0_64 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 64 asconSigma0Rows asconSigma0Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis asconSigma0_64 asconSigma0_64_isLinear asconSigma0Rows asconSigma0Rows_matches x

def asconSigma2Rows : List (BitVec 64) := [
  0x0000000000000043#64, 0x0000000000000086#64, 0x000000000000010c#64, 0x0000000000000218#64,
  0x0000000000000430#64, 0x0000000000000860#64, 0x00000000000010c0#64, 0x0000000000002180#64,
  0x0000000000004300#64, 0x0000000000008600#64, 0x0000000000010c00#64, 0x0000000000021800#64,
  0x0000000000043000#64, 0x0000000000086000#64, 0x000000000010c000#64, 0x0000000000218000#64,
  0x0000000000430000#64, 0x0000000000860000#64, 0x00000000010c0000#64, 0x0000000002180000#64,
  0x0000000004300000#64, 0x0000000008600000#64, 0x0000000010c00000#64, 0x0000000021800000#64,
  0x0000000043000000#64, 0x0000000086000000#64, 0x000000010c000000#64, 0x0000000218000000#64,
  0x0000000430000000#64, 0x0000000860000000#64, 0x00000010c0000000#64, 0x0000002180000000#64,
  0x0000004300000000#64, 0x0000008600000000#64, 0x0000010c00000000#64, 0x0000021800000000#64,
  0x0000043000000000#64, 0x0000086000000000#64, 0x000010c000000000#64, 0x0000218000000000#64,
  0x0000430000000000#64, 0x0000860000000000#64, 0x00010c0000000000#64, 0x0002180000000000#64,
  0x0004300000000000#64, 0x0008600000000000#64, 0x0010c00000000000#64, 0x0021800000000000#64,
  0x0043000000000000#64, 0x0086000000000000#64, 0x010c000000000000#64, 0x0218000000000000#64,
  0x0430000000000000#64, 0x0860000000000000#64, 0x10c0000000000000#64, 0x2180000000000000#64,
  0x4300000000000000#64, 0x8600000000000000#64, 0x0c00000000000001#64, 0x1800000000000002#64,
  0x3000000000000004#64, 0x6000000000000008#64, 0xc000000000000010#64, 0x8000000000000021#64
]
theorem asconSigma2Rows_len : asconSigma2Rows.length = 64 := by decide +kernel
theorem asconSigma2Rows_matches : checkRowsBasis 64 asconSigma2Rows asconSigma2_64 = true := by decide +kernel
theorem evalXorCircuit_eq_asconSigma2_of_check (gates : List (Nat × Nat)) (outputs : List Nat)
    (hcheck : checkLinearCircuit 64 asconSigma2Rows gates outputs = true) :
    ∀ x : BitVec 64, evalXorCircuit 64 gates outputs x = asconSigma2_64 x := by
  intro x
  rw [evalXorCircuit_eq_matMul_of_check 64 asconSigma2Rows asconSigma2Rows_len gates outputs hcheck x]
  exact matMul_eq_of_checkRowsBasis asconSigma2_64 asconSigma2_64_isLinear asconSigma2Rows asconSigma2Rows_matches x

end LwcLinearXor
