use crate::spec::{D_BITS, HALF_TWO_D};

/// TODO (Task: power2round):
/// Implement branchless FIPS 204 Power2Round (d = 13) for every `r` in `0..Q`.
/// Returns `(r1, r0)` such that `r = r1 * 2^13 + r0` and `-2^12 < r0 <= 2^12`.
/// Forbidden tokens: `unsafe`, `if`, `match`, loops, `%`, `/`.
pub fn power2round(_r: i32) -> (i32, i32) {
    let _ = (D_BITS, HALF_TWO_D);
    (0, 0)
}
