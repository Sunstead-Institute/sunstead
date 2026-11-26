import AddChain.Spec
import AddChain.ChainSecp192k1Field

namespace AddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_secp192k1_field_inv_wf : wellFormedChain steps_secp192k1_field_inv = true := by
  decide +kernel

theorem chain_secp192k1_field_inv_len : steps_secp192k1_field_inv.length = score_secp192k1_field_inv := by
  decide +kernel

theorem chain_secp192k1_field_inv_eval : evalChain steps_secp192k1_field_inv = target_secp192k1_field_inv := by
  decide +kernel

theorem bound_secp192k1_field_inv : ValidAddChain target_secp192k1_field_inv score_secp192k1_field_inv :=
  ⟨steps_secp192k1_field_inv, chain_secp192k1_field_inv_wf, chain_secp192k1_field_inv_len, chain_secp192k1_field_inv_eval⟩

end AddChain
