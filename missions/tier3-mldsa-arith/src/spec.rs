//! FROZEN SPECIFICATION — NIST FIPS 204 (ML-DSA / Dilithium) prime modulus q = 2^23 - 2^13 + 1.

pub const Q: i32 = 8_380_417;
pub const HALF_Q: i32 = (Q - 1) / 2; // 4_190_208
pub const QINV: i32 = 58_728_449; // Q^(-1) mod 2^32
pub const R_MOD_Q: i64 = 4_193_792; // 2^32 mod Q
pub const RINV_MOD_Q: i64 = 8_265_825; // (2^32)^(-1) mod Q
pub const D_BITS: u32 = 13;
pub const HALF_TWO_D: i32 = 1 << (D_BITS - 1); // 4096

/// Reference specification for centered reduction of `a in [0, Q)`.
pub fn spec_centered_mod(a: i32) -> i32 {
    assert!((0..Q).contains(&a));
    if a > HALF_Q {
        a - Q
    } else {
        a
    }
}

/// Reference specification for conditional select.
pub fn spec_ct_select(cond: u32, a: i32, b: i32) -> i32 {
    if cond != 0 {
        a
    } else {
        b
    }
}

/// Reference specification for centered addition of `a, b in [-HALF_Q, HALF_Q]`.
pub fn spec_add_centered(a: i32, b: i32) -> i32 {
    assert!((-HALF_Q..=HALF_Q).contains(&a));
    assert!((-HALF_Q..=HALF_Q).contains(&b));
    let mut s = (a as i64) + (b as i64);
    if s > HALF_Q as i64 {
        s -= Q as i64;
    } else if s < -(HALF_Q as i64) {
        s += Q as i64;
    }
    s as i32
}

/// Reference specification for centered subtraction of `a, b in [-HALF_Q, HALF_Q]`.
pub fn spec_sub_centered(a: i32, b: i32) -> i32 {
    assert!((-HALF_Q..=HALF_Q).contains(&a));
    assert!((-HALF_Q..=HALF_Q).contains(&b));
    let mut s = (a as i64) - (b as i64);
    if s > HALF_Q as i64 {
        s -= Q as i64;
    } else if s < -(HALF_Q as i64) {
        s += Q as i64;
    }
    s as i32
}

/// Reference specification for FIPS 204 Algorithm 35: Power2Round (d = 13) for `r in [0, Q)`.
pub fn spec_power2round(r: i32) -> (i32, i32) {
    assert!((0..Q).contains(&r));
    let r1 = (r + HALF_TWO_D - 1) >> D_BITS;
    let r0 = r - (r1 << D_BITS);
    (r1, r0)
}

/// Check Montgomery reduction postconditions: |r| < Q and r * 2^32 ≡ a (mod Q).
pub fn spec_montgomery_ok(a: i64, r: i32) -> bool {
    if r <= -Q || r >= Q {
        return false;
    }
    let lhs = (r as i128) * (1i128 << 32);
    let rhs = a as i128;
    (lhs - rhs).rem_euclid(Q as i128) == 0
}

/// Reference specification for centered Cooley-Tukey butterfly with Montgomery-encoded twiddle `zeta_mont`.
pub fn spec_ct_butterfly(a: i32, b: i32, zeta_mont: i32) -> (i32, i32) {
    assert!((-HALF_Q..=HALF_Q).contains(&a));
    assert!((-HALF_Q..=HALF_Q).contains(&b));
    assert!((-HALF_Q..=HALF_Q).contains(&zeta_mont));
    let q = Q as i128;
    let prod = ((b as i128) * (zeta_mont as i128)).rem_euclid(q);
    let t = (prod * (RINV_MOD_Q as i128)).rem_euclid(q) as i32;
    let t_c = spec_centered_mod(t);
    (spec_add_centered(a, t_c), spec_sub_centered(a, t_c))
}
