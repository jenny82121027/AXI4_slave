`timescale 1ns/1ps

module tb;
    reg        ACLK = 1'b0;
    reg        ARESETN = 1'b0;
    reg [31:0] S_ARADDR = 32'h0;
    reg        S_ARVALID = 1'b0;
    reg        S_RREADY = 1'b0;
    reg [31:0] S_AWADDR = 32'h0;
    reg        S_AWVALID = 1'b0;
    reg [31:0] S_WDATA = 32'h0;
    reg [3:0]  S_WSTRB = 4'h0;
    reg        S_WVALID = 1'b0;
    reg        S_BREADY = 1'b0;
    wire       S_ARREADY;
    wire [31:0] S_RDATA;
    wire [1:0] S_RRESP;
    wire       S_RVALID;
    wire       S_AWREADY;
    wire       S_WREADY;
    wire [1:0] S_BRESP;
    wire       S_BVALID;

    always #5 ACLK = ~ACLK;

    axi4_lite_slave dut (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .S_ARADDR(S_ARADDR),
        .S_ARVALID(S_ARVALID),
        .S_RREADY(S_RREADY),
        .S_AWADDR(S_AWADDR),
        .S_AWVALID(S_AWVALID),
        .S_WDATA(S_WDATA),
        .S_WSTRB(S_WSTRB),
        .S_WVALID(S_WVALID),
        .S_BREADY(S_BREADY),
        .S_ARREADY(S_ARREADY),
        .S_RDATA(S_RDATA),
        .S_RRESP(S_RRESP),
        .S_RVALID(S_RVALID),
        .S_AWREADY(S_AWREADY),
        .S_WREADY(S_WREADY),
        .S_BRESP(S_BRESP),
        .S_BVALID(S_BVALID)
    );
endmodule
