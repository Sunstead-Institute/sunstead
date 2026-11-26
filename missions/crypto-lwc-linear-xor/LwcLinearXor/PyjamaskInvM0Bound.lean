import LwcLinearXor.Spec
import LwcLinearXor.PyjamaskInvM0Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem pyjamaskInvM0_wf : wellFormedXor 32 pyjamaskInvM0Gates pyjamaskInvM0Outputs = true := by
  decide +kernel

theorem pyjamaskInvM0_len : pyjamaskInvM0Gates.length = pyjamaskInvM0Score := by
  decide +kernel

theorem pyjamaskInvM0_check : checkLinearCircuit 32 pyjamaskInvM0Rows pyjamaskInvM0Gates pyjamaskInvM0Outputs = true := by
  decide +kernel

theorem pyjamask_inv_m0_xor_bound : ValidXorCircuit 32 pyjamaskInvM0_32 pyjamaskInvM0Score :=
  ⟨pyjamaskInvM0Gates, pyjamaskInvM0Outputs, pyjamaskInvM0_wf, pyjamaskInvM0_len,
    evalXorCircuit_eq_pyjamaskInvM0_of_check pyjamaskInvM0Gates pyjamaskInvM0Outputs pyjamaskInvM0_check⟩

end LwcLinearXor
