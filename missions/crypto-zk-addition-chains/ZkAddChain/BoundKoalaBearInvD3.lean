import ZkAddChain.Spec
import ZkAddChain.ChainKoalaBearInvD3

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_koalabear_inv_d3_wf : wellFormedChain steps_koalabear_inv_d3 = true := by
  decide +kernel

theorem chain_koalabear_inv_d3_len : steps_koalabear_inv_d3.length = score_koalabear_inv_d3 := by
  decide +kernel

theorem chain_koalabear_inv_d3_eval : evalChain steps_koalabear_inv_d3 = target_koalabear_inv_d3 := by
  decide +kernel

theorem bound_koalabear_inv_d3 : ValidAddChain target_koalabear_inv_d3 score_koalabear_inv_d3 :=
  ⟨steps_koalabear_inv_d3, chain_koalabear_inv_d3_wf, chain_koalabear_inv_d3_len, chain_koalabear_inv_d3_eval⟩

end ZkAddChain
