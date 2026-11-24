use crate::der_tlv::parse_der_tlv;
use crate::spec::DerError;

/// TODO (Task: der_parse_integer):
/// Parse a canonical non-negative DER `INTEGER` (tag `0x02`) into `u64` using `parse_der_tlv`.
/// Enforce exact X.690 minimality: reject wrong tag (`UnexpectedTag`), empty content (`InvalidInteger`),
/// negative sign bit (`NegativeInteger`), redundant leading `0x00` when next byte MSB is 0 (`NonCanonicalInteger`),
/// and magnitude exceeding 8 bytes (`IntegerOverflow`).
/// Must be 100% panic-free and safe (no `unsafe`, `unwrap`, `expect`, `panic!`, `todo!`).
pub fn parse_der_uint64(_input: &[u8]) -> Result<(u64, &[u8]), DerError> {
    let _ = parse_der_tlv;
    Err(DerError::InvalidInteger)
}
