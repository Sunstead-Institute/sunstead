import AddChain.Spec
import AddChain.ChainP384Scalar

namespace AddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_p384_scalar_inv_wf : wellFormedChain steps_p384_scalar_inv = true := by
  decide +kernel

theorem chain_p384_scalar_inv_len : steps_p384_scalar_inv.length = score_p384_scalar_inv := by
  decide +kernel

theorem chain_p384_scalar_inv_eval : evalChain steps_p384_scalar_inv = target_p384_scalar_inv := by
  decide +kernel

theorem bound_p384_scalar_inv : ValidAddChain target_p384_scalar_inv score_p384_scalar_inv :=
  ⟨steps_p384_scalar_inv, chain_p384_scalar_inv_wf, chain_p384_scalar_inv_len, chain_p384_scalar_inv_eval⟩

end AddChain
