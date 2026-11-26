import ZkAddChain.Spec
import ZkAddChain.ChainBn254InvD5

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_bn254_inv_d5_wf : wellFormedChain steps_bn254_inv_d5 = true := by
  decide +kernel

theorem chain_bn254_inv_d5_len : steps_bn254_inv_d5.length = score_bn254_inv_d5 := by
  decide +kernel

theorem chain_bn254_inv_d5_eval : evalChain steps_bn254_inv_d5 = target_bn254_inv_d5 := by
  decide +kernel

theorem bound_bn254_inv_d5 : ValidAddChain target_bn254_inv_d5 score_bn254_inv_d5 :=
  ⟨steps_bn254_inv_d5, chain_bn254_inv_d5_wf, chain_bn254_inv_d5_len, chain_bn254_inv_d5_eval⟩

end ZkAddChain
