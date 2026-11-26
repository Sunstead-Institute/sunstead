import ZkAddChain.Spec
import ZkAddChain.ChainKoalaBearInv

namespace ZkAddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_koalabear_inv_wf : wellFormedChain steps_koalabear_inv = true := by
  decide +kernel

theorem chain_koalabear_inv_len : steps_koalabear_inv.length = score_koalabear_inv := by
  decide +kernel

theorem chain_koalabear_inv_eval : evalChain steps_koalabear_inv = target_koalabear_inv := by
  decide +kernel

theorem bound_koalabear_inv : ValidAddChain target_koalabear_inv score_koalabear_inv :=
  ⟨steps_koalabear_inv, chain_koalabear_inv_wf, chain_koalabear_inv_len, chain_koalabear_inv_eval⟩

end ZkAddChain
