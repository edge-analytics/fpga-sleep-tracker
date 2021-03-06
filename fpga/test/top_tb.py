import cocotb
from cocotb.triggers import Timer
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.binary import BinaryValue
import numpy as np
from dataclasses import dataclass
from enum import Enum
from fixedpoint import FixedPoint
from typing import List

POWER_ON_RESET_DELAY_NS = 2000


class SleepWake(Enum):
    WAKE = 0
    SLEEP = 1


@dataclass
class PacketDelay:
    time_ns: int = 10000

# Simple host/target communication protocol should wait for reads to complete
# before sending a new write request. More complexity enabled by w/r buffering,
# packet token ids, and longer burst write/reads and true full duplex support 
# could be considered.
TEST_PACKETS = [
    [
        [1,0,0,0,0,0,0,1], # Write CMD register Start bit
        [1,0,0,0,0,0,0,0], # LSB = 128
        [0,0,0,0,0,0,0,0], # MSB = 0
        [1,0,0,0,0,0,0,0], # CMD_REG = 0x80 (Start)
    ],
    PacketDelay(10000000), # Wait for several NN computations to complete
    [
        [0,1,0,0,0,0,0,0], # Write Request FIFO output
        [0,0,0,0,0,1,0,0], # LSB = 2 Read two FIFO entries
        [0,0,0,0,0,0,0,0], # MSB = 0
    ]
]

class SimAccelerometer:

    def __init__(self, dut, fs, z_data):
        self.fs = fs
        self.clk = dut.clk
        self.z_data = z_data
        self.accel_z = dut.accel_z
        self.accel_valid = dut.accel_valid
    
    async def _wait_next_sample(self):
        sample_period_ns = int((1/self.fs) * 1e9)
        await Timer(sample_period_ns, units='ns')
    
    async def simulate(self):
        for z in self.z_data: 
            await self._wait_next_sample()
            self.accel_z <= BinaryValue(str(FixedPoint(z/5, signed=True, m=1, n=7, str_base=2)))
            self.accel_valid <= 1
            await ClockCycles(self.clk, 1)
            self.accel_z <= 0
            self.accel_valid <= 0


class Rs232:
    BAUD_RATE = 115200
    CLK_RATE = 6000000
    BITS = 8
    
    def __init__(self, dut):
        self.rx = dut.tx
        self.tx = dut.rx
        self.tx <= 1
        self.clk = dut.clk
        self.reset = dut.reset
        self.rx_count = 0
        self.tx_count = 0
    
    async def _wait_for_signal_level(self, signal, trigger_value):
        wait_for_trigger = True
        while wait_for_trigger:
            await RisingEdge(self.clk)
            wait_for_trigger = not signal.value == trigger_value

    async def _receive(self, recieve_data):
        while True:
            await self._wait_for_signal_level(self.rx, 0) # Start bit
            await self._wait_half_baud_period()
            rx_byte = []
            for _ in range(self.BITS):
                await self._wait_baud_period()
                rx_byte.append(self.rx.value)
            await self._wait_baud_period() # Stop bit
            print(f"RS232 Received Data {self.rx_count} Value: {rx_byte}")
            recieve_data.append(rx_byte)
            self.rx_count += 1

    async def _wait_baud_period(self):
        baud_period_ns = int((1/self.BAUD_RATE) * 1e9)
        await Timer(baud_period_ns, units='ns')
    
    async def _wait_half_baud_period(self):
        baud_half_period_ns = int((1/self.BAUD_RATE/2) * 1e9)
        await Timer(baud_half_period_ns, units='ns')

    async def _send(self, packets):
        for packet in packets:
            if type(packet) == PacketDelay:
                delay_ns = packet.time_ns
                await Timer(delay_ns, units='ns')
            else:
                for byte in packet:
                    self.tx <= 0 # Start Bit
                    byte.reverse()
                    await self._wait_baud_period()
                    for b in byte:
                        self.tx <= b
                        await self._wait_baud_period()
                    self.tx <= 1 # Stop Bit
                    await self._wait_baud_period()
                    print(f"RS232 Transmitted Data {self.tx_count} Value: {byte}")
                    self.tx_count += 1 
    
    async def simulate(self, rx_data=[]):
        global rx
        rx = rx_data
        print("Starting RS232 Simulation")
        await Timer(POWER_ON_RESET_DELAY_NS, units='ns')
        cocotb.fork(self._receive(rx))
        cocotb.fork(self._send(packets=TEST_PACKETS))


def bitlist_to_int(x: List[int]) -> int:
    s = [str(xi) for xi in x]
    s.reverse()
    return int("".join(s), 2)

@cocotb.test()
def test_top(dut):
    """ Exercise top level ports of sleep tracker"""
    dut._log.info("Running test!")

    # Load simulation data
    data = np.loadtxt('../../data/sleep_wake_classifier/46343_acceleration.txt', delimiter=' ')
    fs = 50
    time = np.arange(np.amin(data[:, 0]), np.amax(data[:, 0]), 1.0 / fs)
    z_data = np.interp(time, data[:, 0], data[:, 3])
    accelerated_fs = fs * 10000
    
    # Simulation time parameters
    top_clock_rate = 6000000
    ns_per_sec = 1e9
    clk_period_ns = int((1/top_clock_rate)*ns_per_sec)

    # Dut creation
    rs232_modem = Rs232(dut)
    
    accelerometer = SimAccelerometer(dut, fs=accelerated_fs, z_data=z_data)
    print(f"The simulation clock period in ns is {clk_period_ns}")
   
    accel_sim = cocotb.fork(accelerometer.simulate())
    cocotb.fork(Clock(dut.clk, clk_period_ns, units='ns').start())
    rx_bytes = []
    rs232_sim = cocotb.fork(rs232_modem.simulate(rx_bytes))
    dut.reset <= 0
    yield RisingEdge(dut.clk)
    dut.reset <= 1
    yield RisingEdge(dut.clk)
    dut.reset <= 0
    yield RisingEdge(dut.clk)
    yield Timer(30000000, units='ns')
    rs232_sim.kill()
    accel_sim.kill()
    
    # Received data is a list of bytes where the ordering is counts, prediction, counts, prediction...
    rx = [bitlist_to_int(byte) for byte in rx_bytes]
    correct_labels = [SleepWake.SLEEP.value, SleepWake.SLEEP.value]
    predictions =  rx[1::2]
    counts = rx[::2]
    for i, (c, p) in enumerate(zip(counts, predictions)):
        sleep_wake_str = "awake" if p == 0 else "sleep" 
        print(f"Epoch {i}: counts {c}, prediction {sleep_wake_str}")
    
    assert correct_labels == predictions
