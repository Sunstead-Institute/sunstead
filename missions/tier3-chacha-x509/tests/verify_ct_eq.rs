use chacha_x509::ct_eq::ct_eq_32;

#[test]
fn verify_ct_eq_32_single_bit_and_random() {
    let zero = [0u8; 32];
    let ones = [0xFFu8; 32];
    assert_eq!(ct_eq_32(&zero, &zero), 1);
    assert_eq!(ct_eq_32(&ones, &ones), 1);
    assert_eq!(ct_eq_32(&zero, &ones), 0);

    // Every single bit position flip must return 0.
    let base: [u8; 32] = core::array::from_fn(|i| (i as u8).wrapping_mul(37).wrapping_add(11));
    assert_eq!(ct_eq_32(&base, &base), 1);
    for byte_idx in 0..32 {
        for bit in 0..8 {
            let mut flipped = base;
            flipped[byte_idx] ^= 1u8 << bit;
            assert_eq!(
                ct_eq_32(&base, &flipped),
                0,
                "failed to detect bit flip at byte={byte_idx}, bit={bit}"
            );
            assert_eq!(ct_eq_32(&flipped, &base), 0);
        }
    }

    // 100k random pairs
    let mut s: u64 = 0x1234_5678_9ABC_DEF0;
    for i in 0..100_000 {
        let mut a = [0u8; 32];
        let mut b = [0u8; 32];
        for k in 0..4 {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            a[8 * k..8 * k + 8].copy_from_slice(&s.to_le_bytes());
        }
        if i % 3 == 0 {
            b = a;
        } else {
            for k in 0..4 {
                s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
                b[8 * k..8 * k + 8].copy_from_slice(&s.to_le_bytes());
            }
        }
        let expected = if a == b { 1 } else { 0 };
        assert_eq!(ct_eq_32(&a, &b), expected);
    }
}
