// Single-precision (binary32) floating-point add/subtract,
// round-to-nearest-even. Scope limitation, deliberate: every input is
// assumed to be either a normal finite number (biased exponent in
// [1,254]) or exact zero. NaN, infinity, and subnormal inputs are out
// of scope and may produce numerically wrong (but not X-propagating
// or hanging) results - see fp_mul.v's own comment for the same note.
`timescale 1ns/1ps

module fp_addsub (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        op_sub,   // 0 = a+b, 1 = a-b
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

    // Subtraction is addition with b's sign flipped.
    wire eff_sign_b = sign_b ^ op_sub;

    // 24-bit significands: implicit leading 1 + 23-bit fraction,
    // extended with 2 low zero bits reserved for guard/round precision
    // during alignment (a plain 24-bit shift would silently discard
    // exactly the bits rounding needs to see).
    wire [25:0] siga_ext = {1'b1, frac_a, 2'b00};
    wire [25:0] sigb_ext = {1'b1, frac_b, 2'b00};

    wire a_ge_b_exp = (exp_a >= exp_b);
    wire [7:0]  exp_large   = a_ge_b_exp ? exp_a     : exp_b;
    wire [25:0] sig_large   = a_ge_b_exp ? siga_ext  : sigb_ext;
    wire        sign_large0 = a_ge_b_exp ? sign_a    : eff_sign_b;
    wire [25:0] sig_small   = a_ge_b_exp ? sigb_ext  : siga_ext;
    wire        sign_small0 = a_ge_b_exp ? eff_sign_b : sign_a;
    wire [7:0]  exp_diff    = a_ge_b_exp ? (exp_a - exp_b) : (exp_b - exp_a);

    // Align: right-shift the smaller operand by exp_diff, tracking a
    // sticky bit that ORs together EVERY bit shifted out (not just the
    // last one) - required for correct round-to-nearest-even.
    reg [25:0] sig_small_aligned;
    reg        align_sticky;
    always @(*) begin
        if (exp_diff >= 8'd26) begin
            sig_small_aligned = 26'b0;
            align_sticky = |sig_small;
        end else if (exp_diff == 8'd0) begin
            sig_small_aligned = sig_small;
            align_sticky = 1'b0;
        end else begin
            sig_small_aligned = sig_small >> exp_diff;
            align_sticky = |(sig_small & ((26'b1 << exp_diff) - 26'b1));
        end
    end

    wire same_sign = (sign_large0 == sign_small0);

    // Equal exponents + different signs: the exponent compare alone
    // doesn't tell us which operand has the bigger MAGNITUDE - compare
    // the (unshifted, since exp_diff==0) significands directly.
    wire swap_for_equal_exp = (exp_diff == 8'd0) && !same_sign &&
                               (sig_small_aligned > sig_large);

    wire [25:0] minuend     = swap_for_equal_exp ? sig_small_aligned : sig_large;
    wire [25:0] subtrahend  = swap_for_equal_exp ? sig_large         : sig_small_aligned;
    wire        presub_sign = swap_for_equal_exp ? sign_small0       : sign_large0;

    wire [26:0] add_raw = {1'b0, sig_large} + {1'b0, sig_small_aligned}; // same-sign path
    wire [25:0] sub_raw = minuend - subtrahend;                          // diff-sign path

    // The exact-cancellation case (e.g. a-a): the raw difference is
    // all-zero, so there is no leading 1 for a leading-zero-counter to
    // find - must short-circuit to a clean +0 BEFORE ever attempting
    // to normalize, or the LZC's shift amount is undefined.
    wire sub_is_zero = !same_sign && (sub_raw == 26'b0);

    // Leading-zero count of the 26-bit subtraction result (used only
    // on the differing-sign path, and only when sub_is_zero is false).
    reg [4:0] lzc;
    always @(*) begin
        casez (sub_raw)
            26'b1?????????????????????????: lzc = 5'd0;
            26'b01????????????????????????: lzc = 5'd1;
            26'b001???????????????????????: lzc = 5'd2;
            26'b0001??????????????????????: lzc = 5'd3;
            26'b00001?????????????????????: lzc = 5'd4;
            26'b000001????????????????????: lzc = 5'd5;
            26'b0000001???????????????????: lzc = 5'd6;
            26'b00000001??????????????????: lzc = 5'd7;
            26'b000000001?????????????????: lzc = 5'd8;
            26'b0000000001????????????????: lzc = 5'd9;
            26'b00000000001???????????????: lzc = 5'd10;
            26'b000000000001??????????????: lzc = 5'd11;
            26'b0000000000001?????????????: lzc = 5'd12;
            26'b00000000000001????????????: lzc = 5'd13;
            26'b000000000000001???????????: lzc = 5'd14;
            26'b0000000000000001??????????: lzc = 5'd15;
            26'b00000000000000001?????????: lzc = 5'd16;
            26'b000000000000000001????????: lzc = 5'd17;
            26'b0000000000000000001???????: lzc = 5'd18;
            26'b00000000000000000001??????: lzc = 5'd19;
            26'b000000000000000000001?????: lzc = 5'd20;
            26'b0000000000000000000001????: lzc = 5'd21;
            26'b00000000000000000000001???: lzc = 5'd22;
            26'b000000000000000000000001??: lzc = 5'd23;
            26'b0000000000000000000000001?: lzc = 5'd24;
            26'b00000000000000000000000001: lzc = 5'd25;
            default:                        lzc = 5'd0; // all-zero: guarded by sub_is_zero
        endcase
    end

    // Pre-round normalized significand/exponent/sticky/sign, before
    // the final rounding step (which can itself carry out and need one
    // more shift - handled separately below).
    reg [25:0] norm_sig;
    reg [8:0]  norm_exp;  // 1 extra bit of headroom for +1 from carry/renorm
    reg        norm_sticky;
    reg        norm_sign;
    reg        is_exact_zero;

    always @(*) begin
        is_exact_zero = 1'b0;
        if (same_sign) begin
            if (add_raw[26]) begin
                // Carry out of the top: shift right 1, fold the
                // shifted-out bit into sticky (not lost), exponent+1.
                norm_sig    = add_raw[26:1];
                norm_sticky = align_sticky | add_raw[0];
                norm_exp    = {1'b0, exp_large} + 9'd1;
            end else begin
                norm_sig    = add_raw[25:0];
                norm_sticky = align_sticky;
                norm_exp    = {1'b0, exp_large};
            end
            norm_sign = sign_large0;
        end else if (sub_is_zero) begin
            is_exact_zero = 1'b1;
            norm_sig    = 26'b0;
            norm_sticky = 1'b0;
            norm_exp    = 9'b0;
            norm_sign   = 1'b0; // canonical +0, a documented simplification
        end else begin
            // Left-shift by lzc to renormalize after cancellation.
            // Underflow (exponent would go <=0) flushes to zero -
            // this project's documented simplification for the
            // subnormal-result case, not silently wrong: real hardware
            // would produce a subnormal here, which is out of scope.
            if ({1'b0, exp_large} <= {4'b0, lzc}) begin
                is_exact_zero = 1'b1;
                norm_sig    = 26'b0;
                norm_sticky = 1'b0;
                norm_exp    = 9'b0;
                norm_sign   = 1'b0;
            end else begin
                norm_sig    = sub_raw << lzc;
                norm_sticky = align_sticky; // left-shift never loses low bits
                norm_exp    = {1'b0, exp_large} - {4'b0, lzc};
            end
            norm_sign = presub_sign;
        end
    end

    // Round-to-nearest-even using guard (bit 1) / round (bit 0) /
    // sticky, with a tie broken toward an even (LSB=0) result.
    wire guard  = norm_sig[1];
    wire rnd    = norm_sig[0];
    wire frac_lsb = norm_sig[2];
    wire round_up = guard && (rnd || norm_sticky || frac_lsb);

    // A 25-bit (not 24-bit) sum here is required to actually DETECT a
    // round-up carry out of the top - the normalized significand's
    // bit23 (the implicit leading 1) is set in the ordinary, no-carry
    // case too, so checking a truncated 24-bit result's bit23 can't
    // tell "carried out" apart from "normal" (an earlier draft did
    // exactly that and take the carry-out shift path on EVERY result,
    // not just overflow - found by hand-tracing a constructed
    // round-to-even test case before ever running it).
    wire [24:0] rounded_wide     = {1'b0, norm_sig[25:2]} + (round_up ? 25'd1 : 25'd0);
    wire        round_carry      = rounded_wide[24];
    wire [23:0] rounded_sig_frac = rounded_wide[23:0];
    // A round-up carry out of the top (all-1s -> 1.000...0 x 2^(e+1))
    // needs one more right-shift-by-1 + exponent+1 - handled here as a
    // second, separate normalization pass from the earlier one.
    wire [22:0]  final_frac  = round_carry ? rounded_sig_frac[23:1] : rounded_sig_frac[22:0];
    wire [8:0]   final_exp   = norm_exp + (round_carry ? 9'd1 : 9'd0);

    always @(*) begin
        if (a_is_zero && b_is_zero) begin
            result = 32'b0; // canonical +0, documented simplification
        end else if (a_is_zero) begin
            result = {eff_sign_b, exp_b, frac_b};
        end else if (b_is_zero) begin
            result = a;
        end else if (is_exact_zero) begin
            result = 32'b0;
        end else begin
            result = {norm_sign, final_exp[7:0], final_frac};
        end
    end
endmodule
