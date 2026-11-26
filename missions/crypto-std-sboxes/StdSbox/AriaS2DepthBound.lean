import StdSbox.Spec
import StdSbox.AriaS2DepthCircuit

namespace StdSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem ariaS2Depth_wf : wellFormed 8 ariaS2DepthGates ariaS2DepthOutputs = true := by
  decide +kernel

theorem ariaS2Depth_metric : andDepth 8 ariaS2DepthGates ariaS2DepthOutputs = ariaS2DepthScore := by
  decide +kernel

theorem ariaS2Depth_check : checkCircuitBV 8 initRevBV8 ariaS2Table ariaS2DepthGates ariaS2DepthOutputs = true := by
  decide +kernel

theorem aria_s2_and_depth_bound : ValidAndDepthCircuit 8 ariaS2Sbox ariaS2DepthScore :=
  ⟨ariaS2DepthGates, ariaS2DepthOutputs, ariaS2Depth_wf, ariaS2Depth_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 ariaS2Table ariaS2Sbox
      initRevBV8_ok ariaS2Table_ok ariaS2DepthGates ariaS2DepthOutputs ariaS2Depth_check⟩

end StdSbox
