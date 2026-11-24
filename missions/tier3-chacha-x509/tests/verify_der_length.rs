use chacha_x509::der_length::parse_der_length;
use chacha_x509::spec::{spec_parse_der_length, DerError};

#[test]
fn verify_der_length_canonical_and_fuzz() {
    // Exhaustive short form 0..128
    for b in 0u8..128 {
        let input = [b, 0xAA, 0xBB];
        assert_eq!(parse_der_length(&input), Ok((b as usize, &input[1..])));
    }

    // Adversarial & boundary vectors
    let cases: &[&[u8]] = &[
        &[],
        &[0x80],
        &[0x80, 0x00],
        &[0x81],
        &[0x81, 0x00],
        &[0x81, 0x7F],
        &[0x81, 0x80, 0xFF],
        &[0x81, 0xFF],
        &[0x82, 0x00, 0x80],
        &[0x82, 0x01, 0x00, 0xAA],
        &[0x82, 0x01],
        &[0x83, 0x00, 0x01, 0x00],
        &[0x83, 0x01, 0x02, 0x03, 0x99],
        &[0x84, 0xFF, 0xFF, 0xFF, 0xFF, 0x42],
        &[0x84, 0x00, 0x00, 0x01, 0x00],
        &[0x85, 0x01, 0x00, 0x00, 0x00, 0x00],
        &[0xFF, 0x01, 0x02],
    ];
    for &c in cases {
        assert_eq!(parse_der_length(c), spec_parse_der_length(c), "mismatch on {c:02x?}");
    }

    // Specific CVE-class rejections
    assert_eq!(parse_der_length(&[0x80]), Err(DerError::IndefiniteLength));
    assert_eq!(parse_der_length(&[0x81, 0x7F]), Err(DerError::NonCanonicalLength));
    assert_eq!(parse_der_length(&[0x82, 0x00, 0x80]), Err(DerError::NonCanonicalLength));
    assert_eq!(parse_der_length(&[0x85, 1, 2, 3, 4, 5]), Err(DerError::LengthOverflow));

    // 100k fuzz byte slices (must match spec and never panic)
    let mut s: u64 = 0x3141_5926_5358_9793;
    let mut buf = [0u8; 8];
    for _ in 0..100_000 {
        s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
        let len = (s % 9) as usize;
        for b in &mut buf[..len] {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            *b = (s >> 56) as u8;
        }
        assert_eq!(parse_der_length(&buf[..len]), spec_parse_der_length(&buf[..len]));
    }
}
