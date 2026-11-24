// Frozen crate root for the base16ct Verus mission. Verify one task with
//     verus src/lib.rs --crate-type=lib --verify-module <module>
pub mod spec;
pub mod lower_encode;
pub mod lower_decode;
pub mod upper_encode;
pub mod upper_decode;
pub mod mixed_decode;
pub mod decode_pair;
pub mod mixed_pair;
