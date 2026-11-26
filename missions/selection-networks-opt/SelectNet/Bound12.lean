import SelectNet.Spec
import SelectNet.Net12

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_12 : wellFormed 12 net12 = true := by
  decide +kernel

theorem length_12 : net12.length = score12 := by
  decide +kernel

theorem check_12 : checkMedianNet 12 net12 = true := by
  decide +kernel

/-- Certifies a `score12`-comparator median selection network on `12` wires over every linear order. -/
theorem bound_12 : ValidMedianNetwork 12 score12 :=
  validMedianNetwork_of_check 12 score12 net12 wellFormed_12 length_12 check_12

end SelectNet
