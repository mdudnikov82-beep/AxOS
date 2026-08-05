// AxISA milestone-1 full-core testbench (see sw/asm_test1.py for the
// exact program). Checks BOTH the HALT/tohost value (N-bank arithmetic
// + a real taken branch) AND direct hierarchical peeks into the R/G/B
// banks' own registers - milestone 1 has no cross-bank move
// instruction yet (that's GLUON/BARYON/MESON, milestone 2), so there's
// no way for the PROGRAM itself to report R/G/B results via tohost;
// this is the testbench's way of still proving all 4 regbank instances
// independently compute correctly, not just the one (N) that happens
// to be reachable through HALT.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/test1.hex"
`endif

module tb_cpu;
    reg clk, reset;
    wire halted;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;
    integer errors;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value)
    );

    always #5 clk = ~clk;

    task check(input [31:0] got, input [31:0] expected, input [48*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL: %0s got=%0d expected=%0d", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", name, got);
            end
        end
    endtask

    initial begin
        errors = 0;
        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 200;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 50;

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
            $display("Halted after %0d cycles. tohost=%0d", cycle_count, tohost_value);
            check(tohost_value, expect_tohost, "tohost (N-bank arithmetic + branch)");
            check(dut.r_bank.regs[3], 32'd12, "r3 (R-bank arithmetic, direct peek)");
            check(dut.g_bank.regs[3], 32'd7,  "g3 (G-bank arithmetic, direct peek)");
            check(dut.b_bank.regs[3], 32'd30, "b3 (B-bank arithmetic, direct peek)");
        end

        if (errors == 0) $display("ALL AXISA MILESTONE-1 TESTS PASSED");
        else $display("%0d AXISA TEST(S) FAILED", errors);
        $finish;
    end
endmodule
