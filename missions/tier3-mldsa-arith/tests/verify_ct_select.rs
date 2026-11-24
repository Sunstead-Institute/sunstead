use mldsa_arith::ct_select::ct_select_i32;
use mldsa_arith::spec::{spec_ct_select, HALF_Q, Q};

#[test]
fn verify_ct_select_exhaustive_edge_cases() {
    let conds: &[u32] = &[
        0,
        1,
        2,
        3,
        7,
        255,
        0x0000_FFFF,
        0x0001_0000,
        0x7FFF_FFFF,
        0x8000_0000,
        0x8000_0001,
        0xDEAD_BEEF,
        u32::MAX - 1,
        u32::MAX,
    ];
    let vals: &[i32] = &[
        i32::MIN,
        i32::MIN + 1,
        -Q,
        -HALF_Q,
        -1,
        0,
        1,
        HALF_Q,
        Q - 1,
        Q,
        i32::MAX - 1,
        i32::MAX,
    ];

    for &c in conds {
        for &a in vals {
            for &b in vals {
                assert_eq!(
                    ct_select_i32(c, a, b),
                    spec_ct_select(c, a, b),
                    "mismatch for cond={c:#x}, a={a}, b={b}"
                );
            }
        }
    }

    // Also sweep 65,536 deterministic condition values.
    for c in 0u32..65_536 {
        let a = ((c.wrapping_mul(2654435761)) as i32) ^ 0x5555_5555;
        let b = !a;
        assert_eq!(ct_select_i32(c, a, b), spec_ct_select(c, a, b));
    }
}
