`timescale 1ns/1ps

module tb_shared_bus;
    reg         clk;
    reg         reset;
    reg         p_req, e_req;
    reg  [31:0] p_addr, e_addr;
    reg  [31:0] p_write_data, e_write_data;
    reg         p_mem_write, e_mem_write;
    reg  [1:0]  p_mem_size, e_mem_size;
    reg         p_mem_unsigned, e_mem_unsigned;
    wire        p_grant, e_grant;
    wire [31:0] p_read_data, e_read_data;
    integer     errors;

    shared_bus dut (
        .clk(clk), .reset(reset),
        .p_req(p_req), .p_addr(p_addr), .p_write_data(p_write_data),
        .p_mem_write(p_mem_write), .p_mem_size(p_mem_size), .p_mem_unsigned(p_mem_unsigned),
        .p_grant(p_grant), .p_read_data(p_read_data),
        .e_req(e_req), .e_addr(e_addr), .e_write_data(e_write_data),
        .e_mem_write(e_mem_write), .e_mem_size(e_mem_size), .e_mem_unsigned(e_mem_unsigned),
        .e_grant(e_grant), .e_read_data(e_read_data)
    );

    always #5 clk = ~clk;

    task check(input got, input expected, input [40*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL %0s: got=%b expected=%b", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("OK   %0s", name);
            end
        end
    endtask

    initial begin
        errors = 0;
        clk = 0;
        reset = 1;
        p_req = 0; e_req = 0;
        p_addr = 0; e_addr = 0;
        p_write_data = 0; e_write_data = 0;
        p_mem_write = 0; e_mem_write = 0;
        p_mem_size = 2'b10; e_mem_size = 2'b10;
        p_mem_unsigned = 0; e_mem_unsigned = 0;
        @(posedge clk); #1;
        reset = 0;

        // Neither requests - neither granted.
        #1;
        check(p_grant, 1'b0, "no requests: p_grant=0");
        check(e_grant, 1'b0, "no requests: e_grant=0");

        // Only E requests - E granted.
        e_req = 1;
        #1;
        check(p_grant, 1'b0, "E alone: p_grant=0");
        check(e_grant, 1'b1, "E alone: e_grant=1");

        // Only P requests - P granted.
        e_req = 0; p_req = 1;
        #1;
        check(p_grant, 1'b1, "P alone: p_grant=1");
        check(e_grant, 1'b0, "P alone: e_grant=0");

        // BOTH request the same cycle - the FIRST tie after reset goes
        // to P (an arbitrary but fixed, testable reset default - see
        // shared_bus.v's own reset block), NOT because P always wins.
        e_req = 1; p_req = 1;
        #1;
        check(p_grant, 1'b1, "first tie after reset: P wins (p_grant=1)");
        check(e_grant, 1'b0, "first tie after reset: E loses (e_grant=0)");

        // Round-robin proof: keep BOTH requesting for several MORE
        // consecutive cycles with no reset in between - a fixed-
        // priority arbiter would let P win every single one of these;
        // real round-robin must alternate P, E, P, E, ...
        @(posedge clk); #1;
        check(p_grant, 1'b0, "round-robin tie 2: P loses this time (p_grant=0)");
        check(e_grant, 1'b1, "round-robin tie 2: E wins this time (e_grant=1)");

        @(posedge clk); #1;
        check(p_grant, 1'b1, "round-robin tie 3: back to P (p_grant=1)");
        check(e_grant, 1'b0, "round-robin tie 3: E loses (e_grant=0)");

        @(posedge clk); #1;
        check(p_grant, 1'b0, "round-robin tie 4: back to E (p_grant=0)");
        check(e_grant, 1'b1, "round-robin tie 4: E wins (e_grant=1)");

        p_req = 0; e_req = 0;

        // A lone requester must still be granted immediately regardless
        // of whatever the alternating history says - round-robin only
        // decides actual TIES, it must never make an uncontended access
        // wait its turn.
        @(posedge clk); #1;
        e_req = 1;
        #1;
        check(e_grant, 1'b1, "E alone after ties: still granted immediately");
        e_req = 0;

        // Reset again before the next scenario, so it starts from the
        // same known "P wins the first tie" state the test after it
        // depends on.
        reset = 1;
        @(posedge clk); #1;
        reset = 0;

        // Real memory behavior through the arbiter: E writes a word
        // while it holds the bus alone, P later reads it back through
        // ITS OWN port - proves both cores really share the same
        // underlying memory, not two separate ones.
        e_req = 1; e_addr = 32'h10; e_write_data = 32'hCAFEBABE;
        e_mem_write = 1; e_mem_size = 2'b10;
        @(posedge clk); #1;
        e_mem_write = 0; e_req = 0;

        p_req = 1; p_addr = 32'h10; p_mem_size = 2'b10;
        #1;
        check((p_read_data === 32'hCAFEBABE), 1'b1, "P reads back E's write through shared mem");

        // A write attempted while LOSING arbitration must not land -
        // E tries to write while P is simultaneously requesting; this
        // is (thanks to the reset just above) the first tie again, so
        // P wins, and E's write this cycle must be silently dropped,
        // not just delayed.
        p_req = 1; p_addr = 32'h20; p_mem_write = 0; p_mem_size = 2'b10;
        e_req = 1; e_addr = 32'h20; e_write_data = 32'h11111111;
        e_mem_write = 1; e_mem_size = 2'b10;
        @(posedge clk); #1;
        p_mem_write = 0; e_mem_write = 0; p_req = 0; e_req = 0;
        p_req = 1; p_addr = 32'h20; p_mem_size = 2'b10;
        #1;
        check((p_read_data === 32'h00000000), 1'b1, "E write dropped, lost arbitration");

        if (errors == 0) $display("ALL SHARED_BUS TESTS PASSED");
        else $display("%0d SHARED_BUS TESTS FAILED", errors);
        $finish;
    end
endmodule
