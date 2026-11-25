import SortNet.Spec
import SortNet.Net11

namespace SortNet

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_11 : wellFormed 11 net11 = true := by
  decide +kernel

theorem length_11 : net11.length = score11 := by
  decide +kernel

theorem check_11 : checkSortNet 11 net11 = true := by
  decide +kernel

/-- The submitted comparator network certifies `ValidSortingNetwork 11 score11`. -/
theorem bound_11 : ValidSortingNetwork 11 score11 :=
  ⟨net11, wellFormed_11, length_11, checkSortNet_sound 11 net11 wellFormed_11 check_11⟩

end SortNet
