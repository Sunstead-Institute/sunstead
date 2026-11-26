/-!
# ZK STARK/SNARK Prime Field Addition Chains (Plonky3, 10 Tracks)

Pure Lean 4.36.0 (zero Mathlib) specification of shortest addition chains for
production ZK prime field Fermat inversions (`p - 2`) and Rescue/Poseidon inverse S-box
exponents (`1/α mod (p - 1)`), pinned verbatim to `Plonky3/Plonky3@0d803737b6` (Apache-2.0):

- Goldilocks (`goldilocks/src/goldilocks.rs`):
  `pub(crate) const P: u64 = 0xFFFF_FFFF_0000_0001;`
  `/// Compute the exponential `x -> x^10540996611094048183` using a custom addition chain.`
- BabyBear (`baby-bear/src/baby_bear.rs`):
  `    const PRIME: u32 = 0x78000001;`
  `/// Compute the exponential `x -> x^1725656503` using a custom addition chain.`
- KoalaBear (`koala-bear/src/koala_bear.rs`):
  `    const PRIME: u32 = 0x7f000001;`
  `/// Compute the exponential `x -> x^1420470955` using a custom addition chain.`
- Mersenne31 (`mersenne-31/src/mersenne_31.rs`):
  `const P: u32 = (1 << 31) - 1;`
  `/// Compute the exponential `x -> x^1717986917` using a custom addition chain.`
- BN254 (`bn254/src/bn254.rs`):
```rust
pub(crate) const BN254_PRIME: [u64; 4] = [
    0x43e1f593f0000001,
    0x2833e84879b97091,
    0xb85045b68181585d,
    0x30644e72e131a029,
];
```
-/

namespace ZkAddChain

/-! ## Addition Chain Semantics and Algebraic Power Soundness -/

/-- Check that every step `(i, j)` references strictly earlier wires `i < numWires ∧ j < numWires`. -/
def wellFormedStepsAux (numWires : Nat) : List (Nat × Nat) → Bool
  | [] => true
  | (i, j) :: rest => (i < numWires && j < numWires) && wellFormedStepsAux (numWires + 1) rest

/-- A chain `steps` is well-formed iff step `k` (`0`-indexed) only references wires `0 .. k`. -/
def wellFormedChain (steps : List (Nat × Nat)) : Bool :=
  wellFormedStepsAux 1 steps

/-- Lookup wire `w` in a reversed wire list of length `len` (`O(1)` for recent wires). -/
def getRevWire (len : Nat) (revWires : List Nat) (w : Nat) : Nat :=
  if w < len then revWires.getD (len - 1 - w) 0 else 0

/-- Execute addition chain steps on `Nat` values starting from wire `0 = 1`. -/
def evalChainAux (len : Nat) (revWires : List Nat) : List (Nat × Nat) → Nat
  | [] => revWires.headD 0
  | (i, j) :: rest =>
    let v := getRevWire len revWires i + getRevWire len revWires j
    evalChainAux (len + 1) (v :: revWires) rest

/-- Final exponent computed by an addition chain starting from wire `0 = 1`. -/
def evalChain (steps : List (Nat × Nat)) : Nat :=
  evalChainAux 1 [1] steps

/-- Count of non-doubling (general multiplication) steps `i ≠ j`. -/
def mulStepCount : List (Nat × Nat) → Nat
  | [] => 0
  | (i, j) :: rest => (if i == j then 0 else 1) + mulStepCount rest

/-- Existence of a well-formed addition chain of exact length `len` computing `target`. -/
def ValidAddChain (target : Nat) (len : Nat) : Prop :=
  ∃ steps,
    wellFormedChain steps = true ∧
    steps.length = len ∧
    evalChain steps = target

/-! ### Algebraic Power Soundness in Any Associative Magma / Field -/

/-- `powSucc mul x k` computes `x^(k + 1)` using `mul` (no unit element or commutativity needed). -/
def powSucc {α : Type} (mul : α → α → α) (x : α) : Nat → α
  | 0 => x
  | k + 1 => mul (powSucc mul x k) x

private theorem powSucc_add {α : Type} (mul : α → α → α)
    (hmul_assoc : ∀ a b c, mul (mul a b) c = mul a (mul b c)) (x : α) (a : Nat) :
    ∀ b, powSucc mul x (a + b + 1) = mul (powSucc mul x a) (powSucc mul x b)
  | 0 => rfl
  | b + 1 => by
    have hidx : a + (b + 1) + 1 = (a + b + 1) + 1 := by omega
    rw [hidx]
    show mul (powSucc mul x (a + b + 1)) x = mul (powSucc mul x a) (mul (powSucc mul x b) x)
    rw [powSucc_add mul hmul_assoc x a b, hmul_assoc]

/-- Lookup wire `w` in a reversed polymorphic wire list of length `len`. -/
def getRevPoly {α : Type} (d : α) (len : Nat) (revWires : List α) (w : Nat) : α :=
  if w < len then revWires.getD (len - 1 - w) d else d

/-- Execute an addition chain in any associative magma `(α, mul)` starting from `[x]`. -/
def evalPowAux {α : Type} (mul : α → α → α) (x : α) (len : Nat) (revWires : List α) :
    List (Nat × Nat) → α
  | [] => revWires.headD x
  | (i, j) :: rest =>
    let v := mul (getRevPoly x len revWires i) (getRevPoly x len revWires j)
    evalPowAux mul x (len + 1) (v :: revWires) rest

/-- Compute `x^e` by replaying `steps` using `steps.length` multiplications/squarings. -/
def evalPow {α : Type} (mul : α → α → α) (x : α) (steps : List (Nat × Nat)) : α :=
  evalPowAux mul x 1 [x] steps

private theorem getRevWire_cons (len : Nat) (ws : List Nat) (v w : Nat) :
    getRevWire (len + 1) (v :: ws) w =
      if w < len then getRevWire len ws w else if w = len then v else 0 := by
  unfold getRevWire
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

private theorem getRevPoly_cons {α : Type} (d : α) (len : Nat) (ws : List α) (v : α) (w : Nat) :
    getRevPoly d (len + 1) (v :: ws) w =
      if w < len then getRevPoly d len ws w else if w = len then v else d := by
  unfold getRevPoly
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

private theorem headD_eq_getRevWire {α : Type} (d : α) (len : Nat) (ws : List α)
    (hlen : len = ws.length) (hpos : 0 < len) :
    ws.headD d = getRevPoly d len ws (len - 1) := by
  cases ws with
  | nil => simp at hlen; omega
  | cons a rest =>
    have hlt : len - 1 < len := by omega
    have hidx : len - 1 - (len - 1) = 0 := by omega
    simp [getRevPoly, hlt, hidx, List.headD, List.getD]

private theorem headD_nat_eq_getRevWire (len : Nat) (ws : List Nat)
    (hlen : len = ws.length) (hpos : 0 < len) :
    ws.headD 0 = getRevWire len ws (len - 1) := by
  cases ws with
  | nil => simp at hlen; omega
  | cons a rest =>
    have hlt : len - 1 < len := by omega
    have hidx : len - 1 - (len - 1) = 0 := by omega
    simp [getRevWire, hlt, hidx, List.headD, List.getD]

private theorem evalPowAux_sound {α : Type} (mul : α → α → α)
    (hmul_assoc : ∀ a b c, mul (mul a b) c = mul a (mul b c)) (x : α) :
    ∀ (steps : List (Nat × Nat)) (len : Nat) (revN : List Nat) (revA : List α),
      0 < len →
      len = revN.length →
      len = revA.length →
      wellFormedStepsAux len steps = true →
      (∀ w, w < len → 0 < getRevWire len revN w ∧
        getRevPoly x len revA w = powSucc mul x (getRevWire len revN w - 1)) →
      0 < evalChainAux len revN steps ∧
        evalPowAux mul x len revA steps = powSucc mul x (evalChainAux len revN steps - 1)
  | [], len, revN, revA, hpos, hln, hla, _, hinv => by
    simp only [evalChainAux, evalPowAux]
    rw [headD_nat_eq_getRevWire len revN hln hpos, headD_eq_getRevWire x len revA hla hpos]
    exact hinv (len - 1) (by omega)
  | (i, j) :: rest, len, revN, revA, hpos, hln, hla, hwf, hinv => by
    simp only [wellFormedStepsAux, Bool.and_eq_true, decide_eq_true_eq] at hwf
    rcases hwf with ⟨⟨hi, hj⟩, hwf_rest⟩
    simp only [evalChainAux, evalPowAux]
    apply evalPowAux_sound mul hmul_assoc x rest (len + 1) _ _ (by omega)
      (by simp [hln]) (by simp [hla]) hwf_rest
    intro w hw
    rw [getRevWire_cons, getRevPoly_cons]
    by_cases hlt : w < len
    · simp only [hlt, ite_true]
      exact hinv w hlt
    · have heq : w = len := by omega
      subst heq
      simp only [Nat.lt_irrefl, ite_false, ite_true]
      have ⟨hpi, hvi⟩ := hinv i hi
      have ⟨hpj, hvj⟩ := hinv j hj
      constructor
      · omega
      · rw [hvi, hvj, ← powSucc_add mul hmul_assoc x]
        congr 1
        omega

/-- **Algebraic Exponentiation Soundness Theorem**:
For any associative multiplication `mul` (in particular, any finite field `F_p`, extension
field `F_{p^k}`, or cryptographic group), replaying a well-formed addition chain reaching
`target` computes `x^target` (`powSucc mul x (target - 1)`) in `steps.length` operations. -/
theorem evalPow_eq_powSucc {α : Type} (mul : α → α → α)
    (hmul_assoc : ∀ a b c, mul (mul a b) c = mul a (mul b c)) (x : α)
    (steps : List (Nat × Nat)) (target : Nat)
    (hwf : wellFormedChain steps = true) (heval : evalChain steps = target) :
    evalPow mul x steps = powSucc mul x (target - 1) := by
  have hinv0 : ∀ w, w < 1 → 0 < getRevWire 1 [1] w ∧
      getRevPoly x 1 [x] w = powSucc mul x (getRevWire 1 [1] w - 1) := by
    intro w hw
    have hw0 : w = 0 := by omega
    subst hw0
    simp [getRevWire, getRevPoly, powSucc]
  have h := evalPowAux_sound mul hmul_assoc x steps 1 [1] [x] (by omega) rfl rfl hwf hinv0
  rw [← heval]
  exact h.2

/-! ## Pinned Cryptographic Target Exponents -/

/-- Plonky3 Goldilocks p-2 exponent (Plonky3/known frontier: ~72 steps). -/
def target_goldilocks_inv : Nat := 2 ^ 64 - 2 ^ 32 - 1

/-- Plonky3 Goldilocks 1/7 (x^10540996611094048183) exponent (Plonky3/known frontier: ~71 steps). -/
def target_goldilocks_inv_d7 : Nat := 10540996611094048183

theorem goldilocks_d7_inv : (7 * target_goldilocks_inv_d7) % (2 ^ 64 - 2 ^ 32) = 1 := by decide +kernel

/-- Plonky3 BabyBear p-2 exponent (Plonky3/known frontier: ~38 steps). -/
def target_babybear_inv : Nat := 0x78000001 - 2

/-- Plonky3 BabyBear 1/7 (x^1725656503) exponent (Plonky3/known frontier: ~37 steps). -/
def target_babybear_inv_d7 : Nat := 1725656503

theorem babybear_d7_inv : (7 * target_babybear_inv_d7) % (0x78000001 - 1) = 1 := by decide +kernel

/-- Plonky3 KoalaBear p-2 exponent (Plonky3/known frontier: ~38 steps). -/
def target_koalabear_inv : Nat := 0x7f000001 - 2

/-- Plonky3 KoalaBear 1/3 (x^1420470955) exponent (Plonky3/known frontier: ~36 steps). -/
def target_koalabear_inv_d3 : Nat := 1420470955

theorem koalabear_d3_inv : (3 * target_koalabear_inv_d3) % (0x7f000001 - 1) = 1 := by decide +kernel

/-- Plonky3 Mersenne31 p-2 exponent (Plonky3/known frontier: ~37 steps). -/
def target_mersenne31_inv : Nat := 2 ^ 31 - 3

/-- Plonky3 Mersenne31 1/5 (x^1717986917) exponent (Plonky3/known frontier: ~37 steps). -/
def target_mersenne31_inv_d5 : Nat := 1717986917

theorem mersenne31_d5_inv : (5 * target_mersenne31_inv_d5) % (2 ^ 31 - 2) = 1 := by decide +kernel

/-- Plonky3 BN254 Field p-2 exponent (Plonky3/known frontier: ~295 steps). -/
def target_bn254_inv : Nat := 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001 - 2

/-- Plonky3 BN254 Rescue/Poseidon 1/5 exponent (Plonky3/known frontier: ~295 steps). -/
def target_bn254_inv_d5 : Nat := 0x26b6a528b427b35493736af8679aad17535cb9d394945a0dcfe7f7a98ccccccd

theorem bn254_d5_inv : (5 * target_bn254_inv_d5) % (0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001 - 1) = 1 := by decide +kernel


end ZkAddChain
