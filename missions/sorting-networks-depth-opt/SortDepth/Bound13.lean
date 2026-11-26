import SortDepth.Spec
import SortDepth.Layers13

namespace SortDepth

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_13 : wellFormedLayers 13 layers13 = true := by
  decide +kernel

theorem length_13 : layers13.length = depth13 := by
  decide +kernel

theorem check_13 : checkSortLayers 13 layers13 = true := by
  decide +kernel

/-- The submitted parallel comparator network certifies `ValidParallelSortingNetwork 13 depth13`. -/
theorem bound_13 : ValidParallelSortingNetwork 13 depth13 :=
  validParallelSortingNetwork_of_check 13 depth13 layers13 wellFormed_13 length_13 check_13

end SortDepth
