// Tests the generalized N-way (NUM_CORES=4 by default) round-robin
// shared_bus.v. Expected bit patterns / grant sequences are derived
// directly from the rotating-priority rule (scan starts at
// last_granted+1, grants the first requester found) - the same
// discipline as this project's other testbenches, just applied to an
// arbiter instead of arithmetic.
`timescale 1ns/1ps

module tb_shared_bus;
    localparam NUM_CORES = 4;

    reg         clk, reset;
    reg  [NUM_CORES-1:0]      req;
    reg  [NUM_CORES*32-1:0]   addr_flat, write_data_flat;
    reg  [NUM_CORES-1:0]      mem_write;
    reg  [NUM_CORES*2-1:0]    mem_size_flat;
    reg  [NUM_CORES-1:0]      mem_unsigned;
    wire [NUM_CORES-1:0]      grant;
    wire [31:0]                read_data;
    integer                    errors;

    shared_bus #(.NUM_CORES(NUM_CORES)) dut (
        .clk(clk), .reset(reset),
        .req(req), .addr_flat(addr_flat), .write_data_flat(write_data_flat),
        .mem_write(mem_write), .mem_size_flat(mem_size_flat), .mem_unsigned(mem_unsigned),
        .grant(grant), .read_data(read_data)
    );

    always #5 clk = ~clk;

    task check(input [NUM_CORES-1:0] got, input [NUM_CORES-1:0] expected, input [40*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL %0s: got=%b expected=%b", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("OK   %0s", name);
            end
        end
    endtask

    task set_addr(input integer idx, input [31:0] a);
        begin
            addr_flat[idx*32 +: 32] = a;
        end
    endtask

    task set_write_data(input integer idx, input [31:0] d);
        begin
            write_data_flat[idx*32 +: 32] = d;
        end
    endtask

    task set_mem_size(input integer idx, input [1:0] s);
        begin
            mem_size_flat[idx*2 +: 2] = s;
        end
    endtask

    initial begin
        errors = 0;
        clk = 0;
        reset = 1;
        req = {NUM_CORES{1'b0}};
        addr_flat = 0; write_data_flat = 0; mem_write = 0; mem_unsigned = 0;
        set_mem_size(0, 2'b10); set_mem_size(1, 2'b10);
        set_mem_size(2, 2'b10); set_mem_size(3, 2'b10);
        @(posedge clk); #1;
        reset = 0;

        // Neither requests - no grants.
        #1;
        check(grant, 4'b0000, "no requests: no grants");

        // Only core 1 requests - core 1 granted.
        req = 4'b0010;
        #1;
        check(grant, 4'b0010, "core1 alone: granted");

        // Only core 0 requests - core 0 granted.
        req = 4'b0001;
        #1;
        check(grant, 4'b0001, "core0 alone: granted");

        // Both core0 and core1 request - first tie after reset goes to
        // core 0 (reset default last_granted=NUM_CORES-1=3, scan starts
        // at 0).
        req = 4'b0011;
        #1;
        check(grant, 4'b0001, "first tie after reset: core0 wins");

        // Keep both requesting for several more cycles with no reset -
        // must alternate 0,1,0,1,... (round-robin, not fixed priority).
        @(posedge clk); #1;
        check(grant, 4'b0010, "tie 2: core1 (alternates)");
        @(posedge clk); #1;
        check(grant, 4'b0001, "tie 3: back to core0");
        @(posedge clk); #1;
        check(grant, 4'b0010, "tie 4: back to core1");

        // ===== N=4 fairness: all four request continuously =====
        // From reset, rotation should visit exactly 0,1,2,3,0,1,2,3 -
        // deterministic proof no core is ever skipped among 4.
        reset = 1; @(posedge clk); #1; reset = 0;
        req = 4'b1111;
        #1;
        check(grant, 4'b0001, "4-way rotation: core0 (1st)");
        @(posedge clk); #1;
        check(grant, 4'b0010, "4-way rotation: core1 (2nd)");
        @(posedge clk); #1;
        check(grant, 4'b0100, "4-way rotation: core2 (3rd)");
        @(posedge clk); #1;
        check(grant, 4'b1000, "4-way rotation: core3 (4th)");
        @(posedge clk); #1;
        check(grant, 4'b0001, "4-way rotation: wraps back to core0");
        @(posedge clk); #1;
        check(grant, 4'b0010, "4-way rotation: core1 again");

        // Core2 goes momentarily idle right when it would be its turn -
        // the arbiter must move on to the next actual requester instead
        // of stalling. (Each check below reflects the grant computed
        // from the register state the PRECEDING edge just latched,
        // combined with whatever req currently is - since req is set
        // BEFORE each edge and held through its check, this correctly
        // traces one rotation step per edge.)
        req = 4'b1011; // core2 not requesting this cycle
        @(posedge clk); #1;
        check(grant, 4'b1000, "core2 idle: rotation moves on, doesn't stall on the gap");

        // Core2 rejoins - must be served on ITS next real opportunity,
        // not skipped forever for having missed one turn.
        req = 4'b1111;
        @(posedge clk); #1;
        check(grant, 4'b1000, "core3 still being served this step");
        @(posedge clk); #1;
        check(grant, 4'b0001, "rotation continues to core0");
        @(posedge clk); #1;
        check(grant, 4'b0010, "rotation reaches core1 again");
        @(posedge clk); #1;
        check(grant, 4'b0100, "core2 confirmed NOT skipped - gets its turn");

        req = {NUM_CORES{1'b0}};

        // Real memory behavior through the arbiter: core1 writes a
        // word while it holds the bus alone, core0 later reads it back
        // through ITS OWN port - proves all cores really share the
        // same underlying memory.
        req = 4'b0010; set_addr(1, 32'h10); set_write_data(1, 32'hCAFEBABE);
        mem_write[1] = 1; set_mem_size(1, 2'b10);
        @(posedge clk); #1;
        mem_write[1] = 0; req = 4'b0000;

        req = 4'b0001; set_addr(0, 32'h10); set_mem_size(0, 2'b10);
        #1;
        check((read_data === 32'hCAFEBABE), 4'b0001, "core0 reads back core1's write through shared mem");

        // A write attempted while LOSING arbitration must not land -
        // core1 tries to write while core0 is simultaneously
        // requesting (core0 wins per the first-tie-after-this-point
        // rotation state), so core1's write this cycle must be
        // silently dropped, not just delayed.
        reset = 1; @(posedge clk); #1; reset = 0; // fresh: core0 wins next tie
        req = 4'b0001; set_addr(0, 32'h20); mem_write[0] = 0; set_mem_size(0, 2'b10);
        req = req | 4'b0010; set_addr(1, 32'h20); set_write_data(1, 32'h11111111);
        mem_write[1] = 1; set_mem_size(1, 2'b10);
        @(posedge clk); #1;
        mem_write[0] = 0; mem_write[1] = 0; req = 4'b0000;
        req = 4'b0001; set_addr(0, 32'h20); set_mem_size(0, 2'b10);
        #1;
        check((read_data === 32'h00000000), 4'b0001, "core1 write dropped, lost arbitration");

        if (errors == 0) $display("ALL SHARED_BUS TESTS PASSED");
        else $display("%0d SHARED_BUS TESTS FAILED", errors);
        $finish;
    end
endmodule
