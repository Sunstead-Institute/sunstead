import LwcLinearXor.Spec
import LwcLinearXor.PyjamaskM2Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem pyjamaskM2_wf : wellFormedXor 32 pyjamaskM2Gates pyjamaskM2Outputs = true := by
  decide +kernel

theorem pyjamaskM2_len : pyjamaskM2Gates.length = pyjamaskM2Score := by
  decide +kernel

theorem pyjamaskM2_check : checkLinearCircuit 32 pyjamaskM2Rows pyjamaskM2Gates pyjamaskM2Outputs = true := by
  decide +kernel

theorem pyjamask_m2_xor_bound : ValidXorCircuit 32 pyjamaskM2_32 pyjamaskM2Score :=
  ⟨pyjamaskM2Gates, pyjamaskM2Outputs, pyjamaskM2_wf, pyjamaskM2_len,
    evalXorCircuit_eq_pyjamaskM2_of_check pyjamaskM2Gates pyjamaskM2Outputs pyjamaskM2_check⟩

end LwcLinearXor
