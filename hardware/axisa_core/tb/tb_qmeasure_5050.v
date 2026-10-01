// QMEASURE invariant test: a real 50/50 branch (see
// sw/qmeasure_test_5050.axasm, docs/ISA.md's QMEASURE section). The
// real outcome depends on the live LFSR value - genuinely NOT
// predictable/assertable exactly - so this test reads the outcome
// bit at runtime and asserts INVARIANTS conditioned on it, instead of
// a single fixed expected value. This is the only one of the 3
// QMEASURE tests that exercises a real, non-forced branch (the other
// two are degenerate P0=1.0/P0=0.0 cases with exact expected values).
//
// Since the input amp0/amp1 both hold the SAME exact value (k=1/
// sqrt(2), Im=0), whichever group survives, its nonzero amplitude's
// Re component renormalizes back to approximately 1.0 (k/sqrt(k^2)
// = ~1.0) - checked with a small bit-pattern tolerance (real rounding
// noise from k^2 not being EXACTLY 0.5 in float32, propagated through
// fp_sqrt/fp_div, amounts to at most a few ULPs here), not exact
// equality.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/qmeasure_test_5050.hex"
`endif

module tb_qmeasure_5050;
    reg clk, reset;
    integer errors;
    integer max_cycles;
    integer cycle_count;

    wire halted;
    wire [31:0] tohost_value;
    wire        bus_req, bus_mem_write, bus_mem_unsigned, bus_grant;
    wire [31:0] bus_addr, bus_write_data, bus_read_data;
    wire [1:0]  bus_mem_size;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .irq_in(1'b0),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(1'b0), .bus_read_data(32'b0),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(8'b0), .uart_rx_ready_in(1'b0), .uart_rx_ack()
    );

    always #5 clk = ~clk;

    integer errors_local;
    // Bit-pattern tolerance, not a real ULP-correct float compare -
    // valid here specifically because both values being compared are
    // known positive and near the same exponent (~1.0), so raw
    // unsigned bit-pattern difference is a monotonic, meaningful proxy
    // for relative error. 256 ULPs = ~3e-5 relative - generous enough
    // for real accumulated fp_mul/fp_addsub/fp_sqrt/fp_div rounding,
    // still tight enough to catch a real logic bug (wrong operand,
    // stuck-at-zero, etc).
    localparam [31:0] ONE = 32'h3F800000;
    localparam [31:0] TOL = 32'd256;

    task check_approx_one(input [31:0] got, input [48*8-1:0] name);
        reg [31:0] diff;
        begin
            diff = (got > ONE) ? (got - ONE) : (ONE - got);
            if (diff > TOL) begin
                $display("FAIL: %0s got=0x%h, expected ~1.0 (0x%h) within %0d ULP, diff=%0d",
                          name, got, ONE, TOL, diff);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = 0x%h (within %0d ULP of 1.0)", name, got, diff);
            end
        end
    endtask

    task check_exact(input [31:0] got, input [31:0] expected, input [48*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL: %0s got=0x%h expected=0x%h", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = 0x%h", name, got);
            end
        end
    endtask

    initial begin
        errors = 0;
        max_cycles = 200;

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles", max_cycles);
            errors = errors + 1;
        end else begin
            $display("Halted after %0d cycles. outcome=%0d", cycle_count, tohost_value);
            check_exact(dut.n_bank.regs[1], tohost_value, "n1 matches tohost (outcome, direct peek)");

            if (tohost_value == 32'd0) begin
                // A group (amp0,amp2) survives, renormalized; B group
                // (amp1,amp3) exactly zeroed.
                $display("Outcome=0: checking A group survived, B group zeroed");
                check_approx_one(dut.r_bank.regs[0], "r0 (amp0 Re, survivor, ~1.0)");
                check_exact(dut.r_bank.regs[1], 32'h00000000, "r1 (amp0 Im, exact 0)");
                check_exact(dut.r_bank.regs[4], 32'h00000000, "r4 (amp2 Re, exact 0 - was already 0)");
                check_exact(dut.r_bank.regs[5], 32'h00000000, "r5 (amp2 Im, exact 0)");
                check_exact(dut.r_bank.regs[2], 32'h00000000, "r2 (amp1 Re, zeroed - losing group)");
                check_exact(dut.r_bank.regs[3], 32'h00000000, "r3 (amp1 Im, zeroed - losing group)");
                check_exact(dut.r_bank.regs[6], 32'h00000000, "r6 (amp3 Re, zeroed - losing group)");
                check_exact(dut.r_bank.regs[7], 32'h00000000, "r7 (amp3 Im, zeroed - losing group)");
            end else begin
                // B group (amp1,amp3) survives, renormalized; A group
                // (amp0,amp2) exactly zeroed.
                $display("Outcome=1: checking B group survived, A group zeroed");
                check_approx_one(dut.r_bank.regs[2], "r2 (amp1 Re, survivor, ~1.0)");
                check_exact(dut.r_bank.regs[3], 32'h00000000, "r3 (amp1 Im, exact 0)");
                check_exact(dut.r_bank.regs[6], 32'h00000000, "r6 (amp3 Re, exact 0 - was already 0)");
                check_exact(dut.r_bank.regs[7], 32'h00000000, "r7 (amp3 Im, exact 0)");
                check_exact(dut.r_bank.regs[0], 32'h00000000, "r0 (amp0 Re, zeroed - losing group)");
                check_exact(dut.r_bank.regs[1], 32'h00000000, "r1 (amp0 Im, zeroed - losing group)");
                check_exact(dut.r_bank.regs[4], 32'h00000000, "r4 (amp2 Re, zeroed - losing group)");
                check_exact(dut.r_bank.regs[5], 32'h00000000, "r5 (amp2 Im, zeroed - losing group)");
            end
        end

        if (errors == 0) $display("ALL AXISA QMEASURE 5050 TESTS PASSED");
        else $display("%0d AXISA QMEASURE 5050 TEST(S) FAILED", errors);
        $finish;
    end
endmodule
