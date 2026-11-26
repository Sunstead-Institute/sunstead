import SelectNet.Spec
import SelectNet.Net16

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_16 : wellFormed 16 net16 = true := by
  decide +kernel

theorem length_16 : net16.length = score16 := by
  decide +kernel

theorem check_16 : checkMedianNet 16 net16 = true := by
  decide +kernel

/-- Certifies a `score16`-comparator median selection network on `16` wires over every linear order. -/
theorem bound_16 : ValidMedianNetwork 16 score16 :=
  validMedianNetwork_of_check 16 score16 net16 wellFormed_16 length_16 check_16

end SelectNet
