import SortDepth.Spec
import SortDepth.Layers16

namespace SortDepth

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_16 : wellFormedLayers 16 layers16 = true := by
  decide +kernel

theorem length_16 : layers16.length = depth16 := by
  decide +kernel

theorem check_16 : checkSortLayers 16 layers16 = true := by
  decide +kernel

/-- The submitted parallel comparator network certifies `ValidParallelSortingNetwork 16 depth16`. -/
theorem bound_16 : ValidParallelSortingNetwork 16 depth16 :=
  validParallelSortingNetwork_of_check 16 depth16 layers16 wellFormed_16 length_16 check_16

end SortDepth
