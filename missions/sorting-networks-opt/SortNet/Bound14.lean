import SortNet.Spec
import SortNet.Net14

namespace SortNet

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_14 : wellFormed 14 net14 = true := by
  decide +kernel

theorem length_14 : net14.length = score14 := by
  decide +kernel

theorem check_14 : checkSortNet 14 net14 = true := by
  decide +kernel

/-- The submitted comparator network certifies `ValidSortingNetwork 14 score14`. -/
theorem bound_14 : ValidSortingNetwork 14 score14 :=
  ⟨net14, wellFormed_14, length_14, checkSortNet_sound 14 net14 wellFormed_14 check_14⟩

end SortNet
