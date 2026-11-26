import LwcLinearXor.Spec
import LwcLinearXor.PyjamaskInvM3Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem pyjamaskInvM3_wf : wellFormedXor 32 pyjamaskInvM3Gates pyjamaskInvM3Outputs = true := by
  decide +kernel

theorem pyjamaskInvM3_len : pyjamaskInvM3Gates.length = pyjamaskInvM3Score := by
  decide +kernel

theorem pyjamaskInvM3_check : checkLinearCircuit 32 pyjamaskInvM3Rows pyjamaskInvM3Gates pyjamaskInvM3Outputs = true := by
  decide +kernel

theorem pyjamask_inv_m3_xor_bound : ValidXorCircuit 32 pyjamaskInvM3_32 pyjamaskInvM3Score :=
  ⟨pyjamaskInvM3Gates, pyjamaskInvM3Outputs, pyjamaskInvM3_wf, pyjamaskInvM3_len,
    evalXorCircuit_eq_pyjamaskInvM3_of_check pyjamaskInvM3Gates pyjamaskInvM3Outputs pyjamaskInvM3_check⟩

end LwcLinearXor
