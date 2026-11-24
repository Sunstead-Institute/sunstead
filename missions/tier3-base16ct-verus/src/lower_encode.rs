// Task lower_encode_nibble: every nibble encodes to its lower-case hex digit.
// The function below is base16ct 1.0.0 `src/lower.rs` `encode_nibble`, copied verbatim;
// only the `ensures` clause (the specification) is added.
use vstd::prelude::*;
use crate::spec::*;

verus! {

pub fn encode_nibble(src: u8) -> (r: u8)
    ensures
        src < 16 ==> r == lower_digit(src),
{
    let mut ret = src as i16 + 0x30;
    // 0-9  0x30-0x39
    // a-f  0x61-0x66
    ret += ((0x39i16 - ret) >> 8) & (0x61i16 - 0x3a);
    ret as u8
}

} // verus!
