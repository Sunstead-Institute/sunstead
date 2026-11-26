import AddChain.Spec
import AddChain.ChainCurve25519Scalar

namespace AddChain

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem chain_curve25519_scalar_inv_wf : wellFormedChain steps_curve25519_scalar_inv = true := by
  decide +kernel

theorem chain_curve25519_scalar_inv_len : steps_curve25519_scalar_inv.length = score_curve25519_scalar_inv := by
  decide +kernel

theorem chain_curve25519_scalar_inv_eval : evalChain steps_curve25519_scalar_inv = target_curve25519_scalar_inv := by
  decide +kernel

theorem bound_curve25519_scalar_inv : ValidAddChain target_curve25519_scalar_inv score_curve25519_scalar_inv :=
  ⟨steps_curve25519_scalar_inv, chain_curve25519_scalar_inv_wf, chain_curve25519_scalar_inv_len, chain_curve25519_scalar_inv_eval⟩

end AddChain
