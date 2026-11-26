import LwcLinearXor.Spec
import LwcLinearXor.PyjamaskInvM2Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem pyjamaskInvM2_wf : wellFormedXor 32 pyjamaskInvM2Gates pyjamaskInvM2Outputs = true := by
  decide +kernel

theorem pyjamaskInvM2_len : pyjamaskInvM2Gates.length = pyjamaskInvM2Score := by
  decide +kernel

theorem pyjamaskInvM2_check : checkLinearCircuit 32 pyjamaskInvM2Rows pyjamaskInvM2Gates pyjamaskInvM2Outputs = true := by
  decide +kernel

theorem pyjamask_inv_m2_xor_bound : ValidXorCircuit 32 pyjamaskInvM2_32 pyjamaskInvM2Score :=
  ⟨pyjamaskInvM2Gates, pyjamaskInvM2Outputs, pyjamaskInvM2_wf, pyjamaskInvM2_len,
    evalXorCircuit_eq_pyjamaskInvM2_of_check pyjamaskInvM2Gates pyjamaskInvM2Outputs pyjamaskInvM2_check⟩

end LwcLinearXor
