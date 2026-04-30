import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


ID_REG_ADDR = 1
ID_REG_VALUE = 0x00018644
S_IDLE = 0
S_WRITE_CHANNEL = 1
S_WRESP_CHANNEL = 2
S_RADDR_CHANNEL = 3
S_RDATA_CHANNEL = 4


async def reset_dut(dut, cycles=5):
    dut.ARESETN.value = 0
    dut.S_ARADDR.value = 0
    dut.S_ARVALID.value = 0
    dut.S_RREADY.value = 0
    dut.S_AWADDR.value = 0
    dut.S_AWVALID.value = 0
    dut.S_WDATA.value = 0
    dut.S_WSTRB.value = 0
    dut.S_WVALID.value = 0
    dut.S_BREADY.value = 0

    for _ in range(cycles):
        await RisingEdge(dut.ACLK)

    dut.ARESETN.value = 1
    await RisingEdge(dut.ACLK)


async def wait_for_state(dut, expected_state, max_cycles=40):
    for _ in range(max_cycles):
        if int(dut.dut.state.value) == expected_state:
            return
        await RisingEdge(dut.ACLK)
    raise AssertionError(
        f"Timed out waiting for state {expected_state}, "
        f"last state={int(dut.dut.state.value)}"
    )


async def write_reg(dut, addr, data, wstrb=0xF):
    dut.S_AWADDR.value = addr
    dut.S_AWVALID.value = 1
    dut.S_WDATA.value = data
    dut.S_WSTRB.value = wstrb
    dut.S_WVALID.value = 1
    dut.S_BREADY.value = 1

    await wait_for_state(dut, S_WRITE_CHANNEL)
    await wait_for_state(dut, S_WRESP_CHANNEL)
    await wait_for_state(dut, S_IDLE)

    dut.S_AWVALID.value = 0
    dut.S_WVALID.value = 0
    dut.S_BREADY.value = 0
    await RisingEdge(dut.ACLK)


async def read_reg(dut, addr):
    dut.S_ARADDR.value = addr
    dut.S_ARVALID.value = 1
    dut.S_RREADY.value = 1

    await wait_for_state(dut, S_RADDR_CHANNEL)
    await wait_for_state(dut, S_RDATA_CHANNEL)

    observed = int(dut.S_RDATA.value)

    await wait_for_state(dut, S_IDLE)
    dut.S_ARVALID.value = 0
    dut.S_RREADY.value = 0
    await RisingEdge(dut.ACLK)
    return observed


@cocotb.test()
async def test_basic_read_write_and_read_only_id(dut):
    cocotb.start_soon(Clock(dut.ACLK, 10, unit="ns").start())
    await reset_dut(dut)

    assert int(dut.dut.register[ID_REG_ADDR].value) == ID_REG_VALUE

    id_data = await read_reg(dut, ID_REG_ADDR)
    assert id_data == ID_REG_VALUE, f"ID register mismatch: 0x{id_data:08x}"

    await write_reg(dut, 0, 0xA5A5A5A5)
    assert int(dut.dut.register[0].value) == 0xA5A5A5A5
    readback = await read_reg(dut, 0)
    assert readback == 0xA5A5A5A5, f"Register 0 readback mismatch: 0x{readback:08x}"

    await write_reg(dut, ID_REG_ADDR, 0xDEADBEEF)
    assert int(dut.dut.register[ID_REG_ADDR].value) == ID_REG_VALUE
    id_data_after_write = await read_reg(dut, ID_REG_ADDR)
    assert id_data_after_write == ID_REG_VALUE, "ID register must remain read-only"


@cocotb.test()
async def test_split_write_channels_and_partial_write(dut):
    cocotb.start_soon(Clock(dut.ACLK, 10, unit="ns").start())
    await reset_dut(dut)

    await write_reg(dut, 2, 0x11223344)
    assert int(dut.dut.register[2].value) == 0x11223344
    assert await read_reg(dut, 2) == 0x11223344

    await write_reg(dut, 3, 0x55667788, wstrb=0x3)
    assert int(dut.dut.register[3].value) == 0x00007788
    assert await read_reg(dut, 3) == 0x00007788

