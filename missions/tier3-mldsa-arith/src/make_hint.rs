use crate::decompose::decompose;
use crate::spec::Q;

/// TODO (Task: make_hint):
/// Implement branchless FIPS 204 Algorithm 39 `MakeHint(z, r)` for `z in [-HALF_Q, HALF_Q]` and `r in [0, Q)`.
/// Returns `1` iff `HighBits(r) != HighBits((r + z) mod Q)`, else `0`.
/// Compose `decompose` with zero secret-dependent control flow.
/// Forbidden tokens: `unsafe`, `if`, `match`, loops, `%`, `/`.
pub fn make_hint(_z: i32, _r: i32) -> u32 {
    let _ = (decompose, Q);
    0
}
