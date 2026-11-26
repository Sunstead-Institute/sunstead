import SortDepth.Spec
import SortDepth.Layers9

namespace SortDepth

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_9 : wellFormedLayers 9 layers9 = true := by
  decide +kernel

theorem length_9 : layers9.length = depth9 := by
  decide +kernel

theorem check_9 : checkSortLayers 9 layers9 = true := by
  decide +kernel

/-- The submitted parallel comparator network certifies `ValidParallelSortingNetwork 9 depth9`. -/
theorem bound_9 : ValidParallelSortingNetwork 9 depth9 :=
  validParallelSortingNetwork_of_check 9 depth9 layers9 wellFormed_9 length_9 check_9

end SortDepth
