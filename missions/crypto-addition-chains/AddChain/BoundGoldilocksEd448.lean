import AddChain.Spec
import AddChain.ChainGoldilocksEd448

namespace AddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_goldilocks_ed448_inv_wf : wellFormedChain steps_goldilocks_ed448_inv = true := by
  decide +kernel

theorem chain_goldilocks_ed448_inv_len : steps_goldilocks_ed448_inv.length = score_goldilocks_ed448_inv := by
  decide +kernel

theorem chain_goldilocks_ed448_inv_eval : evalChain steps_goldilocks_ed448_inv = target_goldilocks_ed448_inv := by
  decide +kernel

theorem bound_goldilocks_ed448_inv : ValidAddChain target_goldilocks_ed448_inv score_goldilocks_ed448_inv :=
  ⟨steps_goldilocks_ed448_inv, chain_goldilocks_ed448_inv_wf, chain_goldilocks_ed448_inv_len, chain_goldilocks_ed448_inv_eval⟩

end AddChain
