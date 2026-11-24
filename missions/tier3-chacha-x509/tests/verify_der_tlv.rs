use chacha_x509::der_tlv::parse_der_tlv;
use chacha_x509::spec::{spec_parse_der_tlv, DerError};

#[test]
fn verify_der_tlv_canonical_and_fuzz() {
    let mut long_payload = vec![0x04, 0x81, 0x80];
    long_payload.extend(std::iter::repeat(0xAB).take(128));
    long_payload.push(0x99);

    let cases: &[&[u8]] = &[
        &[],
        &[0x05, 0x00],
        &[0x05, 0x00, 0xFF],
        &[0x02, 0x01, 0x05],
        &[0x02, 0x02, 0x05], // truncated payload
        &[0x1F, 0x01, 0x00], // high tag number unsupported
        &[0x3F, 0x01, 0x00], // high tag number unsupported
        &[0x30, 0x80, 0x00, 0x00], // indefinite
        &[0x30, 0x81, 0x01, 0x00], // non-canonical length
        &[0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF, 0x00], // huge length -> UnexpectedEof (no overflow!)
        &long_payload,
    ];
    for &c in cases {
        assert_eq!(parse_der_tlv(c), spec_parse_der_tlv(c), "mismatch on {c:02x?}");
    }
    assert_eq!(parse_der_tlv(&[0x1F, 0x00]), Err(DerError::UnsupportedTag));
    assert_eq!(parse_der_tlv(&[0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF]), Err(DerError::UnexpectedEof));

    // 50k fuzz byte strings
    let mut s: u64 = 0x2718_2818_2845_9045;
    let mut buf = [0u8; 16];
    for _ in 0..50_000 {
        s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
        let len = (s % 17) as usize;
        for b in &mut buf[..len] {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1);
            *b = (s >> 56) as u8;
        }
        assert_eq!(parse_der_tlv(&buf[..len]), spec_parse_der_tlv(&buf[..len]));
    }
}
