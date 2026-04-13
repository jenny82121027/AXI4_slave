import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


ID_REG_ADDR = 1
ID_REG_VALUE = 0x00018644
REGISTER_COUNT = 32
DATA_MASK = 0xFFFFFFFF
DEFAULT_TIMEOUT = 60
RANDOM_SEED = 18644


def apply_wstrb(current_value, write_value, wstrb):
    """Apply AXI byte strobes to the current register value."""
    merged_value = current_value
    for byte_index in range(4):
        if (wstrb >> byte_index) & 0x1:
            mask = 0xFF << (8 * byte_index)
            merged_value = (merged_value & ~mask) | (write_value & mask)
    return merged_value & DATA_MASK


class AxiLiteSlaveScoreboard:
    """Track the expected register contents and compare observed reads."""

    def __init__(self):
        self.registers = [0] * REGISTER_COUNT
        self.reset()

    def reset(self):
        self.registers = [0] * REGISTER_COUNT
        self.registers[ID_REG_ADDR] = ID_REG_VALUE

    def predict_write(self, addr, data, wstrb=0xF):
        index = addr & (REGISTER_COUNT - 1)
        if index == ID_REG_ADDR:
            return
        self.registers[index] = apply_wstrb(self.registers[index], data, wstrb)

    def expected_read(self, addr):
        return self.registers[addr & (REGISTER_COUNT - 1)]

    def check_read(self, addr, observed_data):
        expected_data = self.expected_read(addr)
        assert observed_data == expected_data, (
            f"Read mismatch at address {addr}: "
            f"got 0x{observed_data:08x}, expected 0x{expected_data:08x}"
        )


class AxiLiteSlaveDriver:
    """Drive AXI4-Lite transactions and connect them to the scoreboard."""

    def __init__(self, dut, scoreboard, timeout_cycles=DEFAULT_TIMEOUT):
        self.dut = dut
        self.scoreboard = scoreboard
        self.timeout_cycles = timeout_cycles

    def clear_inputs(self):
        self.dut.S_ARADDR.value = 0
        self.dut.S_ARVALID.value = 0
        self.dut.S_RREADY.value = 0
        self.dut.S_AWADDR.value = 0
        self.dut.S_AWVALID.value = 0
        self.dut.S_WDATA.value = 0
        self.dut.S_WSTRB.value = 0
        self.dut.S_WVALID.value = 0
        self.dut.S_BREADY.value = 0

    async def wait_cycles(self, cycles):
        for _ in range(cycles):
            await RisingEdge(self.dut.ACLK)

    async def reset(self, cycles=5):
        self.clear_inputs()
        self.dut.ARESETN.value = 0
        self.scoreboard.reset()
        await self.wait_cycles(cycles)
        self.dut.ARESETN.value = 1
        await RisingEdge(self.dut.ACLK)
        self.check_idle_outputs()

    def check_idle_outputs(self):
        """Check the externally visible outputs once reset has completed."""
        assert int(self.dut.S_ARREADY.value) == 0, "ARREADY should be low in IDLE"
        assert int(self.dut.S_RVALID.value) == 0, "RVALID should be low in IDLE"
        assert int(self.dut.S_AWREADY.value) == 0, "AWREADY should be low in IDLE"
        assert int(self.dut.S_WREADY.value) == 0, "WREADY should be low in IDLE"
        assert int(self.dut.S_BVALID.value) == 0, "BVALID should be low in IDLE"

    async def _drive_aw_channel(self, addr, start_delay):
        await self.wait_cycles(start_delay)
        self.dut.S_AWADDR.value = addr
        self.dut.S_AWVALID.value = 1
        for _ in range(self.timeout_cycles):
            await RisingEdge(self.dut.ACLK)
            if int(self.dut.S_AWREADY.value):
                self.dut.S_AWVALID.value = 0
                return
        raise AssertionError("Timed out waiting for the write-address handshake")

    async def _drive_w_channel(self, data, wstrb, start_delay):
        await self.wait_cycles(start_delay)
        self.dut.S_WDATA.value = data
        self.dut.S_WSTRB.value = wstrb
        self.dut.S_WVALID.value = 1
        for _ in range(self.timeout_cycles):
            await RisingEdge(self.dut.ACLK)
            if int(self.dut.S_WREADY.value):
                self.dut.S_WVALID.value = 0
                return
        raise AssertionError("Timed out waiting for the write-data handshake")

    async def issue_write(self, addr, data, wstrb=0xF, aw_delay=0, w_delay=0):
        """Drive the write address and data channels without consuming BRESP."""
        aw_task = cocotb.start_soon(self._drive_aw_channel(addr, aw_delay))
        w_task = cocotb.start_soon(self._drive_w_channel(data, wstrb, w_delay))
        await aw_task
        await w_task

    async def complete_write_response(self, addr, data, wstrb=0xF, bready_delay=0):
        await self.wait_cycles(bready_delay)
        self.dut.S_BREADY.value = 1
        for _ in range(self.timeout_cycles):
            await RisingEdge(self.dut.ACLK)
            if int(self.dut.S_BVALID.value):
                assert int(self.dut.S_BRESP.value) == 0, "BRESP should be OKAY"
                self.scoreboard.predict_write(addr, data, wstrb)
                await RisingEdge(self.dut.ACLK)
                self.dut.S_BREADY.value = 0
                return
        raise AssertionError("Timed out waiting for the write response")

    async def write(self, addr, data, wstrb=0xF, aw_delay=0, w_delay=0, bready_delay=0):
        await self.issue_write(addr, data, wstrb=wstrb, aw_delay=aw_delay, w_delay=w_delay)
        await self.complete_write_response(addr, data, wstrb=wstrb, bready_delay=bready_delay)

    async def read(self, addr, ar_delay=0, rready_delay=0):
        await self.wait_cycles(ar_delay)
        self.dut.S_ARADDR.value = addr
        self.dut.S_ARVALID.value = 1

        for _ in range(self.timeout_cycles):
            await RisingEdge(self.dut.ACLK)
            if int(self.dut.S_ARREADY.value):
                self.dut.S_ARVALID.value = 0
                break
        else:
            raise AssertionError("Timed out waiting for the read-address handshake")

        await self.wait_cycles(rready_delay)
        self.dut.S_RREADY.value = 1

        for _ in range(self.timeout_cycles):
            await RisingEdge(self.dut.ACLK)
            if int(self.dut.S_RVALID.value):
                observed_data = int(self.dut.S_RDATA.value)
                observed_resp = int(self.dut.S_RRESP.value)
                assert observed_resp == 0, "RRESP should be OKAY"
                self.scoreboard.check_read(addr, observed_data)
                await RisingEdge(self.dut.ACLK)
                self.dut.S_RREADY.value = 0
                return observed_data
        raise AssertionError("Timed out waiting for the read response")


async def build_env(dut):
    cocotb.start_soon(Clock(dut.ACLK, 10, unit="ns").start())
    scoreboard = AxiLiteSlaveScoreboard()
    driver = AxiLiteSlaveDriver(dut, scoreboard)
    await driver.reset()
    return driver, scoreboard


@cocotb.test()
async def test_basic_read_write_and_read_only_id(dut):
    """Run the original smoke test using the scoreboard-backed driver."""
    driver, _ = await build_env(dut)

    id_data = await driver.read(ID_REG_ADDR)
    dut._log.info("Read ID register: 0x%08x", id_data)

    await driver.write(addr=0, data=0xA5A5A5A5)
    readback = await driver.read(0)
    dut._log.info("Read register 0: 0x%08x", readback)

    await driver.write(addr=ID_REG_ADDR, data=0xDEADBEEF)
    id_data_after_write = await driver.read(ID_REG_ADDR)
    assert id_data_after_write == ID_REG_VALUE, "ID register must remain read-only"


@cocotb.test()
async def test_split_write_channels_and_write_backpressure(dut):
    """Verify that AW and W can arrive on different cycles and BRESP can be stalled."""
    driver, _ = await build_env(dut)

    await driver.write(
        addr=2,
        data=0x11223344,
        aw_delay=0,
        w_delay=3,
        bready_delay=4,
    )
    await driver.read(2)

    await driver.write(
        addr=3,
        data=0x55667788,
        aw_delay=4,
        w_delay=0,
        bready_delay=2,
    )
    await driver.read(3)


@cocotb.test()
async def test_partial_write_and_read_backpressure(dut):
    """Verify byte-enable behavior and RVALID holding under read backpressure."""
    driver, _ = await build_env(dut)

    await driver.write(addr=4, data=0x11223344)
    await driver.write(addr=4, data=0xAABBCCDD, wstrb=0b0011)
    observed = await driver.read(addr=4, rready_delay=4)
    assert observed == 0x1122CCDD, f"Unexpected partial-write result: 0x{observed:08x}"

    await driver.write(addr=5, data=0x12345678)
    observed = await driver.read(addr=5, rready_delay=3)
    assert observed == 0x12345678, f"Unexpected readback value: 0x{observed:08x}"


@cocotb.test()
async def test_reset_during_pending_write_response(dut):
    """Verify that reset clears the design even if a write response is still pending."""
    driver, _ = await build_env(dut)

    await driver.issue_write(addr=6, data=0xCAFEBABE, aw_delay=1, w_delay=2)

    for _ in range(driver.timeout_cycles):
        await RisingEdge(dut.ACLK)
        if int(dut.S_BVALID.value):
            break
    else:
        raise AssertionError("Timed out waiting for BVALID before reset")

    dut.ARESETN.value = 0
    driver.scoreboard.reset()
    await RisingEdge(dut.ACLK)
    dut.ARESETN.value = 1
    driver.clear_inputs()
    await RisingEdge(dut.ACLK)
    driver.check_idle_outputs()

    observed_after_reset = await driver.read(6)
    assert observed_after_reset == 0, "Reset should clear writable registers"

    id_value = await driver.read(ID_REG_ADDR)
    assert id_value == ID_REG_VALUE, "Reset should restore the ID register"


@cocotb.test()
async def test_randomized_scoreboard_regression(dut):
    """Run a deterministic randomized regression with scoreboard checking."""
    driver, scoreboard = await build_env(dut)
    rng = random.Random(RANDOM_SEED)
    dut._log.info("Randomized regression seed: %d", RANDOM_SEED)

    for transaction_index in range(25):
        addr = rng.randrange(REGISTER_COUNT)
        if rng.choice(["write", "read"]) == "write":
            data = rng.getrandbits(32)
            wstrb = rng.randrange(1, 16)
            aw_delay = rng.randrange(0, 4)
            w_delay = rng.randrange(0, 4)
            bready_delay = rng.randrange(0, 4)
            await driver.write(
                addr=addr,
                data=data,
                wstrb=wstrb,
                aw_delay=aw_delay,
                w_delay=w_delay,
                bready_delay=bready_delay,
            )
            dut._log.info(
                "Write %02d: addr=%d data=0x%08x wstrb=0x%x",
                transaction_index,
                addr,
                data,
                wstrb,
            )
        else:
            ar_delay = rng.randrange(0, 4)
            rready_delay = rng.randrange(0, 4)
            observed = await driver.read(addr=addr, ar_delay=ar_delay, rready_delay=rready_delay)
            expected = scoreboard.expected_read(addr)
            assert observed == expected, (
                f"Randomized read mismatch at address {addr}: "
                f"got 0x{observed:08x}, expected 0x{expected:08x}"
            )
            dut._log.info(
                "Read  %02d: addr=%d data=0x%08x",
                transaction_index,
                addr,
                observed,
            )
