// Cross-core communication test: e0-core (sw/shared_producer.hex)
// writes a payload + ready flag into shared memory; p0-core
// (sw/shared_consumer.hex) polls for it, reads the payload, and
// computes a result that can only be correct (127) if it genuinely
// observed the OTHER core's write through the arbitrated shared_bus -
// not just "cores ran without crashing" like tb_soc.v proves. p1/p2/e1/
// e2 run independent private-memory-only programs alongside, proving
// the cross-core handshake still works correctly on the generalized
// N-way bus with FOUR other cores concurrently contending for it too
// (scaled up from 2P+2E's original two), not just as a 2-core
// degenerate case.
`timescale 1ns/1ps

`ifndef P0_INSTR_HEX
`define P0_INSTR_HEX "sw/shared_consumer.hex"
`endif
`ifndef E0_INSTR_HEX
`define E0_INSTR_HEX "sw/shared_producer.hex"
`endif
`ifndef P1_INSTR_HEX
`define P1_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E1_INSTR_HEX
`define E1_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P2_INSTR_HEX
`define P2_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E2_INSTR_HEX
`define E2_INSTR_HEX "sw/test1.hex"
`endif

module tb_shared_soc;
    reg clk;
    reg reset;
    wire p0_halted, p1_halted, p2_halted, e0_halted, e1_halted, e2_halted, all_halted;
    wire [31:0] p0_tohost, p1_tohost, p2_tohost, e0_tohost, e1_tohost, e2_tohost;

    integer expect_p0, expect_e0, expect_p1, expect_e1, expect_p2, expect_e2;
    integer max_cycles;
    integer cycle_count;
    integer trace_enabled;
    integer any_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024),
        .P0_INSTR_HEX(`P0_INSTR_HEX), .P1_INSTR_HEX(`P1_INSTR_HEX), .P2_INSTR_HEX(`P2_INSTR_HEX),
        .E0_INSTR_HEX(`E0_INSTR_HEX), .E1_INSTR_HEX(`E1_INSTR_HEX), .E2_INSTR_HEX(`E2_INSTR_HEX),
        .DATA_MEM_BYTES(8192)
    ) dut (
        .clk(clk), .reset(reset),
        .p0_halted(p0_halted), .p0_tohost(p0_tohost),
        .p1_halted(p1_halted), .p1_tohost(p1_tohost),
        .p2_halted(p2_halted), .p2_tohost(p2_tohost),
        .e0_halted(e0_halted), .e0_tohost(e0_tohost),
        .e1_halted(e1_halted), .e1_tohost(e1_tohost),
        .e2_halted(e2_halted), .e2_tohost(e2_tohost),
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
        $dumpfile("tb_shared_soc.vcd");
        $dumpvars(0, tb_shared_soc);

        if (!$value$plusargs("EXPECT_P0_TOHOST=%d", expect_p0)) expect_p0 = 127;
        if (!$value$plusargs("EXPECT_E0_TOHOST=%d", expect_e0)) expect_e0 = 77;
        if (!$value$plusargs("EXPECT_P1_TOHOST=%d", expect_p1)) expect_p1 = 42;
        if (!$value$plusargs("EXPECT_E1_TOHOST=%d", expect_e1)) expect_e1 = 42;
        if (!$value$plusargs("EXPECT_P2_TOHOST=%d", expect_p2)) expect_p2 = 42;
        if (!$value$plusargs("EXPECT_E2_TOHOST=%d", expect_e2)) expect_e2 = 42;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 150;
        trace_enabled = $test$plusargs("TRACE");

        clk = 0;
        reset = 1;
        cycle_count = 0;
        any_fail = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        if (trace_enabled) begin
            $display("cyc | p0: pc       stall | e0: pc       stall | p0_req p0_gr e0_req e0_gr");
            $display("----+---------------------+---------------------+---------------------------");
        end

        while (!all_halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (trace_enabled) begin
                $display("%3d | p0: %h  %b     | e0: %h  %b     |    %b      %b      %b      %b",
                         cycle_count, dut.p0_core.pc, dut.p0_core.mem_stall,
                         dut.e0_core.pc, dut.e0_core.mem_stall,
                         dut.p0_bus_req, dut.p0_bus_grant, dut.e0_bus_req, dut.e0_bus_grant);
            end
        end

        if (!all_halted) begin
            $display("FAIL: not all 6 cores halted within %0d cycles (p0=%b p1=%b p2=%b e0=%b e1=%b e2=%b)",
                      max_cycles, p0_halted, p1_halted, p2_halted, e0_halted, e1_halted, e2_halted);
        end else begin
            $display("All 6 cores halted after %0d cycles.", cycle_count);
            check_core(p0_tohost, expect_p0, "p0-core (consumer)");
            check_core(e0_tohost, expect_e0, "e0-core (producer)");
            check_core(p1_tohost, expect_p1, "p1-core (independent)");
            check_core(e1_tohost, expect_e1, "e1-core (independent)");
            check_core(p2_tohost, expect_p2, "p2-core (independent)");
            check_core(e2_tohost, expect_e2, "e2-core (independent)");
            if (!any_fail) $display("PASS: cross-core communication verified (p0 read e0's write)");
        end

        $finish;
    end
endmodule
