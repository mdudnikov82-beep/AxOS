// AxISA multi-core test: 8 real cpu_core.v instances in the 3x3 mesh
// (rtl/soc_top.v) at once - scaled up mechanically from the first 2x2/
// 3-core mesh (same architecture, no fresh design review). c0
// (shared_consumer.hex) busy-waits then reads c1's (shared_producer.hex)
// payload through the arbitrated NoC - the result (127) can only be
// correct if it genuinely observed the OTHER core's write, not just
// "all cores ran without crashing" (that weaker claim is what c2-c7,
// running completely independently on test1.hex, prove happens
// concurrently and correctly alongside the real cross-core traffic - now
// with 6 of them contending for the network instead of 1).
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
`ifndef C3_INSTR_HEX
`define C3_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C4_INSTR_HEX
`define C4_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C5_INSTR_HEX
`define C5_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C6_INSTR_HEX
`define C6_INSTR_HEX "sw/test1.hex"
`endif
`ifndef C7_INSTR_HEX
`define C7_INSTR_HEX "sw/test1.hex"
`endif

module tb_soc;
    reg clk, reset;
    wire c0_halted, c1_halted, c2_halted, c3_halted, c4_halted, c5_halted, c6_halted, c7_halted, all_halted;
    wire [31:0] c0_tohost, c1_tohost, c2_tohost, c3_tohost, c4_tohost, c5_tohost, c6_tohost, c7_tohost;

    integer expect_c0, expect_c1, expect_c2, expect_c3, expect_c4, expect_c5, expect_c6, expect_c7;
    integer max_cycles;
    integer cycle_count;
    integer any_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024), .DATA_MEM_WORDS(1024),
        .C0_INSTR_HEX(`C0_INSTR_HEX), .C1_INSTR_HEX(`C1_INSTR_HEX), .C2_INSTR_HEX(`C2_INSTR_HEX), .C3_INSTR_HEX(`C3_INSTR_HEX), .C4_INSTR_HEX(`C4_INSTR_HEX), .C5_INSTR_HEX(`C5_INSTR_HEX), .C6_INSTR_HEX(`C6_INSTR_HEX), .C7_INSTR_HEX(`C7_INSTR_HEX)
    ) dut (
        .clk(clk), .reset(reset),
        .c0_halted(c0_halted), .c0_tohost(c0_tohost),
        .c1_halted(c1_halted), .c1_tohost(c1_tohost),
        .c2_halted(c2_halted), .c2_tohost(c2_tohost),
        .c3_halted(c3_halted), .c3_tohost(c3_tohost),
        .c4_halted(c4_halted), .c4_tohost(c4_tohost),
        .c5_halted(c5_halted), .c5_tohost(c5_tohost),
        .c6_halted(c6_halted), .c6_tohost(c6_tohost),
        .c7_halted(c7_halted), .c7_tohost(c7_tohost),
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
        if (!$value$plusargs("EXPECT_C3_TOHOST=%d", expect_c3)) expect_c3 = 200;
        if (!$value$plusargs("EXPECT_C4_TOHOST=%d", expect_c4)) expect_c4 = 200;
        if (!$value$plusargs("EXPECT_C5_TOHOST=%d", expect_c5)) expect_c5 = 200;
        if (!$value$plusargs("EXPECT_C6_TOHOST=%d", expect_c6)) expect_c6 = 200;
        if (!$value$plusargs("EXPECT_C7_TOHOST=%d", expect_c7)) expect_c7 = 200;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 200;

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
            $display("FAIL: not all 8 cores halted within %0d cycles (c0=%b c1=%b c2=%b c3=%b c4=%b c5=%b c6=%b c7=%b)",
                      max_cycles, c0_halted, c1_halted, c2_halted, c3_halted, c4_halted, c5_halted, c6_halted, c7_halted);
            any_fail = 1;
        end else begin
            $display("All 8 cores halted after %0d cycles.", cycle_count);
            check_core(c0_tohost, expect_c0, "c0-core (consumer)");
            check_core(c1_tohost, expect_c1, "c1-core (producer)");
            check_core(c2_tohost, expect_c2, "c2-core (indep)");
            check_core(c3_tohost, expect_c3, "c3-core (indep)");
            check_core(c4_tohost, expect_c4, "c4-core (indep)");
            check_core(c5_tohost, expect_c5, "c5-core (indep)");
            check_core(c6_tohost, expect_c6, "c6-core (indep)");
            check_core(c7_tohost, expect_c7, "c7-core (indep)");
            if (!any_fail) $display("PASS: cross-core communication verified (c0 read c1's write)");
        end

        $finish;
    end
endmodule
