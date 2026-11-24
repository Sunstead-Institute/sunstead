/// TODO (Task: ct_select):
/// Implement branchless, constant-time conditional select:
/// returns `a` if `cond != 0`, otherwise returns `b`.
/// Forbidden tokens: `unsafe`, `if`, `match`, `%`, `/`.
pub fn ct_select_i32(_cond: u32, _a: i32, b: i32) -> i32 {
    b
}
