import StdSbox.Spec
import StdSbox.WhirlpoolTotalCircuit

namespace StdSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem whirlpoolTotal_wf : wellFormed 8 whirlpoolTotalGates whirlpoolTotalOutputs = true := by
  decide +kernel

theorem whirlpoolTotal_metric : whirlpoolTotalGates.length = whirlpoolTotalScore := by
  decide +kernel

theorem whirlpoolTotal_check : checkCircuitBV 8 initRevBV8 whirlpoolTable whirlpoolTotalGates whirlpoolTotalOutputs = true := by
  decide +kernel

theorem whirlpool_total_gates_bound : ValidTotalCircuit 8 whirlpoolSbox whirlpoolTotalScore :=
  ⟨whirlpoolTotalGates, whirlpoolTotalOutputs, whirlpoolTotal_wf, whirlpoolTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 whirlpoolTable whirlpoolSbox
      initRevBV8_ok whirlpoolTable_ok whirlpoolTotalGates whirlpoolTotalOutputs whirlpoolTotal_check⟩

end StdSbox
