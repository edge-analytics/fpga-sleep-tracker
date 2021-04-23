//! Library to interact with FPGA+ sleep tracker demo via a Session API.

use std::sync::Mutex;
use std::time::Duration;

use lazy_static::lazy_static;
use serialport::{DataBits, FlowControl, Parity, StopBits};

pub mod data;
pub mod error;
pub mod protocol;
pub mod session;
pub mod traits;

use session::SerialSesh;

/// Result type for FPGA driver communication with simple custom protocol.
pub type FpgaDriverResult<T> = std::result::Result<T, error::FpgaDriverError>;

const PORT: &str = "/dev/cu.usbserial-141401";
const BAUD_RATE: u32 = 115_200;
const DATA_BITS: DataBits = DataBits::Eight;
const FLOW_CONTROL: FlowControl = FlowControl::None;
const PARITY: Parity = Parity::None;
const STOP_BITS: StopBits = StopBits::One;
const TIMEOUT: Duration = Duration::from_millis(5_000);

struct Fpga(Option<SerialSesh>);
impl Fpga {
    fn take(&mut self) -> SerialSesh {
        let sesh = self.0.take();
        sesh.expect("It is forbidden to create more than one FPGA session!")
    }
}

lazy_static! {
    /// Global FPGA handle to be accessed through singleton pattern.
    static ref PORT_TO_FPGA: Mutex<Fpga> = {
        let port = match serialport::new(PORT, BAUD_RATE)
            .data_bits(DATA_BITS)
            .flow_control(FLOW_CONTROL)
            .parity(PARITY)
            .stop_bits(STOP_BITS)
            .timeout(TIMEOUT)
            .open()
        {
            Ok(p) => p,
            Err(e) => panic!(
                "ERROR trying to open serial port {}: {}",
                PORT, e
            ),
        };
        Mutex::new(Fpga(Some(SerialSesh::new(port))))
    };
}
/// Take FPGA session singleton. User must uphold invariant to only call once
/// to avoid a runtime panic.
pub fn take_fpga_session() -> SerialSesh {
    PORT_TO_FPGA.lock().unwrap().take()
}
