import SelectNet.Spec
import SelectNet.Net13

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_13 : wellFormed 13 net13 = true := by
  decide +kernel

theorem length_13 : net13.length = score13 := by
  decide +kernel

theorem check_13 : checkMedianNet 13 net13 = true := by
  decide +kernel

/-- Certifies a `score13`-comparator median selection network on `13` wires over every linear order. -/
theorem bound_13 : ValidMedianNetwork 13 score13 :=
  validMedianNetwork_of_check 13 score13 net13 wellFormed_13 length_13 check_13

end SelectNet
