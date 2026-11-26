import ZkAddChain.Spec
import ZkAddChain.ChainBabyBearInv

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_babybear_inv_wf : wellFormedChain steps_babybear_inv = true := by
  decide +kernel

theorem chain_babybear_inv_len : steps_babybear_inv.length = score_babybear_inv := by
  decide +kernel

theorem chain_babybear_inv_eval : evalChain steps_babybear_inv = target_babybear_inv := by
  decide +kernel

theorem bound_babybear_inv : ValidAddChain target_babybear_inv score_babybear_inv :=
  ⟨steps_babybear_inv, chain_babybear_inv_wf, chain_babybear_inv_len, chain_babybear_inv_eval⟩

end ZkAddChain
