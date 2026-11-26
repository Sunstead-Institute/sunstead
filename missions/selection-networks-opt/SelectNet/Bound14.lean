import SelectNet.Spec
import SelectNet.Net14

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_14 : wellFormed 14 net14 = true := by
  decide +kernel

theorem length_14 : net14.length = score14 := by
  decide +kernel

theorem check_14 : checkMedianNet 14 net14 = true := by
  decide +kernel

/-- Certifies a `score14`-comparator median selection network on `14` wires over every linear order. -/
theorem bound_14 : ValidMedianNetwork 14 score14 :=
  validMedianNetwork_of_check 14 score14 net14 wellFormed_14 length_14 check_14

end SelectNet
