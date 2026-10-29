// Binary32 multiply, round-to-nearest-even, in TWO pipeline stages
// (v2.2). Same arithmetic, bit for bit, as fp_mul.v; a register splits
// it after the 24x24 significand product:
//   stage 1: significand product, exponent sum, sign, zero detect
//   stage 2: normalize, round, underflow / overflow
// The result for the inputs presented in cycle N appears in cycle N+1;
// cpu_core.v holds the inputs for both cycles (fa_wait). Same scope
// limits as fp_mul.v.
`timescale 1ns/1ps

module fp_mul2 (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);
    // ---------------- stage 1 ----------------
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
    // ---------------- stage register ----------------
    reg [47:0]       product_r;
    reg signed [9:0] exp_unbiased_r;
    reg              sign_result_r, zero_r;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            product_r <= 48'b0; exp_unbiased_r <= 10'sd0; sign_result_r <= 1'b0; zero_r <= 1'b1;
        end else begin
            product_r <= product; exp_unbiased_r <= exp_unbiased;
            sign_result_r <= sign_result; zero_r <= a_is_zero || b_is_zero;
        end
    end

    // ---------------- stage 2 ----------------
    wire         prod_ge_2 = product_r[47];
    wire [22:0]  mant_pre  = prod_ge_2 ? product_r[46:24] : product_r[45:23];
    wire         guard     = prod_ge_2 ? product_r[23]    : product_r[22];
    wire         rnd       = prod_ge_2 ? product_r[22]    : product_r[21];
    wire         sticky    = prod_ge_2 ? (|product_r[21:0]) : (|product_r[20:0]);
    wire signed [9:0] exp_norm = exp_unbiased_r + (prod_ge_2 ? 10'sd1 : 10'sd0);

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
        if (zero_r) begin
            result = {sign_result_r, 31'b0};
        end else if (final_exp_pre <= 10'sd0) begin
            // Underflow: this project's documented simplification is
            // to flush to zero rather than produce a subnormal result
            // (subnormals are explicitly out of scope).
            result = {sign_result_r, 31'b0};
        end else if (final_exp_pre >= 10'sd255) begin
            // Overflow: saturate to true infinity (exponent=8'hFF,
            // fraction=0) - the standard IEEE-754 overflow result.
            result = {sign_result_r, 8'hFF, 23'b0};
        end else begin
            result = {sign_result_r, final_exp_pre[7:0], final_frac_pre};
        end
    end
endmodule
