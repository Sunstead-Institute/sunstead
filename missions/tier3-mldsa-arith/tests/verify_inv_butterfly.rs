use mldsa_arith::inv_butterfly::inv_butterfly;
use mldsa_arith::spec::{spec_inv_butterfly, HALF_Q, Q};

#[test]
fn verify_inv_butterfly_critical_and_sweep() {
    let critical: &[i32] = &[-HALF_Q, -HALF_Q + 1, -1024, -1, 0, 1, 1024, HALF_Q - 1, HALF_Q];
    for &a in critical {
        for &b in critical {
            for &z in critical {
                let got = inv_butterfly(a, b, z);
                let exp = spec_inv_butterfly(a, b, z);
                assert!((-HALF_Q..=HALF_Q).contains(&got.0));
                assert!((-HALF_Q..=HALF_Q).contains(&got.1));
                assert_eq!(got, exp, "mismatch at a={a}, b={b}, zeta_mont={z}");
            }
        }
    }

    let mut state: u64 = 0x9E37_79B9_7F4A_7C15;
    let q_u64 = Q as u64;
    for _ in 0..250_000 {
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
        let a = ((state % q_u64) as i32) - HALF_Q;
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
        let b = ((state % q_u64) as i32) - HALF_Q;
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
        let z = ((state % q_u64) as i32) - HALF_Q;
        assert_eq!(inv_butterfly(a, b, z), spec_inv_butterfly(a, b, z));
    }
}
