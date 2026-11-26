import Mathlib

set_option linter.unusedVariables false

/-!
Frozen verbatim upstream definitions and target propositions for `fate-h-fields-and-groups`
(`frenzymath/FATE-H@17967b311808`).
-/

namespace FateHSpec.P1

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {G : Type} [Group G] {n : ℕ} (hn : n ≠ 0) 
    (H : Subgroup G) (hH : H.index = n),
    ∃ K : Subgroup G, K.Normal ∧ K ≤ H ∧ K.index ≠ 0 ∧ K.index ≤ n.factorial
end TargetStmt

end FateHSpec.P1

namespace FateHSpec.P2

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {G : Type} [Group G] (hG : Nat.card G = 56),
    ¬ IsSimpleGroup G
end TargetStmt

end FateHSpec.P2

namespace FateHSpec.P3

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {G : Type} [Group G] (h : Nat.card G = 3393),
    ¬ IsSimpleGroup G
end TargetStmt

end FateHSpec.P3

namespace FateHSpec.P4

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {p : ℕ} [Fact p.Prime] {P : Type} [Group P] (hp : Nat.card P = p ^ 3)
    (h : ∃ (a b : P), a * b ≠ b * a),
    Nat.card (Subgroup.center P) = p ∧
    Nonempty ((P ⧸ Subgroup.center P) ≃* Multiplicative ((ZMod p) × (ZMod p)))
end TargetStmt

end FateHSpec.P4

namespace FateHSpec.P7

section TargetStmt
open Subgroup
def SunsteadTarget : Prop :=
  ∀ {G : Type} [Group G] (H K : Subgroup G)
    [H.Normal] (h1 : K ≤ H) [(K.subgroupOf H).Normal]
    (h2 : Subgroup.centralizer (K.subgroupOf H) = (⊥ : Subgroup H)),
    H ≤ Subgroup.centralizer (Subgroup.centralizer (K : Set G) : Set G)
end TargetStmt

end FateHSpec.P7

namespace FateHSpec.P8

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {G : Type} [Group G] [Finite G] (P : Sylow 2 G)
    (h1 : P.toSubgroup ≠ ⊥) [IsCyclic P],
    ∃ H : Subgroup G, H.index = 2
end TargetStmt

end FateHSpec.P8

namespace FateHSpec.P9

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {n : ℕ} (hn : Odd n) (h : n ≥ 3),
    Subgroup.centralizer ⊤ = (⊥ : Subgroup (DihedralGroup n))
end TargetStmt

end FateHSpec.P9

namespace FateHSpec.P11

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {G : Type} [Group G] (h : Nat.card G = 3825)
    (H : Subgroup G) [H.Normal] (hH : Nat.card H = 17),
    H ≤ Subgroup.center G
end TargetStmt

end FateHSpec.P11

namespace FateHSpec.P12

section TargetStmt
open MatrixGroups
def SunsteadTarget : Prop :=
  ∃ φ : SL(2,ZMod 3) ⧸ Subgroup.center SL(2,ZMod 3) →* alternatingGroup (Fin 4),
    Function.Injective φ
end TargetStmt

end FateHSpec.P12

namespace FateHSpec.P13

section TargetStmt
open Matrix
def SunsteadTarget : Prop :=
  ∀ (p : ℕ) [Fact p.Prime],
    Nat.card (Sylow p <| GL (Fin 2) (ZMod p)) = p + 1
end TargetStmt

end FateHSpec.P13

namespace FateHSpec.P19

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {G : Type} [Group G] [Finite G],
    ∃ (n : ℕ) (H : Subgroup (alternatingGroup (Fin n))), Nonempty (G ≃* H)
end TargetStmt

end FateHSpec.P19

namespace FateHSpec.P20

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {G : Type} [Group G] {p : ℕ} [hp : Fact p.Prime]
    (hG : p ^ 3 = Nat.card G) (h : ∃ x y : G, x * y ≠ y * x),
    Subgroup.center G = commutator G
end TargetStmt

end FateHSpec.P20

namespace FateHSpec.P21

section TargetStmt
def SunsteadTarget : Prop :=
  Nat.card (AddAut <| ZMod 3 × ZMod 9) = 108
end TargetStmt

end FateHSpec.P21

namespace FateHSpec.P22

section TargetStmt
def SunsteadTarget : Prop :=
  Nonempty (MulAut (DihedralGroup 4) ≃* DihedralGroup 4)
end TargetStmt

end FateHSpec.P22

namespace FateHSpec.P23

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (G : Type) [Group G]
    [Finite G] (h_card : Nat.card G = 1053),
    ¬ IsSimpleGroup G
end TargetStmt

end FateHSpec.P23

namespace FateHSpec.P24

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (H : AddSubgroup (ℚ ⧸ (Int.castAddHom ℚ).range)) (h_fin : H.FiniteIndex),
    H = ⊤
end TargetStmt

end FateHSpec.P24

namespace FateHSpec.P26

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {G : Type} [Group G] (H : Subgroup G)
    (h : IsCoatom H),
    Subgroup.center G ≤ H ∨ commutator G ≤ H
end TargetStmt

end FateHSpec.P26

namespace FateHSpec.P28

section TargetStmt
open IntermediateField
def SunsteadTarget : Prop :=
  ∀ {k : Type} [Field k] [PerfectField k] {p : ℕ} [Fact p.Prime] [CharP k p]
    {E : Type} [Field E] [Algebra (RatFunc k) E] [FiniteDimensional (RatFunc k) E],
    ∃ α : E, (RatFunc k)⟮α⟯ = ⊤
end TargetStmt

end FateHSpec.P28

namespace FateHSpec.P29

section TargetStmt
open IntermediateField Polynomial
def SunsteadTarget : Prop :=
  ∀ {F E : Type} [Field F] {p : ℕ} [Fact p.Prime] [CharP F p] [Field E]
    [Algebra F E] [IsGalois F E] (h_deg : Module.finrank F E = p),
    ∃ a : F, Nonempty (AdjoinRoot (X ^ p - X - C a : F[X]) ≃+* E)
end TargetStmt

end FateHSpec.P29

namespace FateHSpec.P30

section TargetStmt
open Polynomial
open scoped IntermediateField
def SunsteadTarget : Prop :=
  ∀ {E : Type} [Field E] [Algebra ℚ E]
    [IsCyclotomicExtension {7} ℚ E] (ζ : E)
    (h : IsPrimitiveRoot ζ 7) (β : E) (hb : β = ζ + ζ ^ 2 + ζ ^ 4),
    Nonempty (ℚ⟮β⟯ ≃+* AdjoinRoot (X ^ 2 + 7 : ℚ[X]))
end TargetStmt

end FateHSpec.P30

namespace FateHSpec.P31

section TargetStmt
open Module
def SunsteadTarget : Prop :=
  ∀ {n : ℕ+},
    (∃ b : Basis (primitiveRoots n (CyclotomicField n ℚ)) ℚ (CyclotomicField n ℚ),
    (b : _ → _) = (↑)) ↔ Squarefree n
end TargetStmt

end FateHSpec.P31

namespace FateHSpec.P32

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  Nonempty (Gal (X ^ 4 - 2 * X ^ 2 - 2 : ℚ[X]) ≃* DihedralGroup 4)
end TargetStmt

end FateHSpec.P32

namespace FateHSpec.P33

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ {n : Nat} (hn : n > 4) (f : ℚ[X]) (hf : f.degree = n)
    (hf' : Irreducible f) (h : f.Gal ≃* (Equiv.Perm <| Fin n))
    {a b : SplittingField f} (ha : f.aeval a = 0) (hb : f.aeval b = 0) (neq : a ≠ b),
    Nat.card {h : f.Gal // h a = b} = Nat.factorial (n - 1)
end TargetStmt

end FateHSpec.P33

namespace FateHSpec.P34

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ {E E': Type} [Field E] [CharZero E] [Field E'] [Algebra E E'] {q : ℕ}
    [Fact q.Prime] {b : E} (hb : b ≠ 0) (not_pow : ∀ c : E, c ^ q ≠ b) {a : E'}
    (ha : a ^ q = algebraMap E E' b) (haE : ⊤ = IntermediateField.adjoin E {a}),
    ¬ Irreducible (X ^ q - C b) ↔ Module.finrank E E' < q
end TargetStmt

end FateHSpec.P34

namespace FateHSpec.P35

section TargetStmt
open Polynomial IntermediateField
def SunsteadTarget : Prop :=
  ∀ {d : ℤ} (hd : Squarefree d) {a : ℚ} (ha : a ≠ 0),
    IsEmpty ((AdjoinRoot ((a⁻¹ • X ^ 2) ^ 2 - C (d : ℚ)) ≃ₐ[ℚ]
      AdjoinRoot ((a⁻¹ • X ^ 2) ^ 2 - C (d : ℚ))) ≃* Multiplicative (ZMod 4))
end TargetStmt

end FateHSpec.P35

namespace FateHSpec.P36

section TargetStmt
open Polynomial IntermediateField
def SunsteadTarget : Prop :=
  Nat.card (IntermediateField ℚ (X ^ 4 - X ^ 2 - 1 : ℚ[X]).SplittingField) = 10
end TargetStmt

end FateHSpec.P36

namespace FateHSpec.P37

section TargetStmt
open Polynomial IntermediateField AdjoinRoot
def SunsteadTarget : Prop :=
  ∀ {K L : Type} [Field K]
    [Field L] [Algebra K L] [IsGalois K L] (n a b : ℕ)
    (σ : L ≃ₐ[K] L) (hσ : orderOf σ = n) (cycle : Subgroup.zpowers σ = ⊤) (hn : n > 0)
    (hn' : n = a * b) (hab : Nat.Coprime a b) {α β : L}
    (hα : K⟮α⟯ = IntermediateField.fixedField (Subgroup.zpowers (σ ^ a)))
    (hβ : K⟮β⟯ = IntermediateField.fixedField (Subgroup.zpowers (σ ^ b))),
    K⟮α + β⟯ = ⊤
end TargetStmt

end FateHSpec.P37

namespace FateHSpec.P38

section TargetStmt
open IntermediateField
def SunsteadTarget : Prop :=
  ∀ {p : Nat} [Fact p.Prime]
    {F K : Type} [Field F] (hF : (primitiveRoots p F).Nonempty) [Field K] [Algebra F K]
    [IsGalois F K] (hK : (K ≃ₐ[F] K) ≃* Multiplicative (ZMod p × ZMod p)),
    ∃ (α β : K), α ≠ 0 ∧ β ≠ 0 ∧ α ^ p ∈ (algebraMap F K).range ∧ β ^ p ∈ (algebraMap F K).range ∧
    IntermediateField.adjoin F {α, β} = ⊤
end TargetStmt

end FateHSpec.P38

namespace FateHSpec.P39

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  letI : Fact (Nat.Prime 7) := by decide
    ∃ ζ : (X ^ 15 - 2 : (ZMod 7)[X]).SplittingField, IsPrimitiveRoot ζ 45 ∧
    IntermediateField.adjoin (ZMod 7) {ζ} = ⊤
end TargetStmt

end FateHSpec.P39

namespace FateHSpec.P40

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ {f : ℚ[X]} {K : Type} [Field K] [Algebra ℚ K]
    [IsSplittingField ℚ K f] (hf1 : Irreducible f) (hf2 : f.natDegree = 5) (a₁ a₂ a₃ : K)
    (ha1 : a₁ ∈ rootSet f K ∧ a₂ ∈ rootSet f K ∧ a₃ ∈ rootSet f K)
    (ha2 : a₁ ≠ a₂ ∧ a₂ ≠ a₃ ∧ a₃ ≠ a₁)
    (h : IntermediateField.adjoin ℚ {a₁, a₂, a₃} ≠ ⊤),
    Nonempty (f.Gal ≃* (Equiv.Perm <| Fin 5))
end TargetStmt

end FateHSpec.P40

namespace FateHSpec.P41

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {F : Type} [Field F] (p : ℕ) [Fact (Nat.Prime p)]
    (h : ∀ (E : Type) [Field E] [Algebra F E] [FiniteDimensional F E],
    Module.finrank F E ≠ 1 → p ∣ Module.finrank F E)
    (E : Type) [Field E] [Algebra F E] [FiniteDimensional F E],
    ∃ k, Module.finrank F E = p ^ k
end TargetStmt

end FateHSpec.P41

namespace FateHSpec.P42

section TargetStmt
open IntermediateField AdjoinRoot Polynomial
def SunsteadTarget : Prop :=
  ∀ (K L : Type) [Field K] [Field L] (h : ¬ CharP K 2) [Algebra K L] [IsGalois K L]
    (f : (L ≃ₐ[K] L) ≃* Multiplicative (ZMod 2 × ZMod 2)) (c : Lˣ) (hc : c.1 ≠ 0)
    (hcs : ¬ IsSquare c.1) [Fact (Irreducible (X ^ 2 - C c.1))],
    IsGalois K (AdjoinRoot (X ^ 2 - C c.1)) ↔ ∀ σ : (L ≃ₐ[K] L), IsSquare (σ c / c)
end TargetStmt

end FateHSpec.P42

namespace FateHSpec.P43

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ (F : IntermediateField ℚ ℂ) [FiniteDimensional ℚ F] [IsGalois ℚ F]
    (h : ∀ f g : F ≃ₐ[ℚ] F, f * g = g * f) (α : F) (f : ℚ[X])
    (h_min : f = minpoly ℚ α) (ha : ‖α‖ = 1)
    (β : ℂ) (hb : β ∈ f.rootSet ℂ),
    ‖β‖ = 1
end TargetStmt

end FateHSpec.P43

namespace FateHSpec.P44

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ {F : Type} (q : ℕ) [Field F]
    [Fintype F] (hF : Fintype.card F = q),
    Nat.card { P : F[X] | P.Monic ∧ Irreducible P ∧ P.natDegree = 19 } =
    (q ^ 19 - q) / 19
end TargetStmt

end FateHSpec.P44

namespace FateHSpec.P46

section TargetStmt
open IntermediateField
def SunsteadTarget : Prop :=
  ∀ {α : ℂ} {K L : Type} [Field K] [NumberField K]
    [Algebra K ℂ] (hk : Module.finrank ℚ K = 2) {a : K} (h : α + α⁻¹ = algebraMap K ℂ a)
    [Field L] [Algebra ℚ L] [IsNormalClosure ℚ ℚ⟮a⟯ L],
    Module.finrank ℚ L ∣ 8
end TargetStmt

end FateHSpec.P46

namespace FateHSpec.P48

section TargetStmt
def SunsteadTarget : Prop :=
  Infinite (ℂ ≃ₐ[ℚ] ℂ)
end TargetStmt

end FateHSpec.P48

namespace FateHSpec.P49

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {F : Type} [Field F] [Algebra ℚ F]
    (h : (⊤ : IntermediateField ℚ F).FG),
    ∃ f : F →ₐ[ℚ] ℂ, Function.Injective f
end TargetStmt

end FateHSpec.P49

namespace FateHSpec.P52

section TargetStmt
open IntermediateField
def SunsteadTarget : Prop :=
  ∀ (p m n : ℕ) (hn : 1 ≤ n) (hm : 1 ≤ m)
    [Fact p.Prime],
    IsGalois (GaloisField p m)⟮(RatFunc.X ^ n : RatFunc (GaloisField p m))⟯
    (RatFunc (GaloisField p m)) ↔ p ^ m ≡ 1 [MOD n]
end TargetStmt

end FateHSpec.P52

namespace FateHSpec.P53

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (f : ℝ ≃ₐ[ℚ] ℝ),
    f = 1
end TargetStmt

end FateHSpec.P53

namespace FateHSpec.P54

section TargetStmt
open IntermediateField RatFunc
def SunsteadTarget : Prop :=
  IsGalois (GaloisField 2 2)⟮(X ^ 4 + X : RatFunc (GaloisField 2 2))⟯
    (RatFunc (GaloisField 2 2))
end TargetStmt

end FateHSpec.P54

namespace FateHSpec.P55

section TargetStmt
open IntermediateField
def SunsteadTarget : Prop :=
  ∀ {K L : Type} [Field K] [Field L]
    [Algebra K L] [IsGalois K L] (hK : ¬ CharP K 2),
    IsKleinFour (L ≃ₐ[K] L) ↔
    ∃ a b : Kˣ, ∃ x y : L, x ^ 2 = algebraMap K L a.1 ∧ y ^ 2 = algebraMap K L b.1 ∧
    K⟮x, y⟯ = ⊤ ∧ ¬IsSquare a ∧ ¬IsSquare b ∧ ¬IsSquare (a / b)
end TargetStmt

end FateHSpec.P55

namespace FateHSpec.P56

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ {n : ℕ} (hn : Odd n) (hn' : 1 < n),
    Polynomial.cyclotomic (2 * n) ℚ = (Polynomial.cyclotomic n ℚ).comp (-X)
end TargetStmt

end FateHSpec.P56

namespace FateHSpec.P57

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {F : Type} [Field F] (h : ¬ PerfectField F),
    ∃ E : IntermediateField F (AlgebraicClosure F), IsPurelyInseparable F E ∧ ⊥ < E
end TargetStmt

end FateHSpec.P57

namespace FateHSpec.P58

section TargetStmt
open IntermediateField
def SunsteadTarget : Prop :=
  ∀ (F : Type) [Field F],
    Subsingleton {M : IntermediateField F (AlgebraicClosure F) //
    ∃ α : AlgebraicClosure F, M = F⟮α⟯ ∧ α ^ 4 ∈ (⊥ : IntermediateField F (AlgebraicClosure F)) ∧
    ¬ α ^ 2 ∈ (⊥ : IntermediateField F (AlgebraicClosure F)) ∧ F⟮α⟯ = F⟮α ^ 2⟯}
end TargetStmt

end FateHSpec.P58

namespace FateHSpec.P60

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ {a : ℤ} (ha : a > 0),
    IsSolvable
    (X ^ 6 + C (3 * a : ℚ) * X ^ 4 + C 3 * X ^ 3 + C (3 * a : ℚ) * X ^ 2 + C 1 : ℚ[X]).Gal
end TargetStmt

end FateHSpec.P60

namespace FateHSpec.P62

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (E F : Type) [Field E] [Field F] [Algebra F E]
    (f : Polynomial F) (h_f_irr : Irreducible f) (h_splitting_field : f.IsSplittingField F E)
    (a : E) (ha : f.aeval a = 0) (n : ℕ) (hn : n ≥ 1)
    (g : Polynomial F) (h_g_irr : Irreducible g) (h_ga : g.aeval (a ^ n) = 0)
    (h_deg : f.degree = g.degree * n) (h_char : (n : F) ≠ 0),
    primitiveRoots n E ≠ ∅
end TargetStmt

end FateHSpec.P62

namespace FateHSpec.P63

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ {n : ℕ} (hn : 1 ≤ n) (f : ℚ[X]) (ξ : ℂˣ)
    (h : ξ ∈ rootsOfUnity n ℂ),
    f.eval₂ (algebraMap ℚ ℂ) ξ ≠ (2 : ℂ) ^ ((1 : ℂ) / 4)
end TargetStmt

end FateHSpec.P63

namespace FateHSpec.P65

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ {p n : ℕ} [Fact p.Prime] (a b : GaloisField p n)
    (h_irr : Irreducible (X ^ 3 + C a * X + C b)),
    IsSquare (- 4 * a ^ 3 - 27 * b ^ 2)
end TargetStmt

end FateHSpec.P65

namespace FateHSpec.P66

section TargetStmt
open Polynomial
def SunsteadTarget : Prop :=
  ∀ {n : ℕ} (hn : n ≥ 3),
    ¬ Irreducible (X ^ 2 ^ n + X + C 1 : (ZMod 2)[X])
end TargetStmt

end FateHSpec.P66

namespace FateHSpec.P97

section TargetStmt
open Real
def SunsteadTarget : Prop :=
  IsAlgebraic ℚ (sin (π / 180))
end TargetStmt

end FateHSpec.P97

