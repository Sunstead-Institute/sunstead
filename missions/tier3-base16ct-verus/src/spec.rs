// Frozen specification for the base16ct Verus mission.
//
// Hex alphabet per RFC 4648 section 8: nibbles 0..=9 are the ASCII digits
// '0'..='9' (0x30..=0x39), nibbles 10..=15 are 'a'..='f' (0x61..=0x66) in
// lower case or 'A'..='F' (0x41..=0x46) in upper case.
use vstd::prelude::*;

verus! {

pub open spec fn is_digit(c: u8) -> bool { 0x30 <= c && c <= 0x39 }

pub open spec fn is_lower_af(c: u8) -> bool { 0x61 <= c && c <= 0x66 }

pub open spec fn is_upper_af(c: u8) -> bool { 0x41 <= c && c <= 0x46 }

pub open spec fn is_hex(c: u8) -> bool { is_digit(c) || is_lower_af(c) || is_upper_af(c) }

pub open spec fn lower_digit(n: u8) -> u8 {
    if n < 10 { (0x30 + n) as u8 } else { (0x61 + n - 10) as u8 }
}

pub open spec fn upper_digit(n: u8) -> u8 {
    if n < 10 { (0x30 + n) as u8 } else { (0x41 + n - 10) as u8 }
}

/// The nibble a hex character stands for (meaningful when is_hex(c)).
pub open spec fn hex_value(c: u8) -> u8 {
    if is_digit(c) {
        (c - 0x30) as u8
    } else if is_lower_af(c) {
        (c - 0x61 + 10) as u8
    } else {
        (c - 0x41 + 10) as u8
    }
}

/// What a base16ct decode_nibble returns: the value of an accepted character,
/// 0xffff for any other byte (decode_inner relies on this to flag errors).
pub open spec fn nibble_result(c: u8, accepted: bool) -> u16 {
    if accepted { hex_value(c) as u16 } else { 0xffff }
}

} // verus!
