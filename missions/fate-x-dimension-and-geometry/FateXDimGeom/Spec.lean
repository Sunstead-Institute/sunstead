import Mathlib

set_option linter.unusedVariables false

/-!
Frozen verbatim upstream definitions and target propositions for `fate-x-dimension-and-geometry`
(`frenzymath/FATE-X@a6fb49ee85fd`).
-/

namespace Problem10

section TargetStmt
def SunsteadTarget : Prop :=
  IsPrincipalIdealRing ((MvPolynomial (Fin 2) ℝ) ⧸
    Ideal.span {(.X 0 ^ 2 + .X 1 ^ 2 + .C 1 : (MvPolynomial (Fin 2) ℝ))})
end TargetStmt

end Problem10

namespace Problem19

/--
Let $E$ denote the algebra $\mathbb{Q}(\sqrt{(2+\sqrt 2)(3+\sqrt 3)})
-/
abbrev E : Type := (Algebra.adjoin ℚ {Real.sqrt ((2 + Real.sqrt 2) * (3 + Real.sqrt 3))})

section TargetStmt
def SunsteadTarget : Prop :=
  Nonempty ((E ≃ₐ[ℚ] E) ≃* (QuaternionGroup 2))
end TargetStmt

end Problem19

namespace Problem39

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] [IsDomain R]
    [IsNoetherianRing R] [IsIntegrallyClosed R] (L : Type) [Field L] [Algebra R L]
    [Algebra (FractionRing R) L] [IsScalarTower R (FractionRing R) L]
    [FiniteDimensional (FractionRing R) L] (p : Ideal R) [p.IsPrime],
    (p.primesOver (integralClosure R L)).Finite
end TargetStmt

end Problem39

namespace Problem40

section TargetStmt
open TensorProduct
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] [IsLocalRing R] [IsReduced R]
    (h : (minimalPrimes R).Finite) (r : ℕ) (M : Type) [AddCommGroup M] [Module R M] [Module.Finite R M],
    Module.Free R M ∧ Module.rank R M = r ↔
    (Module.rank (IsLocalRing.ResidueField R) ((IsLocalRing.ResidueField R) ⊗[R] M) = r ∧
    ∀ p ∈ minimalPrimes R,
    Module.rank (FractionRing (R ⧸ p)) ((FractionRing (R ⧸ p)) ⊗[R] M) = r)
end TargetStmt

end Problem40

namespace Problem44

open MvPolynomial

/--
Let $k$ be a field. Let $S$ be a finite type $k$-algebra. We say that $S$ is a
\textit{global complete intersection over $k$} if there exists a presentation
$S = k[x_1, \dots, x_n]/(f_1, \dots, f_c)$ such that $\dim(S) = n - c$.
-/
class IsGlobalCompleteIntersection (k : Type) [Field k] (S : Type) [CommRing S] [Algebra k S] :
    Prop extends Algebra.FiniteType k S where
  isGlobalCompleteIntersection : ∃ n : ℕ, ∃ rs : List (MvPolynomial (Fin n) k),
    Nonempty (S ≃ₐ[k] (MvPolynomial (Fin n) k) ⧸ Ideal.ofList rs) ∧ ringKrullDim S + rs.length = n

section TargetStmt
open MvPolynomial
def SunsteadTarget : Prop :=
  ∀ (k : Type) [Field k],
    ¬ IsGlobalCompleteIntersection k (MvPolynomial (Fin 3) k ⧸ Ideal.span
    ({(X 0)^ 2 - (X 1)^2, (X 1)^2 - (X 2)^2, (X 0) * (X 1), (X 1) * (X 2), (X 2) * (X 0)} :
    Set (MvPolynomial (Fin 3) k)))
end TargetStmt

end Problem44

namespace Problem45

/--
A linear map `f` between graded modules is a graded homomorphism if it respects the
grading structure.
-/
def IsGradedHom {R M N ι : Type} [CommRing R] [AddCommGroup M] [AddCommGroup N]
    [Module R M] [Module R N] (𝓜 : ι → Submodule R M) (𝒩 : ι → Submodule R N)
    (f : M →ₗ[R] N) : Prop := ∀ (i : ι) (x : 𝓜 i), f x ∈ 𝒩 i

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {k : Type} [Field k] {r : ℕ}
    (C : ChainComplex (ModuleCat.{0} (MvPolynomial (Fin r) k)) ℕ)
    (hC : ∀ (n : ℕ), n > (r + 1) → CategoryTheory.Limits.IsZero (C.X n))
    (𝓜 : ∀ (n : ℕ), (ℕ → Submodule (MvPolynomial (Fin r) k) (C.X n)))
    [hM : ∀ (n : ℕ), DirectSum.Decomposition (𝓜 n)]
    [hM' : ∀ (n : ℕ), SetLike.GradedSMul (MvPolynomial.homogeneousSubmodule (Fin r) k) (𝓜 n)]
    (h_exact : C.Acyclic)
    (h_gr : ∀ (i j : ℕ), IsGradedHom (𝓜 i) (𝓜 j) (C.d i j).hom)
    (h_free : ∀ (n : ℕ), 1 ≤ n ∧ n ≤ r → Module.Free (MvPolynomial (Fin r) k) (C.X n)),
    Module.Free (MvPolynomial (Fin r) k) (C.X (r + 1))
end TargetStmt

end Problem45

namespace Problem47

/--
The ring \(A = k[x,y]/(y^{2} - f(x))\),
where \(k\) is a field and \(f(x) = (x - t_{1})\ldots(x - t_{n})\).
-/
abbrev A {k : Type} [Field k] {n : ℕ} (t : (Fin n) → k) : Type := (MvPolynomial (Fin 2) k) ⧸ Ideal.span {(.X 1 ^ 2) - ∏ (m : Fin n), (.X 0 - .C (t m) : (MvPolynomial (Fin 2) k))}

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (k : Type) [Field k] (h_char : ¬ CharP k 2)
    (n : ℕ) (h_ge : n ≥ 3) (h_odd : Odd n) (t : (Fin n) → k) (h_inj : Function.Injective t),
    ∃ _ : IsDedekindDomain (A t), Nontrivial (ClassGroup (A t))
end TargetStmt

end Problem47

namespace Problem48

/--
A commutative ring \( A \) is \textit{absolutely flat} if every \( A \)-module is flat.
-/
class IsAbsolutelyFlat (R : Type) [CommRing R] : Prop where
  out ⦃P : Type⦄ [AddCommGroup P] [Module R P] : Module.Flat R P

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R],
    IsAbsolutelyFlat R ↔ (∀ I : Ideal R, I.IsPrincipal → I ^ 2 = I)
end TargetStmt

end Problem48

namespace Problem52

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] (m : Ideal R)
    (h_le_jac : m ≤ Ring.jacobson R) (G₁ G₂ : Polynomial R) (h_monic : G₁.Monic)
    (h_gen : Ideal.span {G₁.map (Ideal.Quotient.mk m), G₂.map (Ideal.Quotient.mk m)} = ⊤),
    Ideal.span {G₁, G₂} = ⊤
end TargetStmt

end Problem52

namespace Problem56

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R S M : Type) [CommRing R] [CommRing S]
    [Algebra R S] [Module.FaithfullyFlat R S] [AddCommGroup M] [Module R M]
    [Module.Projective S (TensorProduct R S M)],
    Module.Projective R M
end TargetStmt

end Problem56

namespace Problem58

section TargetStmt
open TensorProduct
def SunsteadTarget : Prop :=
  ∀ (R S : Type) [CommRing R] [CommRing S]
    [IsLocalRing R] [IsLocalRing S] [IsNoetherianRing R] [IsNoetherianRing S] [Algebra R S]
    (h_map : Ideal.map (algebraMap R S) (IsLocalRing.maximalIdeal R) ≤ IsLocalRing.maximalIdeal S)
    (M : Type) [AddCommGroup M] [Module S M] [Module R M] [IsScalarTower R S M] [Module.Finite S M]
    (h_flat_quotient : ∀ (n : ℕ), Module.Flat (R ⧸ (IsLocalRing.maximalIdeal R) ^ n) ((R ⧸ (IsLocalRing.maximalIdeal R) ^ n) ⊗[R] M)),
    Module.Flat R M
end TargetStmt

end Problem58

namespace Problem60

open Problem60

/--
For a Noetherian domain \( R \), we say that an ideal \( I \subset R \) is invertible if
it is it not the zero ideal and there exists an ideal \( N \) such that \( N \cdot I \) is principal
and \( N \) is not the zero ideal.
-/
def Ideal.Invertible {R : Type} [CommRing R] [IsDomain R] (I : Ideal R) : Prop :=
    I ≠ ⊥ ∧ ∃ (N : Ideal R), (N * I).IsPrincipal ∧ N ≠ ⊥

section TargetStmt
open Problem60
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] [IsDomain R] [IsNoetherianRing R]
    (h_ufd : ∀ (p : Ideal R), (h : p.IsMaximal) → UniqueFactorizationMonoid (Localization.AtPrime p))
    (I : Ideal R),
    I.Invertible ↔ ∀ (p : associatedPrimes R I), ringKrullDim (R ⧸ p.1) = 1
end TargetStmt

end Problem60

namespace Problem61

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R S : Type) [CommRing R] [CommRing S]
    [Algebra R S] [Module.Flat R S] (I : Ideal R) (h : I ^ 2 = 0)
    [Algebra.FormallySmooth (R ⧸ I) (S ⧸ (I.map (algebraMap R S)))],
    Algebra.FormallySmooth R S
end TargetStmt

end Problem61

namespace Problem64

section

open CategoryTheory Abelian Problem64

variable {R : Type} [CommRing R]

instance : CategoryTheory.HasExt.{0} (ModuleCat.{0} R) :=
  CategoryTheory.hasExt_of_enoughProjectives (ModuleCat R)

noncomputable def moduleDepth (N M : ModuleCat.{0} R) : ℕ∞ :=
  sSup {n : ℕ∞ | ∀ i : ℕ, i < n → Subsingleton (CategoryTheory.Abelian.Ext.{0} N M i)}

noncomputable def Ideal.depth (I : Ideal R) (M : ModuleCat.{0} R) : ℕ∞ :=
  moduleDepth (ModuleCat.of R (R ⧸ I)) M

noncomputable def IsLocalRing.depth [IsLocalRing R] (M : ModuleCat.{0} R) : ℕ∞ :=
  (IsLocalRing.maximalIdeal R).depth M

variable (R)

class IsCohenMacaulayLocalRing : Prop extends IsLocalRing R where
  depth_eq_dim : ringKrullDim R = IsLocalRing.depth (ModuleCat.of R R)

class IsCohenMacaulayRing : Prop where
  CM_localize : ∀ p : Ideal R, ∀ (_ : p.IsPrime), IsCohenMacaulayLocalRing (Localization.AtPrime p)

end

open MvPolynomial

section TargetStmt
open MvPolynomial
def SunsteadTarget : Prop :=
  ∀ (k : Type) [Field k],
    ¬ IsCohenMacaulayRing (Algebra.adjoin k ({(X 0) ^ 4, (X 0) ^ 3 * X 1,
      X 0 * (X 1) ^ 3, (X 1) ^ 4} : Set (MvPolynomial (Fin 2) k)))
end TargetStmt

end Problem64

namespace Problem65

open IsLocalRing ModuleCat CategoryTheory Polynomial

instance (R : Type) [CommRing R] : CategoryTheory.HasExt.{0} (ModuleCat.{0} R) :=
  CategoryTheory.hasExt_of_enoughProjectives.{0} (ModuleCat.{0} R)

/--
A Noetherian local ring $R$ is a Gorenstein ring if $\mathrm{inj}.\dim_R R < +\infty$.
-/
class IsGorensteinLocalRing (R : Type) [CommRing R] : Prop extends
    IsLocalRing R, IsNoetherianRing R where
  injDim_le_infity :
    ∃ n : ℕ, ∀ i : ℕ, n ≤ i →
    Subsingleton (Abelian.Ext.{0} (of.{0} R (ResidueField R)) (of.{0} R R) i)

/--
A Noetherian ring is a Gorenstein ring if its localization at every maximal ideal is a
  Gorenstein local ring.
-/
class IsGorensteinRing (R : Type) [CommRing R] : Prop extends IsNoetherianRing R where
  localization_maximal_isGorensteinLocalRing :
    ∀ m : Ideal R, (_ : m.IsMaximal) → IsGorensteinLocalRing (Localization.AtPrime m)

section TargetStmt
open IsLocalRing ModuleCat CategoryTheory Polynomial
def SunsteadTarget : Prop :=
  ∀ {R : Type} [CommRing R] [IsGorensteinRing R],
    IsGorensteinRing R[X]
end TargetStmt

end Problem65

namespace Problem66

section TargetStmt
open RingTheory
def SunsteadTarget : Prop :=
  ∀ {R : Type} [CommRing R] [IsNoetherianRing R] (I : Ideal R) (rs : List R)
    (gen : I = Ideal.ofList rs) (h₂ : Sequence.IsRegular R rs),
    ∃ rs' : List R,
    I = Ideal.ofList rs' ∧ (∀ l : List R, (l.Perm rs') → Sequence.IsRegular R l)
end TargetStmt

end Problem66

namespace Problem67

section TargetStmt
open scoped TensorProduct
def SunsteadTarget : Prop :=
  ∀ {k : Type} [Field k] (n : ℕ) (hn : n ≠ 0),
    IsEmpty ((MvPowerSeries (Fin n) k) ⊗[k] (MvPowerSeries (Fin n) k) ≃ₐ[k]
    (MvPowerSeries (Fin (n + n)) k))
end TargetStmt

end Problem67

namespace Problem68

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] [IsLocalRing R]
    [IsNoetherianRing R] (f : R) (hf : f ∈ IsLocalRing.maximalIdeal R) (ne0 : ¬ IsNilpotent f),
    IsJacobsonRing (Localization.Away f)
end TargetStmt

end Problem68

namespace Problem69

open IsLocalRing Polynomial

/--
A commutative local noetherian ring $R$ is regular if $\dim m/m^2 = \dim R$.
-/
class IsRegularLocalRing (R : Type) [CommRing R] : Prop extends
    IsLocalRing R, IsNoetherianRing R where
  reg : Module.finrank (ResidueField R) (CotangentSpace R) = ringKrullDim R

section TargetStmt
open IsLocalRing Polynomial
def SunsteadTarget : Prop :=
  ∀ {R : Type} [CommRing R] [IsRegularLocalRing R]
    (P : Ideal R[X]) [P.IsPrime] [P.LiesOver (maximalIdeal R)],
    IsRegularLocalRing (Localization.AtPrime P)
end TargetStmt

end Problem69

namespace Problem70

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R S : Type) [CommRing R] [IsDomain R] [IsNoetherianRing R]
    [CommRing S] [IsNoetherianRing S] [IsLocalRing S] [Algebra R S] [NoZeroSMulDivisors R S],
    ∃ (p : minimalPrimes S), Ideal.comap (algebraMap R S) p.1 = ⊥
end TargetStmt

end Problem70

namespace Problem71

section

variable (A B : Type) [CommRing A] [CommRing B] [Algebra A B]
variable (G : Type) [Monoid G] [MulSemiringAction G B] [SMulCommClass G A B]

/--
The set of fixed points under a group action, as a subring.
-/
def FixedPoints.subring : Subring B where
  __ := FixedPoints.addSubgroup G B
  __ := FixedPoints.submonoid G B

/--
The set of fixed points under a group action, as a subalgebra.
-/
def FixedPoints.subalgebra : Subalgebra A B where
  __ := FixedPoints.addSubgroup G B
  __ := FixedPoints.submonoid G B
  algebraMap_mem' r := by simp

end

section

open CategoryTheory Abelian Problem71

variable {R : Type} [CommRing R]

instance : CategoryTheory.HasExt.{0} (ModuleCat.{0} R) :=
  CategoryTheory.hasExt_of_enoughProjectives (ModuleCat R)

noncomputable def moduleDepth (N M : ModuleCat.{0} R) : ℕ∞ :=
  sSup {n : ℕ∞ | ∀ i : ℕ, i < n → Subsingleton (CategoryTheory.Abelian.Ext.{0} N M i)}

noncomputable def Ideal.depth (I : Ideal R) (M : ModuleCat.{0} R) : ℕ∞ :=
  moduleDepth (ModuleCat.of R (R ⧸ I)) M

noncomputable def IsLocalRing.depth [IsLocalRing R] (M : ModuleCat.{0} R) : ℕ∞ :=
  (IsLocalRing.maximalIdeal R).depth M

variable (R)

class IsCohenMacaulayLocalRing : Prop extends IsLocalRing R where
  depth_eq_dim : ringKrullDim R = IsLocalRing.depth (ModuleCat.of R R)

class IsCohenMacaulayRing : Prop where
  CM_localize : ∀ p : Ideal R, ∀ (_ : p.IsPrime), IsCohenMacaulayLocalRing (Localization.AtPrime p)

end

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {R : Type} [CommRing R] (k : Type) [Field k]
    [CharZero k] [Algebra k R] [IsNoetherianRing R] [IsCohenMacaulayRing R]
    (G : Subgroup (R ≃ₐ[k] R)) [Finite G],
    IsCohenMacaulayRing (FixedPoints.subalgebra k R G)
end TargetStmt

end Problem71

namespace Problem72

/--
The krull dimension of module, defined as `krullDim` of its support.
-/
noncomputable def Module.supportDim (R : Type) [CommRing R] (M : Type) [AddCommGroup M]
    [Module R M] : WithBot ℕ∞ :=
  Order.krullDim (Module.support R M)

section

open CategoryTheory Abelian Problem72

variable {R : Type} [CommRing R]

instance : CategoryTheory.HasExt.{0} (ModuleCat.{0} R) :=
  CategoryTheory.hasExt_of_enoughProjectives (ModuleCat R)

noncomputable def moduleDepth (N M : ModuleCat.{0} R) : ℕ∞ :=
  sSup {n : ℕ∞ | ∀ i : ℕ, i < n → Subsingleton (CategoryTheory.Abelian.Ext.{0} N M i)}

noncomputable def Ideal.depth (I : Ideal R) (M : ModuleCat.{0} R) : ℕ∞ :=
  moduleDepth (ModuleCat.of R (R ⧸ I)) M

noncomputable def IsLocalRing.depth [IsLocalRing R] (M : ModuleCat.{0} R) : ℕ∞ :=
  (IsLocalRing.maximalIdeal R).depth M

class ModuleCat.IsCohenMacaulay [IsLocalRing R] (M : ModuleCat.{0} R) : Prop where
  depth_eq_dim : Subsingleton M ∨ Module.supportDim R M = IsLocalRing.depth M

variable (R)

class Module.IsCohenMacaulay (M : Type) [AddCommGroup M] [Module R M] : Prop where
  depth_eq_dim : ∀ p : Ideal R, ∀ (_ : p.IsPrime), (ModuleCat.of (Localization.AtPrime p)
    (LocalizedModule.AtPrime p M)).IsCohenMacaulay

end

open TensorProduct

noncomputable instance (R : Type) [CommRing R] (M : Type) [AddCommGroup M] [Module R M] (n : ℕ) :
    Module (MvPolynomial (Fin n) R) ((MvPolynomial (Fin n) R) ⊗[R] M) := leftModule

section TargetStmt
open TensorProduct
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] (M : Type) [AddCommGroup M] [Module R M]
    [IsNoetherianRing R] [Module.IsCohenMacaulay R M] (n : ℕ),
    Module.IsCohenMacaulay (MvPolynomial (Fin n) R) ((MvPolynomial (Fin n) R) ⊗[R] M)
end TargetStmt

end Problem72

namespace Problem74

open IsLocalRing ModuleCat CategoryTheory

instance (R : Type) [CommRing R] : CategoryTheory.HasExt.{0} (ModuleCat.{0} R) :=
  CategoryTheory.hasExt_of_enoughProjectives.{0} (ModuleCat.{0} R)

/--
A commutative local noetherian ring $R$ is regular if $\dim m/m^2 = \dim R$.
-/
class IsRegularLocalRing (R : Type) [CommRing R] : Prop extends
    IsLocalRing R, IsNoetherianRing R where
  reg : Module.finrank (ResidueField R) (CotangentSpace R) = ringKrullDim R

/--
A Noetherian local ring $R$ is a Gorenstein ring if $\mathrm{inj}.\dim_R R < +\infty$.
-/
class IsGorensteinLocalRing (R : Type) [CommRing R] : Prop extends
    IsLocalRing R, IsNoetherianRing R where
  injDim_le_infity :
    ∃ n : ℕ, ∀ i : ℕ, n ≤ i →
    Subsingleton (Abelian.Ext.{0} (of.{0} R (ResidueField R)) (of.{0} R R) i)

/--
A Noetherian ring is a Gorenstein ring if its localization at every maximal ideal is a
  Gorenstein local ring.
-/
class IsGorensteinRing (R : Type) [CommRing R] : Prop extends IsNoetherianRing R where
  localization_maximal_isGorensteinLocalRing :
    ∀ m : Ideal R, (_ : m.IsMaximal) → IsGorensteinLocalRing (Localization.AtPrime m)
variable {R : Type} [CommRing R]

section TargetStmt
open IsLocalRing ModuleCat CategoryTheory
def SunsteadTarget : Prop :=
  ∀ {R : Type} [CommRing R]
    [IsRegularLocalRing R] {rs : List R} (reg : RingTheory.Sequence.IsRegular R rs) (y : R)
    (h : y ∉ Ideal.ofList rs),
    IsGorensteinRing (R ⧸ (Ideal.ofList rs / Ideal.span {y}))
end TargetStmt

end Problem74

namespace Problem76

open List

/--
A ring $R$ is said to be \textit{catenary} if for any pair of prime ideals $\mathfrak{p} \subset
  \mathfrak{q}$, there exists an integer bounding the lengths of all finite chains of prime ideals
  $\mathfrak{p} = \mathfrak{p}_0 \subset \mathfrak{p}_1 \subset \dots \subset \mathfrak{p}_e =
  \mathfrak{q}$ and all maximal such chains have the same length.
-/
def IsCatenary (R : Type) [CommRing R] : Prop :=
  ∀ p q : PrimeSpectrum R, p ≤ q →
  ∃ n : ℕ, ∀ (l : LTSeries (PrimeSpectrum R)), l.head = p → l.last = q →
  (∀ l' : LTSeries (PrimeSpectrum R), l'.head = p → l'.last = q → l.toList <+ l'.toList → l' = l) →
  l.toList.length = n

section TargetStmt
open List
def SunsteadTarget : Prop :=
  ∀ {A : Type} [CommRing A] [IsNoetherianRing A]
    [IsDomain A] [UniqueFactorizationMonoid A] (h : ringKrullDim A ≤ 3),
    IsCatenary A
end TargetStmt

end Problem76

namespace Problem81

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] [IsLocalRing R]
    [IsNoetherianRing R] (I : Ideal R) (netop : I ≠ ⊤),
    ∃ (rs : List R), (RingTheory.Sequence.IsRegular R rs) ∧ Ideal.ofList rs = I ↔
    Module.Free (R ⧸ I) I.Cotangent ∧
    (∃ n, CategoryTheory.HasProjectiveDimensionLE (ModuleCat.of R I) n)
end TargetStmt

end Problem81

namespace Problem82

section TargetStmt
open IsLocalRing
def SunsteadTarget : Prop :=
  ∀ (d : ℕ) (A : Type) [CommRing A] [IsLocalRing A]
    [IsNoetherianRing A] [IsAdicComplete (maximalIdeal A) A] (dim : ringKrullDim A = d)
    {p : ℕ} (hp : p.Prime) [CharZero A] [CharP (ResidueField A) p]
    (ht : (Ideal.span {(p : A)}).height = 1),
    ∃ B : Subring A, Module.Finite B A ∧
    ∃ (C : Type) (_ : CommRing C) (_ : IsDomain C), IsDiscreteValuationRing C ∧
    Nonempty (B ≃+* MvPowerSeries (Fin (d - 1)) C)
end TargetStmt

end Problem82

namespace Problem83

open IsLocalRing

/--
A commutative local noetherian ring $R$ is regular if $\dim m/m^2 = \dim R$.
-/
class IsRegularLocalRing (R : Type) [CommRing R] : Prop extends
    IsLocalRing R, IsNoetherianRing R where
  reg : Module.finrank (ResidueField R) (CotangentSpace R) = ringKrullDim R

section TargetStmt
open IsLocalRing
def SunsteadTarget : Prop :=
  ∀ {A B : Type} [CommRing A] [CommRing B]
    [IsRegularLocalRing A] [IsNoetherianRing B] [IsLocalRing B] {f : A →+* B} (hfl : IsLocalHom f)
    (hff : f.Flat) [IsRegularLocalRing (B ⧸ (maximalIdeal A).map f)],
    IsRegularLocalRing B
end TargetStmt

end Problem83

namespace Problem84

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R M : Type) [CommRing R] [AddCommGroup M]
    [Module R M] [Module.Projective R M],
    ∃ (N : Type) (_ : AddCommGroup N) (_ : Module R N),
    Module.Free R N ∧ Module.Free R (N × M)
end TargetStmt

end Problem84

namespace Problem85

/--
Definition of a Euclidean norm taking value in \(\mathbb{N}\).
-/
class EuclideanNormNat (R : Type) [CommRing R] extends Nontrivial R where
  quotient : R → R → R
  quotient_zero : ∀ a, quotient a 0 = 0
  remainder : R → R → R
  quotient_mul_add_remainder_eq : ∀ a b, b * quotient a b + remainder a b = a
  norm : R → ℕ
  remainder_lt : ∀ (a) {b}, b ≠ 0 → norm (remainder a b) < norm b
  mul_left_not_lt : ∀ (a) {b}, b ≠ 0 → ¬ norm (a * b) < norm a

section TargetStmt
def SunsteadTarget : Prop :=
  ∃ (R : Type) (_ : EuclideanDomain R), IsEmpty (EuclideanNormNat R)
end TargetStmt

end Problem85

namespace Problem86

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (A : Type) [CommRing A],
    ringKrullDim (MvPolynomial (Fin 2) A) + ringKrullDim A ≤ 2 * ringKrullDim (Polynomial A)
end TargetStmt

end Problem86

namespace Problem87

section TargetStmt
def SunsteadTarget : Prop :=
  ∃ (R S : Type) (_ : CommRing R) (_ : CommRing S),
    Nonempty ((Polynomial R) ≃+* (Polynomial S)) ∧ IsEmpty (R ≃+* S)
end TargetStmt

end Problem87

