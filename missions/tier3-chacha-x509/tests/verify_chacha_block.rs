use chacha_x509::chacha_block::chacha20_block;
use chacha_x509::spec::spec_chacha20_block;

#[test]
fn verify_rfc8439_block_vector_and_random() {
    // Official RFC 8439 Section 2.3.2 test vector
    let key: [u8; 32] = core::array::from_fn(|i| i as u8);
    let counter: u32 = 1;
    let nonce: [u8; 12] = [0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x4a, 0x00, 0x00, 0x00, 0x00];
    let expected: [u8; 64] = [
        0x10, 0xf1, 0xe7, 0xe4, 0xd1, 0x3b, 0x59, 0x15, 0x50, 0x0f, 0xdd, 0x1f, 0xa3, 0x20, 0x71, 0xc4,
        0xc7, 0xd1, 0xf4, 0xc7, 0x33, 0xc0, 0x68, 0x03, 0x04, 0x22, 0xaa, 0x9a, 0xc3, 0xd4, 0x6c, 0x4e,
        0xd2, 0x82, 0x64, 0x46, 0x07, 0x9f, 0xaa, 0x09, 0x14, 0xc2, 0xd7, 0x05, 0xd9, 0x8b, 0x02, 0xa2,
        0xb5, 0x12, 0x9c, 0xd1, 0xde, 0x16, 0x4e, 0xb9, 0xcb, 0xd0, 0x83, 0xe8, 0xa2, 0x50, 0x3c, 0x4e,
    ];
    assert_eq!(chacha20_block(&key, counter, &nonce), expected);

    // 5,000 randomized blocks against frozen reference spec
    let mut s: u64 = 0xE703_7ED1_A0B4_28DB;
    for _ in 0..5_000 {
        let mut k = [0u8; 32];
        for j in 0..4 {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            k[8 * j..8 * j + 8].copy_from_slice(&s.to_le_bytes());
        }
        s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
        let ctr = (s >> 32) as u32;
        let mut n = [0u8; 12];
        for b in &mut n {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            *b = (s >> 56) as u8;
        }
        assert_eq!(chacha20_block(&k, ctr, &n), spec_chacha20_block(&k, ctr, &n));
    }
}
