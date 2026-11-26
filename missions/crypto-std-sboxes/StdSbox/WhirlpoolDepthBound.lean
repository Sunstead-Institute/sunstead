import StdSbox.Spec
import StdSbox.WhirlpoolDepthCircuit

namespace StdSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem whirlpoolDepth_wf : wellFormed 8 whirlpoolDepthGates whirlpoolDepthOutputs = true := by
  decide +kernel

theorem whirlpoolDepth_metric : andDepth 8 whirlpoolDepthGates whirlpoolDepthOutputs = whirlpoolDepthScore := by
  decide +kernel

theorem whirlpoolDepth_check : checkCircuitBV 8 initRevBV8 whirlpoolTable whirlpoolDepthGates whirlpoolDepthOutputs = true := by
  decide +kernel

theorem whirlpool_and_depth_bound : ValidAndDepthCircuit 8 whirlpoolSbox whirlpoolDepthScore :=
  ⟨whirlpoolDepthGates, whirlpoolDepthOutputs, whirlpoolDepth_wf, whirlpoolDepth_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 whirlpoolTable whirlpoolSbox
      initRevBV8_ok whirlpoolTable_ok whirlpoolDepthGates whirlpoolDepthOutputs whirlpoolDepth_check⟩

end StdSbox
