import ZkAddChain.Spec
import ZkAddChain.ChainGoldilocksInv

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_goldilocks_inv_wf : wellFormedChain steps_goldilocks_inv = true := by
  decide +kernel

theorem chain_goldilocks_inv_len : steps_goldilocks_inv.length = score_goldilocks_inv := by
  decide +kernel

theorem chain_goldilocks_inv_eval : evalChain steps_goldilocks_inv = target_goldilocks_inv := by
  decide +kernel

theorem bound_goldilocks_inv : ValidAddChain target_goldilocks_inv score_goldilocks_inv :=
  ⟨steps_goldilocks_inv, chain_goldilocks_inv_wf, chain_goldilocks_inv_len, chain_goldilocks_inv_eval⟩

end ZkAddChain
