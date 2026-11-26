import LwcLinearXor.Spec
import LwcLinearXor.PyjamaskMKCircuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem pyjamaskMK_wf : wellFormedXor 32 pyjamaskMKGates pyjamaskMKOutputs = true := by
  decide +kernel

theorem pyjamaskMK_len : pyjamaskMKGates.length = pyjamaskMKScore := by
  decide +kernel

theorem pyjamaskMK_check : checkLinearCircuit 32 pyjamaskMKRows pyjamaskMKGates pyjamaskMKOutputs = true := by
  decide +kernel

theorem pyjamask_mk_xor_bound : ValidXorCircuit 32 pyjamaskMK_32 pyjamaskMKScore :=
  ⟨pyjamaskMKGates, pyjamaskMKOutputs, pyjamaskMK_wf, pyjamaskMK_len,
    evalXorCircuit_eq_pyjamaskMK_of_check pyjamaskMKGates pyjamaskMKOutputs pyjamaskMK_check⟩

end LwcLinearXor
