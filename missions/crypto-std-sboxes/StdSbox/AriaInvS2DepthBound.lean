import StdSbox.Spec
import StdSbox.AriaInvS2DepthCircuit

namespace StdSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem ariaInvS2Depth_wf : wellFormed 8 ariaInvS2DepthGates ariaInvS2DepthOutputs = true := by
  decide +kernel

theorem ariaInvS2Depth_metric : andDepth 8 ariaInvS2DepthGates ariaInvS2DepthOutputs = ariaInvS2DepthScore := by
  decide +kernel

theorem ariaInvS2Depth_check : checkCircuitBV 8 initRevBV8 ariaInvS2Table ariaInvS2DepthGates ariaInvS2DepthOutputs = true := by
  decide +kernel

theorem aria_invs2_and_depth_bound : ValidAndDepthCircuit 8 ariaInvS2Sbox ariaInvS2DepthScore :=
  ⟨ariaInvS2DepthGates, ariaInvS2DepthOutputs, ariaInvS2Depth_wf, ariaInvS2Depth_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 ariaInvS2Table ariaInvS2Sbox
      initRevBV8_ok ariaInvS2Table_ok ariaInvS2DepthGates ariaInvS2DepthOutputs ariaInvS2Depth_check⟩

end StdSbox
