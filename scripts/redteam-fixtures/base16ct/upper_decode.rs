// Task upper_decode_nibble: 0-9 and A-F decode to their value; every other byte to 0xffff.
// The function below is base16ct 1.0.0 `src/upper.rs` `decode_nibble`, copied verbatim;
// only the `ensures` clause (the specification) is added.
use vstd::prelude::*;
use crate::spec::*;

verus! {

pub fn decode_nibble(src: u8) -> (r: u16)
    ensures
        r == nibble_result(src, is_digit(src) || is_upper_af(src)),
{
    // 0-9  0x30-0x39
    // A-F  0x41-0x46 or a-f  0x61-0x66
    let byte = src as i16;
    let mut ret: i16 = -1;

    // 0-9  0x30-0x39
    // if (byte > 0x2f && byte < 0x3a) ret += byte - 0x30 + 1; // -47
    assert((((0x2fi16 - byte) as i16 & (byte - 0x3a) as i16) >> 8) & (byte - 47) as i16 ==
        (if 0x2f < byte && byte < 0x3a { (byte - 47) as i16 } else { 0i16 })) by (bit_vector)
        requires 0 <= byte && byte < 256;
    ret += (((0x2fi16 - byte) & (byte - 0x3a)) >> 8) & (byte - 47);
    // A-F  0x41-0x46
    // if (byte > 0x40 && byte < 0x47) ret += byte - 0x41 + 10 + 1; // -54
    assert((((0x40i16 - byte) as i16 & (byte - 0x47) as i16) >> 8) & (byte - 54) as i16 ==
        (if 0x40 < byte && byte < 0x47 { (byte - 54) as i16 } else { 0i16 })) by (bit_vector)
        requires 0 <= byte && byte < 256;
    ret += (((0x40i16 - byte) & (byte - 0x47)) >> 8) & (byte - 54);

    assert(-1i16 as u16 == 0xffffu16) by (bit_vector);
    ret as u16
}

} // verus!
