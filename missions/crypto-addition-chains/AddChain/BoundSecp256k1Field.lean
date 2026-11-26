import AddChain.Spec
import AddChain.ChainSecp256k1Field

namespace AddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_secp256k1_field_inv_wf : wellFormedChain steps_secp256k1_field_inv = true := by
  decide +kernel

theorem chain_secp256k1_field_inv_len : steps_secp256k1_field_inv.length = score_secp256k1_field_inv := by
  decide +kernel

theorem chain_secp256k1_field_inv_eval : evalChain steps_secp256k1_field_inv = target_secp256k1_field_inv := by
  decide +kernel

theorem bound_secp256k1_field_inv : ValidAddChain target_secp256k1_field_inv score_secp256k1_field_inv :=
  ⟨steps_secp256k1_field_inv, chain_secp256k1_field_inv_wf, chain_secp256k1_field_inv_len, chain_secp256k1_field_inv_eval⟩

end AddChain
