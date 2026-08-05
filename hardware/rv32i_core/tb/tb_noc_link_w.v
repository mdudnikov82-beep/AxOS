// Minimal 2-node NoC integration test, DEDICATED to the new W axis
// (ana/kata) specifically - mirrors tb_noc_link.v exactly, except the
// two nodes differ ONLY in W: a core-side adapter at (0,0,0,0), a
// memory adapter at (0,0,0,1), connected by a single Ana/Kata hop
// instead of an E/W hop. Design review flagged this as non-negotiable:
// reusing tb_noc_link.v's existing X-axis case would prove nothing
// about the just-added ana/kata wiring, since router.v's per-axis
// routing logic is hand-written per tier (not derived generically),
// so a bug specific to the W tier's decode/port-wiring is invisible to
// every other axis's test.
`timescale 1ns/1ps

module tb_noc_link_w;
    localparam RQW = 92; // 8*COORD_BITS + 68 at COORD_BITS=3 (see noc_core_adapter.v)
    localparam RSW = 44; // 4*COORD_BITS + 32 at COORD_BITS=3

    reg clk, reset;
    integer errors;

    task check(input cond, input [200*8-1:0] msg);
        begin
            if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
            else $display("PASS: %0s", msg);
        end
    endtask

    // ---- Fake core driver, at (0,0,0,0) ----
    reg         bus_req;
    reg  [31:0] bus_addr, bus_write_data;
    reg         bus_mem_write;
    reg  [1:0]  bus_mem_size;
    reg         bus_mem_unsigned;
    wire        bus_grant;
    wire [31:0] bus_read_data;

    noc_core_adapter #(.MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0), .MEM_X(0), .MEM_Y(0), .MEM_Z(0), .MEM_W(1),
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

    // ---- req router at (0,0,0,0) ----
    router #(.FLIT_WIDTH(RQW), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RQW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({RQW{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({RQW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({RQW{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({RQW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RQW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(req_r1_kata_out_valid), .ana_in_flit(req_r1_kata_out_flit), .ana_in_ready(req_r0_ana_in_ready),
        .ana_out_valid(req_r0_ana_out_valid), .ana_out_flit(req_r0_ana_out_flit), .ana_out_ready(req_r1_kata_in_ready),
        .kata_in_valid(1'b0), .kata_in_flit({RQW{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(core_req_out_valid), .l_in_flit(core_req_out_flit), .l_in_ready(core_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0) // (0,0,0,0) never receives a request
    );
    wire req_r0_ana_out_valid; wire [RQW-1:0] req_r0_ana_out_flit; wire req_r0_ana_in_ready;

    // ---- req router at (0,0,0,1) ----
    router #(.FLIT_WIDTH(RQW), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(1)) req_r1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RQW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({RQW{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
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
        .kata_in_valid(req_r0_ana_out_valid), .kata_in_flit(req_r0_ana_out_flit), .kata_in_ready(req_r1_kata_in_ready),
        .kata_out_valid(req_r1_kata_out_valid), .kata_out_flit(req_r1_kata_out_flit), .kata_out_ready(req_r0_ana_in_ready),
        .l_in_valid(1'b0), .l_in_flit({RQW{1'b0}}), .l_in_ready(),
        .l_out_valid(mem_req_in_valid), .l_out_flit(mem_req_in_flit), .l_out_ready(mem_req_in_ready)
    );
    wire req_r1_kata_out_valid; wire [RQW-1:0] req_r1_kata_out_flit; wire req_r1_kata_in_ready;

    // ---- resp router at (0,0,0,1) ----
    router #(.FLIT_WIDTH(RSW), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(1)) resp_r1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RSW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({RSW{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
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
        .kata_in_valid(resp_r0_ana_out_valid), .kata_in_flit(resp_r0_ana_out_flit), .kata_in_ready(resp_r1_kata_in_ready),
        .kata_out_valid(resp_r1_kata_out_valid), .kata_out_flit(resp_r1_kata_out_flit), .kata_out_ready(resp_r0_ana_in_ready),
        .l_in_valid(mem_resp_out_valid), .l_in_flit(mem_resp_out_flit), .l_in_ready(mem_resp_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0) // (0,0,0,1) never RECEIVES a response
    );
    wire resp_r1_kata_out_valid; wire [RSW-1:0] resp_r1_kata_out_flit; wire resp_r1_kata_in_ready;

    // ---- resp router at (0,0,0,0) ----
    router #(.FLIT_WIDTH(RSW), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RSW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({RSW{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({RSW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({RSW{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({RSW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RSW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(resp_r1_kata_out_valid), .ana_in_flit(resp_r1_kata_out_flit), .ana_in_ready(resp_r0_ana_in_ready),
        .ana_out_valid(resp_r0_ana_out_valid), .ana_out_flit(resp_r0_ana_out_flit), .ana_out_ready(resp_r1_kata_in_ready),
        .kata_in_valid(1'b0), .kata_in_flit({RSW{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({RSW{1'b0}}), .l_in_ready(),
        .l_out_valid(core_resp_in_valid), .l_out_flit(core_resp_in_flit), .l_out_ready(core_resp_in_ready)
    );
    wire resp_r0_ana_out_valid; wire [RSW-1:0] resp_r0_ana_out_flit; wire resp_r0_ana_in_ready;

    // ---- memory adapter at (0,0,0,1) ----
    wire                mem_req_in_valid;
    wire [RQW-1:0]      mem_req_in_flit;
    wire                mem_req_in_ready;
    wire                mem_resp_out_valid;
    wire [RSW-1:0]      mem_resp_out_flit;
    wire                mem_resp_out_ready;

    noc_mem_adapter #(.MEM_BYTES(64), .COORD_BITS(3), .REQ_FLIT_WIDTH(RQW), .RESP_FLIT_WIDTH(RSW)) mem_adap (
        .clk(clk), .reset(reset),
        .req_in_valid(mem_req_in_valid), .req_in_flit(mem_req_in_flit), .req_in_ready(mem_req_in_ready),
        .resp_out_valid(mem_resp_out_valid), .resp_out_flit(mem_resp_out_flit), .resp_out_ready(mem_resp_out_ready)
    );

    always #5 clk = ~clk;

    task do_access(input write, input [31:0] addr, input [31:0] wdata, output [31:0] rdata);
        integer cyc;
        begin
            bus_req = 1; bus_addr = addr; bus_write_data = wdata;
            bus_mem_write = write; bus_mem_size = 2'b10; bus_mem_unsigned = 1;
            cyc = 0;
            while (!bus_grant && cyc < 50) begin
                @(posedge clk);
                cyc = cyc + 1;
            end
            check(bus_grant, "access completed within 50 cycles");
            rdata = bus_read_data;
            bus_req = 0;
            @(posedge clk);
        end
    endtask

    reg [31:0] got;
    initial begin
        clk = 0; reset = 1; errors = 0;
        bus_req = 0; bus_addr = 0; bus_write_data = 0; bus_mem_write = 0;
        bus_mem_size = 2'b10; bus_mem_unsigned = 1;
        @(posedge clk); @(posedge clk);
        reset = 0;
        @(posedge clk);

        // Write 0xCAFEF00D to address 4, read it back through the SAME
        // real round trip over the Ana/Kata hop specifically - proves
        // actual memory persistence through the NEW axis, not just
        // "grant eventually fired."
        do_access(1, 32'd4, 32'hCAFEF00D, got);
        do_access(0, 32'd4, 32'h0, got);
        check(got == 32'hCAFEF00D, "read-back through the Ana/Kata hop matches what was written");

        // A second, different address/value - rules out "always returns
        // the first thing written" as an accidental pass.
        do_access(1, 32'd8, 32'h87654321, got);
        do_access(0, 32'd8, 32'h0, got);
        check(got == 32'h87654321, "second independent write/read pair also round-trips correctly over Ana/Kata");

        // Re-read the FIRST address again - confirms the second write
        // didn't clobber unrelated memory and that this node correctly
        // serves MULTIPLE sequential transactions over the W hop.
        do_access(0, 32'd4, 32'h0, got);
        check(got == 32'hCAFEF00D, "first address unaffected by the second write, third round trip also correct");

        if (errors == 0) $display("ALL NOC LINK-W TESTS PASSED");
        else $display("%0d NOC LINK-W TEST(S) FAILED", errors);
        $finish;
    end
endmodule
