// Task mixed_pair_correct (needs decode_pair_flags and mixed_decode_nibble).
//
// Combine the specification of the mixed-case decode_nibble with
// decode_pair_flags: for any two input bytes, base16ct's mixed-case decoder
// flags an error exactly when one of them is not a hex digit, and otherwise
// writes the byte they encode.
use vstd::prelude::*;
use crate::spec::*;

verus! {

pub proof fn mixed_pair_correct(c0: u8, c1: u8)
    ensures
        ({
            let hi = nibble_result(c0, is_hex(c0));
            let lo = nibble_result(c1, is_hex(c1));
            let byte = (hi << 4u16) | lo;
            &&& ((byte >> 8u16 == 0) <==> (is_hex(c0) && is_hex(c1)))
            &&& ((is_hex(c0) && is_hex(c1)) ==> byte as u8 == hex_value(c0) * 16 + hex_value(c1))
        }),
{
}

} // verus!
