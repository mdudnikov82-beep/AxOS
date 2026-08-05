// AxISA's FIRST multi-core test: 3 real cpu_core.v instances in the
// 2x2 mesh (rtl/soc_top.v) at once. c0 (shared_consumer.hex) busy-
// waits then reads c1's (shared_producer.hex) payload through the
// arbitrated NoC - the result (127) can only be correct if it
// genuinely observed the OTHER core's write, not just "both cores ran
// without crashing" (that weaker claim is what c2, running completely
// independently on test1.hex, proves happens concurrently and
// correctly alongside the real cross-core traffic).
`timescale 1ns/1ps

`ifndef C0_INSTR_HEX
`define C0_INSTR_HEX "sw/shared_consumer.hex"
`endif
`ifndef C1_INSTR_HEX
`define C1_INSTR_HEX "sw/shared_producer.hex"
`endif
`ifndef C2_INSTR_HEX
`define C2_INSTR_HEX "sw/test1.hex"
`endif

module tb_soc;
    reg clk, reset;
    wire c0_halted, c1_halted, c2_halted, all_halted;
    wire [31:0] c0_tohost, c1_tohost, c2_tohost;

    integer expect_c0, expect_c1, expect_c2;
    integer max_cycles;
    integer cycle_count;
    integer any_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024), .DATA_MEM_WORDS(1024),
        .C0_INSTR_HEX(`C0_INSTR_HEX), .C1_INSTR_HEX(`C1_INSTR_HEX), .C2_INSTR_HEX(`C2_INSTR_HEX)
    ) dut (
        .clk(clk), .reset(reset),
        .c0_halted(c0_halted), .c0_tohost(c0_tohost),
        .c1_halted(c1_halted), .c1_tohost(c1_tohost),
        .c2_halted(c2_halted), .c2_tohost(c2_tohost),
        .all_halted(all_halted)
    );

    always #5 clk = ~clk;

    task check_core(input [31:0] got, input [31:0] expected, input [24*8-1:0] name);
        begin
            $display("%0s: tohost=%0d (0x%h)", name, got, got);
            if (got === expected) begin
                $display("PASS: %0s matches expected value %0d", name, expected);
            end else begin
                $display("FAIL: %0s tohost=%0d, expected=%0d", name, got, expected);
                any_fail = 1;
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("EXPECT_C0_TOHOST=%d", expect_c0)) expect_c0 = 127;
        if (!$value$plusargs("EXPECT_C1_TOHOST=%d", expect_c1)) expect_c1 = 77;
        if (!$value$plusargs("EXPECT_C2_TOHOST=%d", expect_c2)) expect_c2 = 200;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 150;

        clk = 0;
        reset = 1;
        cycle_count = 0;
        any_fail = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        while (!all_halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!all_halted) begin
            $display("FAIL: not all 3 cores halted within %0d cycles (c0=%b c1=%b c2=%b)",
                      max_cycles, c0_halted, c1_halted, c2_halted);
            any_fail = 1;
        end else begin
            $display("All 3 cores halted after %0d cycles.", cycle_count);
            check_core(c0_tohost, expect_c0, "c0-core (consumer)");
            check_core(c1_tohost, expect_c1, "c1-core (producer)");
            check_core(c2_tohost, expect_c2, "c2-core (indep)");
            if (!any_fail) $display("PASS: cross-core communication verified (c0 read c1's write)");
        end

        $finish;
    end
endmodule
