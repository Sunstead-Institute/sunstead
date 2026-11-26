import ZkAddChain.Spec
import ZkAddChain.ChainMersenne31Inv

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_mersenne31_inv_wf : wellFormedChain steps_mersenne31_inv = true := by
  decide +kernel

theorem chain_mersenne31_inv_len : steps_mersenne31_inv.length = score_mersenne31_inv := by
  decide +kernel

theorem chain_mersenne31_inv_eval : evalChain steps_mersenne31_inv = target_mersenne31_inv := by
  decide +kernel

theorem bound_mersenne31_inv : ValidAddChain target_mersenne31_inv score_mersenne31_inv :=
  ⟨steps_mersenne31_inv, chain_mersenne31_inv_wf, chain_mersenne31_inv_len, chain_mersenne31_inv_eval⟩

end ZkAddChain
