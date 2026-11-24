use crate::spec::{HALF_Q, Q};

/// TODO (Task: centered_mod):
/// Implement branchless, constant-time centered reduction modulo Q = 8_380_417.
/// For all `a` in `0..Q`, return `r` in `-HALF_Q..=HALF_Q` with `r ≡ a (mod Q)`.
/// Forbidden tokens: `unsafe`, `if`, `match`, `%`, `/`.
pub fn centered_mod(_a: i32) -> i32 {
    let _ = (Q, HALF_Q);
    0
}
