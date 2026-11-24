use crate::spec::DerError;

/// TODO (Task: der_parse_length):
/// Parse a canonical ITU-T X.690 DER definite length (up to 4 length octets / `u32::MAX`).
/// Reject empty input (`UnexpectedEof`), indefinite `0x80` (`IndefiniteLength`),
/// `0xFF` or `> 4` octets (`LengthOverflow`), truncated octets (`UnexpectedEof`),
/// and non-minimal encodings (`NonCanonicalLength`: leading `0x00` or long-form value `< 128`).
/// Must be 100% panic-free and safe (no `unsafe`, `unwrap`, `expect`, `panic!`, `todo!`).
pub fn parse_der_length(_input: &[u8]) -> Result<(usize, &[u8]), DerError> {
    Err(DerError::UnexpectedEof)
}
