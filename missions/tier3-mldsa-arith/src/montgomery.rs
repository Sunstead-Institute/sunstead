use crate::spec::{Q, QINV};

/// TODO (Task: montgomery_reduce):
/// Implement branchless FIPS 204 Montgomery reduction for `a` in `[-(2^31-1)*Q, (2^31-1)*Q]`.
/// Must return `r` with `|r| < Q` and `r * 2^32 ≡ a (mod Q)`.
/// Forbidden tokens: `unsafe`, `if`, `match`, loops, `%`, `/`.
pub fn montgomery_reduce(_a: i64) -> i32 {
    let _ = (Q, QINV);
    0
}
