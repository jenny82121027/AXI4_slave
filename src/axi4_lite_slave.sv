module axi4_lite_slave #(
    parameter ADDRESS = 32,
    parameter DATA_WIDTH = 32
    )
    (
        //Global Signals
        input                           ACLK,
        input                           ARESETN,

        ////Read Address Channel INPUTS
        /* verilator lint_off UNUSEDSIGNAL */
        input           [ADDRESS-1:0]   S_ARADDR,
        /* verilator lint_on UNUSEDSIGNAL */
        input                           S_ARVALID,
        //Read Data Channel INPUTS
        input                           S_RREADY,
        //Write Address Channel INPUTS
        /* verilator lint_off UNUSED */
        input           [ADDRESS-1:0]   S_AWADDR,
        input                           S_AWVALID,
        //Write Data  Channel INPUTS
        input          [DATA_WIDTH-1:0] S_WDATA,
        input          [(DATA_WIDTH/8)-1:0] S_WSTRB,
        input                           S_WVALID,
        //Write Response Channel INPUTS
        input                           S_BREADY,	

        //Read Address Channel OUTPUTS
        output logic                    S_ARREADY,
        //Read Data Channel OUTPUTS
        output logic    [DATA_WIDTH-1:0]S_RDATA,
        output logic         [1:0]      S_RRESP,
        output logic                    S_RVALID,
        //Write Address Channel OUTPUTS
        output logic                    S_AWREADY,
        output logic                    S_WREADY,
        //Write Response Channel OUTPUTS
        output logic         [1:0]      S_BRESP,
        output logic                    S_BVALID
    );

    localparam int no_of_registers = 32;
    localparam int ADDR_INDEX_W = $clog2(no_of_registers);
    localparam logic [ADDR_INDEX_W-1:0] ID_REG_ADDR = 5'd1;
    localparam logic [DATA_WIDTH-1:0] ID_REG_VALUE = 32'h00018644;
    localparam int STRB_WIDTH = DATA_WIDTH / 8; // byte number in the data bus

    logic [DATA_WIDTH-1 : 0] register [no_of_registers-1 : 0];
    logic [ADDR_INDEX_W-1 : 0] addr;
    logic [ADDR_INDEX_W-1:0] awaddr_latched;
    logic [DATA_WIDTH-1:0] wdata_latched;
    logic [STRB_WIDTH-1:0] wstrb_latched;
    logic aw_captured;
    logic w_captured;
    logic aw_handshake;
    logic w_handshake;
    logic aw_complete;
    logic w_complete;
    logic [ADDR_INDEX_W-1:0] pending_write_addr;
    logic [DATA_WIDTH-1:0] pending_write_data;
    logic [STRB_WIDTH-1:0] pending_write_strb;

    typedef enum logic [2 : 0] {IDLE,WRITE_CHANNEL,WRESP__CHANNEL, RADDR_CHANNEL, RDATA__CHANNEL} state_type;
    state_type state , next_state;

    // AR
    assign S_ARREADY = (state == RADDR_CHANNEL);
    // 
    assign S_RVALID = (state == RDATA__CHANNEL);
    assign S_RDATA  = (state == RDATA__CHANNEL) ? register[addr] : 0;
    assign S_RRESP  = 2'b00;
    // AW
    assign S_AWREADY = (state == WRITE_CHANNEL) && !aw_captured;
    // W
    assign S_WREADY = (state == WRITE_CHANNEL) && !w_captured;
    assign aw_handshake = S_AWVALID && S_AWREADY;
    assign w_handshake = S_WREADY && S_WVALID;
    assign aw_complete = aw_captured || aw_handshake;
    assign w_complete = w_captured || w_handshake;
    assign pending_write_addr = aw_captured ? awaddr_latched : S_AWADDR[ADDR_INDEX_W-1:0];
    assign pending_write_data = w_captured ? wdata_latched : S_WDATA;
    assign pending_write_strb = w_captured ? wstrb_latched : S_WSTRB;
    // B
    assign S_BVALID = (state == WRESP__CHANNEL);
    assign S_BRESP  = 2'b00;

    integer i;

    function automatic logic [DATA_WIDTH-1:0] apply_wstrb(
        input logic [DATA_WIDTH-1:0] current_value,
        input logic [DATA_WIDTH-1:0] write_value,
        input logic [STRB_WIDTH-1:0] write_strobe
    );
        logic [DATA_WIDTH-1:0] merged_value;
        integer byte_index;
        begin
            // Update only the byte lanes selected by WSTRB.
            merged_value = current_value;
            for (byte_index = 0; byte_index < STRB_WIDTH; byte_index++) begin
                if (write_strobe[byte_index]) begin
                    merged_value[8*byte_index +: 8] = write_value[8*byte_index +: 8];
                end
            end
            apply_wstrb = merged_value;
        end
    endfunction

    always_ff @(posedge ACLK) begin
        // Reset the register array and restore the read-only ID register.
        if (~ARESETN) begin
            for (i = 0; i < 32; i++) begin
                register[i] <= 32'b0;
            end
            register[ID_REG_ADDR] <= ID_REG_VALUE;
            addr <= '0;
            awaddr_latched <= '0;
            wdata_latched <= '0;
            wstrb_latched <= '0;
            aw_captured <= 1'b0;
            w_captured <= 1'b0;
        end
        else begin
            if (state == WRITE_CHANNEL && aw_complete && w_complete) begin
                // Perform the write once both address and data have been accepted.
                if (pending_write_addr != ID_REG_ADDR) begin
                    register[pending_write_addr] <= apply_wstrb(
                        register[pending_write_addr],
                        pending_write_data,
                        pending_write_strb
                    );
                end
                aw_captured <= 1'b0;
                w_captured <= 1'b0;
            end
            else if (state == RADDR_CHANNEL && S_ARVALID && S_ARREADY) begin
                // Latch the read address at the read-address handshake.
                addr <= S_ARADDR[ADDR_INDEX_W-1:0];
            end

            if (state == WRITE_CHANNEL && aw_handshake && !w_complete) begin
                awaddr_latched <= S_AWADDR[ADDR_INDEX_W-1:0];
                aw_captured <= 1'b1;
            end

            if (state == WRITE_CHANNEL && w_handshake && !aw_complete) begin
                wdata_latched <= S_WDATA;
                wstrb_latched <= S_WSTRB;
                w_captured <= 1'b1;
            end
        end
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETN) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end

    always_comb begin
        // Default assignment to prevent latch inference
        next_state = state;
        case (state)
            IDLE : begin
                if (S_AWVALID) begin
                    next_state = WRITE_CHANNEL;
                end 
                else if (S_ARVALID) begin
                    next_state = RADDR_CHANNEL;
                end 
            end
            RADDR_CHANNEL   : if (S_ARVALID && S_ARREADY ) next_state = RDATA__CHANNEL;
            RDATA__CHANNEL  : if (S_RVALID  && S_RREADY  ) next_state = IDLE;
            WRITE_CHANNEL   : if (aw_complete && w_complete) next_state = WRESP__CHANNEL;
            WRESP__CHANNEL  : if (S_BVALID  && S_BREADY  ) next_state = IDLE;
            default         : next_state = IDLE;
        endcase
    end

`ifdef VERILATOR
    // Keep the read response stable until the master accepts it.
    property p_read_response_holds_until_handshake;
        @(posedge ACLK) disable iff (!ARESETN)
            S_RVALID && !S_RREADY |=> S_RVALID && $stable(S_RDATA) && $stable(S_RRESP);
    endproperty

    assert property (p_read_response_holds_until_handshake)
        else $error("Read response changed before the read handshake completed.");

    // Keep the write response valid and stable until the master accepts it.
    property p_write_response_holds_until_handshake;
        @(posedge ACLK) disable iff (!ARESETN)
            S_BVALID && !S_BREADY |=> S_BVALID && $stable(S_BRESP);
    endproperty

    assert property (p_write_response_holds_until_handshake)
        else $error("Write response changed before the write response handshake completed.");

    // The state machine must always remain within the declared encoding set.
    property p_state_is_legal;
        @(posedge ACLK) disable iff (!ARESETN)
            state inside {IDLE, WRITE_CHANNEL, WRESP__CHANNEL, RADDR_CHANNEL, RDATA__CHANNEL};
    endproperty

    assert property (p_state_is_legal)
        else $error("State machine entered an illegal state.");

    // The ID register is read-only and must retain its constant value after reset releases.
    property p_id_register_is_constant;
        @(posedge ACLK) disable iff (!ARESETN)
            register[ID_REG_ADDR] == ID_REG_VALUE;
    endproperty

    assert property (p_id_register_is_constant)
        else $error("ID register changed from its fixed read-only value.");

    // A cycle sampled in reset must return the design to the idle state and clear the read address latch.
    property p_reset_returns_to_idle;
        @(posedge ACLK)
            !ARESETN |=> state == IDLE && addr == '0;
    endproperty

    assert property (p_reset_returns_to_idle)
        else $error("Reset did not return the slave to the idle state.");
`endif
endmodule
