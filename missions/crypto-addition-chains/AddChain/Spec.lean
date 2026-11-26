/-!
# Cryptographic Elliptic-Curve Addition Chains (20 Production Curves)

Pure Lean 4.36.0 (zero Mathlib) specification of shortest addition chains for
production elliptic-curve field and scalar Fermat inversion exponents (`a^(p-2) ≡ a^-1`),
pinned verbatim to `mmcloughlin/addchain@6c4dbba3ac` (BSD-3-Clause):

```go
	// P2213 is the prime 2²²¹ - 3 used in curve M-221 [aranha].
	P2213 = NewCrandall(221, 3)

	// P222117 is the prime 2²²² - 117 used in curve E-222 [aranha].
	P222117 = NewCrandall(222, 117)

	// P2519 is the prime 2²⁵¹ - 9 used in Curve1174 [elligator].
	P2519 = NewCrandall(251, 9)

	// P25519 is the prime 2²⁵⁵ - 19 used in Curve25519 [curve25519].
	P25519 = NewCrandall(255, 19)

	// P382105 is the prime 2³⁸² - 105 used in curve E-382 [aranha].
	P382105 = NewCrandall(382, 105)

	// P383187 is the prime 2³⁸³ - 187 used in curves M-383 and Curve383187 [aranha].
	P383187 = NewCrandall(383, 187)

	// P41417 is the prime 2⁴¹⁴ - 17 used in Curve41417 [nistdanger].
	P41417 = NewCrandall(414, 17)

	// P511187 is the prime 2⁵¹¹ - 187 used in M-511 [aranha].
	P511187 = NewCrandall(511, 187)

	// NISTP192 is the P-192 prime 2¹⁹² - 2⁶⁴ - 1 defined in [fips186-2].
	NISTP192 = NewSolinas(polynomial.Polynomial{{A: -1, N: 0}, {A: -1, N: 1}, {A: 1, N: 3}}, 64)

	// NISTP224 is the P-224 prime 2²²⁴ - 2⁹⁶ + 1 defined in [fips186-2].
	NISTP224 = NewSolinas(polynomial.Polynomial{{A: 1, N: 0}, {A: -1, N: 3}, {A: 1, N: 7}}, 32)

	// NISTP256 is the P-256 prime 2²⁵⁶ - 2²²⁴ + 2¹⁹² + 2⁹⁶ - 1 defined in [fips186-2].
	NISTP256 = NewSolinas(polynomial.Polynomial{{A: -1, N: 0}, {A: +1, N: 3}, {A: +1, N: 6}, {A: -1, N: 7}, {A: +1, N: 8}}, 32)

	// NISTP384 is the P-384 prime 2³⁸⁴ - 2¹²⁸ - 2⁹⁶ + 2³² - 1 defined in [fips186-2].
	NISTP384 = NewSolinas(polynomial.Polynomial{{A: -1, N: 0}, {A: 1, N: 1}, {A: -1, N: 3}, {A: -1, N: 4}, {A: 1, N: 12}}, 32)

	// Goldilocks is the prime 2⁴⁴⁸ - 2²²⁴ - 1 defined in [goldilocks].
	Goldilocks = NewSolinas(polynomial.Polynomial{{A: -1, N: 0}, {A: -1, N: 1}, {A: 1, N: 2}}, 224)

	// Secp192k1 is the prime for the 192-bit Koblitz curve recommended in [sec2].
	Secp192k1 = MustHex("FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_FFFFEE37")

	// Secp192r1 is the prime for the 192-bit "random" curve recommended in [sec2].
	Secp192r1 = NISTP192

	// Secp224k1 is the prime for the 224-bit Koblitz curve recommended in [sec2].
	Secp224k1 = MustHex("FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_FFFFE56D")

	// Secp224r1 is the prime for the 224-bit "random" curve recommended in [sec2].
	Secp224r1 = NISTP224

	// Secp256k1 is the prime for the 256-bit Koblitz curve recommended in [sec2].
	Secp256k1 = MustHex("FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_FFFFFC2F")

	// Secp256r1 is the prime for the 256-bit "random" curve recommended in [sec2].
	Secp256r1 = NISTP256

	// Secp384r1 is the prime for the 384-bit "random" curve recommended in [sec2].
	Secp384r1 = NISTP384
```

```go
var Results = []Result{
	{
		Name:          "Curve25519 Field Inversion",
		Slug:          "curve25519_field",
		N:             prime.P25519,
		D:             2,
		Length:        266,
		AlgorithmName: "opt(runs(continued_fractions(dichotomic)))",
		BestKnown:     265,
	},
	{
		Name:          "NIST P-256 Field Inversion",
		Slug:          "p256_field",
		N:             prime.NISTP256,
		D:             3,
		Length:        266,
		AlgorithmName: "opt(runs(continued_fractions(dichotomic)))",
		BestKnown:     266,
	},
	{
		Name:          "NIST P-384 Field Inversion",
		Slug:          "p384_field",
		N:             prime.NISTP384,
		D:             3,
		Length:        397,
		AlgorithmName: "opt(runs(heuristic(use_first(halving,approximation))))",
		BestKnown:     396,
	},
	{
		Name:          "secp256k1 (Bitcoin) Field Inversion",
		Slug:          "secp256k1_field",
		N:             prime.Secp256k1,
		D:             3,
		Length:        269,
		AlgorithmName: "opt(runs(heuristic(use_first(halving,delta_largest))))",
		BestKnown:     269,
	},
	{
		Name:          "Curve25519 Scalar Inversion",
		Slug:          "curve25519_scalar",
		N:             Hex("1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed"),
		D:             2,
		Length:        283,
		AlgorithmName: "opt(dictionary(hybrid(4,0),continued_fractions(binary)))",
		BestKnown:     284,
	},
	{
		Name:          "NIST P-256 Scalar Inversion",
		Slug:          "p256_scalar",
		N:             Hex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"),
		D:             2,
		Length:        294,
		AlgorithmName: "opt(dictionary(hybrid(8,16),heuristic(use_first(halving,delta_largest))))",
		BestKnown:     292,
	},
	{
		Name:          "NIST P-384 Scalar Inversion",
		Slug:          "p384_scalar",
		N:             Hex("ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973"),
		D:             2,
		Length:        434,
		AlgorithmName: "opt(dictionary(hybrid(4,0),continued_fractions(dichotomic)))",
		BestKnown:     433,
	},
	{
		Name:          "secp256k1 (Bitcoin) Scalar Inversion",
		Slug:          "secp256k1_scalar",
		N:             Hex("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"),
		D:             2,
		Length:        293,
		AlgorithmName: "opt(dictionary(hybrid(4,0),continued_fractions(dichotomic)))",
		BestKnown:     290,
	},
```
-/

namespace AddChain

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

/-- Curve25519 Field p-2 Fermat inversion exponent (best known: 265 steps). -/
def target_curve25519_field_inv : Nat := 2 ^ 255 - 21

/-- Curve25519 Scalar l-2 Fermat inversion exponent (best known: 283 steps). -/
def target_curve25519_scalar_inv : Nat := 0x1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed - 2

/-- NIST P-256 Field p-2 Fermat inversion exponent (best known: 267 steps). -/
def target_p256_field_inv : Nat := 2 ^ 256 - 2 ^ 224 + 2 ^ 192 + 2 ^ 96 - 3

/-- NIST P-256 Scalar n-2 Fermat inversion exponent (best known: 292 steps). -/
def target_p256_scalar_inv : Nat := 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551 - 2

/-- NIST P-384 Field p-2 Fermat inversion exponent (best known: 397 steps). -/
def target_p384_field_inv : Nat := 2 ^ 384 - 2 ^ 128 - 2 ^ 96 + 2 ^ 32 - 3

/-- NIST P-384 Scalar n-2 Fermat inversion exponent (best known: 433 steps). -/
def target_p384_scalar_inv : Nat := 0xffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973 - 2

/-- secp256k1 Field p-2 Fermat inversion exponent (best known: 270 steps). -/
def target_secp256k1_field_inv : Nat := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F - 2

/-- secp256k1 Scalar n-2 Fermat inversion exponent (best known: 290 steps). -/
def target_secp256k1_scalar_inv : Nat := 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141 - 2

/-- Ed448-Goldilocks Field p-2 Fermat inversion exponent (best known: 460 steps). -/
def target_goldilocks_ed448_inv : Nat := 2 ^ 448 - 2 ^ 224 - 3

/-- NIST P-224 Field p-2 Fermat inversion exponent (best known: 234 steps). -/
def target_p224_field_inv : Nat := 2 ^ 224 - 2 ^ 96 - 1

/-- NIST P-192 Field p-2 Fermat inversion exponent (best known: 203 steps). -/
def target_p192_field_inv : Nat := 2 ^ 192 - 2 ^ 64 - 3

/-- secp192k1 Field p-2 Fermat inversion exponent (best known: 205 steps). -/
def target_secp192k1_field_inv : Nat := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFEE37 - 2

/-- secp224k1 Field p-2 Fermat inversion exponent (best known: 238 steps). -/
def target_secp224k1_field_inv : Nat := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFE56D - 2

/-- M-221 Field p-2 Fermat inversion exponent (best known: 231 steps). -/
def target_p2213_field_inv : Nat := 2 ^ 221 - 5

/-- E-222 Field p-2 Fermat inversion exponent (best known: 233 steps). -/
def target_p222117_field_inv : Nat := 2 ^ 222 - 119

/-- Curve1174 Field p-2 Fermat inversion exponent (best known: 263 steps). -/
def target_p2519_field_inv : Nat := 2 ^ 251 - 11

/-- E-382 Field p-2 Fermat inversion exponent (best known: 395 steps). -/
def target_p382105_field_inv : Nat := 2 ^ 382 - 107

/-- M-383 Field p-2 Fermat inversion exponent (best known: 396 steps). -/
def target_p383187_field_inv : Nat := 2 ^ 383 - 189

/-- Curve41417 Field p-2 Fermat inversion exponent (best known: 426 steps). -/
def target_p41417_field_inv : Nat := 2 ^ 414 - 19

/-- M-511 Field p-2 Fermat inversion exponent (best known: 525 steps). -/
def target_p511187_field_inv : Nat := 2 ^ 511 - 189


end AddChain
