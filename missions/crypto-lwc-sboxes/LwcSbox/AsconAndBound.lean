import LwcSbox.Spec
import LwcSbox.AsconAndCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem asconAnd_wf : wellFormed 5 asconAndGates asconAndOutputs = true := by
  decide +kernel

theorem asconAnd_metric : andCount asconAndGates = asconAndScore := by
  decide +kernel

theorem asconAnd_check : checkCircuitBV 5 initRevBV5 asconTable asconAndGates asconAndOutputs = true := by
  decide +kernel

theorem ascon_and_gates_bound : ValidAndCircuit 5 asconSbox asconAndScore :=
  ⟨asconAndGates, asconAndOutputs, asconAnd_wf, asconAnd_metric,
    evalCircuit_eq_of_checkCircuitBV 5 initRevBV5 asconTable asconSbox
      initRevBV5_ok asconTable_ok asconAndGates asconAndOutputs asconAnd_check⟩

end LwcSbox
