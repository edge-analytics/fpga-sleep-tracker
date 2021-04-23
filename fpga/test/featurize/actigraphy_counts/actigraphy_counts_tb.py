import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadWrite, NextTimeStep, RisingEdge, FallingEdge
from cocotb.binary import BinaryValue
import numpy as np
from matplotlib import pyplot as plt
from scipy.signal import butter, filtfilt
from fixedpoint import FixedPoint


@cocotb.test() 
async def test_peak_detect(dut):
    num_samples_per_epoch = 15*50
    num_epochs = 10
    num_samples = num_samples_per_epoch * num_epochs
    data = np.loadtxt('46343_acceleration.txt', delimiter=' ')
    #count_feature = np.loadtxt('46343_cleaned_counts.out', delimiter=' ')
    fs = 50
    time = np.arange(np.amin(data[:, 0]), np.amax(data[:, 0]), 1.0 / fs)
    z_accel = np.interp(time, data[:, 0], data[:, 3])
    # cf_low = 3
    # cf_hi = 11
    # order = 5
    # w1 = cf_low / (fs / 2)
    # w2 = cf_hi / (fs / 2)
    # pass_band = [w1, w2]
    # b, a = butter(order, pass_band, 'bandpass')
    # z_filt = filtfilt(b, a, z_accel)
    start_offset_sec = 120
    offset = fs * start_offset_sec
    z_accel = z_accel[offset:offset+num_samples]

    print(f"Number of samples to input {z_accel.shape[0]}")
    #count_feature = count_feature[::num_epochs]
    clk = dut.clk
    dut.i_z_accel <= 0
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

    for i, z in enumerate(z_accel):
        dut.i_z_accel <= BinaryValue(str(FixedPoint(float(z/5), 1, 7)))
        dut.i_valid <= 1
        await ClockCycles(clk, 1)
        dut.i_valid <= 0
        await ClockCycles(clk, 10)
    
    dut.i_valid <= 0

    await ClockCycles(clk, 100)
