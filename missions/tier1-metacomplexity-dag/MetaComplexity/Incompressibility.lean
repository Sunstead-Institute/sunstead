import MetaComplexity.Spec
import MetaComplexity.Pigeonhole
import MetaComplexity.DecoderInjective

namespace MetaComplexity

/-- TODO (Task: incompressibility_theorem):
Combine `no_inj_lt` and `encode_injective_of_lossless` to prove that for `k < n`,
no lossless compressor maps all `2 ^ n` strings into `2 ^ k` descriptions.
Must compile with 0 `sorry` and 0 custom axioms.
-/
theorem no_universal_lossless_compressor {n k : Nat} (hk : k < n)
    (c : LosslessCompressor n k) : False := by
  sorry

end MetaComplexity
