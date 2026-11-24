use mldsa_arith::spec::{spec_sub_centered, HALF_Q};
use mldsa_arith::sub_reduce::sub_centered;

#[test]
fn verify_sub_centered_boundaries_and_grid() {
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
            let got = sub_centered(a, b);
            let exp = spec_sub_centered(a, b);
            assert!((-HALF_Q..=HALF_Q).contains(&got));
            assert_eq!(got, exp, "mismatch at ({a}, {b})");
        }
    }

    let step = 8_003;
    let mut a = -HALF_Q;
    while a <= HALF_Q {
        let mut b = -HALF_Q;
        while b <= HALF_Q {
            assert_eq!(sub_centered(a, b), spec_sub_centered(a, b));
            b += step;
        }
        a += step;
    }
}
