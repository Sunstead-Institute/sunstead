import LwcLinearXor.Spec
import LwcLinearXor.PyjamaskM0Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem pyjamaskM0_wf : wellFormedXor 32 pyjamaskM0Gates pyjamaskM0Outputs = true := by
  decide +kernel

theorem pyjamaskM0_len : pyjamaskM0Gates.length = pyjamaskM0Score := by
  decide +kernel

theorem pyjamaskM0_check : checkLinearCircuit 32 pyjamaskM0Rows pyjamaskM0Gates pyjamaskM0Outputs = true := by
  decide +kernel

theorem pyjamask_m0_xor_bound : ValidXorCircuit 32 pyjamaskM0_32 pyjamaskM0Score :=
  ⟨pyjamaskM0Gates, pyjamaskM0Outputs, pyjamaskM0_wf, pyjamaskM0_len,
    evalXorCircuit_eq_pyjamaskM0_of_check pyjamaskM0Gates pyjamaskM0Outputs pyjamaskM0_check⟩

end LwcLinearXor
