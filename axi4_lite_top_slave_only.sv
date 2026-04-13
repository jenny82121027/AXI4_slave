module axi4_lite_top_slave_only #(
    parameter DATA_WIDTH = 32,
    parameter ADDRESS = 32
) (
    input                       ACLK,
    input                       ARESETN,
    input                       btn_mode,
    input                       btn_step,
    output logic [7:0]          led
);

    localparam logic [ADDRESS-1:0] ID_REG_ADDR = 'd1;
    localparam logic [ADDRESS-1:0] TEST_REG_ADDR = 'd0;
    localparam logic [DATA_WIDTH-1:0] ID_REG_VALUE = 32'h00018644;
    localparam logic [DATA_WIDTH-1:0] TEST_REG_VALUE = 32'hA5A5A5A5;
    localparam logic [DATA_WIDTH-1:0] WRITE_ID_VALUE = 32'hDEADBEEF;
    localparam logic [(DATA_WIDTH/8)-1:0] FULL_WSTRB = {(DATA_WIDTH/8){1'b1}};

    logic [ADDRESS-1:0] s_araddr;
    logic               s_arvalid;
    logic               s_rready;
    logic [ADDRESS-1:0] s_awaddr;
    logic               s_awvalid;
    logic [DATA_WIDTH-1:0] s_wdata;
    logic [(DATA_WIDTH/8)-1:0] s_wstrb;
    logic               s_wvalid;
    logic               s_bready;
    logic               s_arready;
    logic [DATA_WIDTH-1:0] s_rdata;
    logic [1:0]         s_rresp;
    logic               s_rvalid;
    logic               s_awready;
    logic               s_wready;
    logic [1:0]         s_bresp;
    logic               s_bvalid;

    logic btn_mode_sync_0, btn_mode_sync_1;
    logic btn_step_sync_0, btn_step_sync_1;
    logic btn_mode_last, btn_step_last;
    logic btn_mode_rise, btn_step_rise;

    logic [1:0] display_mode;
    logic [2:0] demo_step;
    logic [DATA_WIDTH-1:0] last_read_data;
    logic [1:0] last_read_resp;
    logic [1:0] last_write_resp;
    logic       last_op_was_read;
    logic       last_check_pass;

    typedef enum logic [2:0] {
        S_IDLE,
        S_WRITE_REQ,
        S_WRITE_RESP,
        S_READ_REQ,
        S_READ_RESP
    } state_t;
    state_t state, next_state;

    logic                   current_is_write;
    logic [ADDRESS-1:0]     current_addr;
    logic [DATA_WIDTH-1:0]  current_wdata;
    logic [DATA_WIDTH-1:0]  expected_rdata;
    logic                   aw_done;
    logic                   w_done;
    logic                   next_aw_done;
    logic                   next_w_done;

    wire aw_hs = s_awvalid & s_awready;
    wire w_hs  = s_wvalid  & s_wready;
    wire b_hs  = s_bvalid  & s_bready;
    wire ar_hs = s_arvalid & s_arready;
    wire r_hs  = s_rvalid  & s_rready;

    // Synchronize the push buttons into the clock domain.
    always_ff @(posedge ACLK) begin
        btn_mode_sync_0 <= btn_mode;
        btn_mode_sync_1 <= btn_mode_sync_0;
        btn_step_sync_0 <= btn_step;
        btn_step_sync_1 <= btn_step_sync_0;
    end

    // Detect a single-cycle rising-edge pulse for each button.
    always_ff @(posedge ACLK) begin
        if (!ARESETN) begin
            btn_mode_last <= 1'b0;
            btn_step_last <= 1'b0;
        end
        else begin
            btn_mode_last <= btn_mode_sync_1;
            btn_step_last <= btn_step_sync_1;
        end
    end

    assign btn_mode_rise = btn_mode_sync_1 & ~btn_mode_last;
    assign btn_step_rise = btn_step_sync_1 & ~btn_step_last;

    // Cycle through four LED display modes with the mode button.
    always_ff @(posedge ACLK) begin
        if (!ARESETN) begin
            display_mode <= 2'd0;
        end
        else if (btn_mode_rise) begin
            display_mode <= display_mode + 1'b1;
        end
    end

    // Predefined demo sequence:
    // 0: read ID register
    // 1: write test value to register 0
    // 2: read back register 0
    // 3: attempt to overwrite the read-only ID register
    // 4: read ID register again
    always_comb begin
        current_is_write = 1'b0;
        current_addr = ID_REG_ADDR;
        current_wdata = '0;
        expected_rdata = ID_REG_VALUE;

        case (demo_step)
            3'd0: begin
                current_addr = ID_REG_ADDR;
                expected_rdata = ID_REG_VALUE;
            end
            3'd1: begin
                current_is_write = 1'b1;
                current_addr = TEST_REG_ADDR;
                current_wdata = TEST_REG_VALUE;
            end
            3'd2: begin
                current_addr = TEST_REG_ADDR;
                expected_rdata = TEST_REG_VALUE;
            end
            3'd3: begin
                current_is_write = 1'b1;
                current_addr = ID_REG_ADDR;
                current_wdata = WRITE_ID_VALUE;
            end
            default: begin
                current_addr = ID_REG_ADDR;
                expected_rdata = ID_REG_VALUE;
            end
        endcase
    end

    assign next_aw_done = aw_done | aw_hs;
    assign next_w_done = w_done | w_hs;

    // Drive a minimal AXI-Lite controller for the fixed demo sequence.
    always_comb begin
        s_araddr = current_addr;
        s_arvalid = (state == S_READ_REQ);
        s_rready = (state == S_READ_RESP);
        s_awaddr = current_addr;
        s_awvalid = (state == S_WRITE_REQ) && !aw_done;
        s_wdata = current_wdata;
        s_wstrb = FULL_WSTRB;
        s_wvalid = (state == S_WRITE_REQ) && !w_done;
        s_bready = (state == S_WRITE_RESP);

        next_state = state;
        case (state)
            S_IDLE: begin
                if (btn_step_rise) begin
                    next_state = current_is_write ? S_WRITE_REQ : S_READ_REQ;
                end
            end
            S_WRITE_REQ: begin
                if (next_aw_done && next_w_done) begin
                    next_state = S_WRITE_RESP;
                end
            end
            S_WRITE_RESP: begin
                if (b_hs) begin
                    next_state = S_IDLE;
                end
            end
            S_READ_REQ: begin
                if (ar_hs) begin
                    next_state = S_READ_RESP;
                end
            end
            S_READ_RESP: begin
                if (r_hs) begin
                    next_state = S_IDLE;
                end
            end
            default: next_state = S_IDLE;
        endcase
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETN) begin
            state <= S_IDLE;
            demo_step <= 3'd0;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            last_read_data <= '0;
            last_read_resp <= 2'b00;
            last_write_resp <= 2'b00;
            last_op_was_read <= 1'b0;
            last_check_pass <= 1'b0;
        end
        else begin
            state <= next_state;

            if (state != S_WRITE_REQ) begin
                aw_done <= 1'b0;
                w_done <= 1'b0;
            end
            else begin
                aw_done <= next_aw_done;
                w_done <= next_w_done;
            end

            if (state == S_WRITE_RESP && b_hs) begin
                last_write_resp <= s_bresp;
                last_op_was_read <= 1'b0;
                // Writing the read-only ID register is expected to leave the slave in a legal state.
                last_check_pass <= (s_bresp == 2'b00);
                demo_step <= (demo_step == 3'd4) ? 3'd0 : (demo_step + 1'b1);
            end

            if (state == S_READ_RESP && r_hs) begin
                last_read_data <= s_rdata;
                last_read_resp <= s_rresp;
                last_op_was_read <= 1'b1;
                last_check_pass <= (s_rresp == 2'b00) && (s_rdata == expected_rdata);
                demo_step <= (demo_step == 3'd4) ? 3'd0 : (demo_step + 1'b1);
            end
        end
    end

    // LED modes:
    // 0: current control state and demo step
    // 1: low byte of the last read data
    // 2: last result summary
    // 3: AXI handshake activity
    always_comb begin
        case (display_mode)
            2'd0: led = {2'b00, state, demo_step};
            2'd1: led = last_read_data[7:0];
            2'd2: led = {
                2'b00,
                last_op_was_read,
                last_check_pass,
                last_write_resp,
                last_read_resp
            };
            2'd3: led = {aw_hs, w_hs, b_hs, ar_hs, r_hs, 3'b000};
            default: led = 8'h00;
        endcase
    end

    axi4_lite_slave #(
        .ADDRESS(ADDRESS),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_axi4_lite_slave0 (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .S_ARADDR(s_araddr),
        .S_ARVALID(s_arvalid),
        .S_RREADY(s_rready),
        .S_AWADDR(s_awaddr),
        .S_AWVALID(s_awvalid),
        .S_WDATA(s_wdata),
        .S_WSTRB(s_wstrb),
        .S_WVALID(s_wvalid),
        .S_BREADY(s_bready),
        .S_ARREADY(s_arready),
        .S_RDATA(s_rdata),
        .S_RRESP(s_rresp),
        .S_RVALID(s_rvalid),
        .S_AWREADY(s_awready),
        .S_WREADY(s_wready),
        .S_BRESP(s_bresp),
        .S_BVALID(s_bvalid)
    );
endmodule
