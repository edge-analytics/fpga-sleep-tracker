//! Traits for an FPGA session.

use crate::FpgaDriverResult;

/// Trait for FPGA data types to serialize/deserialize to/from little-endian bytes.
pub trait Data: Sized {
    /// From little-endian byte slice.
    fn from_le_bytes(bytes: &[u8]) -> FpgaDriverResult<Self>;
    /// To little-endian byte `Vec`.
    fn to_le_bytes(self) -> Box<[u8]>;
}
