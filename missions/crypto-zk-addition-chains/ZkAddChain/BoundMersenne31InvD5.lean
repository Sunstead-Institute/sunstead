import ZkAddChain.Spec
import ZkAddChain.ChainMersenne31InvD5

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_mersenne31_inv_d5_wf : wellFormedChain steps_mersenne31_inv_d5 = true := by
  decide +kernel

theorem chain_mersenne31_inv_d5_len : steps_mersenne31_inv_d5.length = score_mersenne31_inv_d5 := by
  decide +kernel

theorem chain_mersenne31_inv_d5_eval : evalChain steps_mersenne31_inv_d5 = target_mersenne31_inv_d5 := by
  decide +kernel

theorem bound_mersenne31_inv_d5 : ValidAddChain target_mersenne31_inv_d5 score_mersenne31_inv_d5 :=
  ⟨steps_mersenne31_inv_d5, chain_mersenne31_inv_d5_wf, chain_mersenne31_inv_d5_len, chain_mersenne31_inv_d5_eval⟩

end ZkAddChain
