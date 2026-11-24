use mldsa_arith::power2round::power2round;
use mldsa_arith::spec::{spec_power2round, D_BITS, HALF_TWO_D, Q};

#[test]
fn exhaustive_power2round_all_q_residues() {
    for r in 0..Q {
        let (r1, r0) = power2round(r);
        let (e1, e0) = spec_power2round(r);
        assert!(
            r0 > -HALF_TWO_D && r0 <= HALF_TWO_D,
            "r0 out of range at r={r}: r0={r0}"
        );
        assert_eq!(
            (r1 << D_BITS) + r0,
            r,
            "reconstruction failed at r={r}: ({r1}, {r0})"
        );
        assert_eq!((r1, r0), (e1, e0), "mismatch at r={r}");
    }
}
