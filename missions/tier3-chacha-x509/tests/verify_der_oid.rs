use chacha_x509::der_oid::parse_der_oid;
use chacha_x509::spec::{spec_parse_der_oid, DerError};

#[test]
fn verify_der_oid_x509_vectors_and_fuzz() {
    // sha256WithRSAEncryption: 1.2.840.113549.1.1.11
    let rsa_sha256: &[u8] = &[0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0xFF];
    assert_eq!(
        parse_der_oid(rsa_sha256),
        Ok((vec![1, 2, 840, 113549, 1, 1, 11], &[0xFF][..]))
    );

    // NIST FIPS 204 ML-DSA-44: 2.16.840.1.101.3.4.3.17
    let mldsa44: &[u8] = &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x03, 0x11];
    assert_eq!(
        parse_der_oid(mldsa44),
        Ok((vec![2, 16, 840, 1, 101, 3, 4, 3, 17], &[][..]))
    );

    // Arc 2 with large second component: 2.999.3 (2*40 + 999 = 1079 = 0x88 0x37)
    let large_arc2: &[u8] = &[0x06, 0x03, 0x88, 0x37, 0x03];
    assert_eq!(parse_der_oid(large_arc2), Ok((vec![2, 999, 3], &[][..])));

    let cases: &[&[u8]] = &[
        &[],
        &[0x02, 0x01, 0x00],                         // wrong tag
        &[0x06, 0x00],                               // empty OID
        &[0x06, 0x01, 0x00],                         // 0.0
        &[0x06, 0x01, 0x27],                         // 0.39
        &[0x06, 0x01, 0x28],                         // 1.0
        &[0x06, 0x01, 0x4F],                         // 1.39
        &[0x06, 0x01, 0x50],                         // 2.0
        &[0x06, 0x02, 0x80, 0x01],                   // non-canonical leading 0x80!
        &[0x06, 0x03, 0x2a, 0x80, 0x01],             // non-canonical subid!
        &[0x06, 0x02, 0x2a, 0x81],                   // truncated VLQ!
        &[0x06, 0x06, 0x2a, 0x8F, 0xFF, 0xFF, 0xFF, 0x7F], // exact u32::MAX (0xFFFFFFFF)
        &[0x06, 0x06, 0x2a, 0x90, 0x80, 0x80, 0x80, 0x00], // overflow u32::MAX + 1!
    ];
    for &c in cases {
        assert_eq!(parse_der_oid(c), spec_parse_der_oid(c), "mismatch on {c:02x?}");
    }
    assert_eq!(parse_der_oid(&[0x06, 0x03, 0x2a, 0x80, 0x01]), Err(DerError::NonCanonicalOid));
    assert_eq!(parse_der_oid(&[0x06, 0x02, 0x2a, 0x81]), Err(DerError::InvalidOid));
    assert_eq!(
        parse_der_oid(&[0x06, 0x06, 0x2a, 0x90, 0x80, 0x80, 0x80, 0x00]),
        Err(DerError::OidOverflow)
    );

    // 50k fuzz slices with tag 0x06 bias
    let mut s: u64 = 0xB7E1_5162_8AED_2A6A;
    let mut buf = [0u8; 16];
    for i in 0..50_000 {
        s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
        let len = (s % 16) as usize;
        for b in &mut buf[..len] {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            *b = (s >> 56) as u8;
        }
        if len >= 2 && i % 2 == 0 {
            buf[0] = 0x06;
            buf[1] = ((s >> 48) as u8) % 12;
        }
        assert_eq!(parse_der_oid(&buf[..len]), spec_parse_der_oid(&buf[..len]));
    }
}
