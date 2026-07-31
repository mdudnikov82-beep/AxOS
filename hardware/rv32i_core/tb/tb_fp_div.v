// Expected bit patterns are an independent oracle (Python's
// struct.pack('<f',...) IEEE-754 float32 division), same discipline
// as tb_fp_addsub.v/tb_fp_mul.v. Unlike those single-cycle units,
// fp_div.v is a real multi-cycle divider - each test pulses `start`
// for one cycle and waits for `done`, proving the start/busy/done
// handshake itself works, not just the arithmetic in isolation.
`timescale 1ns/1ps

module tb_fp_div;
    reg         clk, reset;
    reg         start;
    reg  [31:0] a, b;
    wire        busy, done;
    wire [31:0] result;
    integer     errors;
    integer     cycles;

    fp_div dut (.clk(clk), .reset(reset), .start(start), .a(a), .b(b),
                .busy(busy), .done(done), .result(result));

    always #5 clk = ~clk;

    task run_div(input [31:0] av, input [31:0] bv);
        begin
            // Make sure the DUT has actually settled back in IDLE
            // before asserting a new start - a previous division's
            // ST_DONE->IDLE transition happens on ITS OWN edge, and
            // asserting start on that exact edge (before IDLE is truly
            // reached) would drop start again before IDLE ever sees
            // it, silently never launching the next division.
            while (busy) begin
                @(posedge clk); #1;
            end
            a = av; b = bv;
            start = 1;
            @(posedge clk); #1;
            start = 0;
            cycles = 1;
            while (!done && cycles < 100) begin
                @(posedge clk); #1;
                cycles = cycles + 1;
            end
        end
    endtask

    task check(input [31:0] expected, input [40*8-1:0] name);
        begin
            if (!done) begin
                $display("FAIL %0s: never completed (busy=%b after %0d cycles)", name, busy, cycles);
                errors = errors + 1;
            end else if (result !== expected) begin
                $display("FAIL %0s: got=%h expected=%h (took %0d cycles)", name, result, expected, cycles);
                errors = errors + 1;
            end else begin
                $display("OK   %0s (took %0d cycles)", name, cycles);
            end
        end
    endtask

    initial begin
        errors = 0;
        clk = 0; reset = 1; start = 0; a = 0; b = 0;
        @(posedge clk); #1;
        reset = 0;

        run_div(32'h40c00000, 32'h40000000); // 6.0/2.0
        check(32'h40400000, "6.0 / 2.0 = 3.0 (exact)");

        run_div(32'h3f800000, 32'h40400000); // 1.0/3.0
        check(32'h3eaaaaab, "1.0 / 3.0 (inexact, round-to-nearest-even)");

        run_div(32'h41200000, 32'h40800000); // 10.0/4.0
        check(32'h40200000, "10.0 / 4.0 = 2.5");

        run_div(32'h40400000, 32'h40800000); // 3.0/4.0 - quotient<1 branch
        check(32'h3f400000, "3.0 / 4.0 = 0.75 (quotient<1 normalization branch)");

        run_div(32'h40e00000, 32'h40000000); // 7.0/2.0 - quotient>=1 branch
        check(32'h40600000, "7.0 / 2.0 = 3.5 (quotient>=1 normalization branch)");

        run_div(32'hc0a00000, 32'h40000000); // -5.0/2.0
        check(32'hc0200000, "-5.0 / 2.0 = -2.5 (sign handling)");

        run_div(32'h40a00000, 32'h00000000); // 5.0/0.0
        check(32'h7f800000, "5.0 / 0.0 = +infinity");

        run_div(32'h00000000, 32'h40a00000); // 0.0/5.0
        check(32'h00000000, "0.0 / 5.0 = +0");

        run_div(32'h00800000, 32'h7f000000); // smallest normal / near-max normal
        check(32'h00000000, "underflow: smallest-normal / near-max flushes to zero");

        // Back-to-back divisions - proves the FSM correctly returns to
        // IDLE and accepts a genuinely new start, not just a one-shot.
        run_div(32'h40400000, 32'h40000000); // 3.0/2.0
        check(32'h3fc00000, "back-to-back: 3.0 / 2.0 = 1.5");

        if (errors == 0) $display("ALL FP_DIV TESTS PASSED");
        else $display("%0d FP_DIV TESTS FAILED", errors);
        $finish;
    end
endmodule
