/-!
# AES S-box Specification and Straight-Line Boolean Circuit Semantics

`SBOX` is copied verbatim from AWS Automated Reasoning's `leanprover/LNSym`
(`Specs/AESCommon.lean`, commit `49f8a1d9e46f8dcfc345f4bc15d35b0ba845ff5c`,
Apache-2.0). `aesSbox` defines the NIST FIPS 197 S-box algebraically over
GF(2^8) = GF(2)[x]/(x^8 + x^4 + x^3 + x + 1) and `aesSbox_eq_lnsymSbox`
kernel-checks byte-for-byte agreement across all 256 inputs.
-/

namespace AesSbox

/-- Verbatim NIST FIPS 197 AES S-box table from `leanprover/LNSym` (`Specs/AESCommon.lean`). -/
def SBOX :=
  --   F E D C B A 9 8 7 6 5 4 3 2 1 0
  [ 0x16bb54b00f2d99416842e6bf0d89a18c#128, -- F
    0xdf2855cee9871e9b948ed9691198f8e1#128, -- E
    0x9e1dc186b95735610ef6034866b53e70#128, -- D
    0x8a8bbd4b1f74dde8c6b4a61c2e2578ba#128, -- C
    0x08ae7a65eaf4566ca94ed58d6d37c8e7#128, -- B
    0x79e4959162acd3c25c2406490a3a32e0#128, -- A
    0xdb0b5ede14b8ee4688902a22dc4f8160#128, -- 9
    0x73195d643d7ea7c41744975fec130ccd#128, -- 8
    0xd2f3ff1021dab6bcf5389d928f40a351#128, -- 7
    0xa89f3c507f02f94585334d43fbaaefd0#128, -- 6
    0xcf584c4a39becb6a5bb1fc20ed00d153#128, -- 5
    0x842fe329b3d63b52a05a6e1b1a2c8309#128, -- 4
    0x75b227ebe28012079a059618c323c704#128, -- 3
    0x1531d871f1e5a534ccf73f362693fdb7#128, -- 2
    0xc072a49cafa2d4adf04759fa7dc982ca#128, -- 1
    0x76abd7fe2b670130c56f6bf27b777c63#128  -- 0
  ]

/-- Lookup a byte directly from LNSym's verbatim `SBOX` constant. -/
def lnsymSbox (x : BitVec 8) : BitVec 8 :=
  let hi := x.toNat / 16
  let lo := x.toNat % 16
  let row := SBOX.getD (15 - hi) 0#128
  BitVec.extractLsb' (lo * 8) 8 row

/-- Pack 8 LSB-first bits into a `BitVec 8`. -/
def packByte (b0 b1 b2 b3 b4 b5 b6 b7 : Bool) : BitVec 8 :=
  BitVec.ofNat 8
    ((if b0 then 1 else 0) + (if b1 then 2 else 0) +
     (if b2 then 4 else 0) + (if b3 then 8 else 0) +
     (if b4 then 16 else 0) + (if b5 then 32 else 0) +
     (if b6 then 64 else 0) + (if b7 then 128 else 0))

/-- Multiplication by `x` in GF(2^8) = GF(2)[x] / (x^8 + x^4 + x^3 + x + 1). -/
def gfXtime (a : BitVec 8) : BitVec 8 :=
  if a.getLsbD 7 then (a <<< 1) ^^^ 0x1b#8 else a <<< 1

/-- Shift-and-add multiplication in GF(2^8) modulo `0x11b`. -/
def gfMulAux : Nat → BitVec 8 → BitVec 8 → BitVec 8 → BitVec 8
  | 0, _, _, acc => acc
  | n + 1, a, b, acc =>
    let acc' := if b.getLsbD 0 then acc ^^^ a else acc
    gfMulAux n (gfXtime a) (b >>> 1) acc'

/-- Multiplication in GF(2^8) modulo `x^8 + x^4 + x^3 + x + 1` (`0x11b`). -/
def gfMul (a b : BitVec 8) : BitVec 8 :=
  gfMulAux 8 a b 0#8

/-- Multiplicative inverse in GF(2^8) (`x ↦ x^254`, sending `0 ↦ 0`). -/
def gfInv (x : BitVec 8) : BitVec 8 :=
  let x2 := gfMul x x
  let x3 := gfMul x2 x
  let x6 := gfMul x3 x3
  let x12 := gfMul x6 x6
  let x15 := gfMul x12 x3
  let x30 := gfMul x15 x15
  let x60 := gfMul x30 x30
  let x120 := gfMul x60 x60
  let x126 := gfMul x120 x6
  let x127 := gfMul x126 x
  gfMul x127 x127

/-- NIST FIPS 197 affine transformation over GF(2):
`b'_i = b_i ⊕ b_{(i+4)%8} ⊕ b_{(i+5)%8} ⊕ b_{(i+6)%8} ⊕ b_{(i+7)%8} ⊕ c_i` with `c = 0x63`. -/
def aesAffine (b : BitVec 8) : BitVec 8 :=
  let bit (k : Nat) : Bool :=
    xor (b.getLsbD k)
      (xor (b.getLsbD ((k + 4) % 8))
        (xor (b.getLsbD ((k + 5) % 8))
          (xor (b.getLsbD ((k + 6) % 8))
            (xor (b.getLsbD ((k + 7) % 8)) ((0x63#8).getLsbD k)))))
  packByte (bit 0) (bit 1) (bit 2) (bit 3) (bit 4) (bit 5) (bit 6) (bit 7)

/-- Algebraic NIST FIPS 197 AES S-box. -/
def aesSbox (x : BitVec 8) : BitVec 8 :=
  aesAffine (gfInv x)

theorem gfInv_mul_self : ∀ x : BitVec 8, x ≠ 0#8 → gfMul x (gfInv x) = 1#8 := by
  decide +kernel

theorem gfInv_zero : gfInv 0#8 = 0#8 := by
  decide +kernel

/-- The algebraic GF(2^8) AES S-box matches LNSym's NIST FIPS 197 table on all 256 bytes. -/
theorem aesSbox_eq_lnsymSbox : ∀ x : BitVec 8, aesSbox x = lnsymSbox x := by
  decide +kernel

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

/-- Existence of a well-formed AES S-box circuit with exactly `n` total gates. -/
def ValidTotalCircuit (n : Nat) : Prop :=
  ∃ gates outputs,
    wellFormed gates outputs = true ∧
    gates.length = n ∧
    ∀ x : BitVec 8, evalCircuit gates outputs x = aesSbox x

/-- Existence of a well-formed AES S-box circuit with exactly `n` AND gates. -/
def ValidAndCircuit (n : Nat) : Prop :=
  ∃ gates outputs,
    wellFormed gates outputs = true ∧
    andCount gates = n ∧
    ∀ x : BitVec 8, evalCircuit gates outputs x = aesSbox x

/-! ## Bit-sliced 256-input kernel-verified evaluator -/

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
  [ 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000#256,
    0xffffffffffffffff0000000000000000ffffffffffffffff0000000000000000#256,
    0xffffffff00000000ffffffff00000000ffffffff00000000ffffffff00000000#256,
    0xffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000#256,
    0xff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00#256,
    0xf0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0#256,
    0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc#256,
    0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa#256 ]

def aesSboxTable256 : List (BitVec 256) :=
  [ 0x4f1ead396f247a0410bdb210c006eab568ab4bfa8acb7a13b14ede67096c6eed#256,
    0xc870974094ead8a96a450b2ef33486b4e61a4c5e97816f7a7bae007d4c53fc7d#256,
    0xac39b6c0d6ce2efc577d64e03b0c3ffb23a869a2a428c424a16387fb3b48b4c6#256,
    0x4e9ddb76c892fb1be9da849cf6ac6c1b2568ea2effa8527d109020a2193d586a#256,
    0xf210a3aece472e532624b286bc48ecb4f7f17a494ce30f58c2b0f97752b8b11e#256,
    0x54b248130b4f256f7d8dcc4706319e086bc2aa4e0d787aa4f8045f7b6d98dd7f#256,
    0x21e0b833255917823f6bcb91b30db559e4851b3bf3ab2560980a3cc2c2fdb4ff#256,
    0x52379de7b844e3e14cb3770196ca0329e7bac28f866aac825caa2ec7bf977090#256 ]

/-- Evaluate all 256 inputs simultaneously as 256-bit truth tables and compare to `aesSbox`. -/
def checkCircuit256 (gates : List (Nat × Nat × Nat)) (outputs : List Nat) : Bool :=
  let (n, wires) := evalWires256Aux 8 initRevWires256 gates
  (getRevWire n wires (outputs.getD 0 0) == aesSboxTable256.getD 0 0#256) &&
  (getRevWire n wires (outputs.getD 1 0) == aesSboxTable256.getD 1 0#256) &&
  (getRevWire n wires (outputs.getD 2 0) == aesSboxTable256.getD 2 0#256) &&
  (getRevWire n wires (outputs.getD 3 0) == aesSboxTable256.getD 3 0#256) &&
  (getRevWire n wires (outputs.getD 4 0) == aesSboxTable256.getD 4 0#256) &&
  (getRevWire n wires (outputs.getD 5 0) == aesSboxTable256.getD 5 0#256) &&
  (getRevWire n wires (outputs.getD 6 0) == aesSboxTable256.getD 6 0#256) &&
  (getRevWire n wires (outputs.getD 7 0) == aesSboxTable256.getD 7 0#256)

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

theorem initRevWires256_correct :
    ∀ x : BitVec 8, ∀ i : Fin 8,
      (getRevWire 8 initRevWires256 i.val).getLsbD x.toNat = (initWires x).getD i.val false := by
  decide +kernel

theorem aesSboxTable256_lnsym_correct :
    ∀ x : BitVec 8,
      packByte
        ((aesSboxTable256.getD 0 0#256).getLsbD x.toNat)
        ((aesSboxTable256.getD 1 0#256).getLsbD x.toNat)
        ((aesSboxTable256.getD 2 0#256).getLsbD x.toNat)
        ((aesSboxTable256.getD 3 0#256).getLsbD x.toNat)
        ((aesSboxTable256.getD 4 0#256).getLsbD x.toNat)
        ((aesSboxTable256.getD 5 0#256).getLsbD x.toNat)
        ((aesSboxTable256.getD 6 0#256).getLsbD x.toNat)
        ((aesSboxTable256.getD 7 0#256).getLsbD x.toNat) = lnsymSbox x := by
  decide +kernel

/-- Soundness of bit-sliced verification: a passing `checkCircuit256` proves exact
pointwise agreement with `aesSbox` on all 256 input bytes. -/
theorem evalCircuit_eq_aesSbox_of_checkCircuit256 (gates : List (Nat × Nat × Nat)) (outputs : List Nat)
    (hcheck : checkCircuit256 gates outputs = true) :
    ∀ x : BitVec 8, evalCircuit gates outputs x = aesSbox x := by
  intro x
  have hinv0 : ∀ i, (getRevWire 8 initRevWires256 i).getLsbD x.toNat = (initWires x).getD i false := by
    intro i
    by_cases hi : i < 8
    · exact initRevWires256_correct x ⟨i, hi⟩
    · simp [getRevWire, Array.getD, initWires, hi]
  have hwires := evalWires256Aux_getLsbD gates 8 initRevWires256 (initWires x) x rfl hinv0
  simp only [checkCircuit256, Bool.and_eq_true, beq_iff_eq] at hcheck
  rcases hcheck with ⟨⟨⟨⟨⟨⟨⟨h0, h1⟩, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩, h7⟩
  have hb : ∀ k,
      getRevWire (evalWires256Aux 8 initRevWires256 gates).1
        (evalWires256Aux 8 initRevWires256 gates).2 (outputs.getD k 0) = aesSboxTable256.getD k 0#256 →
      (evalWiresAux (initWires x) gates).getD (outputs.getD k 0) false =
        (aesSboxTable256.getD k 0#256).getLsbD x.toNat := by
    intro k heq
    rw [← hwires (outputs.getD k 0), heq]
  simp only [evalCircuit]
  rw [hb 0 h0, hb 1 h1, hb 2 h2, hb 3 h3, hb 4 h4, hb 5 h5, hb 6 h6, hb 7 h7]
  rw [aesSboxTable256_lnsym_correct x, aesSbox_eq_lnsymSbox x]

end AesSbox
