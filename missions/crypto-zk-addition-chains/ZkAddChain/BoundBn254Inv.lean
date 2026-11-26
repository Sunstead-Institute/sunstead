import ZkAddChain.Spec
import ZkAddChain.ChainBn254Inv

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_bn254_inv_wf : wellFormedChain steps_bn254_inv = true := by
  decide +kernel

theorem chain_bn254_inv_len : steps_bn254_inv.length = score_bn254_inv := by
  decide +kernel

theorem chain_bn254_inv_eval : evalChain steps_bn254_inv = target_bn254_inv := by
  decide +kernel

theorem bound_bn254_inv : ValidAddChain target_bn254_inv score_bn254_inv :=
  ⟨steps_bn254_inv, chain_bn254_inv_wf, chain_bn254_inv_len, chain_bn254_inv_eval⟩

end ZkAddChain
