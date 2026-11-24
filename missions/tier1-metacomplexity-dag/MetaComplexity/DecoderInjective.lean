import MetaComplexity.Spec

namespace MetaComplexity

/-- TODO (Task: decoder_injective):
Prove that the encoder of any `LosslessCompressor` is injective.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem encode_injective_of_lossless {n k : Nat} (c : LosslessCompressor n k) :
    Injective c.encode := by
  sorry

end MetaComplexity
