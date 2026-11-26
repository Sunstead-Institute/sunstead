import LwcLinearXor.Spec
import LwcLinearXor.PyjamaskInvM1Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem pyjamaskInvM1_wf : wellFormedXor 32 pyjamaskInvM1Gates pyjamaskInvM1Outputs = true := by
  decide +kernel

theorem pyjamaskInvM1_len : pyjamaskInvM1Gates.length = pyjamaskInvM1Score := by
  decide +kernel

theorem pyjamaskInvM1_check : checkLinearCircuit 32 pyjamaskInvM1Rows pyjamaskInvM1Gates pyjamaskInvM1Outputs = true := by
  decide +kernel

theorem pyjamask_inv_m1_xor_bound : ValidXorCircuit 32 pyjamaskInvM1_32 pyjamaskInvM1Score :=
  ⟨pyjamaskInvM1Gates, pyjamaskInvM1Outputs, pyjamaskInvM1_wf, pyjamaskInvM1_len,
    evalXorCircuit_eq_pyjamaskInvM1_of_check pyjamaskInvM1Gates pyjamaskInvM1Outputs pyjamaskInvM1_check⟩

end LwcLinearXor
