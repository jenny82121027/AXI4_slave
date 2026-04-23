// Simplified AXI4-Lite slave — 12 port names, 8 registers.
// Simplifications vs full AXI4-Lite:
//   - S_ARADDR  : shared address for both read and write
//   - S_WVALID  : doubles as AWVALID (AW+W presented together)
//   - S_WREADY  : doubles as AWREADY
//   - RREADY    : hardcoded to 1 (read data accepted immediately)
//   - WSTRB     : hardcoded to full strobe
//   - RRESP / BRESP : removed (always 2'b00)

module axi4_lite_slave #(
    parameter ADDRESS    = 32,
    parameter DATA_WIDTH = 32
)(
    // Global
    input                           ACLK,
    input                           ARESETN,

    // Shared address port (read and write; upper bits unused when NO_REGS is small)
    /* verilator lint_off UNUSEDSIGNAL */
    input  [ADDRESS-1:0]            S_ARADDR,
    /* verilator lint_on UNUSEDSIGNAL */

    // Read address channel
    input                           S_ARVALID,
    output logic                    S_ARREADY,

    // Read data channel  (RREADY hardcoded to 1)
    output logic [DATA_WIDTH-1:0]   S_RDATA,
    output logic                    S_RVALID,

    // Write channel (AWVALID=WVALID, AWREADY=WREADY, WSTRB=full)
    input  [DATA_WIDTH-1:0]         S_WDATA,
    input                           S_WVALID,
    output logic                    S_WREADY,

    // Write response (BRESP removed, always 2'b00)
    output logic                    S_BVALID,
    input                           S_BREADY
);

    localparam int NO_REGS      = 8;
    localparam int ADDR_INDEX_W = $clog2(NO_REGS);
    localparam logic [ADDR_INDEX_W-1:0] ID_REG_ADDR  = 3'd1;
    localparam logic [DATA_WIDTH-1:0]   ID_REG_VALUE = 32'h00018644;

    logic [DATA_WIDTH-1:0]   register [NO_REGS-1:0];
    logic [ADDR_INDEX_W-1:0] rd_addr;

    typedef enum logic [2:0] {
        IDLE, WRITE_CHANNEL, WRESP_CHANNEL, RADDR_CHANNEL, RDATA_CHANNEL
    } state_t;
    state_t state, next_state;

    wire w_hs  = S_WVALID & S_WREADY;
    wire b_hs  = S_BVALID & S_BREADY;
    wire ar_hs = S_ARVALID & S_ARREADY;
    wire r_hs  = S_RVALID;   // RREADY hardcoded to 1

    assign S_ARREADY = (state == RADDR_CHANNEL);
    assign S_RVALID  = (state == RDATA_CHANNEL);
    assign S_RDATA   = (state == RDATA_CHANNEL) ? register[rd_addr] : '0;
    assign S_WREADY  = (state == WRITE_CHANNEL);
    assign S_BVALID  = (state == WRESP_CHANNEL);

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (S_WVALID)       next_state = WRITE_CHANNEL;
                else if (S_ARVALID) next_state = RADDR_CHANNEL;
            end
            WRITE_CHANNEL:  if (w_hs)  next_state = WRESP_CHANNEL;
            WRESP_CHANNEL:  if (b_hs)  next_state = IDLE;
            RADDR_CHANNEL:  if (ar_hs) next_state = RDATA_CHANNEL;
            RDATA_CHANNEL:  if (r_hs)  next_state = IDLE;
            default:                   next_state = IDLE;
        endcase
    end

    integer i;
    always_ff @(posedge ACLK) begin
        if (!ARESETN) begin
            state   <= IDLE;
            rd_addr <= '0;
            for (i = 0; i < NO_REGS; i++) register[i] <= '0;
            register[ID_REG_ADDR] <= ID_REG_VALUE;
        end else begin
            state <= next_state;

            if (state == WRITE_CHANNEL && w_hs) begin
                if (S_ARADDR[ADDR_INDEX_W-1:0] != ID_REG_ADDR)
                    register[S_ARADDR[ADDR_INDEX_W-1:0]] <= S_WDATA;
            end

            if (state == RADDR_CHANNEL && ar_hs)
                rd_addr <= S_ARADDR[ADDR_INDEX_W-1:0];
        end
    end

endmodule
