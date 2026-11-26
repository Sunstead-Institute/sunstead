import LwcLinearXor.Spec
import LwcLinearXor.PyjamaskM1Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem pyjamaskM1_wf : wellFormedXor 32 pyjamaskM1Gates pyjamaskM1Outputs = true := by
  decide +kernel

theorem pyjamaskM1_len : pyjamaskM1Gates.length = pyjamaskM1Score := by
  decide +kernel

theorem pyjamaskM1_check : checkLinearCircuit 32 pyjamaskM1Rows pyjamaskM1Gates pyjamaskM1Outputs = true := by
  decide +kernel

theorem pyjamask_m1_xor_bound : ValidXorCircuit 32 pyjamaskM1_32 pyjamaskM1Score :=
  ⟨pyjamaskM1Gates, pyjamaskM1Outputs, pyjamaskM1_wf, pyjamaskM1_len,
    evalXorCircuit_eq_pyjamaskM1_of_check pyjamaskM1Gates pyjamaskM1Outputs pyjamaskM1_check⟩

end LwcLinearXor
