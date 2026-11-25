import SortNet.Spec
import SortNet.Net16

namespace SortNet

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_16 : wellFormed 16 net16 = true := by
  decide +kernel

theorem length_16 : net16.length = score16 := by
  decide +kernel

theorem check_16 : checkSortNet 16 net16 = true := by
  decide +kernel

/-- The submitted comparator network certifies `ValidSortingNetwork 16 score16`. -/
theorem bound_16 : ValidSortingNetwork 16 score16 :=
  ⟨net16, wellFormed_16, length_16, checkSortNet_sound 16 net16 wellFormed_16 check_16⟩

end SortNet
