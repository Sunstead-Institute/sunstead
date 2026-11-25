import SortNet.Spec
import SortNet.Net10

namespace SortNet

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_10 : wellFormed 10 net10 = true := by
  decide +kernel

theorem length_10 : net10.length = score10 := by
  decide +kernel

theorem check_10 : checkSortNet 10 net10 = true := by
  decide +kernel

/-- The submitted comparator network certifies `ValidSortingNetwork 10 score10`. -/
theorem bound_10 : ValidSortingNetwork 10 score10 :=
  ⟨net10, wellFormed_10, length_10, checkSortNet_sound 10 net10 wellFormed_10 check_10⟩

end SortNet
