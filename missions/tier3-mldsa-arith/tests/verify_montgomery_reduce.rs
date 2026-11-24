use mldsa_arith::montgomery::montgomery_reduce;
use mldsa_arith::spec::{spec_montgomery_ok, HALF_Q, Q};

#[test]
fn verify_montgomery_reduce_boundaries_and_sweep() {
    let max_a: i64 = ((i32::MAX as i64) - 1) * (Q as i64);
    let min_a: i64 = -max_a;

    let critical: &[i64] = &[
        min_a,
        min_a + 1,
        -(Q as i64) * (Q as i64),
        -(HALF_Q as i64) * (HALF_Q as i64),
        -(1i64 << 32),
        -(Q as i64) - 1,
        -(Q as i64),
        -(Q as i64) + 1,
        -1,
        0,
        1,
        Q as i64 - 1,
        Q as i64,
        Q as i64 + 1,
        1i64 << 32,
        (HALF_Q as i64) * (HALF_Q as i64),
        (Q as i64) * (Q as i64),
        max_a - 1,
        max_a,
    ];

    for &a in critical {
        let r = montgomery_reduce(a);
        assert!(
            spec_montgomery_ok(a, r),
            "montgomery_reduce({a}) = {r} violated spec"
        );
    }

    // Sweep 1,000,000 deterministic products across [-max_a, max_a].
    let mut state: u64 = 0x9E37_79B9_7F4A_7C15;
    for _ in 0..1_000_000 {
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let x = ((state >> 32) as i32) as i64;
        let y = (((state & 0xFFFF_FFFF) as u32) % (Q as u32)) as i64 - (HALF_Q as i64);
        let a = x * y;
        if a >= min_a && a <= max_a {
            let r = montgomery_reduce(a);
            assert!(
                spec_montgomery_ok(a, r),
                "montgomery_reduce({a}) = {r} violated spec"
            );
        }
    }
}
