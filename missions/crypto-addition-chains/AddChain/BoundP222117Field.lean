import AddChain.Spec
import AddChain.ChainP222117Field

namespace AddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_p222117_field_inv_wf : wellFormedChain steps_p222117_field_inv = true := by
  decide +kernel

theorem chain_p222117_field_inv_len : steps_p222117_field_inv.length = score_p222117_field_inv := by
  decide +kernel

theorem chain_p222117_field_inv_eval : evalChain steps_p222117_field_inv = target_p222117_field_inv := by
  decide +kernel

theorem bound_p222117_field_inv : ValidAddChain target_p222117_field_inv score_p222117_field_inv :=
  ⟨steps_p222117_field_inv, chain_p222117_field_inv_wf, chain_p222117_field_inv_len, chain_p222117_field_inv_eval⟩

end AddChain
