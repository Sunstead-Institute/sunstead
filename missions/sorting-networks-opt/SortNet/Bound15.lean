import SortNet.Spec
import SortNet.Net15

namespace SortNet

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_15 : wellFormed 15 net15 = true := by
  decide +kernel

theorem length_15 : net15.length = score15 := by
  decide +kernel

theorem check_15 : checkSortNet 15 net15 = true := by
  decide +kernel

/-- The submitted comparator network certifies `ValidSortingNetwork 15 score15`. -/
theorem bound_15 : ValidSortingNetwork 15 score15 :=
  ⟨net15, wellFormed_15, length_15, checkSortNet_sound 15 net15 wellFormed_15 check_15⟩

end SortNet
