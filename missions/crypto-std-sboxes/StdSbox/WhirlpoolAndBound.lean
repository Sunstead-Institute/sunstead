import StdSbox.Spec
import StdSbox.WhirlpoolAndCircuit

namespace StdSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem whirlpoolAnd_wf : wellFormed 8 whirlpoolAndGates whirlpoolAndOutputs = true := by
  decide +kernel

theorem whirlpoolAnd_metric : andCount whirlpoolAndGates = whirlpoolAndScore := by
  decide +kernel

theorem whirlpoolAnd_check : checkCircuitBV 8 initRevBV8 whirlpoolTable whirlpoolAndGates whirlpoolAndOutputs = true := by
  decide +kernel

theorem whirlpool_and_gates_bound : ValidAndCircuit 8 whirlpoolSbox whirlpoolAndScore :=
  ⟨whirlpoolAndGates, whirlpoolAndOutputs, whirlpoolAnd_wf, whirlpoolAnd_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 whirlpoolTable whirlpoolSbox
      initRevBV8_ok whirlpoolTable_ok whirlpoolAndGates whirlpoolAndOutputs whirlpoolAnd_check⟩

end StdSbox
