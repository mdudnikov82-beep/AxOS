// Single REAL AxISA core (sw/noc_single_test.axasm) + one router hop
// + one memory adapter - the first test to actually exercise
// cpu_core.v's own is_shared_access/mem_stall/write-enable-gating/
// effective_dmem_rdata logic, as opposed to tb_noc_link.v (a fake
// reg-driven bus driver that only proves the adapter+router protocol
// itself). Same 2-node X-axis topology as tb_noc_link.v: core at
// (0,0,0,0), memory at (1,0,0,0).
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/noc_single_test.hex"
`endif

module tb_noc_single;
    localparam CB  = 1;
    localparam RQW = 8 * CB + 68; // 76
    localparam RSW = 4 * CB + 32; // 36

    reg clk, reset;
    integer errors;
    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;

    task check(input cond, input [200*8-1:0] msg);
        begin
            if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
            else $display("PASS: %0s", msg);
        end
    endtask

    wire halted;
    wire [31:0] tohost_value;
    wire        bus_req, bus_mem_write, bus_mem_unsigned, bus_grant;
    wire [31:0] bus_addr, bus_write_data, bus_read_data;
    wire [1:0]  bus_mem_size;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX),
               .SHARED_MEM_BASE(32'h0000_2000), .SHARED_MEM_BYTES(256)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(bus_grant), .bus_read_data(bus_read_data)
    );

    noc_core_adapter #(.COORD_BITS(CB), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0),
                        .MEM_X(1), .MEM_Y(0), .MEM_Z(0), .MEM_W(0),
                        .REQ_FLIT_WIDTH(RQW), .RESP_FLIT_WIDTH(RSW)) core_adap (
        .clk(clk), .reset(reset),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(bus_grant), .bus_read_data(bus_read_data),
        .req_out_valid(core_req_out_valid), .req_out_flit(core_req_out_flit), .req_out_ready(core_req_out_ready),
        .resp_in_valid(core_resp_in_valid), .resp_in_flit(core_resp_in_flit), .resp_in_ready(core_resp_in_ready)
    );
    wire                core_req_out_valid;
    wire [RQW-1:0]      core_req_out_flit;
    wire                core_req_out_ready;
    wire                core_resp_in_valid;
    wire [RSW-1:0]      core_resp_in_flit;
    wire                core_resp_in_ready;

    router #(.FLIT_WIDTH(RQW), .COORD_BITS(CB), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RQW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_r1_w_out_valid), .e_in_flit(req_r1_w_out_flit), .e_in_ready(req_r0_e_in_ready),
        .e_out_valid(req_r0_e_out_valid), .e_out_flit(req_r0_e_out_flit), .e_out_ready(req_r1_w_in_ready),
        .s_in_valid(1'b0), .s_in_flit({RQW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({RQW{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({RQW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RQW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({RQW{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({RQW{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(core_req_out_valid), .l_in_flit(core_req_out_flit), .l_in_ready(core_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );
    wire req_r0_e_out_valid; wire [RQW-1:0] req_r0_e_out_flit; wire req_r0_e_in_ready;

    router #(.FLIT_WIDTH(RQW), .COORD_BITS(CB), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RQW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({RQW{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({RQW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_r0_e_out_valid), .w_in_flit(req_r0_e_out_flit), .w_in_ready(req_r1_w_in_ready),
        .w_out_valid(req_r1_w_out_valid), .w_out_flit(req_r1_w_out_flit), .w_out_ready(req_r0_e_in_ready),
        .u_in_valid(1'b0), .u_in_flit({RQW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RQW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({RQW{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({RQW{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({RQW{1'b0}}), .l_in_ready(),
        .l_out_valid(mem_req_in_valid), .l_out_flit(mem_req_in_flit), .l_out_ready(mem_req_in_ready)
    );
    wire req_r1_w_out_valid; wire [RQW-1:0] req_r1_w_out_flit; wire req_r1_w_in_ready;

    router #(.FLIT_WIDTH(RSW), .COORD_BITS(CB), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RSW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({RSW{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({RSW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_r0_e_out_valid), .w_in_flit(resp_r0_e_out_flit), .w_in_ready(resp_r1_w_in_ready),
        .w_out_valid(resp_r1_w_out_valid), .w_out_flit(resp_r1_w_out_flit), .w_out_ready(resp_r0_e_in_ready),
        .u_in_valid(1'b0), .u_in_flit({RSW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RSW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({RSW{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({RSW{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(mem_resp_out_valid), .l_in_flit(mem_resp_out_flit), .l_in_ready(mem_resp_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );
    wire resp_r1_w_out_valid; wire [RSW-1:0] resp_r1_w_out_flit; wire resp_r1_w_in_ready;

    router #(.FLIT_WIDTH(RSW), .COORD_BITS(CB), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RSW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_r1_w_out_valid), .e_in_flit(resp_r1_w_out_flit), .e_in_ready(resp_r0_e_in_ready),
        .e_out_valid(resp_r0_e_out_valid), .e_out_flit(resp_r0_e_out_flit), .e_out_ready(resp_r1_w_in_ready),
        .s_in_valid(1'b0), .s_in_flit({RSW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({RSW{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({RSW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RSW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({RSW{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({RSW{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({RSW{1'b0}}), .l_in_ready(),
        .l_out_valid(core_resp_in_valid), .l_out_flit(core_resp_in_flit), .l_out_ready(core_resp_in_ready)
    );
    wire resp_r0_e_out_valid; wire [RSW-1:0] resp_r0_e_out_flit; wire resp_r0_e_in_ready;

    wire                mem_req_in_valid;
    wire [RQW-1:0]      mem_req_in_flit;
    wire                mem_req_in_ready;
    wire                mem_resp_out_valid;
    wire [RSW-1:0]      mem_resp_out_flit;
    wire                mem_resp_out_ready;

    noc_mem_adapter #(.MEM_BYTES(64), .COORD_BITS(CB), .REQ_FLIT_WIDTH(RQW), .RESP_FLIT_WIDTH(RSW)) mem_adap (
        .clk(clk), .reset(reset),
        .req_in_valid(mem_req_in_valid), .req_in_flit(mem_req_in_flit), .req_in_ready(mem_req_in_ready),
        .resp_out_valid(mem_resp_out_valid), .resp_out_flit(mem_resp_out_flit), .resp_out_ready(mem_resp_out_ready)
    );

    always #5 clk = ~clk;

    initial begin
        errors = 0;
        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 99;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 100;

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles", max_cycles);
            errors = errors + 1;
        end else begin
            $display("Halted after %0d cycles. tohost=%0d", cycle_count, tohost_value);
            check(tohost_value == expect_tohost, "tohost matches expected value (real STORE/LOAD round trip through the NoC)");
        end

        if (errors == 0) $display("ALL AXISA NOC SINGLE-CORE TESTS PASSED");
        else $display("%0d AXISA NOC SINGLE-CORE TEST(S) FAILED", errors);
        $finish;
    end
endmodule
