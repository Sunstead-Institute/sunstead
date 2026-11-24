use crate::centered_mod::centered_mod;
use crate::ct_select::ct_select_i32;
use crate::spec::Q;

/// TODO (Task: sub_reduce):
/// Implement branchless, constant-time centered modular subtraction for `a, b in [-HALF_Q, HALF_Q]`.
/// Must return `(a - b) mod± Q` in `[-HALF_Q, HALF_Q]` with no overflow and no secret branches.
/// Forbidden tokens: `unsafe`, `if`, `match`, loops, `%`, `/`.
pub fn sub_centered(_a: i32, _b: i32) -> i32 {
    let _ = (Q, centered_mod, ct_select_i32);
    0
}
