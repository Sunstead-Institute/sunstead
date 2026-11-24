// Task decode_pair_flags.
//
// base16ct 1.0.0 `src/lib.rs` `decode_inner` decodes each pair of input
// characters with
//
//     let byte = (decode_nibble(src[0]) << 4) | decode_nibble(src[1]);
//     err |= byte >> 8;
//     *dst = byte as u8;
//
// and reports an error iff `err != 0` at the end. decode_nibble returns a value
// below 16, or 0xffff for a rejected character. Show that `byte >> 8` is zero
// exactly when both characters were accepted, and that the output byte is then
// `hi * 16 + lo`.
use vstd::prelude::*;
use crate::spec::*;

verus! {

pub proof fn decode_pair_flags(hi: u16, lo: u16)
    requires
        hi < 16 || hi == 0xffff,
        lo < 16 || lo == 0xffff,
    ensures
        (((hi << 4u16) | lo) >> 8u16 == 0) <==> (hi < 16 && lo < 16),
        (hi < 16 && lo < 16) ==> ((hi << 4u16) | lo) as u8 == hi * 16 + lo,
{
}

} // verus!
