//! Custom packet protocol implementation.

use crate::{error::FpgaDriverError, traits::Data, FpgaDriverResult};

pub const PROTO_HEADER_BYTES: usize = 1;
pub const PROTO_ADDRESS_BYTES: usize = 2;
pub const PROTO_META_BYTES: usize = PROTO_HEADER_BYTES + PROTO_ADDRESS_BYTES;
pub const PROTO_PAYLOAD_MAX_SIZE: usize = 15;
pub const PROTO_MAX_PACKET_SIZE: usize = PROTO_META_BYTES + PROTO_PAYLOAD_MAX_SIZE;
pub const READ_FIFO_DEPTH: usize = 4096;

#[derive(Debug, Copy, Clone)]
struct ReadContiguous {
    num_bytes: u8,
    address: u16,
}

#[derive(Debug, Clone)]
struct WriteContiguous {
    payload: Box<[u8]>,
    address: u16,
}

#[derive(Debug, Copy, Clone)]
struct ReadFifo {
    num_bytes: u16,
    id: u8,
}

#[derive(Debug, Clone)]
enum TransactionKind {
    ReadContiguous(ReadContiguous),
    ReadFifo(ReadFifo),
    WriteContiguous(WriteContiguous),
}

/// Representation of packet in custom protocol for host <-> FPGA serial communication.
pub struct Packet(TransactionKind);
impl Packet {
    /// Construct a contiguous read transaction packet for the given target register address.
    pub fn contiguous_read<D: Data>(target_reg_address: u16) -> FpgaDriverResult<Self> {
        let num_bytes = std::mem::size_of::<D>();
        if num_bytes > PROTO_PAYLOAD_MAX_SIZE {
            return Err(FpgaDriverError::ProtocolMaxPayloadBytesExceeded {
                max_supported: PROTO_PAYLOAD_MAX_SIZE,
                encountered: num_bytes,
            });
        }
        Ok(Self(TransactionKind::ReadContiguous(ReadContiguous {
            num_bytes: num_bytes as u8,
            address: target_reg_address,
        })))
    }
    /// Construct a contiguous write transaction packet for the given the payload and target register address.
    pub fn contiguous_write(payload: Box<[u8]>, target_reg_address: u16) -> FpgaDriverResult<Self> {
        let num_bytes = payload.len();
        if num_bytes > PROTO_PAYLOAD_MAX_SIZE {
            return Err(FpgaDriverError::ProtocolMaxPayloadBytesExceeded {
                max_supported: PROTO_PAYLOAD_MAX_SIZE,
                encountered: num_bytes,
            });
        }
        Ok(Self(TransactionKind::WriteContiguous(WriteContiguous {
            payload,
            address: target_reg_address,
        })))
    }
    /// Construct a FIFO read transaction packet for a given number of bytes and target FIFO ID.
    pub fn read_fifo(num_bytes: usize, id: u8) -> FpgaDriverResult<Self> {
        if num_bytes > READ_FIFO_DEPTH {
            return Err(FpgaDriverError::ReadFifoRequestExceedsFifoDepth {
                depth: READ_FIFO_DEPTH,
                encountered: num_bytes,
            });
        }
        Ok(Self(TransactionKind::ReadFifo(ReadFifo {
            num_bytes: num_bytes as u16,
            id,
        })))
    }
    /// Convert packet structure to little endian bytes per protocol definition.
    pub fn to_le_bytes(self) -> FpgaDriverResult<Vec<u8>> {
        let mut vec: Vec<u8> = Vec::with_capacity(PROTO_MAX_PACKET_SIZE);
        let mut single_byte_header: u8;
        match self.0 {
            TransactionKind::ReadContiguous(ref r) => {
                single_byte_header = r.num_bytes;
                single_byte_header &= !(1 << 7);
            }
            TransactionKind::WriteContiguous(ref w) => {
                single_byte_header = w.payload.len() as u8;
                single_byte_header |= 1 << 7;
            }
            TransactionKind::ReadFifo(ref r) => {
                single_byte_header = r.id;
                single_byte_header &= !(1 << 7);
                single_byte_header |= 1 << 6;
            }
        };
        vec.push(single_byte_header);
        match self.0 {
            TransactionKind::ReadContiguous(ref r) => {
                vec.extend_from_slice(&r.address.to_le_bytes())
            }
            TransactionKind::WriteContiguous(ref w) => {
                vec.extend_from_slice(&w.address.to_le_bytes())
            }
            TransactionKind::ReadFifo(r) => vec.extend_from_slice(&r.num_bytes.to_le_bytes()),
        }
        if let TransactionKind::WriteContiguous(ref w) = self.0 {
            vec.extend_from_slice(&w.payload);
        }
        match self.0 {
            TransactionKind::ReadContiguous(_) | TransactionKind::ReadFifo(_) => {
                if vec.len() != PROTO_META_BYTES {
                    return Err(FpgaDriverError::MalformedReadPacket {
                        expected_bytes: PROTO_META_BYTES,
                        encountered_bytes: vec.len(),
                    });
                }
            }
            TransactionKind::WriteContiguous(p) => {
                if vec.len() != PROTO_META_BYTES + p.payload.len() {
                    return Err(FpgaDriverError::MalformedWritePacket {
                        expected_bytes: PROTO_META_BYTES + p.payload.len(),
                        encountered_bytes: vec.len(),
                    });
                }
            }
        }
        Ok(vec)
    }
}
