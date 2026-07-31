// Multi-cycle radix-2 restoring divider for single-precision
// (binary32) FDIV.S. Same scope limitation as fp_addsub.v/fp_mul.v:
// every input is assumed to be either a normal finite number (biased
// exponent in [1,254]) or exact zero - NaN/infinity/subnormal inputs
// are out of scope and may produce numerically wrong (but not
// X-propagating or hanging) results.
//
// Algorithm: both 24-bit significands (1.xxx, already in [1,2)) are
// divided as plain unsigned integers - since both share the same
// implicit scale, the integer ratio already equals the real
// significand ratio, which lands in (0.5,2). Standard restoring
// division, 1 quotient bit per cycle: TOTAL_ITERS=49 (24 iterations
// consuming the dividend's own bits, then 25 more with an implicit 0
// bit brought down each time, extracting fractional quotient bits) -
// this K=25 is the minimum confirmed by design review to leave a
// correct guard bit in the worst case (quotient just above 0.5,
// needing a 1-bit renormalizing left-shift). The final leftover
// remainder (nonzero iff the division was inexact) is the ONLY sound
// source for the round/sticky decision - unlike fp_mul.v's exact
// 48-bit product, a quotient can be a non-terminating binary fraction,
// so no finite number of explicitly-computed extra quotient bits can
// ever prove the discarded tail is exactly zero the way a product's
// static bit-slice can.
`timescale 1ns/1ps

module fp_div (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire        busy,
    output wire        done,
    output wire [31:0] result
);
    localparam TOTAL_ITERS = 49;

    localparam ST_IDLE    = 2'b00;
    localparam ST_COMPUTE = 2'b01;
    localparam ST_DONE    = 2'b10;

    reg [1:0]  state;
    reg [5:0]  iter_count;
    reg [24:0] remainder;   // steady-state <2^24; transient (pre-subtract) <2^25
    reg [48:0] quotient;    // TOTAL_ITERS bits, one per iteration - only the low
                            // 26 ever end up nonzero (A/B<2 bounds it), but we
                            // simply never read the upper bits rather than
                            // relying on that as a correctness guarantee
    reg [23:0] dividend_r, divisor_r;
    reg        sign_r;
    reg        a_is_zero_r, b_is_zero_r;
    reg signed [9:0] exp_r;

    wire        sign_a = a[31];
    wire [7:0]  exp_a  = a[30:23];
    wire [22:0] frac_a = a[22:0];
    wire        sign_b = b[31];
    wire [7:0]  exp_b  = b[30:23];
    wire [22:0] frac_b = b[22:0];
    wire a_is_zero = (exp_a == 8'b0) && (frac_a == 23'b0);
    wire b_is_zero = (exp_b == 8'b0) && (frac_b == 23'b0);

    assign busy = (state != ST_IDLE);
    assign done = (state == ST_DONE);

    // One quotient bit per cycle while ST_COMPUTE: bring down the next
    // dividend bit (real bits first, then 0s once exhausted), shift
    // remainder left, subtract-and-record-1 if it fits.
    wire        bit_in = (iter_count < 24) ? dividend_r[23 - iter_count] : 1'b0;
    wire [24:0] trial  = {remainder[23:0], bit_in};
    wire        fits   = (trial >= {1'b0, divisor_r});

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= ST_IDLE;
            iter_count <= 6'b0;
            remainder <= 25'b0;
            quotient <= 49'b0;
            dividend_r <= 24'b0; divisor_r <= 24'b0;
            sign_r <= 1'b0; exp_r <= 10'sd0;
            a_is_zero_r <= 1'b0; b_is_zero_r <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        dividend_r  <= {1'b1, frac_a};
                        divisor_r   <= {1'b1, frac_b};
                        sign_r      <= sign_a ^ sign_b;
                        exp_r       <= $signed({2'b0, exp_a}) - $signed({2'b0, exp_b}) + 10'sd127;
                        a_is_zero_r <= a_is_zero;
                        b_is_zero_r <= b_is_zero;
                        remainder   <= 25'b0;
                        quotient    <= 49'b0;
                        iter_count  <= 6'b0;
                        state       <= ST_COMPUTE;
                    end
                end

                ST_COMPUTE: begin
                    if (fits) begin
                        remainder <= trial - {1'b0, divisor_r};
                        quotient  <= {quotient[47:0], 1'b1};
                    end else begin
                        remainder <= trial;
                        quotient  <= {quotient[47:0], 1'b0};
                    end
                    if (iter_count == TOTAL_ITERS - 1) begin
                        state <= ST_DONE;
                    end else begin
                        iter_count <= iter_count + 6'd1;
                    end
                end

                ST_DONE: begin
                    // One full cycle here before returning to IDLE -
                    // this is what gives `result` (combinational, off
                    // these now fully-settled registers) time to be
                    // genuinely valid on the same cycle `done` is high,
                    // rather than racing the final iteration's own
                    // not-yet-latched update (a real bug a design
                    // review caught before this was ever built).
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // ==================== Result assembly (combinational, valid during ST_DONE) ====================
    // quotient[25] set: result already in [1,2) scale (26 usable
    // bits: implicit + 23 frac + guard + round-or-sticky bit).
    // quotient[25] clear: result in [0.5,1) scale, needs a 1-bit left
    // shift + exponent decrement - only 25 usable bits are available
    // in this branch (the K_min=25 margin the design review derived),
    // so guard is the very last computed bit and the combined
    // round-or-sticky signal comes entirely from the leftover
    // remainder.
    wire branch_ge1 = quotient[25];
    wire [22:0] frac_pre        = branch_ge1 ? quotient[24:2] : quotient[23:1];
    wire        guard            = branch_ge1 ? quotient[1]    : quotient[0];
    wire        round_or_sticky  = branch_ge1 ? (quotient[0] | (remainder != 25'b0))
                                               : (remainder != 25'b0);
    wire        round_up = guard && (round_or_sticky || frac_pre[0]);

    wire [23:0] rounded      = {1'b0, frac_pre} + (round_up ? 24'd1 : 24'd0);
    wire        round_carry  = rounded[23];
    wire [22:0] final_frac   = rounded[22:0];
    wire signed [9:0] exp_after_branch = branch_ge1 ? exp_r : (exp_r - 10'sd1);
    wire signed [9:0] final_exp        = exp_after_branch + (round_carry ? 10'sd1 : 10'sd0);

    reg [31:0] result_r;
    always @(*) begin
        if (a_is_zero_r && b_is_zero_r) begin
            result_r = 32'b0; // canonical +0, documented simplification (real IEEE-754 would be NaN)
        end else if (b_is_zero_r) begin
            result_r = {sign_r, 8'hFF, 23'b0}; // divide by zero -> signed infinity
        end else if (a_is_zero_r) begin
            result_r = {sign_r, 31'b0}; // zero dividend -> signed zero
        end else if (final_exp <= 10'sd0) begin
            result_r = {sign_r, 31'b0}; // underflow -> flush to zero
        end else if (final_exp >= 10'sd255) begin
            result_r = {sign_r, 8'hFF, 23'b0}; // overflow -> saturate to infinity
        end else begin
            result_r = {sign_r, final_exp[7:0], final_frac};
        end
    end
    assign result = result_r;
endmodule
