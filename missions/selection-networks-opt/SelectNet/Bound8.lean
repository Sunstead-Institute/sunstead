import SelectNet.Spec
import SelectNet.Net8

namespace SelectNet

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem wellFormed_8 : wellFormed 8 net8 = true := by
  decide +kernel

theorem length_8 : net8.length = score8 := by
  decide +kernel

theorem check_8 : checkMedianNet 8 net8 = true := by
  decide +kernel

/-- Certifies a `score8`-comparator median selection network on `8` wires over every linear order. -/
theorem bound_8 : ValidMedianNetwork 8 score8 :=
  validMedianNetwork_of_check 8 score8 net8 wellFormed_8 length_8 check_8

end SelectNet
