use crate::spec::{ALPHA, DECOMPOSE_M, GAMMA2, HALF_Q, Q};

/// TODO (Task: decompose_lowbits):
/// Implement branchless FIPS 204 Algorithm 36 `Decompose(r)` for ML-DSA-44 (`GAMMA2 = (Q - 1) / 88 = 95,232`)
/// for every `r` in `0..Q`.
/// Returns `(r1, r0)` where `0 <= r1 < 44`, `-GAMMA2 <= r0 <= GAMMA2`, and
/// `r1 * (2 * GAMMA2) + r0 ≡ r (mod Q)`, matching `spec_decompose(r)` on every residue.
/// Forbidden tokens: `unsafe`, `if`, `match`, loops, `%`, `/`.
pub fn decompose(_r: i32) -> (i32, i32) {
    let _ = (ALPHA, DECOMPOSE_M, GAMMA2, HALF_Q, Q);
    (0, 0)
}
