import SortDepth.Spec
import SortDepth.Layers10

namespace SortDepth

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_10 : wellFormedLayers 10 layers10 = true := by
  decide +kernel

theorem length_10 : layers10.length = depth10 := by
  decide +kernel

theorem check_10 : checkSortLayers 10 layers10 = true := by
  decide +kernel

/-- The submitted parallel comparator network certifies `ValidParallelSortingNetwork 10 depth10`. -/
theorem bound_10 : ValidParallelSortingNetwork 10 depth10 :=
  validParallelSortingNetwork_of_check 10 depth10 layers10 wellFormed_10 length_10 check_10

end SortDepth
