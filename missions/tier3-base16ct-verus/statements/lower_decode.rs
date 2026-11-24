// Task lower_decode_nibble: 0-9 and a-f decode to their value; every other byte to 0xffff.
// The function below is base16ct 1.0.0 `src/lower.rs` `decode_nibble`, copied verbatim;
// only the `ensures` clause (the specification) is added.
use vstd::prelude::*;
use crate::spec::*;

verus! {

pub fn decode_nibble(src: u8) -> (r: u16)
    ensures
        r == nibble_result(src, is_digit(src) || is_lower_af(src)),
{
    // 0-9  0x30-0x39
    // A-F  0x41-0x46 or a-f  0x61-0x66
    let byte = src as i16;
    let mut ret: i16 = -1;

    // 0-9  0x30-0x39
    // if (byte > 0x2f && byte < 0x3a) ret += byte - 0x30 + 1; // -47
    ret += (((0x2fi16 - byte) & (byte - 0x3a)) >> 8) & (byte - 47);
    // a-f  0x61-0x66
    // if (byte > 0x60 && byte < 0x67) ret += byte - 0x61 + 10 + 1; // -86
    ret += (((0x60i16 - byte) & (byte - 0x67)) >> 8) & (byte - 86);

    ret as u16
}

} // verus!
