use crate::add_reduce::add_centered;
use crate::montgomery::montgomery_reduce;
use crate::sub_reduce::sub_centered;

/// TODO (Task: inv_butterfly):
/// Implement branchless Gentleman-Sande Inverse NTT butterfly for centered `a, b, zeta_mont in [-HALF_Q, HALF_Q]`.
/// Returns `((a + b) mod± Q, ((a - b) * zeta_mont * 2^-32) mod± Q)` in `[-HALF_Q, HALF_Q]`.
/// Compose `add_centered`, `sub_centered`, and `montgomery_reduce`.
/// Forbidden tokens: `unsafe`, `if`, `match`, loops, `%`, `/`.
pub fn inv_butterfly(_a: i32, _b: i32, _zeta_mont: i32) -> (i32, i32) {
    let _ = (add_centered, sub_centered, montgomery_reduce);
    (0, 0)
}
