import AddChain.Spec
import AddChain.ChainSecp256k1Scalar

namespace AddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_secp256k1_scalar_inv_wf : wellFormedChain steps_secp256k1_scalar_inv = true := by
  decide +kernel

theorem chain_secp256k1_scalar_inv_len : steps_secp256k1_scalar_inv.length = score_secp256k1_scalar_inv := by
  decide +kernel

theorem chain_secp256k1_scalar_inv_eval : evalChain steps_secp256k1_scalar_inv = target_secp256k1_scalar_inv := by
  decide +kernel

theorem bound_secp256k1_scalar_inv : ValidAddChain target_secp256k1_scalar_inv score_secp256k1_scalar_inv :=
  ⟨steps_secp256k1_scalar_inv, chain_secp256k1_scalar_inv_wf, chain_secp256k1_scalar_inv_len, chain_secp256k1_scalar_inv_eval⟩

end AddChain
