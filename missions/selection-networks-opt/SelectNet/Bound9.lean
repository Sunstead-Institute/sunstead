import SelectNet.Spec
import SelectNet.Net9

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_9 : wellFormed 9 net9 = true := by
  decide +kernel

theorem length_9 : net9.length = score9 := by
  decide +kernel

theorem check_9 : checkMedianNet 9 net9 = true := by
  decide +kernel

/-- Certifies a `score9`-comparator median selection network on `9` wires over every linear order. -/
theorem bound_9 : ValidMedianNetwork 9 score9 :=
  validMedianNetwork_of_check 9 score9 net9 wellFormed_9 length_9 check_9

end SelectNet
