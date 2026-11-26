import SortDepth.Spec
import SortDepth.Layers12

namespace SortDepth

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_12 : wellFormedLayers 12 layers12 = true := by
  decide +kernel

theorem length_12 : layers12.length = depth12 := by
  decide +kernel

theorem check_12 : checkSortLayers 12 layers12 = true := by
  decide +kernel

/-- The submitted parallel comparator network certifies `ValidParallelSortingNetwork 12 depth12`. -/
theorem bound_12 : ValidParallelSortingNetwork 12 depth12 :=
  validParallelSortingNetwork_of_check 12 depth12 layers12 wellFormed_12 length_12 check_12

end SortDepth
