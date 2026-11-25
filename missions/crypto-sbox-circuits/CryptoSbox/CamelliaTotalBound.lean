import CryptoSbox.Spec
import CryptoSbox.CamelliaTotalCircuit

namespace CryptoSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem camelliaTotal_wellFormed : wellFormed camelliaTotalGates camelliaTotalOutputs = true := by
  decide +kernel

theorem camelliaTotal_length : camelliaTotalGates.length = camelliaTotalScore := by
  decide +kernel

theorem camelliaTotal_check : checkCircuit256 camelliaTable256 camelliaTotalGates camelliaTotalOutputs = true := by
  decide +kernel

/-- The submitted straight-line circuit certifies `ValidTotalCircuit camelliaSbox1 camelliaTotalScore`. -/
theorem camellia_total_bound : ValidTotalCircuit camelliaSbox1 camelliaTotalScore :=
  ⟨camelliaTotalGates, camelliaTotalOutputs, camelliaTotal_wellFormed, camelliaTotal_length,
    evalCircuit_eq_camelliaSbox1_of_checkCircuit256 camelliaTotalGates camelliaTotalOutputs camelliaTotal_check⟩

end CryptoSbox
