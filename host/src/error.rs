//! FPGA driver library errors.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum FpgaDriverError {
    #[error("Protocol only supports {max_supported} bytes but tried to form packet with {encountered} payload bytes")]
    ProtocolMaxPayloadBytesExceeded {
        max_supported: usize,
        encountered: usize,
    },
    #[error("Read packet should be {expected_bytes} bytes but serialized with {encountered_bytes} bytes")]
    MalformedReadPacket {
        expected_bytes: usize,
        encountered_bytes: usize,
    },
    #[error("Write packet should be {expected_bytes} bytes but serialized with {encountered_bytes} bytes")]
    MalformedWritePacket {
        expected_bytes: usize,
        encountered_bytes: usize,
    },
    #[error(
        "Attempt to read more elements ({encountered}) from FIFO than maximum depth ({depth})"
    )]
    ReadFifoRequestExceedsFifoDepth { depth: usize, encountered: usize },
    #[error("Wrong number of bytes provided ({encountered_bytes}) to cast to `{ty}` (need {expected_bytes})")]
    WrongNumBytesToCastToConcreteType {
        ty: &'static str,
        expected_bytes: usize,
        encountered_bytes: usize,
    },
    #[error("Error trying to write packet cause by {source}")]
    SendPacketIo { source: std::io::Error },
    #[error("Error trying to read bytes from FPGA caused by {source}")]
    ReadBytes { source: std::io::Error },
    #[error("Error trying to clear the serial port buffer caused by {source}")]
    ClearPort { source: serialport::Error },
}
