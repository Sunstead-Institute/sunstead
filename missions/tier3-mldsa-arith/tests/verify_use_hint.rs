use mldsa_arith::spec::{spec_decompose, spec_make_hint, spec_use_hint, DECOMPOSE_M, GAMMA2, Q};
use mldsa_arith::use_hint::use_hint;

#[test]
fn exhaustive_use_hint_all_q_residues_and_fips_identity() {
    for r in 0..Q {
        for h in 0..=1u32 {
            let got = use_hint(h, r);
            let exp = spec_use_hint(h, r);
            assert!(
                (0..DECOMPOSE_M).contains(&got),
                "use_hint out of range at h={h}, r={r}: {got}"
            );
            assert_eq!(got, exp, "mismatch at h={h}, r={r}");
        }
    }

    // Also confirm FIPS 204 recovery lemma on boundary perturbations |z| <= GAMMA2.
    let samples_z: &[i32] = &[-GAMMA2, -GAMMA2 + 1, -1, 0, 1, GAMMA2 - 1, GAMMA2];
    let samples_r: &[i32] = &[
        0,
        1,
        GAMMA2,
        GAMMA2 + 1,
        Q - GAMMA2 - 1,
        Q - GAMMA2,
        Q - 1,
    ];
    for &r in samples_r {
        for &z in samples_z {
            let h = spec_make_hint(z, r);
            let recovered = use_hint(h, r);
            let expected_high = spec_decompose((r + z).rem_euclid(Q)).0;
            assert_eq!(recovered, expected_high, "FIPS 204 recovery failed at z={z}, r={r}");
        }
    }
}
