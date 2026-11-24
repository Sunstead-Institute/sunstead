use crate::add_reduce::add_centered;
use crate::centered_mod::centered_mod;
use crate::ct_select::ct_select_i32;
use crate::montgomery::montgomery_reduce;
use crate::spec::Q;
use crate::sub_reduce::sub_centered;

/// TODO (Task: ct_butterfly):
/// Implement a branchless, constant-time ML-DSA Cooley-Tukey NTT butterfly for centered inputs
/// `a, b, zeta_mont in [-HALF_Q, HALF_Q]`, returning `(a + t, a - t) mod± Q` where
/// `t = b * zeta_mont * 2^(-32) mod± Q`.
/// Forbidden tokens: `unsafe`, `if`, `match`, loops, `%`, `/`.
pub fn ct_butterfly(_a: i32, _b: i32, _zeta_mont: i32) -> (i32, i32) {
    let _ = (Q, montgomery_reduce, centered_mod, ct_select_i32, add_centered, sub_centered);
    (0, 0)
}
