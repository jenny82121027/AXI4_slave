// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// AXI4-Lite Slave wrapper for Tiny Tapeout
//
// Pin mapping:
//   ui_in[2:0]  : reg address (0-7)
//   ui_in[3]    : write_req  (hold high to initiate write)
//   ui_in[4]    : read_req   (hold high to initiate read)
//   ui_in[5]    : S_BREADY   (master ready to accept write response)
//   uio_in[7:0] : write data [7:0] (zero-extended to 32-bit internally)
//   uo_out[7:0] : read data [7:0]  (lower byte, latched after each read)
//   uio_out[7:0]: read data [15:8] (upper byte, latched after each read)
//   uio_oe      : 8'hFF (all bidir pins configured as outputs)
//
// ID register (addr=1) returns 0x00018644 -> uo_out=0x44, uio_out=0x86

/* verilator lint_off DECLFILENAME */
module tt_um_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
/* verilator lint_on DECLFILENAME */

    logic [31:0] s_araddr;
    logic        s_arvalid;
    wire         s_arready;
    /* verilator lint_off UNUSEDSIGNAL */
    wire  [31:0] s_rdata;
    /* verilator lint_on UNUSEDSIGNAL */
    wire         s_rvalid;
    logic [31:0] s_wdata;
    logic        s_wvalid;
    wire         s_wready;
    wire         s_bvalid;

    logic [15:0] rdata_latch;

    // Synchronous reset to match axi4_lite_slave
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_araddr    <= '0;
            s_arvalid   <= 1'b0;
            s_wdata     <= '0;
            s_wvalid    <= 1'b0;
            rdata_latch <= '0;
        end else begin
            // Write: assert WVALID when write_req is high and slave is free
            if (ui_in[3] && !s_wvalid && !s_arvalid && !s_bvalid) begin
                s_araddr <= {29'b0, ui_in[2:0]};
                s_wdata  <= {24'b0, uio_in};
                s_wvalid <= 1'b1;
            end else if (s_wvalid && s_wready) begin
                s_wvalid <= 1'b0;
            end

            // Read: assert ARVALID when read_req is high and slave is free
            if (ui_in[4] && !s_arvalid && !s_wvalid && !s_bvalid) begin
                s_araddr  <= {29'b0, ui_in[2:0]};
                s_arvalid <= 1'b1;
            end else if (s_arvalid && s_arready) begin
                s_arvalid <= 1'b0;
            end

            // Latch lower 16 bits of read data when RVALID fires
            if (s_rvalid)
                rdata_latch <= s_rdata[15:0];
        end
    end

    assign uo_out  = rdata_latch[7:0];
    assign uio_out = rdata_latch[15:8];
    assign uio_oe  = 8'hFF;

    axi4_lite_slave slave (
        .ACLK      (clk),
        .ARESETN   (rst_n),
        .S_ARADDR  (s_araddr),
        .S_ARVALID (s_arvalid),
        .S_ARREADY (s_arready),
        .S_RDATA   (s_rdata),
        .S_RVALID  (s_rvalid),
        .S_WDATA   (s_wdata),
        .S_WVALID  (s_wvalid),
        .S_WREADY  (s_wready),
        .S_BVALID  (s_bvalid),
        .S_BREADY  (ui_in[5])
    );

    wire _unused = &{ena, ui_in[7:6], 1'b0};

endmodule
