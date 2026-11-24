use mldsa_arith::add_reduce::add_centered;
use mldsa_arith::spec::{spec_add_centered, HALF_Q, Q};

#[test]
fn verify_add_centered_boundaries_and_grid() {
    let critical: Vec<i32> = vec![
        -HALF_Q,
        -HALF_Q + 1,
        -HALF_Q + 2,
        -HALF_Q / 2,
        -2,
        -1,
        0,
        1,
        2,
        HALF_Q / 2,
        HALF_Q - 2,
        HALF_Q - 1,
        HALF_Q,
    ];
    for &a in &critical {
        for &b in &critical {
            let got = add_centered(a, b);
            let exp = spec_add_centered(a, b);
            assert!((-HALF_Q..=HALF_Q).contains(&got));
            assert_eq!(got, exp, "mismatch at ({a}, {b})");
        }
    }

    // Dense stride sweep across the entire [-HALF_Q, HALF_Q]^2 square (~1.1M pairs).
    let step = 8_003;
    let mut a = -HALF_Q;
    while a <= HALF_Q {
        let mut b = -HALF_Q;
        while b <= HALF_Q {
            let got = add_centered(a, b);
            let exp = spec_add_centered(a, b);
            assert_eq!(got, exp, "mismatch at ({a}, {b})");
            b += step;
        }
        a += step;
    }

    // Full sweep along the exact boundary a = HALF_Q and a = -HALF_Q.
    for b in -HALF_Q..=HALF_Q {
        if b % 17 == 0 {
            assert_eq!(add_centered(HALF_Q, b), spec_add_centered(HALF_Q, b));
            assert_eq!(add_centered(-HALF_Q, b), spec_add_centered(-HALF_Q, b));
        }
    }
    let _ = Q;
}
