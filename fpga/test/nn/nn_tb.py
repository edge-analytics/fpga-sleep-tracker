import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadWrite, NextTimeStep, RisingEdge
from cocotb.binary import BinaryValue
import numpy as np

from fixedpoint import FixedPoint

async def capture_mem_writes(mem, num_captures=3630):
    """ Useful debugging tool to compare the memory writes for intermediate 
        computations against the Keras model """
    write_capture = []
    i = 0
    while True:
        i+=1
        await RisingEdge(mem.write_en)
        print(f"new mem write {i}")
        await NextTimeStep()
        x = float(FixedPoint(mem.data_in.value.binstr, int_bits=16, fract_bits=16))
        write_capture.append(x)
        if i == num_captures:
            break
    return write_capture
        

@cocotb.test()
def test_nn(dut):
    clk = dut.clk
    dut.i_addr <= 0
    dut.i_data <= 0
    dut.i_we <= 0
    dut.i_valid <= 0
    dut.i_start <= 0
    cocotb.fork(Clock(clk, 25, units="ns").start())
    #we = cocotb.fork(capture_mem_writes(dut.next_layer_mem.write_en))
    # Reset logic
    yield NextTimeStep()
    dut.reset <= 1
    yield ClockCycles(clk, 1)
    yield ReadWrite()
    dut.reset <= 0
    yield ClockCycles(clk, 1)
    yield ReadWrite()
    test_features = [[ 0.036, -0.123, -0.271]]
    test_labels = [[1]]
    
    num_tests = 1
    correct_predictions = 0
    for test_idx, features in enumerate(test_features[0:num_tests]):
        dut.i_we <= 1
        dut.i_valid <= 1
        for i, feature in enumerate(features):
            dut.i_addr <= i
            dut.i_data <= BinaryValue(str(FixedPoint(float(feature), int_bits=1, fract_bits=7)))
            yield ClockCycles(clk, 1)
        dut.i_we <= 0
        dut.i_valid <= 0
        yield ClockCycles(clk, 1)
        dut.i_start <= 1
        yield ClockCycles(clk, 1)
        dut.i_start <= 0

        # NOTE uncomment for memory capture debugging
        # x = yield capture_mem_writes(dut.next_layer_mem)
        # x_np = np.array(x)
        # np.savez("mem", x=x_np)
        # print(x[0:100])

        yield ClockCycles(clk, 10000)
        
        num_outputs = 3
        results = []
        yield NextTimeStep()
        for i in range(num_outputs):
            dut.i_addr <= i
            dut.i_we <= 0
            dut.i_valid <= 1
            yield ClockCycles(clk, 2)
            yield ReadWrite()
            results.append(float(FixedPoint(dut.o_data.value.binstr, int_bits=16, fract_bits=16)))
        dut.i_valid <= 0
        yield ClockCycles(clk, 1)
        print(results)
        predicted_class = np.argmax(np.array(results))
        print(f"Labeled Class: {test_labels[test_idx]} FPGA NN Predicted Class: {predicted_class}")
        if predicted_class == test_labels[test_idx]:
            correct_predictions += 1
    print(f"FPGA NN accuracy is {100 * correct_predictions / num_tests}%")


    