# AXI4-Lite Slave Example

This repository contains an AXI4-Lite slave design with Verilator/Cocotb simulation support, plus FPGA and ASIC flow setups.

## What is included

- `axi4_lite_slave.sv` - AXI4-Lite slave RTL
- `axi4_lite_top_slave_only.sv` - Slave-only top with button-driven demo control
- `test_axi4_lite_slave_only_cocotb.py` - Cocotb testbench for the slave-only design
- `diagrams/` - FSM and datapath diagrams
- `fpga_axi4_lite_slave/` - FPGA flow for the slave RTL
- `fpga_axi4_lite_top_slave_only/` - FPGA flow for the demo top
- `asic_axi4_lite_slave/` - ASIC flow for the slave RTL
- `asic_axi4_lite_top_slave_only/` - ASIC flow for the demo top

## Design Notes

The AXI4-Lite slave implements:

- 32-bit data width
- 32-register memory map
- Byte-write support with `WSTRB`
- A read-only ID register at address `1`
- Verilator assertions for handshake and reset behavior

The top-level demo adds:

- LED status display
- Button synchronizers
- Step/mode control for interactive testing

## Simulation

Run the slave-only cocotb test from this repo root:

```sh
make -f Makefile.slave_only.cocotb
```

Run the combined top/slave simulation from the parent Verilator project if needed:

```sh
make
```

## Lint

```sh
make lint
```

This runs Verilator lint on `axi4_lite_slave.sv`.

## FPGA Flow

For the slave-only FPGA flow:

```sh
make -C fpga_axi4_lite_slave synth
make -C fpga_axi4_lite_slave pnr
make -C fpga_axi4_lite_slave bit
make -C fpga_axi4_lite_slave prog
```

For the demo top FPGA flow:

```sh
make -C fpga_axi4_lite_top_slave_only synth
make -C fpga_axi4_lite_top_slave_only pnr
make -C fpga_axi4_lite_top_slave_only bit
make -C fpga_axi4_lite_top_slave_only prog
```

## ASIC Flow

For lint or implementation:

```sh
make -C asic_axi4_lite_slave lint
make -C asic_axi4_lite_slave run
make -C asic_axi4_lite_top_slave_only lint
make -C asic_axi4_lite_top_slave_only run
```

The ASIC flows expect the LibreLane / IIC-OSIC environment to be available in your shell.

## Diagrams

Rendered diagram files are stored in `diagrams/`. They can be regenerated with Graphviz:

```sh
dot -Tsvg diagrams/<name>.dot -o diagrams/<name>.svg
```

