import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadWrite, NextTimeStep, RisingEdge, FallingEdge
from cocotb.binary import BinaryValue
import numpy as np
from matplotlib import pyplot as plt

from fixedpoint import FixedPoint


@cocotb.test() 
async def test_biquad(dut):
    clk = dut.clk
    dut.i_data <= 0
    dut.i_valid <= 0
    cocotb.fork(Clock(clk, 25, units="ns").start())
    # Reset logic
    await NextTimeStep()
    dut.reset <= 1
    await ClockCycles(clk, 1)
    await ReadWrite()
    dut.reset <= 0
    await ClockCycles(clk, 1)
    await ReadWrite()
    n = 100
    fs = 50
    f0 = 4
    f1 = 19
    amp0 = 0.5
    amp1 = 0.25
    x = np.linspace(0, n/fs, n)
    xs = amp0 * np.sin(2*np.pi*x*f0) + amp1 * np.cos(2*np.pi*x*f1)
    results = []
    for xn in xs:
        dut.i_data <= BinaryValue(str(FixedPoint(float(xn), 1, 7)))
        dut.i_valid <= 1
        await ClockCycles(clk, 1)
        dut.i_valid <= 0
        detected = False
        await ClockCycles(clk, 6)
        # while not detected:
        #     await FallingEdge(clk)
        #     detected = dut.o_data.value == 1
        y = float(FixedPoint(dut.o_data.value.binstr, int_bits=1, fract_bits=7))
        results.append(y)
        print(y)
    plt.plot(xs)
    plt.plot(results)
    plt.show()
    