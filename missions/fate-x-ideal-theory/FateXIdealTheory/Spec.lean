import Mathlib

set_option linter.unusedVariables false

/-!
Frozen verbatim upstream definitions and target propositions for `fate-x-ideal-theory`
(`frenzymath/FATE-X@a6fb49ee85fd`).
-/

namespace Problem12

section TargetStmt
def SunsteadTarget : Prop :=
  IsPrincipalIdealRing (Algebra.adjoin ℤ {(1 + (Real.sqrt 19) * Complex.I) / 2}) ∧ IsDomain (Algebra.adjoin ℤ {(1 + (Real.sqrt 19) * Complex.I) / 2})
end TargetStmt

end Problem12

namespace Problem25

section TargetStmt
def SunsteadTarget : Prop :=
  Nonempty ((RatFunc (ZMod 2) ≃+* RatFunc (ZMod 2)) ≃* (Equiv.Perm (Fin 3))) ∧
    IntermediateField.fixedField (F := ZMod 2) (E := RatFunc (ZMod 2)) ⊤ =
    IntermediateField.adjoin (ZMod 2) {((.X ^ 4 - .X) ^ 3 / (.X ^ 2 - .X) ^ 5 : (RatFunc (ZMod 2)))}
end TargetStmt

end Problem25

namespace Problem26

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (K : Type) [Field K] [Algebra ℚ K] [Module.Finite ℚ K]
    (H : Subgroup (Field.absoluteGaloisGroup K))
    (h_closed : IsClosed (H : Set (Field.absoluteGaloisGroup K)))
    (h_fin : Finite H),
    Nat.card H = 1 ∨ Nat.card H = 2
end TargetStmt

end Problem26

namespace Problem27

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (p : ℕ) (hp : p.Prime) {K : Type} [Field K]
    [NumberField K] {ζ : K} (h : IsPrimitiveRoot ζ (p^2))
    {L : IntermediateField K (AlgebraicClosure K)} [IsGalois K L]
    (hdeg : Module.rank K L = p),
    ∃ (L' : Type) (_ : Field L') (_ : Algebra K L')
    (_ : Algebra L L') (_ : IsScalarTower K L L'),
    IsGalois K L' ∧ IsGalois L L' ∧ Module.rank L L' = p
end TargetStmt

end Problem27

namespace Problem28

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (K : Type)
    [Field K] [Algebra ℚ K] [Module.Finite ℚ K] (g : Field.absoluteGaloisGroup K) (h : g ≠ 1),
    {g' : Field.absoluteGaloisGroup K | IsConj g g'}.Infinite
end TargetStmt

end Problem28

namespace Problem29

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (K : Type)
    [Field K] [Algebra ℚ K] [Module.Finite ℚ K] (g : Field.absoluteGaloisGroup K),
    IsClosed ((Subgroup.zpowers g) : Set (Field.absoluteGaloisGroup K)) ↔ IsOfFinOrder g
end TargetStmt

end Problem29

namespace Problem30

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (B : Type) [CommRing B] (A : Subring B)
    (h : ∀ (x y : B), x ∉ A → y ∉ A → x * y ∉ A),
    IsIntegrallyClosedIn A B
end TargetStmt

end Problem30

namespace Problem31

open MvPolynomial

/--
Let \( R = \mathbb{C}[x_1, \dots, x_n]/(x_1^2 + x_2^2 + \dots + x_n^2) \).
-/
abbrev R (n : ℕ) : Type :=
  MvPolynomial (Fin n) ℂ ⧸ Ideal.span {(∑ i : Fin n, X i ^ 2 : MvPolynomial (Fin n) ℂ)}

section TargetStmt
open MvPolynomial
def SunsteadTarget : Prop :=
  ∀ (n : ℕ) (h : n ≥ 5),
    ∃ (h : IsDomain (R n)), UniqueFactorizationMonoid (R n)
end TargetStmt

end Problem31

namespace Problem32

section TargetStmt
open IsLocalRing
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] [IsLocalRing R] [IsNoetherianRing R]
    [IsDomain (AdicCompletion (maximalIdeal R) R)]
    [UniqueFactorizationMonoid (AdicCompletion (maximalIdeal R) R)],
    ∃ (h : IsDomain R), UniqueFactorizationMonoid R
end TargetStmt

end Problem32

namespace Problem34

section TargetStmt
open PowerSeries
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R]
    [IsDomain R] [ValuationRing R] (two_lt : 2 ≤ ringKrullDim R),
    ¬ (IsIntegrallyClosed R⟦X⟧)
end TargetStmt

end Problem34

namespace Problem35

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R]
    (h_fg : ∀ (p : Ideal R), p.IsPrime → p.FG),
    IsNoetherianRing R
end TargetStmt

end Problem35

namespace Problem36

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R]
    [IsNoetherianRing R] (M N : Type) [AddCommGroup M] [AddCommGroup N] [Module R M] [Module R N]
    [Module.Finite R M] [Module.Finite R N],
    associatedPrimes R (M →ₗ[R] N) =
    {p | p ∈ associatedPrimes R N ∧ Module.annihilator R M ≤ p}
end TargetStmt

end Problem36

namespace Problem37

/--
Let $R=\mathbb{C}[x_{11},x_{12},\dots,x_{1n},x_{21},x_{22},\dots,
x_{2n},\dots,x_{n1},x_{n2},\dots,x_{nn}]/(\det(x_{ij})-1)$.
-/
abbrev QuotDetSubOne (n : ℕ) : Type := MvPolynomial ((Fin n) × (Fin n)) ℂ ⧸ Ideal.span {
      Matrix.det (fun (i : Fin n) ↦ (fun (j : Fin n) ↦ (.X ⟨i, j⟩ : (MvPolynomial ((Fin n) × (Fin n)) ℂ)))) - .C 1}

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (n : ℕ) (h : n ≥ 1),
    ∃ (h : IsDomain (QuotDetSubOne n)),
    UniqueFactorizationMonoid (QuotDetSubOne n)
end TargetStmt

end Problem37

namespace Problem42

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (k : Type) [Field k]
    (g : MvPowerSeries (Fin 2) k) (hg : g - .X 0 * .X 1 ∈ (Ideal.span {MvPowerSeries.X 0, .X 1}) ^ 3),
    Nonempty (((MvPowerSeries (Fin 2) k) ⧸ Ideal.span {(.X 0 * .X 1 : (MvPowerSeries (Fin 2) k))}) ≃+*
    ((MvPowerSeries (Fin 2) k) ⧸ Ideal.span {g}))
end TargetStmt

end Problem42

namespace Problem43

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
  ∀ {A : Type} [CommRing A] [IsNoetherianRing A]
    [IsLocalRing A] [IsReduced A] (p : ℕ) [Fact p.Prime] [CharP A p],
    (frobenius A p).Flat ↔ IsRegularLocalRing A
end TargetStmt

end Problem43

namespace Problem46

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] (M : Type) [AddCommGroup M] [Module R M],
    Module.Flat R M ↔
    ∀ P : Type, ∀ (_ : AddCommGroup P), ∀ (_ : Module R P), ∀ f : P →ₗ[R] M, Module.FinitePresentation R P →
      ∃ (F : Type) (_ : AddCommGroup F) (_ : Module R F), Module.Finite R F ∧ Module.Free R F ∧
      ∃ h : P →ₗ[R] F, ∃ g : F →ₗ[R] M, f = g.comp h
end TargetStmt

end Problem46

namespace Problem49

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (A : Type) [CommRing A],
    (∀ I : Ideal A, I.IsPrincipal → I ^ 2 = I) ↔
    (∀ I : Ideal A, I.FG → (∃ J : Ideal A, I ⊔ J = ⊤ ∧ I ⊓ J = ⊥ ))
end TargetStmt

end Problem49

namespace Problem50

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] [IsLocalRing R] [IsAdicComplete (IsLocalRing.maximalIdeal R) R]
    (k : Type) [Field k] [Algebra k R] [NoZeroSMulDivisors k R]
    (hfg : (IsLocalRing.maximalIdeal R).FG),
    IsNoetherianRing R
end TargetStmt

end Problem50

namespace Problem53

open IsLocalRing ModuleCat CategoryTheory MvPolynomial

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
open IsLocalRing ModuleCat CategoryTheory MvPolynomial
def SunsteadTarget : Prop :=
  ∀ (k : Type) [Field k],
    IsGorensteinRing <| MvPolynomial (Fin 3) k ⧸ Ideal.span ({(X 0)^ 2 - (X 1)^2, (X 1)^2 - (X 2)^2,
    (X 0) * (X 1), (X 1) * (X 2), (X 2) * (X 0)} : Set (MvPolynomial (Fin 3) k))
end TargetStmt

end Problem53

namespace Problem55

/--
A module \( M \) over a ring \( R \) is \textit{stably free} if there exists a free finitely
generated module \( F \) over \( R \) such that
\[
M \oplus F
\]
is a free module.
-/
def IsStablyFree (R : Type) (M : Type) [CommRing R] [AddCommGroup M] [Module R M] : Prop :=
    ∃ (N : Type) (_ : AddCommGroup N) (_ : Module R N),
    Module.Finite R N ∧ Module.Free R N ∧ Module.Free R (M × N)

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) (M : Type) [CommRing R] [AddCommGroup M]
    [Module R M] (h : ¬ Module.Finite R M),
    Module.Free R M ↔ IsStablyFree R M
end TargetStmt

end Problem55

namespace Problem57

/--
Let \( A \) be a domain and \( K \) its field of fractions.
\( x \in K \) is called almost integral if there exists an element \( r\in A, r \ne 0 \)
such that \( rx^n \in A \) for all \( n \ge 0 \).
-/
def IsAlmostIntegral {A : Type} [CommRing A] [IsDomain A] (x : FractionRing A) : Prop :=
  ∃ r : A, r ≠ 0 ∧ ∀ n : ℕ, ∃ y : A, r • (x ^ n) = algebraMap A (FractionRing A) y

/--
\( A \) is called \textit{completely integrally closed} if every almost integral element
of \( K \) is contained in \( A \).
-/
def IsCompletelyIntegrallyClosed (A : Type) [CommRing A] [IsDomain A] : Prop :=
  ∀ x : FractionRing A, IsAlmostIntegral x → ∃ y : A, x = algebraMap A (FractionRing A) y

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {A : Type} [CommRing A] [IsDomain A]
    (h : IsCompletelyIntegrallyClosed A),
    IsCompletelyIntegrallyClosed (Polynomial A)
end TargetStmt

end Problem57

namespace Problem62

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R S : Type) [CommRing R] [CommRing S]
    [Algebra R S] [Algebra.Smooth R S] (σ : S →+* R)
    (h : Function.LeftInverse σ (algebraMap R S)) (hf : Module.Free R (RingHom.ker σ).Cotangent),
    ∃ d : ℕ, Nonempty (AdicCompletion (RingHom.ker σ) S ≃ₐ[R] MvPowerSeries (Fin d) R)
end TargetStmt

end Problem62

namespace Problem63

/--
The universal property:
Given any commutative diagram
\[
\begin{tikzcd}
S \arrow[r, "a"] & A/I \\
R \arrow[u] \arrow[r, "b"] & A \arrow[u]
\end{tikzcd}
\]
where \( I \subset A \) is an ideal of square zero, there is a unique \( R \)-algebra map
\( \alpha': S' \to A \) such that \( S' \to A \to A/I \) is equal to \( S' \to S \to A/I \).
-/
def UniversalProperty.liftOfSqZeroIdeal {R S S' : Type} [CommRing R] [CommRing S] [CommRing S']
    [Algebra R S] [Algebra R S'] (f : S' →ₐ[R] S) :=
  ∀ (A : Type) [CommRing A] [Algebra R A] (I : Ideal A) (g : S →ₐ[R] A⧸I),
  I^2 = 0 → (g.toRingHom.comp (algebraMap R S) = (Ideal.Quotient.mk I).comp (algebraMap R A)) →
  ∃! (g' : S' →ₐ[R] A), (Ideal.Quotient.mk I).comp g'.toRingHom  = g.comp f

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R S : Type) [CommRing R] [CommRing S]
    [Algebra R S] [Algebra.FormallyUnramified R S],
    ∃ (S' : Type) (_ : CommRing S') (_ : Algebra R S') (f : S' →ₐ[R] S), (RingHom.ker f) ^ 2 = 0 ∧ UniversalProperty.liftOfSqZeroIdeal f
end TargetStmt

end Problem63

namespace Problem73

section

open CategoryTheory Abelian Problem73

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

attribute [local instance] MvPolynomial.gradedAlgebra

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (k : Type) [Field k] (n : ℕ)
    (R : Type) [CommRing R] (f : (MvPolynomial (Fin n) k) →+* R) (surj : Function.Surjective f)
    (homo : (RingHom.ker f).IsHomogeneous (MvPolynomial.homogeneousSubmodule (Fin n) k))
    (le : RingHom.ker f ≤ RingHom.ker MvPolynomial.constantCoeff),
    IsCohenMacaulayRing R ↔
    IsCohenMacaulayRing (Localization.AtPrime ((RingHom.ker MvPolynomial.constantCoeff).map f)
      (hp := Ideal.map_isPrime_of_surjective surj le (H := RingHom.ker_isPrime _)))
end TargetStmt

end Problem73

namespace Problem75

open IsLocalRing ModuleCat CategoryTheory Problem75

section

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
open IsLocalRing ModuleCat CategoryTheory Problem75
def SunsteadTarget : Prop :=
  ∀ {A : Type} [CommRing A] [IsNoetherianRing A]
    (𝒜 : ℕ → Submodule ℤ A) [GradedAlgebra 𝒜] (h : IsField (𝒜 0)) (h1 : Algebra.adjoin (𝒜 0) (𝒜 1) = (⊤ : Subalgebra (𝒜 0) A)),
    IsCohenMacaulayRing A ↔
    ∀ p : Ideal A, (_ : p.IsPrime) → p.IsHomogeneous 𝒜 →
    IsCohenMacaulayLocalRing (HomogeneousLocalization.AtPrime 𝒜 p)
end TargetStmt

end Problem75

namespace Problem77

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (R : Type) [CommRing R] [IsNoetherianRing R] (P Q : Ideal R)
    (le : P ≤ Q) [P.IsPrime] [Q.IsPrime] (h d : ℕ) (lt : 1 < d) (ht1 : P.height = h)
    (ht2 : (Q.map (Ideal.Quotient.mk P)).height = d),
    {P' : Ideal R | P ≤ P' ∧ P' ≤ Q ∧ P'.IsPrime ∧ P'.height = h + 1 ∧
      (Q.map (Ideal.Quotient.mk P')).height = d - 1}.Infinite
end TargetStmt

end Problem77

namespace Problem78

open IsLocalRing ModuleCat CategoryTheory Problem78

section

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

section TargetStmt
open IsLocalRing ModuleCat CategoryTheory Problem78
def SunsteadTarget : Prop :=
  ∀ {A B : Type} [CommRing A]
    [IsCohenMacaulayLocalRing A] [IsDomain A] [UniqueFactorizationMonoid A] [CommRing B]
    [IsRegularLocalRing B] {f : B →+* A} (hf : Function.Surjective f),
    IsGorensteinRing A
end TargetStmt

end Problem78

namespace Problem88

/--
The ring $R = \mathbb{C}[x, y, z] / (x^2 + y^3 + z^7)$.
-/
abbrev R : Type := (MvPolynomial (Fin 3) ℂ) ⧸ Ideal.span {(.X 0 ^ 2 + .X 1 ^ 3 + .X 2 ^ 7 : MvPolynomial (Fin 3) ℂ)}

section TargetStmt
def SunsteadTarget : Prop :=
  ∃ (h : IsDomain R),
    (UniqueFactorizationMonoid R)
end TargetStmt

end Problem88

namespace Problem89

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (G : Type) [Group G]
    [Finite G] (h_card : Nat.card G = 336),
    ¬ IsSimpleGroup G
end TargetStmt

end Problem89

namespace Problem90

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ (k : Type) [Field k],
    ∃ (n : ℕ) (K : IntermediateField k (FractionRing (MvPolynomial (Fin n) k))),
    ¬ Algebra.FiniteType k (K.toSubalgebra ⊓ (Algebra.algHom k (MvPolynomial (Fin n) k)
    (FractionRing (MvPolynomial (Fin n) k))).range :
    Subalgebra k (FractionRing (MvPolynomial (Fin n) k)))
end TargetStmt

end Problem90

namespace Problem91

open CategoryTheory MvPolynomial

/--
The Picard group of a commutative ring R consists of the invertible R-modules,
  up to isomorphism.
-/
abbrev CommRing.Pic (R : Type) [CommRing R] : Type 1 := (Skeleton <| ModuleCat.{0} R)ˣ

section TargetStmt
open CategoryTheory MvPolynomial
def SunsteadTarget : Prop :=
  ∀ {k : Type} [Field k],
    Nonempty <|
    CommRing.Pic (MvPolynomial (Fin 2) k ⧸ Ideal.span ({(X 0) * (X 1) * (X 0 + X 1 - 1)} :
    Set (MvPolynomial (Fin 2) k))) ≃* kˣ
end TargetStmt

end Problem91

namespace Problem92

/--
\(a_n = 2n+1\) if \(n \le k\) else \(a_n = n + k + 1\), for some \(k \in \mathbb{N} \{+\infty\}\).
-/
def a (k : ℕ∞) (n : ℕ) :=
  if h : n ≤ k then 2 * n + 1
  else n + WithTop.untop k (by rintro rfl; exact h le_top) + 1

section TargetStmt
def SunsteadTarget : Prop :=
  (∀ (A : Type) [CommRing A] (h : ringKrullDim A = 1),
      ∃ (k : ℕ∞), (∀ (n : ℕ), ringKrullDim (MvPolynomial (Fin n) A) = a k n)) ∧
    (∀ (k : ℕ), ∃ (A : Type) (_ : CommRing A) (h : ringKrullDim A = 1),
      (∀ (n : ℕ), ringKrullDim (MvPolynomial (Fin n) A) = a k n))
end TargetStmt

end Problem92

namespace Problem93

section TargetStmt
def SunsteadTarget : Prop :=
  ∃ (k A : Type) (_ : Field k)
    (_ : Ring A) (_ : Algebra k A),
    Algebra.IsIntegral k A ∧ Algebra.FiniteType k A ∧ ¬ FiniteDimensional k A
end TargetStmt

end Problem93

namespace Problem94

variable {k A : Type} [Field k] [CharZero k] [CommRing A] [IsDomain A] [Algebra k A]
  [Algebra.FiniteType k A] (f : A →ₐ[k] A) (ϕ : A →ₐ[k] k) (I : Ideal A)

/--
The set $\{ n \in \mathbb{N} \mid \left. \varphi \circ f^n \right|_I = 0 \right\rbrace \}$.
-/
def zeroSet : Set ℕ := {n | ∀ x : I, (ϕ.comp (f ^ n)) (x : A) = 0}

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {k A : Type} [Field k] [CharZero k] [CommRing A] [IsDomain A] [Algebra k A] [Algebra.FiniteType k A] (f : A →ₐ[k] A) (ϕ : A →ₐ[k] k) (I : Ideal A) (hf : f.FormallyEtale),
    (zeroSet f ϕ I).Finite ∨ ∃ (d : ℕ+) (a : ℕ), ∀ n : ℕ, a + d * n ∈ zeroSet f ϕ I
end TargetStmt

end Problem94

namespace Problem95

open Polynomial Bivariate

/--
Let $f : \mathbb{C}[x, y] \to \mathbb{C}[x, y]$, $x \mapsto p(x) + ay, y \mapsto x$,
where $a \in \mathbb{C}$, $p(x) \in \mathbb{C}[x]$.
-/
noncomputable
def f (a : ℂ) (p : ℂ[X]): ℂ[X][Y] →+* ℂ[X][Y] :=
  eval₂RingHom (aeval (a • Y + C p)).toRingHom (C X)

section TargetStmt
open Polynomial Bivariate
def SunsteadTarget : Prop :=
  ∀ (p : ℂ[X]) (h : p.natDegree > 1) {a : ℂ} (ha : a ≠ 0)
    (𝔭 : Ideal ℂ[X][Y]) (h𝔭 : 𝔭.IsPrime) (h : 𝔭.height = 1),
    𝔭.map (f a p) ≠ 𝔭
end TargetStmt

end Problem95

namespace Problem96

section TargetStmt
open RatFunc
def SunsteadTarget : Prop :=
  ∀ {f : RatFunc ℚ} (hf : f.num.natDegree ≥ 2 ∨ f.denom.natDegree ≥ 2) {a : ℚ}
    (h : ∀ n : ℕ, (f.eval (RingHom.id ℚ))^[n] a ≠ 0) -- exclude the case that the `denom` is zero
    (ha : {m : ℤ | ∃ n : ℕ, m = (f.eval (RingHom.id ℚ))^[n] a}.Infinite),
    ∃ g : Polynomial ℚ, g = f.eval C f
end TargetStmt

end Problem96

namespace Problem97

section TargetStmt
open scoped Polynomial
def SunsteadTarget : Prop :=
  ∀ {τ k : Type} [Finite τ] [Nonempty τ] [Field k] [CharZero k]
    {f : τ → k[X]} (hfd : ∀ i : τ, (f i).natDegree ≥ 2),
    ∃ a : τ → k,
    ∀ p : MvPolynomial τ k, p ≠ 0 →
    ∃ m : ℕ, (((MvPolynomial.aeval (fun i ↦ (f i).toMvPolynomial i)) ^ m) p).aeval a ≠ 0
end TargetStmt

end Problem97

namespace Problem98

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {K A : Type} [Field K] [NumberField K] [CommRing A]
    [IsDomain A] [Algebra K A] [Algebra.FiniteType K A] {f : A →ₐ[K] A} (hf : ∀ n > 0, f ^ n ≠ 1),
    ∃ m : Ideal A, m.IsMaximal ∧ ∀ n > 0, m.comap (f ^ n) ≠ m
end TargetStmt

end Problem98

namespace Problem99

section TargetStmt
def SunsteadTarget : Prop :=
  ∀ {A : Type} [CommRing A] [IsDomain A] [Algebra ℂ A]
    [Algebra.FiniteType ℂ A] {n : ℕ} (hn : n ≥ 1)
    (e : (A ≃ₐ[ℂ] A) ≃* (MvPolynomial (Fin n) ℂ ≃ₐ[ℂ] MvPolynomial (Fin n) ℂ)),
    Nonempty (A ≃ₐ[ℂ] MvPolynomial (Fin n) ℂ)
end TargetStmt

end Problem99

namespace Problem100

section TargetStmt
open Module
def SunsteadTarget : Prop :=
  ∀ {R : Type} [CommRing R]
    [IsNoetherianRing R] (P : Type) [AddCommGroup P] [Module R P] [Projective R P]
    (hcg : ∃ s : Set P, s.Countable ∧ Submodule.span R s = ⊤)
    (hm : ∀ m : Ideal R, (_ : m.IsMaximal) →
      ¬ Module.Finite (Localization.AtPrime m) (LocalizedModule.AtPrime m P)),
    Free R P
end TargetStmt

end Problem100

