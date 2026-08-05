// Expected bit patterns are an independent oracle (Python's
// struct.pack('<f',...)/math.sqrt), same discipline as tb_fp_div.v.
// The exact algorithm (radix-4 restoring recurrence, exponent-parity
// doubling, rounding) was independently modeled in Python and fuzzed
// against real math.sqrt for 2,000,000+ random cases plus every
// boundary exponent BEFORE fp_sqrt.v was written - these are a curated
// subset covering the same categories that fuzz pass exercises: exact
// squares (round_or_sticky=0 path), an inexact case with a full hand-
// verifiable trace (sqrt(2.0), see fp_sqrt.v's header), sign handling
// (zero/negative-zero/negative-nonzero->NaN), and the odd/even exponent
// parity boundary that a first hand-derivation attempt got wrong.
`timescale 1ns/1ps

module tb_fp_sqrt;
    reg         clk, reset;
    reg         start;
    reg  [31:0] a;
    wire        busy, done;
    wire [31:0] result;
    integer     errors;
    integer     cycles;

    fp_sqrt dut (.clk(clk), .reset(reset), .start(start), .a(a),
                 .busy(busy), .done(done), .result(result));

    always #5 clk = ~clk;

    task run_sqrt(input [31:0] av);
        begin
            while (busy) begin
                @(posedge clk); #1;
            end
            a = av;
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
        clk = 0; reset = 1; start = 0; a = 0;
        @(posedge clk); #1;
        reset = 0;

        run_sqrt(32'h3f800000); // sqrt(1.0)
        check(32'h3f800000, "sqrt(1.0) = 1.0 (exact)");

        run_sqrt(32'h40800000); // sqrt(4.0)
        check(32'h40000000, "sqrt(4.0) = 2.0 (exact, even exponent)");

        run_sqrt(32'h41100000); // sqrt(9.0)
        check(32'h40400000, "sqrt(9.0) = 3.0 (exact, odd exponent -> doubling branch)");

        run_sqrt(32'h41800000); // sqrt(16.0)
        check(32'h40800000, "sqrt(16.0) = 4.0 (exact)");

        run_sqrt(32'h42c80000); // sqrt(100.0)
        check(32'h41200000, "sqrt(100.0) = 10.0 (exact)");

        run_sqrt(32'h461c4000); // sqrt(10000.0)
        check(32'h42c80000, "sqrt(10000.0) = 100.0 (exact)");

        run_sqrt(32'h40000000); // sqrt(2.0) - the fully hand-verified trace in fp_sqrt.v's header
        check(32'h3fb504f3, "sqrt(2.0) (inexact, round-to-nearest-even)");

        run_sqrt(32'h40400000); // sqrt(3.0)
        check(32'h3fddb3d7, "sqrt(3.0) (inexact)");

        run_sqrt(32'h3e800000); // sqrt(0.25)
        check(32'h3f000000, "sqrt(0.25) = 0.5 (exact, exponent below bias)");

        run_sqrt(32'h40a00000); // sqrt(5.0)
        check(32'h400f1bbd, "sqrt(5.0) (inexact)");

        run_sqrt(32'h49800000); // sqrt(1048576.0) = 1024.0
        check(32'h44800000, "sqrt(1048576.0) = 1024.0 (large exact power-of-2 square)");

        run_sqrt(32'h00000000); // sqrt(+0)
        check(32'h00000000, "sqrt(+0) = +0");

        run_sqrt(32'h80000000); // sqrt(-0)
        check(32'h80000000, "sqrt(-0) = -0 (sign preserved, NOT the NaN branch)");

        run_sqrt(32'hbf800000); // sqrt(-1.0)
        check(32'h7fc00000, "sqrt(-1.0) = canonical quiet NaN");

        run_sqrt(32'hc0800000); // sqrt(-4.0)
        check(32'h7fc00000, "sqrt(-4.0) = canonical quiet NaN");

        // Back-to-back square roots - proves the FSM correctly returns
        // to IDLE and accepts a genuinely new start, not just a one-shot.
        run_sqrt(32'h40800000); // sqrt(4.0) again
        check(32'h40000000, "back-to-back: sqrt(4.0) = 2.0");

        if (errors == 0) $display("ALL FP_SQRT TESTS PASSED");
        else $display("%0d FP_SQRT TESTS FAILED", errors);
        $finish;
    end
endmodule
