import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, NextTimeStep, ReadWrite

N = 16
test_input = list(range(N))

async def writer(dut):
    for i in test_input:
        busy_check = lambda : not dut.ready_for_input.value
        while busy_check():
            await ClockCycles(dut.clk, 1)
        dut.input_valid <= 1
        dut.data_in <= i
        await ClockCycles(dut.clk, 1)
        dut.input_valid <= 0
        await ClockCycles(dut.clk, 1)

# FIXME add more unit tests here
async def reader(dut):
    dut.ready_for_output <=1
    data_out = []
    while (len(data_out) < N):
        await RisingEdge(dut.clk)
        await ReadWrite()
        if dut.output_valid.value:
            data_out.append(int(dut.data_out.value))
            print(int(dut.data_out.value))
        # Introduce random read delay to show that the fifo will respect
        # ready for output signals
        if (len(data_out) % (N//6)) == 0:
            dut.ready_for_output <= 0
            await ClockCycles(dut.clk, 100)
            dut.ready_for_output <= 1
    return data_out
    

@cocotb.test()
async def test_fifo(dut):
    clk = dut.clk
    cocotb.fork(Clock(clk, 10, units="ns").start())
    # Reset Started
    await NextTimeStep()
    dut.reset <= 1
    await ClockCycles(clk, 1)
    dut.reset <= 0
    await ClockCycles(clk, 1)
    # Reset Done

    writer_process = cocotb.fork(writer(dut))
    fifo_readback = await reader(dut)

    assert(test_input == fifo_readback)
