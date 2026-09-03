// Single-precision (binary32) floating-point multiply,
// round-to-nearest-even. Ported near-verbatim from
// hardware/rv32i_core/rtl/fp_mul.v (that project's real, working
// RV32F FPU) - used here by cpu_core.v's QHAD amplitude-mixing
// sequencer. Same scope limitation as fp_addsub.v, inherited
// unchanged: every input is assumed to be either a normal finite
// number (biased exponent in [1,254]) or exact zero - NaN/infinity/
// subnormal inputs are out of scope and may produce numerically wrong
// (but not X-propagating or hanging) results.
`timescale 1ns/1ps

module fp_mul (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);
    wire        sign_a = a[31];
    wire [7:0]  exp_a  = a[30:23];
    wire [22:0] frac_a = a[22:0];
    wire        sign_b = b[31];
    wire [7:0]  exp_b  = b[30:23];
    wire [22:0] frac_b = b[22:0];

    wire a_is_zero = (exp_a == 8'b0) && (frac_a == 23'b0);
    wire b_is_zero = (exp_b == 8'b0) && (frac_b == 23'b0);
    wire sign_result = sign_a ^ sign_b;

    // 24-bit significands (implicit leading 1 + 23-bit fraction), full
    // 48-bit product - no truncation in the multiply itself.
    wire [23:0] siga = {1'b1, frac_a};
    wire [23:0] sigb = {1'b1, frac_b};
    wire [47:0] product = siga * sigb;

    // Wide enough signed intermediate: exp_a/exp_b are each 0..255, so
    // their raw sum tops out at 510, comfortably inside a 10-bit
    // signed range even before subtracting the single bias.
    wire signed [9:0] exp_unbiased =
        $signed({2'b0, exp_a}) + $signed({2'b0, exp_b}) - 10'sd127;

    // Both significands are in [1.0, 2.0), so their product is in
    // [1.0, 4.0). product[47] set means the product is >= 2.0 and
    // needs one extra exponent step - the two cases pick a different
    // 23-bit mantissa slice and a different guard/round/sticky source.
    wire         prod_ge_2 = product[47];
    wire [22:0]  mant_pre  = prod_ge_2 ? product[46:24] : product[45:23];
    wire         guard     = prod_ge_2 ? product[23]    : product[22];
    wire         rnd       = prod_ge_2 ? product[22]    : product[21];
    wire         sticky    = prod_ge_2 ? (|product[21:0]) : (|product[20:0]);
    wire signed [9:0] exp_norm = exp_unbiased + (prod_ge_2 ? 10'sd1 : 10'sd0);

    wire round_up = guard && (rnd || sticky || mant_pre[0]);

    // 24-bit width (not 23) so an all-1s mantissa rounding up is
    // actually detected as a carry-out, not silently wrapped - the
    // exact bug class hand-caught and fixed in fp_addsub.v's own
    // rounding step.
    wire [23:0] rounded = {1'b0, mant_pre} + (round_up ? 24'd1 : 24'd0);
    wire        round_carry = rounded[23];
    // Unlike fp_addsub.v's rounding step, mant_pre here is ALREADY the
    // pure 23-bit fraction (no guard/round bits mixed in) - on a
    // genuine carry-out (mant_pre was all-1s), the arithmetic itself
    // already leaves rounded[22:0] at exactly zero (the correct
    // renormalized fraction for 1.000...0 x 2^(e+1)), so no extra
    // shift is needed in either branch.
    wire [22:0] final_frac_pre = rounded[22:0];
    wire signed [9:0] final_exp_pre = exp_norm + (round_carry ? 10'sd1 : 10'sd0);

    always @(*) begin
        if (a_is_zero || b_is_zero) begin
            result = {sign_result, 31'b0};
        end else if (final_exp_pre <= 10'sd0) begin
            // Underflow: this project's documented simplification is
            // to flush to zero rather than produce a subnormal result
            // (subnormals are explicitly out of scope).
            result = {sign_result, 31'b0};
        end else if (final_exp_pre >= 10'sd255) begin
            // Overflow: saturate to true infinity (exponent=8'hFF,
            // fraction=0) - the standard IEEE-754 overflow result.
            result = {sign_result, 8'hFF, 23'b0};
        end else begin
            result = {sign_result, final_exp_pre[7:0], final_frac_pre};
        end
    end
endmodule
