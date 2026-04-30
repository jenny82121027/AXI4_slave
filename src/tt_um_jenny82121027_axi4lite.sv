// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// Tiny Tapeout top for the AXI4-Lite slave demo.
//
// Pin mapping:
//   ui_in[4:0]  : register address
//   ui_in[5]    : write request
//   ui_in[6]    : read request
//   ui_in[7]    : write-response ready
//   uio_in[7:0] : write data
//   uo_out[7:0]  : read data [7:0]
//   uio_out[7:0] : read data [15:8]
//   uio_oe       : high only while driving a read response

/* verilator lint_off DECLFILENAME */
module tt_um_jenny82121027_axi4lite (
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

    typedef enum logic [1:0] {
        IDLE  = 2'd0,
        WRITE = 2'd1,
        RESP  = 2'd2,
        READ  = 2'd3
    } state_t;

    state_t state;
    logic [31:0] s_awaddr, s_araddr;
    logic        s_awvalid, s_arvalid;
    wire         s_awready, s_arready;
    logic [31:0] s_wdata;
    logic        s_wvalid;
    wire         s_wready;
    wire  [31:0] s_rdata;
    wire  [1:0]  s_rresp, s_bresp;
    wire         s_rvalid, s_bvalid;
    logic        s_bready;
    logic        aw_done, w_done;
    logic [15:0] rdata_latch;

    wire aw_complete = aw_done || (s_awvalid && s_awready);
    wire w_complete  = w_done  || (s_wvalid  && s_wready);
    wire read_active = (state == READ);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state       <= IDLE;
            s_awvalid   <= 1'b0;
            s_arvalid   <= 1'b0;
            s_wvalid    <= 1'b0;
            s_bready    <= 1'b0;
            s_awaddr    <= '0;
            s_araddr    <= '0;
            s_wdata     <= '0;
            aw_done     <= 1'b0;
            w_done      <= 1'b0;
            rdata_latch <= '0;
        end else begin
            case (state)
                IDLE: begin
                    s_bready <= 1'b0;
                    aw_done  <= 1'b0;
                    w_done   <= 1'b0;
                    if (ui_in[5]) begin
                        s_awaddr  <= {27'b0, ui_in[4:0]};
                        s_wdata   <= {24'b0, uio_in};
                        s_awvalid <= 1'b1;
                        s_wvalid  <= 1'b1;
                        state     <= WRITE;
                    end else if (ui_in[6]) begin
                        s_araddr  <= {27'b0, ui_in[4:0]};
                        s_arvalid <= 1'b1;
                        state     <= READ;
                    end
                end

                WRITE: begin
                    if (s_awvalid && s_awready) begin
                        s_awvalid <= 1'b0;
                        aw_done   <= 1'b1;
                    end
                    if (s_wvalid && s_wready) begin
                        s_wvalid <= 1'b0;
                        w_done   <= 1'b1;
                    end
                    if (aw_complete && w_complete) begin
                        state <= RESP;
                    end
                end

                RESP: begin
                    if (s_bvalid) begin
                        s_bready <= ui_in[7];
                        if (ui_in[7]) begin
                            state <= IDLE;
                        end
                    end
                end

                READ: begin
                    if (s_arvalid && s_arready) begin
                        s_arvalid <= 1'b0;
                    end
                    if (s_rvalid) begin
                        rdata_latch <= s_rdata[15:0];
                        state       <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign uo_out  = read_active ? rdata_latch[7:0]  : 8'h00;
    assign uio_out = read_active ? rdata_latch[15:8] : 8'h00;
    assign uio_oe  = read_active ? 8'hFF : 8'h00;

    axi4_lite_slave slave (
        .ACLK      (clk),
        .ARESETN   (rst_n),
        .S_AWADDR  (s_awaddr),
        .S_AWVALID (s_awvalid),
        .S_AWREADY (s_awready),
        .S_ARADDR  (s_araddr),
        .S_ARVALID (s_arvalid),
        .S_ARREADY (s_arready),
        .S_WDATA   (s_wdata),
        .S_WSTRB   (4'hF),
        .S_WVALID  (s_wvalid),
        .S_WREADY  (s_wready),
        .S_RDATA   (s_rdata),
        .S_RRESP   (s_rresp),
        .S_RVALID  (s_rvalid),
        .S_RREADY  (1'b1),
        .S_BRESP   (s_bresp),
        .S_BVALID  (s_bvalid),
        .S_BREADY  (s_bready)
    );

    wire _unused = &{ena, 1'b0};

endmodule
