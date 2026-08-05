// Minimal 2-node NoC integration test: one core-side adapter at (0,0),
// one memory adapter at (1,0), connected by a single E/W hop on each of
// the two (request/response) router networks. Isolates "does the
// adapter+router round-trip protocol actually work" from "was the full
// 4x4 mesh wired correctly" - matches this project's established
// practice of testing a new mechanism at the smallest scale that
// exercises it before scaling up (see e.g. the 1P+1E mini-SoC before
// today's 12-core one). A plain reg-driven fake "core" (no real
// cpu_core.v instance) drives bus_req/bus_addr/etc directly, exactly
// mirroring the port shape noc_core_adapter.v expects from a real core.
`timescale 1ns/1ps

module tb_noc_link;
    localparam RQW = 80; // 6*COORD_BITS + 68 at COORD_BITS=2 (see noc_core_adapter.v)
    localparam RSW = 38; // 3*COORD_BITS + 32 at COORD_BITS=2

    reg clk, reset;
    integer errors;

    task check(input cond, input [200*8-1:0] msg);
        begin
            if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
            else $display("PASS: %0s", msg);
        end
    endtask

    // ---- Fake core driver ----
    reg         bus_req;
    reg  [31:0] bus_addr, bus_write_data;
    reg         bus_mem_write;
    reg  [1:0]  bus_mem_size;
    reg         bus_mem_unsigned;
    wire        bus_grant;
    wire [31:0] bus_read_data;

    noc_core_adapter #(.MY_X(0), .MY_Y(0), .MY_Z(0), .MEM_X(1), .MEM_Y(0), .MEM_Z(0),
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

    // ---- req router (0,0) ----
    router #(.FLIT_WIDTH(RQW), .MY_X(0), .MY_Y(0), .MY_Z(0)) req_r00 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RQW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_r10_w_out_valid), .e_in_flit(req_r10_w_out_flit), .e_in_ready(req_r00_e_in_ready),
        .e_out_valid(req_r00_e_out_valid), .e_out_flit(req_r00_e_out_flit), .e_out_ready(req_r10_w_in_ready),
        .s_in_valid(1'b0), .s_in_flit({RQW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({RQW{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({RQW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RQW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(core_req_out_valid), .l_in_flit(core_req_out_flit), .l_in_ready(core_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0) // (0,0,0) never receives a request
    );
    wire req_r00_e_out_valid; wire [RQW-1:0] req_r00_e_out_flit; wire req_r00_e_in_ready;

    // ---- req router (1,0) ----
    router #(.FLIT_WIDTH(RQW), .MY_X(1), .MY_Y(0), .MY_Z(0)) req_r10 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RQW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({RQW{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({RQW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_r00_e_out_valid), .w_in_flit(req_r00_e_out_flit), .w_in_ready(req_r10_w_in_ready),
        .w_out_valid(req_r10_w_out_valid), .w_out_flit(req_r10_w_out_flit), .w_out_ready(req_r00_e_in_ready),
        .u_in_valid(1'b0), .u_in_flit({RQW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RQW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({RQW{1'b0}}), .l_in_ready(),
        .l_out_valid(mem_req_in_valid), .l_out_flit(mem_req_in_flit), .l_out_ready(mem_req_in_ready)
    );
    wire req_r10_w_out_valid; wire [RQW-1:0] req_r10_w_out_flit; wire req_r10_w_in_ready;

    // ---- resp router (1,0) ----
    router #(.FLIT_WIDTH(RSW), .MY_X(1), .MY_Y(0), .MY_Z(0)) resp_r10 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RSW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({RSW{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({RSW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_r00_e_out_valid), .w_in_flit(resp_r00_e_out_flit), .w_in_ready(resp_r10_w_in_ready),
        .w_out_valid(resp_r10_w_out_valid), .w_out_flit(resp_r10_w_out_flit), .w_out_ready(resp_r00_e_in_ready),
        .u_in_valid(1'b0), .u_in_flit({RSW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RSW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(mem_resp_out_valid), .l_in_flit(mem_resp_out_flit), .l_in_ready(mem_resp_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0) // (1,0,0) never RECEIVES a response
    );
    wire resp_r10_w_out_valid; wire [RSW-1:0] resp_r10_w_out_flit; wire resp_r10_w_in_ready;

    // ---- resp router (0,0) ----
    router #(.FLIT_WIDTH(RSW), .MY_X(0), .MY_Y(0), .MY_Z(0)) resp_r00 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({RSW{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_r10_w_out_valid), .e_in_flit(resp_r10_w_out_flit), .e_in_ready(resp_r00_e_in_ready),
        .e_out_valid(resp_r00_e_out_valid), .e_out_flit(resp_r00_e_out_flit), .e_out_ready(resp_r10_w_in_ready),
        .s_in_valid(1'b0), .s_in_flit({RSW{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({RSW{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({RSW{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({RSW{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({RSW{1'b0}}), .l_in_ready(),
        .l_out_valid(core_resp_in_valid), .l_out_flit(core_resp_in_flit), .l_out_ready(core_resp_in_ready)
    );
    wire resp_r00_e_out_valid; wire [RSW-1:0] resp_r00_e_out_flit; wire resp_r00_e_in_ready;

    // ---- memory adapter at (1,0) ----
    wire                mem_req_in_valid;
    wire [RQW-1:0]      mem_req_in_flit;
    wire                mem_req_in_ready;
    wire                mem_resp_out_valid;
    wire [RSW-1:0]      mem_resp_out_flit;
    wire                mem_resp_out_ready;

    noc_mem_adapter #(.MEM_BYTES(64), .REQ_FLIT_WIDTH(RQW), .RESP_FLIT_WIDTH(RSW)) mem_adap (
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

        // Write 0xDEADBEEF to address 4, read it back through the SAME
        // real round trip - proves actual memory persistence across the
        // network, not just "grant eventually fired."
        do_access(1, 32'd4, 32'hDEADBEEF, got);
        do_access(0, 32'd4, 32'h0, got);
        check(got == 32'hDEADBEEF, "read-back through the NoC matches what was written");

        // A second, different address/value - rules out "always returns
        // the first thing written" as an accidental pass.
        do_access(1, 32'd8, 32'h12345678, got);
        do_access(0, 32'd8, 32'h0, got);
        check(got == 32'h12345678, "second independent write/read pair also round-trips correctly");

        // Re-read the FIRST address again - confirms the second write
        // didn't clobber unrelated memory (byte-addressed, distinct
        // offsets) and that this node correctly serves MULTIPLE
        // sequential transactions, not just one.
        do_access(0, 32'd4, 32'h0, got);
        check(got == 32'hDEADBEEF, "first address unaffected by the second write, third round trip also correct");

        if (errors == 0) $display("ALL NOC LINK TESTS PASSED");
        else $display("%0d NOC LINK TEST(S) FAILED", errors);
        $finish;
    end
endmodule
