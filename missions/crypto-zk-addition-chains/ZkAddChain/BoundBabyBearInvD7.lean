import ZkAddChain.Spec
import ZkAddChain.ChainBabyBearInvD7

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_babybear_inv_d7_wf : wellFormedChain steps_babybear_inv_d7 = true := by
  decide +kernel

theorem chain_babybear_inv_d7_len : steps_babybear_inv_d7.length = score_babybear_inv_d7 := by
  decide +kernel

theorem chain_babybear_inv_d7_eval : evalChain steps_babybear_inv_d7 = target_babybear_inv_d7 := by
  decide +kernel

theorem bound_babybear_inv_d7 : ValidAddChain target_babybear_inv_d7 score_babybear_inv_d7 :=
  ⟨steps_babybear_inv_d7, chain_babybear_inv_d7_wf, chain_babybear_inv_d7_len, chain_babybear_inv_d7_eval⟩

end ZkAddChain
