use crate::der_tlv::parse_der_tlv;
use crate::spec::DerError;

/// TODO (Task: der_parse_oid):
/// Parse a canonical DER `OBJECT IDENTIFIER` (tag `0x06`, X.690 §8.19) into `Vec<u32>` arcs
/// using `parse_der_tlv`.
/// Reject wrong tag (`UnexpectedTag`), empty content or truncated VLQ (`InvalidOid`),
/// non-minimal base-128 subidentifier starting with `0x80` (`NonCanonicalOid`),
/// and subidentifiers overflowing `u32::MAX` (`OidOverflow`).
/// Must be 100% panic-free and safe (no `unsafe`, `unwrap`, `expect`, `panic!`, `todo!`).
pub fn parse_der_oid(_input: &[u8]) -> Result<(Vec<u32>, &[u8]), DerError> {
    let _ = parse_der_tlv;
    Err(DerError::InvalidOid)
}
