use chacha_x509::ct_cmov::ct_cmov_u32;

#[test]
fn verify_ct_cmov_u32_exhaustive_conds() {
    let conds: &[u32] = &[0, 1, 2, 3, 0x7FFF_FFFF, 0x8000_0000, 0xDEAD_BEEF, u32::MAX];
    let mut s: u64 = 0xCAFE_BABE_1337_0001;

    for _ in 0..5_000 {
        let mut a = [0u32; 16];
        let mut b = [0u32; 16];
        for i in 0..16 {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            a[i] = (s >> 32) as u32;
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            b[i] = (s >> 32) as u32;
        }
        for &c in conds {
            let mut dst = a;
            ct_cmov_u32(c, &mut dst, &b);
            let exp = if c != 0 { b } else { a };
            assert_eq!(dst, exp, "ct_cmov_u32 mismatch for cond={c:#x}");
        }
    }
}
