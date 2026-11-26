import LwcLinearXor.Spec
import LwcLinearXor.PyjamaskM3Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem pyjamaskM3_wf : wellFormedXor 32 pyjamaskM3Gates pyjamaskM3Outputs = true := by
  decide +kernel

theorem pyjamaskM3_len : pyjamaskM3Gates.length = pyjamaskM3Score := by
  decide +kernel

theorem pyjamaskM3_check : checkLinearCircuit 32 pyjamaskM3Rows pyjamaskM3Gates pyjamaskM3Outputs = true := by
  decide +kernel

theorem pyjamask_m3_xor_bound : ValidXorCircuit 32 pyjamaskM3_32 pyjamaskM3Score :=
  ⟨pyjamaskM3Gates, pyjamaskM3Outputs, pyjamaskM3_wf, pyjamaskM3_len,
    evalXorCircuit_eq_pyjamaskM3_of_check pyjamaskM3Gates pyjamaskM3Outputs pyjamaskM3_check⟩

end LwcLinearXor
