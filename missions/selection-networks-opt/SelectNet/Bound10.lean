import SelectNet.Spec
import SelectNet.Net10

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_10 : wellFormed 10 net10 = true := by
  decide +kernel

theorem length_10 : net10.length = score10 := by
  decide +kernel

theorem check_10 : checkMedianNet 10 net10 = true := by
  decide +kernel

/-- Certifies a `score10`-comparator median selection network on `10` wires over every linear order. -/
theorem bound_10 : ValidMedianNetwork 10 score10 :=
  validMedianNetwork_of_check 10 score10 net10 wellFormed_10 length_10 check_10

end SelectNet
