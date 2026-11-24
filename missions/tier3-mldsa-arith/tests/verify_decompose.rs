use mldsa_arith::decompose::decompose;
use mldsa_arith::spec::{spec_decompose, ALPHA, DECOMPOSE_M, GAMMA2, Q};

#[test]
fn exhaustive_decompose_all_q_residues() {
    for r in 0..Q {
        let (r1, r0) = decompose(r);
        let (e1, e0) = spec_decompose(r);
        assert!(
            (0..DECOMPOSE_M).contains(&r1),
            "r1 out of range at r={r}: r1={r1}"
        );
        assert!(
            (-GAMMA2..=GAMMA2).contains(&r0),
            "r0 out of range at r={r}: r0={r0}"
        );
        let recon = ((r1 as i64) * (ALPHA as i64) + (r0 as i64)).rem_euclid(Q as i64);
        assert_eq!(recon, r as i64, "modular reconstruction failed at r={r}");
        assert_eq!((r1, r0), (e1, e0), "mismatch at r={r}");
    }
}
