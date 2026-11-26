import SelectNet.Spec
import SelectNet.Net11

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_11 : wellFormed 11 net11 = true := by
  decide +kernel

theorem length_11 : net11.length = score11 := by
  decide +kernel

theorem check_11 : checkMedianNet 11 net11 = true := by
  decide +kernel

/-- Certifies a `score11`-comparator median selection network on `11` wires over every linear order. -/
theorem bound_11 : ValidMedianNetwork 11 score11 :=
  validMedianNetwork_of_check 11 score11 net11 wellFormed_11 length_11 check_11

end SelectNet
