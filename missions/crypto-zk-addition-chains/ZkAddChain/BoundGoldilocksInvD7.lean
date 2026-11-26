import ZkAddChain.Spec
import ZkAddChain.ChainGoldilocksInvD7

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_goldilocks_inv_d7_wf : wellFormedChain steps_goldilocks_inv_d7 = true := by
  decide +kernel

theorem chain_goldilocks_inv_d7_len : steps_goldilocks_inv_d7.length = score_goldilocks_inv_d7 := by
  decide +kernel

theorem chain_goldilocks_inv_d7_eval : evalChain steps_goldilocks_inv_d7 = target_goldilocks_inv_d7 := by
  decide +kernel

theorem bound_goldilocks_inv_d7 : ValidAddChain target_goldilocks_inv_d7 score_goldilocks_inv_d7 :=
  ⟨steps_goldilocks_inv_d7, chain_goldilocks_inv_d7_wf, chain_goldilocks_inv_d7_len, chain_goldilocks_inv_d7_eval⟩

end ZkAddChain
