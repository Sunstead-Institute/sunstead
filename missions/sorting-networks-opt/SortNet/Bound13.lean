import SortNet.Spec
import SortNet.Net13

namespace SortNet

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_13 : wellFormed 13 net13 = true := by
  decide +kernel

theorem length_13 : net13.length = score13 := by
  decide +kernel

theorem check_13 : checkSortNet 13 net13 = true := by
  decide +kernel

/-- The submitted comparator network certifies `ValidSortingNetwork 13 score13`. -/
theorem bound_13 : ValidSortingNetwork 13 score13 :=
  ⟨net13, wellFormed_13, length_13, checkSortNet_sound 13 net13 wellFormed_13 check_13⟩

end SortNet
