// Expected bit patterns computed via Python's IEEE-754-correct
// float32 arithmetic (an independent oracle), same discipline as
// tb_fp_addsub.v.
`timescale 1ns/1ps

module tb_fp_mul;
    reg  [31:0] a, b;
    wire [31:0] result;
    integer     errors;

    fp_mul dut (.a(a), .b(b), .result(result));

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

        a = 32'h40000000; b = 32'h40400000; // 2.0 * 3.0
        check(32'h40c00000, "2.0 * 3.0 = 6.0");

        a = 32'h3fc00000; b = 32'h3fc00000; // 1.5 * 1.5, product >= 2.0
        check(32'h40100000, "1.5 * 1.5 = 2.25 (product>=2.0 renorm path)");

        a = 32'hc0200000; b = 32'h40800000; // -2.5 * 4.0
        check(32'hc1200000, "-2.5 * 4.0 = -10.0 (sign handling)");

        a = 32'h3f000000; b = 32'h3f000000; // 0.5 * 0.5, product < 2.0
        check(32'h3e800000, "0.5 * 0.5 = 0.25 (product<2.0 path)");

        a = 32'h00800000; b = 32'h00800000; // smallest normal squared
        check(32'h00000000, "underflow: smallest-normal^2 flushes to zero");

        a = 32'h7f000000; b = 32'h7f000000; // near-max normal squared
        check(32'h7f800000, "overflow: saturates to +infinity");

        if (errors == 0) $display("ALL FP_MUL TESTS PASSED");
        else $display("%0d FP_MUL TESTS FAILED", errors);
        $finish;
    end
endmodule
