// Standalone router.v testbench - verifies routing/arbitration/
// backpressure in isolation before any mesh integration (matches this
// project's established practice of testing a new component alone
// first). FLIT_WIDTH=12: top 4 bits {dest_x,dest_y} (routing-relevant),
// low 8 bits an opaque "tag" byte used only so test output is easy to
// read - router.v never inspects it.
`timescale 1ns/1ps

module tb_router;
    localparam FW = 12;
    reg clk, reset;
    integer errors;
    reg n_seen, w_seen;

    // Router under test at (1,1) - an interior node, so all 5 output
    // directions are meaningfully reachable from some dest.
    reg           n_in_valid, e_in_valid, s_in_valid, w_in_valid, l_in_valid;
    reg  [FW-1:0] n_in_flit,  e_in_flit,  s_in_flit,  w_in_flit,  l_in_flit;
    wire          n_in_ready, e_in_ready, s_in_ready, w_in_ready, l_in_ready;
    wire          n_out_valid, e_out_valid, s_out_valid, w_out_valid, l_out_valid;
    wire [FW-1:0] n_out_flit,  e_out_flit,  s_out_flit,  w_out_flit,  l_out_flit;
    reg           n_out_ready, e_out_ready, s_out_ready, w_out_ready, l_out_ready;

    router #(.FLIT_WIDTH(FW), .MY_X(1), .MY_Y(1)) dut (
        .clk(clk), .reset(reset),
        .n_in_valid(n_in_valid), .n_in_flit(n_in_flit), .n_in_ready(n_in_ready),
        .n_out_valid(n_out_valid), .n_out_flit(n_out_flit), .n_out_ready(n_out_ready),
        .e_in_valid(e_in_valid), .e_in_flit(e_in_flit), .e_in_ready(e_in_ready),
        .e_out_valid(e_out_valid), .e_out_flit(e_out_flit), .e_out_ready(e_out_ready),
        .s_in_valid(s_in_valid), .s_in_flit(s_in_flit), .s_in_ready(s_in_ready),
        .s_out_valid(s_out_valid), .s_out_flit(s_out_flit), .s_out_ready(s_out_ready),
        .w_in_valid(w_in_valid), .w_in_flit(w_in_flit), .w_in_ready(w_in_ready),
        .w_out_valid(w_out_valid), .w_out_flit(w_out_flit), .w_out_ready(w_out_ready),
        .l_in_valid(l_in_valid), .l_in_flit(l_in_flit), .l_in_ready(l_in_ready),
        .l_out_valid(l_out_valid), .l_out_flit(l_out_flit), .l_out_ready(l_out_ready)
    );

    always #5 clk = ~clk;

    function [FW-1:0] mkflit(input [1:0] dx, input [1:0] dy, input [7:0] tag);
        mkflit = {dx, dy, tag};
    endfunction

    task clear_inputs;
        begin
            n_in_valid = 0; e_in_valid = 0; s_in_valid = 0; w_in_valid = 0; l_in_valid = 0;
            n_in_flit = 0; e_in_flit = 0; s_in_flit = 0; w_in_flit = 0; l_in_flit = 0;
        end
    endtask

    task check(input cond, input [200*8-1:0] msg);
        begin
            if (!cond) begin
                $display("FAIL: %0s", msg);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", msg);
            end
        end
    endtask

    initial begin
        clk = 0; reset = 1; errors = 0;
        clear_inputs;
        n_out_ready = 1; e_out_ready = 1; s_out_ready = 1; w_out_ready = 1; l_out_ready = 1;
        @(posedge clk); @(posedge clk);
        reset = 0;
        @(posedge clk);

        // ---- Test 1: basic XY routing, one direction at a time ----
        // dest_x > MY_X(1) -> must exit East.
        l_in_valid = 1; l_in_flit = mkflit(2'd2, 2'd1, 8'hAA);
        @(posedge clk);
        #1;
        check(e_out_valid && e_out_flit == mkflit(2'd2,2'd1,8'hAA), "dest_x>MY_X routes East");
        check(!n_out_valid && !s_out_valid && !w_out_valid && !l_out_valid, "no OTHER output fired for the East case");
        l_in_valid = 0;
        e_out_ready = 1; @(posedge clk); // drain

        // dest_x < MY_X -> West.
        l_in_valid = 1; l_in_flit = mkflit(2'd0, 2'd1, 8'hBB);
        @(posedge clk); #1;
        check(w_out_valid && w_out_flit == mkflit(2'd0,2'd1,8'hBB), "dest_x<MY_X routes West");
        l_in_valid = 0; @(posedge clk);

        // dest_x==MY_X, dest_y>MY_Y -> South.
        l_in_valid = 1; l_in_flit = mkflit(2'd1, 2'd2, 8'hCC);
        @(posedge clk); #1;
        check(s_out_valid && s_out_flit == mkflit(2'd1,2'd2,8'hCC), "dest_y>MY_Y (dest_x match) routes South");
        l_in_valid = 0; @(posedge clk);

        // dest_x==MY_X, dest_y<MY_Y -> North.
        l_in_valid = 1; l_in_flit = mkflit(2'd1, 2'd0, 8'hDD);
        @(posedge clk); #1;
        check(n_out_valid && n_out_flit == mkflit(2'd1,2'd0,8'hDD), "dest_y<MY_Y (dest_x match) routes North");
        l_in_valid = 0; @(posedge clk);

        // dest == self -> Local.
        w_in_valid = 1; w_in_flit = mkflit(2'd1, 2'd1, 8'hEE);
        @(posedge clk); #1;
        check(l_out_valid && l_out_flit == mkflit(2'd1,2'd1,8'hEE), "dest==self routes to Local");
        w_in_valid = 0; @(posedge clk);

        // ---- Test 2: straight-through (arrived from W, continues East) ----
        w_in_valid = 1; w_in_flit = mkflit(2'd3, 2'd1, 8'h11); // dest further east than MY_X
        @(posedge clk); #1;
        check(e_out_valid && e_out_flit == mkflit(2'd3,2'd1,8'h11), "arrived-from-W continues East (straight through, not blocked)");
        w_in_valid = 0; @(posedge clk);

        // ---- Test 3: contention + round-robin fairness ----
        // N and W BOTH want to go East at the same time - only one can
        // win this cycle; the other must be held (in_ready=0), and BOTH
        // must eventually get through as East keeps draining (neither
        // starved). Both testbench drivers keep asserting valid with
        // the same flit continuously (a real upstream would withdraw
        // once accepted, but re-presenting identical data is harmless
        // and keeps this test simple) - round-robin's last_granted
        // update guarantees the non-winner gets priority next.
        clear_inputs;
        e_out_ready = 0; // hold East's output empty so the FIRST arbitration below is a genuine tie
        @(posedge clk);
        n_in_valid = 1; n_in_flit = mkflit(2'd3, 2'd1, 8'h21);
        w_in_valid = 1; w_in_flit = mkflit(2'd3, 2'd1, 8'h22);
        #1; // sample in_ready in THIS cycle, before the edge consumes it -
            // right after the edge, East's register has already latched
            // the winner and can_accept drops, so BOTH in_ready would
            // read 0 by then (that's expected steady-state, not a bug).
        check((n_in_ready ^ w_in_ready), "exactly one of {N,W} wins arbitration for contended East output");
        @(posedge clk); #1;

        e_out_ready = 1; // start draining - both contenders should get serviced over the next couple cycles
        n_seen = n_in_ready; w_seen = w_in_ready;
        @(posedge clk); #1;
        n_seen = n_seen || n_in_ready; w_seen = w_seen || w_in_ready;
        @(posedge clk); #1;
        n_seen = n_seen || n_in_ready; w_seen = w_seen || w_in_ready;
        check(n_seen && w_seen, "both N and W contenders eventually won arbitration (neither starved)");
        clear_inputs;
        e_out_ready = 1;
        @(posedge clk);

        // ---- Test 4: real backpressure - output register holds its
        // flit unchanged across MULTIPLE cycles while out_ready=0, and
        // does not accept (or corrupt) a different flit meanwhile. ----
        clear_inputs;
        e_out_ready = 0;
        l_in_valid = 1; l_in_flit = mkflit(2'd3, 2'd1, 8'h33);
        @(posedge clk); #1;
        check(e_out_valid && e_out_flit == mkflit(2'd3,2'd1,8'h33), "backpressure test: flit captured into East's register");
        l_in_valid = 0;
        // Hold out_ready low for several cycles - flit must NOT change.
        @(posedge clk); #1;
        check(e_out_valid && e_out_flit == mkflit(2'd3,2'd1,8'h33), "held flit unchanged after 1 extra cycle of backpressure");
        @(posedge clk); #1;
        check(e_out_valid && e_out_flit == mkflit(2'd3,2'd1,8'h33), "held flit unchanged after 2 extra cycles of backpressure");
        // Try to inject a DIFFERENT flit wanting East while blocked - must not be accepted.
        w_in_valid = 1; w_in_flit = mkflit(2'd3, 2'd1, 8'h44);
        @(posedge clk); #1;
        check(!w_in_ready, "new East-bound flit NOT accepted while East's register is still full and undrained");
        check(e_out_flit == mkflit(2'd3,2'd1,8'h33), "East's register still holds the ORIGINAL flit, not overwritten");
        w_in_valid = 0;
        // Finally drain - the waiting flit must now get through.
        e_out_ready = 1;
        w_in_valid = 1; w_in_flit = mkflit(2'd3, 2'd1, 8'h44);
        @(posedge clk); #1;
        check(w_in_ready, "waiting flit accepted once East drains");
        check(e_out_flit == mkflit(2'd3,2'd1,8'h44), "East's register now holds the NEW flit after drain+refill");
        w_in_valid = 0;

        if (errors == 0) $display("ALL ROUTER TESTS PASSED");
        else $display("%0d ROUTER TEST(S) FAILED", errors);
        $finish;
    end
endmodule
