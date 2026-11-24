use mldsa_arith::centered_mod::centered_mod;
use mldsa_arith::spec::{spec_centered_mod, HALF_Q, Q};

#[test]
fn exhaustive_centered_mod_all_q_residues() {
    for a in 0..Q {
        let got = centered_mod(a);
        let expected = spec_centered_mod(a);
        assert!(
            (-HALF_Q..=HALF_Q).contains(&got),
            "out of range for a={a}: got={got}"
        );
        assert_eq!(got, expected, "mismatch at a={a}");
    }
}
