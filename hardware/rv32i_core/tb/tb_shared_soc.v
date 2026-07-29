// Cross-core communication test: E-core (sw/shared_producer.hex)
// writes a payload + ready flag into shared memory; P-core
// (sw/shared_consumer.hex) polls for it, reads the payload, and
// computes a result that can only be correct (127) if it genuinely
// observed the OTHER core's write through the arbitrated shared_bus -
// not just "both cores ran without crashing" like tb_soc.v proves.
`timescale 1ns/1ps

`ifndef P_INSTR_HEX
`define P_INSTR_HEX "sw/shared_consumer.hex"
`endif
`ifndef E_INSTR_HEX
`define E_INSTR_HEX "sw/shared_producer.hex"
`endif

module tb_shared_soc;
    reg clk;
    reg reset;
    wire p_halted, e_halted, both_halted;
    wire [31:0] p_tohost, e_tohost;

    integer expect_p_tohost, expect_e_tohost;
    integer max_cycles;
    integer cycle_count;
    integer trace_enabled;
    integer p_fail, e_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024),
        .P_INSTR_HEX(`P_INSTR_HEX),
        .E_INSTR_HEX(`E_INSTR_HEX),
        .DATA_MEM_BYTES(8192)
    ) dut (
        .clk(clk), .reset(reset),
        .p_halted(p_halted), .p_tohost(p_tohost),
        .e_halted(e_halted), .e_tohost(e_tohost),
        .both_halted(both_halted)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_shared_soc.vcd");
        $dumpvars(0, tb_shared_soc);

        if (!$value$plusargs("EXPECT_P_TOHOST=%d", expect_p_tohost)) expect_p_tohost = 127;
        if (!$value$plusargs("EXPECT_E_TOHOST=%d", expect_e_tohost)) expect_e_tohost = 77;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 150;
        trace_enabled = $test$plusargs("TRACE");

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        if (trace_enabled) begin
            $display("cyc | P: pc       stall | E: pc       stall | p_req p_gr e_req e_gr");
            $display("----+---------------------+---------------------+---------------------");
        end

        while (!both_halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (trace_enabled) begin
                $display("%3d | P: %h  %b     | E: %h  %b     |   %b     %b    %b     %b",
                         cycle_count, dut.p_core.pc, dut.p_core.mem_stall,
                         dut.e_core.pc, dut.e_core.mem_stall,
                         dut.p_bus_req, dut.p_bus_grant, dut.e_bus_req, dut.e_bus_grant);
            end
        end

        if (!both_halted) begin
            $display("FAIL: not both cores halted within %0d cycles (P halted=%b, E halted=%b)",
                      max_cycles, p_halted, e_halted);
        end else begin
            $display("Both cores halted after %0d cycles.", cycle_count);

            p_fail = 0;
            $display("P-core (consumer): tohost=%0d (0x%h)", p_tohost, p_tohost);
            if (p_tohost === expect_p_tohost) begin
                $display("PASS: P-core tohost matches expected value %0d", expect_p_tohost);
            end else begin
                $display("FAIL: P-core tohost=%0d, expected=%0d", p_tohost, expect_p_tohost);
                p_fail = 1;
            end

            e_fail = 0;
            $display("E-core (producer): tohost=%0d (0x%h)", e_tohost, e_tohost);
            if (e_tohost === expect_e_tohost) begin
                $display("PASS: E-core tohost matches expected value %0d", expect_e_tohost);
            end else begin
                $display("FAIL: E-core tohost=%0d, expected=%0d", e_tohost, expect_e_tohost);
                e_fail = 1;
            end

            if (!p_fail && !e_fail) $display("PASS: cross-core communication verified (P read E's write)");
        end

        $finish;
    end
endmodule
