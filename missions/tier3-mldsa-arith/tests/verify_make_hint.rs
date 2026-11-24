use mldsa_arith::make_hint::make_hint;
use mldsa_arith::spec::{spec_make_hint, ALPHA, GAMMA2, HALF_Q, Q};

#[test]
fn verify_make_hint_boundaries_and_sweep() {
    let critical_r: &[i32] = &[
        0,
        1,
        GAMMA2 - 1,
        GAMMA2,
        GAMMA2 + 1,
        ALPHA - 1,
        ALPHA,
        ALPHA + 1,
        Q - GAMMA2 - 1,
        Q - GAMMA2,
        Q - GAMMA2 + 1,
        Q - 1,
    ];
    let critical_z: &[i32] = &[
        -HALF_Q,
        -ALPHA,
        -GAMMA2 - 1,
        -GAMMA2,
        -GAMMA2 + 1,
        -1,
        0,
        1,
        GAMMA2 - 1,
        GAMMA2,
        GAMMA2 + 1,
        ALPHA,
        HALF_Q,
    ];
    for &r in critical_r {
        for &z in critical_z {
            let got = make_hint(z, r);
            let exp = spec_make_hint(z, r);
            assert!(got <= 1, "hint must be 0 or 1, got {got}");
            assert_eq!(got, exp, "mismatch at z={z}, r={r}");
        }
    }

    let mut state: u64 = 0x517C_C1B7_2722_0A95;
    let q_u64 = Q as u64;
    for _ in 0..250_000 {
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
        let r = (state % q_u64) as i32;
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
        let z = ((state % q_u64) as i32) - HALF_Q;
        assert_eq!(make_hint(z, r), spec_make_hint(z, r));
    }
}
