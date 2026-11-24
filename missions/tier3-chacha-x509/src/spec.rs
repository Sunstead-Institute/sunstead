//! FROZEN SPECIFICATION — RFC 8439 ChaCha20 constant-time primitives &
//! ITU-T X.690 canonical ASN.1 DER / X.509 parser primitives.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DerError {
    UnexpectedEof,
    IndefiniteLength,
    LengthOverflow,
    NonCanonicalLength,
    UnsupportedTag,
    UnexpectedTag,
    InvalidInteger,
    NegativeInteger,
    NonCanonicalInteger,
    IntegerOverflow,
    InvalidOid,
    NonCanonicalOid,
    OidOverflow,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DerTlv<'a> {
    pub tag: u8,
    pub value: &'a [u8],
}

/// Reference RFC 8439 §2.1 ChaCha20 quarter round.
pub fn spec_quarter_round(state: &mut [u32; 16], a: usize, b: usize, c: usize, d: usize) {
    state[a] = state[a].wrapping_add(state[b]);
    state[d] = (state[d] ^ state[a]).rotate_left(16);

    state[c] = state[c].wrapping_add(state[d]);
    state[b] = (state[b] ^ state[c]).rotate_left(12);

    state[a] = state[a].wrapping_add(state[b]);
    state[d] = (state[d] ^ state[a]).rotate_left(8);

    state[c] = state[c].wrapping_add(state[d]);
    state[b] = (state[b] ^ state[c]).rotate_left(7);
}

/// Reference RFC 8439 §2.3 ChaCha20 block function.
pub fn spec_chacha20_block(key: &[u8; 32], counter: u32, nonce: &[u8; 12]) -> [u8; 64] {
    let mut state = [0u32; 16];
    state[0] = 0x6170_7865;
    state[1] = 0x3320_646e;
    state[2] = 0x7962_2d32;
    state[3] = 0x6b20_6574;
    for i in 0..8 {
        state[4 + i] = u32::from_le_bytes([
            key[4 * i],
            key[4 * i + 1],
            key[4 * i + 2],
            key[4 * i + 3],
        ]);
    }
    state[12] = counter;
    for i in 0..3 {
        state[13 + i] = u32::from_le_bytes([
            nonce[4 * i],
            nonce[4 * i + 1],
            nonce[4 * i + 2],
            nonce[4 * i + 3],
        ]);
    }

    let mut working = state;
    for _ in 0..10 {
        // Column rounds
        spec_quarter_round(&mut working, 0, 4, 8, 12);
        spec_quarter_round(&mut working, 1, 5, 9, 13);
        spec_quarter_round(&mut working, 2, 6, 10, 14);
        spec_quarter_round(&mut working, 3, 7, 11, 15);
        // Diagonal rounds
        spec_quarter_round(&mut working, 0, 5, 10, 15);
        spec_quarter_round(&mut working, 1, 6, 11, 12);
        spec_quarter_round(&mut working, 2, 7, 8, 13);
        spec_quarter_round(&mut working, 3, 4, 9, 14);
    }

    let mut out = [0u8; 64];
    for i in 0..16 {
        let word = working[i].wrapping_add(state[i]).to_le_bytes();
        out[4 * i..4 * i + 4].copy_from_slice(&word);
    }
    out
}

/// Reference X.690 canonical DER definite length decoder (up to 4 length octets / u32::MAX).
pub fn spec_parse_der_length(input: &[u8]) -> Result<(usize, &[u8]), DerError> {
    let (&first, rest) = input.split_first().ok_or(DerError::UnexpectedEof)?;
    if first < 0x80 {
        return Ok((first as usize, rest));
    }
    if first == 0x80 {
        return Err(DerError::IndefiniteLength);
    }
    if first == 0xFF {
        return Err(DerError::LengthOverflow);
    }
    let num_octets = (first & 0x7F) as usize;
    if num_octets > 4 {
        return Err(DerError::LengthOverflow);
    }
    if rest.len() < num_octets {
        return Err(DerError::UnexpectedEof);
    }
    if rest[0] == 0x00 {
        return Err(DerError::NonCanonicalLength);
    }
    let mut len: u32 = 0;
    for &b in &rest[..num_octets] {
        len = (len << 8) | (b as u32);
    }
    if len < 128 {
        return Err(DerError::NonCanonicalLength);
    }
    Ok((len as usize, &rest[num_octets..]))
}

/// Reference canonical DER single-byte-tag TLV parser.
pub fn spec_parse_der_tlv(input: &[u8]) -> Result<(DerTlv<'_>, &[u8]), DerError> {
    let (&tag, rest) = input.split_first().ok_or(DerError::UnexpectedEof)?;
    if (tag & 0x1F) == 0x1F {
        return Err(DerError::UnsupportedTag);
    }
    let (len, after_len) = spec_parse_der_length(rest)?;
    if after_len.len() < len {
        return Err(DerError::UnexpectedEof);
    }
    let (value, rem) = after_len.split_at(len);
    Ok((DerTlv { tag, value }, rem))
}

/// Reference canonical DER non-negative INTEGER -> u64 parser (tag 0x02).
pub fn spec_parse_der_uint64(input: &[u8]) -> Result<(u64, &[u8]), DerError> {
    let (tlv, rem) = spec_parse_der_tlv(input)?;
    if tlv.tag != 0x02 {
        return Err(DerError::UnexpectedTag);
    }
    let bytes = tlv.value;
    if bytes.is_empty() {
        return Err(DerError::InvalidInteger);
    }
    if (bytes[0] & 0x80) != 0 {
        return Err(DerError::NegativeInteger);
    }
    if bytes.len() > 1 && bytes[0] == 0x00 && (bytes[1] & 0x80) == 0 {
        return Err(DerError::NonCanonicalInteger);
    }
    let mag = if bytes.len() > 1 && bytes[0] == 0x00 {
        &bytes[1..]
    } else {
        bytes
    };
    if mag.len() > 8 {
        return Err(DerError::IntegerOverflow);
    }
    let mut val: u64 = 0;
    for &b in mag {
        val = (val << 8) | (b as u64);
    }
    Ok((val, rem))
}

/// Reference canonical DER OBJECT IDENTIFIER parser (tag 0x06, X.690 §8.19).
pub fn spec_parse_der_oid(input: &[u8]) -> Result<(Vec<u32>, &[u8]), DerError> {
    let (tlv, rem) = spec_parse_der_tlv(input)?;
    if tlv.tag != 0x06 {
        return Err(DerError::UnexpectedTag);
    }
    let bytes = tlv.value;
    if bytes.is_empty() {
        return Err(DerError::InvalidOid);
    }
    let mut subids: Vec<u32> = Vec::new();
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == 0x80 {
            return Err(DerError::NonCanonicalOid);
        }
        let mut acc: u32 = 0;
        let mut terminated = false;
        while i < bytes.len() {
            let b = bytes[i];
            i += 1;
            if acc > (u32::MAX >> 7) {
                return Err(DerError::OidOverflow);
            }
            acc = (acc << 7) | ((b & 0x7F) as u32);
            if (b & 0x80) == 0 {
                terminated = true;
                break;
            }
        }
        if !terminated {
            return Err(DerError::InvalidOid);
        }
        subids.push(acc);
    }

    let first = subids[0];
    let (a0, a1) = if first < 40 {
        (0u32, first)
    } else if first < 80 {
        (1u32, first - 40)
    } else {
        (2u32, first - 80)
    };
    let mut arcs = Vec::with_capacity(subids.len() + 1);
    arcs.push(a0);
    arcs.push(a1);
    arcs.extend_from_slice(&subids[1..]);
    Ok((arcs, rem))
}
