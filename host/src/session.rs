//! Implementation of FPGA Session API for a simple serial port API.

use crate::data::{SleepTrackerOutput, SleepTrackerOutputVec};
use crate::error::FpgaDriverError;
use crate::protocol::{Packet, PROTO_MAX_PACKET_SIZE, PROTO_PAYLOAD_MAX_SIZE, READ_FIFO_DEPTH};
use crate::traits::Data;
use crate::FpgaDriverResult;
use serialport::SerialPort;

pub const INPUT_BASE_ADDRESS: u16 = 0;
pub const OUTPUT_BASE_ADDRESS: u16 = 64;
pub const COMMAND_REG_ADDRESS: u16 = 128;
pub const STATUS_REG_ADDRESS: u16 = 129;

/// Session for FPGA I/O through an RS-232 serial port.
pub struct SerialSesh {
    port: Box<dyn SerialPort>,
    read_fifo_buf: [u8; READ_FIFO_DEPTH],
    read_reg_buf: [u8; PROTO_PAYLOAD_MAX_SIZE],
    write_reg_buf: [u8; PROTO_MAX_PACKET_SIZE],
}
impl SerialSesh {
    /// Constructor for RS-232 FPGA session.
    pub fn new(port: Box<dyn SerialPort>) -> Self {
        Self {
            port,
            read_fifo_buf: [0u8; READ_FIFO_DEPTH],
            read_reg_buf: [0u8; PROTO_PAYLOAD_MAX_SIZE],
            write_reg_buf: [0u8; PROTO_MAX_PACKET_SIZE],
        }
    }
}
impl SerialSesh {
    fn clear_read_reg_buf(&mut self) {
        self.read_reg_buf.iter_mut().for_each(|v| *v = 0);
    }
    fn clear_read_fifo_buf(&mut self) {
        self.read_fifo_buf.iter_mut().for_each(|v| *v = 0);
    }
    fn clear_write_reg_buf(&mut self) {
        self.write_reg_buf.iter_mut().for_each(|v| *v = 0);
    }
    fn clear_port(&mut self) -> FpgaDriverResult<()> {
        self.port
            .clear(serialport::ClearBuffer::All)
            .map_err(|source| FpgaDriverError::ClearPort { source })
    }
    fn send_packet(&mut self, p: Packet) -> FpgaDriverResult<()> {
        let packet_bytes = p.to_le_bytes()?;
        let plen = packet_bytes.len();
        eprintln!("Sending packet bytes: {:?}", &packet_bytes[0..plen]);
        self.write_reg_buf[0..plen].copy_from_slice(&packet_bytes[0..plen]);
        self.port
            .write_all(&self.write_reg_buf[0..plen])
            .map_err(|source| FpgaDriverError::SendPacketIo { source })?;
        self.clear_write_reg_buf();
        Ok(())
    }
    fn read_bytes(&mut self, num_bytes: usize) -> FpgaDriverResult<Vec<u8>> {
        self.port
            .read_exact(&mut self.read_reg_buf[0..num_bytes])
            .map_err(|source| FpgaDriverError::ReadBytes { source })?;
        let mut vec = Vec::with_capacity(num_bytes);
        vec.extend_from_slice(&self.read_reg_buf[0..num_bytes]);
        self.clear_read_reg_buf();
        Ok(vec)
    }
    fn send_read_packet<T: Data>(&mut self, target_address: u16) -> FpgaDriverResult<()> {
        let packet = Packet::contiguous_read::<T>(target_address)?;
        self.send_packet(packet)
    }
    /// Try to read any type that implements the `Data` trait.
    pub fn read_data<T: Data>(&mut self, target_address: u16) -> FpgaDriverResult<T> {
        self.send_read_packet::<T>(target_address)?;
        std::thread::sleep(std::time::Duration::from_millis(100));
        let bytes = self.read_bytes(std::mem::size_of::<T>())?;
        T::from_le_bytes(bytes.as_slice())
    }
    /// Try to read bytes from the FPGA FIFO.
    pub fn read_fifo(
        &mut self,
        num_bytes: usize,
        id: u8,
    ) -> FpgaDriverResult<Vec<SleepTrackerOutput>> {
        self.clear_port()?;
        std::thread::sleep(std::time::Duration::from_millis(100));
        let packet = Packet::read_fifo(num_bytes, id)?;
        self.send_packet(packet)?;
        let num_read = self
            .port
            .read(&mut self.read_fifo_buf[0..num_bytes])
            .map_err(|source| FpgaDriverError::ReadBytes { source })?;
        let mut byte_vec = Vec::with_capacity(num_read);
        byte_vec.extend_from_slice(&self.read_fifo_buf[0..num_read]);
        self.clear_read_fifo_buf();
        Ok(SleepTrackerOutputVec::from(byte_vec).into_vec())
    }
    /// Try to read all available bytes from the FPGA FIFO.
    pub fn read_fifo_all(&mut self, id: u8) -> FpgaDriverResult<Vec<SleepTrackerOutput>> {
        self.read_fifo(READ_FIFO_DEPTH, id)
    }
    /// Read the status register.
    pub fn read_status_register(&mut self) -> FpgaDriverResult<u8> {
        self.read_data(STATUS_REG_ADDRESS)
    }
    /// Read the status bit of the status register.
    pub fn calc_is_done(&mut self) -> FpgaDriverResult<bool> {
        Ok(self.read_status_register()? >> 7 != 0)
    }
    /// Read the command register.
    pub fn read_command_register(&mut self) -> FpgaDriverResult<u8> {
        self.read_data(COMMAND_REG_ADDRESS)
    }
    /// Try to send a write packet.
    pub fn write_data<T: Data>(&mut self, payload: T, target_address: u16) -> FpgaDriverResult<()> {
        let packet = Packet::contiguous_write(payload.to_le_bytes(), target_address)?;
        self.send_packet(packet)
    }
    /// Start a data acquisition session.
    pub fn start(&mut self) -> FpgaDriverResult<()> {
        self.write_data(0x80_u8, COMMAND_REG_ADDRESS)
    }
    /// Stop a data acquisition session.
    pub fn stop(&mut self) -> FpgaDriverResult<()> {
        self.write_data(0x00_u8, COMMAND_REG_ADDRESS)
    }
    /// Clear the status register.
    pub fn clear_status(&mut self) -> FpgaDriverResult<()> {
        self.write_data(0x00_u8, STATUS_REG_ADDRESS)
    }
}
impl Drop for SerialSesh {
    fn drop(&mut self) {
        eprintln!("Dropping FPGA serial port session!");
        if let Err(e) = self.stop() {
            eprintln!("Failed to send stop command caused by: {}", e);
        }
        if let Err(e) = self.clear_status() {
            eprintln!("Fialed to send clear status command caused by: {}", e);
        }
    }
}
