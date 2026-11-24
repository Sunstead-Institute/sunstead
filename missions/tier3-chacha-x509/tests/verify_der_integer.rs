use chacha_x509::der_integer::parse_der_uint64;
use chacha_x509::spec::{spec_parse_der_uint64, DerError};

#[test]
fn verify_der_uint64_canonical_and_fuzz() {
    let cases: &[&[u8]] = &[
        &[],
        &[0x03, 0x01, 0x00],                                            // wrong tag
        &[0x02, 0x00],                                                  // empty integer
        &[0x02, 0x01, 0x00],                                            // 0
        &[0x02, 0x01, 0x01],                                            // 1
        &[0x02, 0x01, 0x7F],                                            // 127
        &[0x02, 0x01, 0x80],                                            // -128 (negative!)
        &[0x02, 0x02, 0x00, 0x80],                                      // +128 (valid sign pad)
        &[0x02, 0x02, 0x00, 0x7F],                                      // non-canonical leading zero!
        &[0x02, 0x02, 0x00, 0x00],                                      // non-canonical zero!
        &[0x02, 0x03, 0x01, 0x00, 0x01, 0xAA],                          // 65537 (RSA F4) + trailing
        &[0x02, 0x08, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],  // i64::MAX
        &[0x02, 0x09, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], // u64::MAX
        &[0x02, 0x09, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], // overflow!
        &[0x02, 0x0A, 0x00, 0x80, 0, 0, 0, 0, 0, 0, 0, 0],                   // overflow!
    ];
    for &c in cases {
        assert_eq!(parse_der_uint64(c), spec_parse_der_uint64(c), "mismatch on {c:02x?}");
    }
    assert_eq!(parse_der_uint64(&[0x02, 0x01, 0x80]), Err(DerError::NegativeInteger));
    assert_eq!(parse_der_uint64(&[0x02, 0x02, 0x00, 0x7F]), Err(DerError::NonCanonicalInteger));
    assert_eq!(
        parse_der_uint64(&[0x02, 0x09, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
        Ok((u64::MAX, &[][..]))
    );

    // 50k fuzz cases with tag 0x02 bias
    let mut s: u64 = 0x1618_0339_8874_9895;
    let mut buf = [0u8; 16];
    for i in 0..50_000 {
        s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
        let len = (s % 16) as usize;
        for b in &mut buf[..len] {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            *b = (s >> 56) as u8;
        }
        if len >= 2 && i % 2 == 0 {
            buf[0] = 0x02;
            buf[1] = ((s >> 48) as u8) % 12;
        }
        assert_eq!(parse_der_uint64(&buf[..len]), spec_parse_der_uint64(&buf[..len]));
    }
}
