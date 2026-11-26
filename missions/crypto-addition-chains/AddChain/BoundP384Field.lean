import AddChain.Spec
import AddChain.ChainP384Field

namespace AddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_p384_field_inv_wf : wellFormedChain steps_p384_field_inv = true := by
  decide +kernel

theorem chain_p384_field_inv_len : steps_p384_field_inv.length = score_p384_field_inv := by
  decide +kernel

theorem chain_p384_field_inv_eval : evalChain steps_p384_field_inv = target_p384_field_inv := by
  decide +kernel

theorem bound_p384_field_inv : ValidAddChain target_p384_field_inv score_p384_field_inv :=
  ⟨steps_p384_field_inv, chain_p384_field_inv_wf, chain_p384_field_inv_len, chain_p384_field_inv_eval⟩

end AddChain
