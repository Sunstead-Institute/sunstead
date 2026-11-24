/// TODO (Task: chacha20_quarter_round):
/// Implement RFC 8439 §2.1 ChaCha20 ARX quarter-round in-place on `state[a], state[b], state[c], state[d]`.
/// Strictly branchless and loop-free: no `unsafe`, `if`, `match`, loops, `%`, `/`, `unwrap`, `expect`, `panic!`.
pub fn quarter_round(_state: &mut [u32; 16], _a: usize, _b: usize, _c: usize, _d: usize) {}
