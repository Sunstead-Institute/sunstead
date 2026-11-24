use crate::der_length::parse_der_length;
use crate::spec::{DerError, DerTlv};

/// TODO (Task: der_parse_tlv):
/// Parse a canonical single-byte-tag DER TLV element using `parse_der_length`.
/// Reject empty input (`UnexpectedEof`), high-tag-number `tag & 0x1F == 0x1F` (`UnsupportedTag`),
/// invalid length (propagate `DerError`), or truncated payload (`UnexpectedEof`).
/// Must be 100% panic-free and safe (no `unsafe`, `unwrap`, `expect`, `panic!`, `todo!`).
pub fn parse_der_tlv(_input: &[u8]) -> Result<(DerTlv<'_>, &[u8]), DerError> {
    let _ = parse_der_length;
    Err(DerError::UnexpectedEof)
}
