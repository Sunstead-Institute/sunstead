import LwcSbox.Spec
import LwcSbox.KeccakChiTotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem keccakChiTotal_wf : wellFormed 5 keccakChiTotalGates keccakChiTotalOutputs = true := by
  decide +kernel

theorem keccakChiTotal_metric : keccakChiTotalGates.length = keccakChiTotalScore := by
  decide +kernel

theorem keccakChiTotal_check : checkCircuitBV 5 initRevBV5 keccakChiTable keccakChiTotalGates keccakChiTotalOutputs = true := by
  decide +kernel

theorem keccak_chi_total_gates_bound : ValidTotalCircuit 5 keccakChiSbox keccakChiTotalScore :=
  ⟨keccakChiTotalGates, keccakChiTotalOutputs, keccakChiTotal_wf, keccakChiTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 5 initRevBV5 keccakChiTable keccakChiSbox
      initRevBV5_ok keccakChiTable_ok keccakChiTotalGates keccakChiTotalOutputs keccakChiTotal_check⟩

end LwcSbox
