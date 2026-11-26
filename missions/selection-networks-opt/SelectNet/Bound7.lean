import SelectNet.Spec
import SelectNet.Net7

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_7 : wellFormed 7 net7 = true := by
  decide +kernel

theorem length_7 : net7.length = score7 := by
  decide +kernel

theorem check_7 : checkMedianNet 7 net7 = true := by
  decide +kernel

/-- Certifies a `score7`-comparator median selection network on `7` wires over every linear order. -/
theorem bound_7 : ValidMedianNetwork 7 score7 :=
  validMedianNetwork_of_check 7 score7 net7 wellFormed_7 length_7 check_7

end SelectNet
