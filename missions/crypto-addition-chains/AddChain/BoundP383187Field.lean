import AddChain.Spec
import AddChain.ChainP383187Field

namespace AddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_p383187_field_inv_wf : wellFormedChain steps_p383187_field_inv = true := by
  decide +kernel

theorem chain_p383187_field_inv_len : steps_p383187_field_inv.length = score_p383187_field_inv := by
  decide +kernel

theorem chain_p383187_field_inv_eval : evalChain steps_p383187_field_inv = target_p383187_field_inv := by
  decide +kernel

theorem bound_p383187_field_inv : ValidAddChain target_p383187_field_inv score_p383187_field_inv :=
  ⟨steps_p383187_field_inv, chain_p383187_field_inv_wf, chain_p383187_field_inv_len, chain_p383187_field_inv_eval⟩

end AddChain
