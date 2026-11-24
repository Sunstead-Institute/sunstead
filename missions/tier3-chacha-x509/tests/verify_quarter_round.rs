use chacha_x509::quarter_round::quarter_round;
use chacha_x509::spec::spec_quarter_round;

#[test]
fn verify_rfc8439_quarter_round_vectors_and_sweep() {
    // RFC 8439 Section 2.1.1 test vector
    let mut state = [0u32; 16];
    state[0] = 0x1111_1111;
    state[1] = 0x0102_0304;
    state[2] = 0x9b8d_6f43;
    state[3] = 0x0123_4567;
    quarter_round(&mut state, 0, 1, 2, 3);
    assert_eq!(state[0], 0xea2a_92f4);
    assert_eq!(state[1], 0xcb1c_f8ce);
    assert_eq!(state[2], 0x4581_472e);
    assert_eq!(state[3], 0x5881_c4bb);

    // RFC 8439 Section 2.2.1 full state vector (indices 2, 7, 8, 13)
    let mut full: [u32; 16] = [
        0x879531e0, 0xc5ecf37d, 0x516461b1, 0xc9a62f8a,
        0x44c20ef3, 0x3390af7f, 0xd9fc690b, 0x2a5f714c,
        0x53372767, 0xb00a5631, 0x974c541a, 0x359e9963,
        0x5c971061, 0x3d631689, 0x2098d9d6, 0x91dbd320,
    ];
    quarter_round(&mut full, 2, 7, 8, 13);
    assert_eq!(full[2], 0xbdb8_86dc);
    assert_eq!(full[7], 0xcfac_afd2);
    assert_eq!(full[8], 0xe46b_ea80);
    assert_eq!(full[13], 0xccc0_7c79);

    // 100k randomized sweeps
    let mut s: u64 = 0xA076_1D64_78BD_642F;
    let tuples = [(0, 4, 8, 12), (1, 5, 9, 13), (2, 6, 10, 14), (3, 7, 11, 15), (0, 5, 10, 15), (2, 7, 8, 13)];
    for idx in 0..100_000 {
        let mut st1 = [0u32; 16];
        for i in 0..16 {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            st1[i] = (s >> 32) as u32;
        }
        let mut st2 = st1;
        let (a, b, c, d) = tuples[idx % tuples.len()];
        quarter_round(&mut st1, a, b, c, d);
        spec_quarter_round(&mut st2, a, b, c, d);
        assert_eq!(st1, st2);
    }
}
