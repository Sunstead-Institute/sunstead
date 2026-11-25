import SortNet.Spec
import SortNet.Net9

namespace SortNet

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_9 : wellFormed 9 net9 = true := by
  decide +kernel

theorem length_9 : net9.length = score9 := by
  decide +kernel

theorem check_9 : checkSortNet 9 net9 = true := by
  decide +kernel

/-- The submitted comparator network certifies `ValidSortingNetwork 9 score9`. -/
theorem bound_9 : ValidSortingNetwork 9 score9 :=
  ⟨net9, wellFormed_9, length_9, checkSortNet_sound 9 net9 wellFormed_9 check_9⟩

end SortNet
