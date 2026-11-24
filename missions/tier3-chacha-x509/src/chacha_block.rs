use crate::quarter_round::quarter_round;

/// TODO (Task: chacha20_block):
/// Implement RFC 8439 §2.3 ChaCha20 64-byte keystream block function using `quarter_round`.
/// Initial state: constants `"expand 32-byte k"`, 8 LE key words, `counter`, 3 LE nonce words;
/// 10 double-rounds (column + diagonal), feed-forward wrapping addition, LE serialization.
/// Forbidden tokens: `unsafe`, `if`, `match`, `while`, `loop`, `break`, `continue`, `%`, `/`, `unwrap`, `expect`, `panic!`.
pub fn chacha20_block(_key: &[u8; 32], _counter: u32, _nonce: &[u8; 12]) -> [u8; 64] {
    let _ = quarter_round;
    [0u8; 64]
}
