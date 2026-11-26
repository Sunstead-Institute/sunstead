import SelectNet.Spec
import SelectNet.Net15

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_15 : wellFormed 15 net15 = true := by
  decide +kernel

theorem length_15 : net15.length = score15 := by
  decide +kernel

theorem check_15 : checkMedianNet 15 net15 = true := by
  decide +kernel

/-- Certifies a `score15`-comparator median selection network on `15` wires over every linear order. -/
theorem bound_15 : ValidMedianNetwork 15 score15 :=
  validMedianNetwork_of_check 15 score15 net15 wellFormed_15 length_15 check_15

end SelectNet
