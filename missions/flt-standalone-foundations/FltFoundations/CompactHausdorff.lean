import FltFoundations.Spec

section CompactHausdorff

/-- A connected compact Hausdorff vector space over `𝔽_p` is trivial. -/
@[to_additive]
theorem Group.subsingleton_of_pow_prime_eq_one
    (A : Type*) [CommGroup A] [TopologicalSpace A] [IsTopologicalGroup A]
    [ConnectedSpace A] [CompactSpace A] [T2Space A]
    (p : ℕ) (hp : p.Prime) (hAp : ∀ a : A, a ^ p = 1) :
    Subsingleton A := by
  sorry

end CompactHausdorff
