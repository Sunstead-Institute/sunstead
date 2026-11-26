import SortDepth.Spec
import SortDepth.Layers15

namespace SortDepth

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_15 : wellFormedLayers 15 layers15 = true := by
  decide +kernel

theorem length_15 : layers15.length = depth15 := by
  decide +kernel

theorem check_15 : checkSortLayers 15 layers15 = true := by
  decide +kernel

/-- The submitted parallel comparator network certifies `ValidParallelSortingNetwork 15 depth15`. -/
theorem bound_15 : ValidParallelSortingNetwork 15 depth15 :=
  validParallelSortingNetwork_of_check 15 depth15 layers15 wellFormed_15 length_15 check_15

end SortDepth
