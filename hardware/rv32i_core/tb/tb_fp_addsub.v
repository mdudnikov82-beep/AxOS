// Expected bit patterns are an independent oracle, computed via
// Python's IEEE-754-correct float32 arithmetic (struct.pack('<f',...)),
// not hand-derived hex - matching this project's practice of trusting
// a second, independent computation over manual derivation wherever
// possible. The two round-to-even TIE cases (1.0 + exactly half a ULP)
// were hand-traced bit-by-bit instead, since Python's plain float add
// happens in double precision first and isn't guaranteed to reproduce
// a true single-rounding float32 result for an exact-tie input.
`timescale 1ns/1ps

module tb_fp_addsub;
    reg  [31:0] a, b;
    reg         op_sub;
    wire [31:0] result;
    integer     errors;

    fp_addsub dut (.a(a), .b(b), .op_sub(op_sub), .result(result));

    task check(input [31:0] expected, input [40*8-1:0] name);
        begin
            #1;
            if (result !== expected) begin
                $display("FAIL %0s: got=%h expected=%h", name, result, expected);
                errors = errors + 1;
            end else begin
                $display("OK   %0s", name);
            end
        end
    endtask

    initial begin
        errors = 0;

        a = 32'h3fc00000; b = 32'h40100000; op_sub = 0; // 1.5 + 2.25
        check(32'h40700000, "1.5 + 2.25 = 3.75");

        a = 32'h40b00000; b = 32'h40b00000; op_sub = 1; // 5.5 - 5.5 (exact cancellation)
        check(32'h00000000, "exact cancellation a-a = clean +0");

        a = 32'h3f800000; b = 32'h3f700000; op_sub = 1; // 1.0 - 0.9375
        check(32'h3d800000, "1.0 - 0.9375 = 0.0625 (multi-bit LZC renorm)");

        a = 32'h3fc00000; b = 32'h3fe00000; op_sub = 1; // 1.5 - 1.75, equal exponents
        check(32'hbe800000, "1.5 - 1.75 = -0.25 (equal-exponent magnitude swap)");

        a = 32'h3fc00000; b = 32'h3fc00000; op_sub = 0; // 1.5 + 1.5
        check(32'h40400000, "1.5 + 1.5 = 3.0 (carry-out during addition)");

        a = 32'hc0200000; b = 32'h3f800000; op_sub = 0; // -2.5 + 1.0
        check(32'hbfc00000, "-2.5 + 1.0 = -1.5");

        a = 32'h40400000; b = 32'h40a00000; op_sub = 1; // 3.0 - 5.0
        check(32'hc0000000, "3.0 - 5.0 = -2.0");

        // Round-to-nearest-EVEN tie: 1.0 + exactly half a ULP (2^-24).
        // 1.0's mantissa LSB is 0 (even) - a tie must round DOWN,
        // leaving the result exactly 1.0.
        a = 32'h3f800000; b = 32'h33800000; op_sub = 0;
        check(32'h3f800000, "round-to-even tie, even LSB: rounds DOWN (stays 1.0)");

        // Same half-ULP tie, but starting from 1.0's very next
        // representable value (mantissa LSB=1, odd) - a tie must round
        // UP this time, to the next-EVEN mantissa.
        a = 32'h3f800001; b = 32'h33800000; op_sub = 0;
        check(32'h3f800002, "round-to-even tie, odd LSB: rounds UP (to even)");

        if (errors == 0) $display("ALL FP_ADDSUB TESTS PASSED");
        else $display("%0d FP_ADDSUB TESTS FAILED", errors);
        $finish;
    end
endmodule
