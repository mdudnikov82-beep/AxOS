// AxISA milestone-2 full-core testbench (see sw/asm_test2.py for the
// exact program and its hand-computed expected values). Every new
// instruction (GLUON/BARYON/MESON/LOAD/STORE/JAL) folds its result
// into a running N-bank accumulator via ordinary ALUR adds, so the
// final tohost value can only be right if every step upstream
// computed correctly - not just proof that the core "ran without
// crashing." r3 (GLUON's same-bank-R, worst-case 2R+1W result) is
// checked separately via direct hierarchical peek, since it's an
// R-bank result milestone 2 still has no way to surface through
// tohost directly (same reasoning tb_cpu.v already uses for R/G/B).
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/test2.hex"
`endif

module tb_cpu2;
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
        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 324;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 60;

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
            check(tohost_value, expect_tohost, "tohost (BARYON+MESON+GLUON+LOAD/STORE+JAL chain)");
            check(dut.r_bank.regs[3], 32'd3, "r3 (GLUON same-bank R, 2R+1W, direct peek)");
        end

        if (errors == 0) $display("ALL AXISA MILESTONE-2 TESTS PASSED");
        else $display("%0d AXISA TEST(S) FAILED", errors);
        $finish;
    end
endmodule
