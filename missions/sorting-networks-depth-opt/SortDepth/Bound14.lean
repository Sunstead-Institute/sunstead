import SortDepth.Spec
import SortDepth.Layers14

namespace SortDepth

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_14 : wellFormedLayers 14 layers14 = true := by
  decide +kernel

theorem length_14 : layers14.length = depth14 := by
  decide +kernel

theorem check_14 : checkSortLayers 14 layers14 = true := by
  decide +kernel

/-- The submitted parallel comparator network certifies `ValidParallelSortingNetwork 14 depth14`. -/
theorem bound_14 : ValidParallelSortingNetwork 14 depth14 :=
  validParallelSortingNetwork_of_check 14 depth14 layers14 wellFormed_14 length_14 check_14

end SortDepth
