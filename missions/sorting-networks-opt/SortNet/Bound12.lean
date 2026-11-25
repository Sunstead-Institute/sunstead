import SortNet.Spec
import SortNet.Net12

namespace SortNet

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_12 : wellFormed 12 net12 = true := by
  decide +kernel

theorem length_12 : net12.length = score12 := by
  decide +kernel

theorem check_12 : checkSortNet 12 net12 = true := by
  decide +kernel

/-- The submitted comparator network certifies `ValidSortingNetwork 12 score12`. -/
theorem bound_12 : ValidSortingNetwork 12 score12 :=
  ⟨net12, wellFormed_12, length_12, checkSortNet_sound 12 net12 wellFormed_12 check_12⟩

end SortNet
