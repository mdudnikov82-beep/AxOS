// Adversarial timing test for SFENCE.VMA's tlb_flush pulse on the
// pipelined P-core - the exact scenario a design review flagged before
// any RTL was written (see cpu_core_pipelined.v's tlb_flush comment): a
// load that misses the TLB is immediately followed by SFENCE.VMA, close
// enough in program order that SFENCE reaches ID/EX and sits HELD there
// (via mmu_stall) for the entire multi-cycle walk, since IF/ID and ID/EX
// both freeze while EX/MEM is walking. A NAIVE design that fires
// tlb_flush from raw, un-edge-detected id_is_sfence (held true this
// whole time) would repeatedly wipe the walk's own freshly-filled TLB
// entry the instant S_FILL writes it, which keeps mmu_stall asserted,
// which keeps holding SFENCE, which keeps the flush held - a genuine
// self-sustaining livelock, not a one-off collision. The fix (a real
// one-shot pulse tied to the same "advancing into ID/EX for real this
// cycle" condition the register's own real-latch branch uses) must let
// this program complete normally and quickly.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/sfence_race_test.hex"
`endif

module tb_cpu_pipelined_sfence_race;
    localparam DMB = 20480; // must exceed physical 0x4000 (16384) - that landing exactly at DATA_MEM_BYTES's boundary correctly faults otherwise
    localparam PT_BASE = 32'h0000_1000;

    reg clk, reset;
    wire halted, page_fault;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX), .DATA_MEM_BYTES(DMB),
        .MMU_ENABLE(1), .MMU_TLB_ENTRIES(4), .PAGE_TABLE_BASE(PT_BASE)
    ) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value), .page_fault(page_fault),
        .bus_grant(1'b1), .bus_read_data(32'b0)
    );

    always #5 clk = ~clk;

    task poke32(input [31:0] addr, input [31:0] val);
        begin
            dut.dmem.mem[addr]   = val[7:0];
            dut.dmem.mem[addr+1] = val[15:8];
            dut.dmem.mem[addr+2] = val[23:16];
            dut.dmem.mem[addr+3] = val[31:24];
        end
    endtask

    initial begin
        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 4242;
        // Tight on purpose (mirrors tb_cpu_pipelined_mmu_race.v's own
        // bound) - a real one-shot flush finishes this tiny program in
        // well under 20 cycles; the naive held-pulse livelock never
        // halts at all within any reasonable bound.
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 40;

        clk = 0; reset = 1; cycle_count = 0;
        @(posedge clk);

        poke32(PT_BASE + 0*4, {20'h0_0003, 9'h0, 3'b011});     // L1[0] -> L0 table @0x3000
        poke32(32'h0000_3000 + 0*4, {20'h0_0004, 9'h0, 3'b111}); // L0[0] -> physical 0x4000, RW
        poke32(32'h0000_4000, 32'd4242);

        @(posedge clk);
        reset = 0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles (SFENCE-held-during-walk livelock)", max_cycles);
        end else if (page_fault) begin
            $display("FAIL: unexpected page_fault");
        end else begin
            $display("Halted after %0d cycles. tohost=%0d", cycle_count, tohost_value);
            if (tohost_value === expect_tohost) begin
                $display("PASS: tohost matches expected value %0d (SFENCE held during an older walk did not livelock)", expect_tohost);
            end else begin
                $display("FAIL: tohost=%0d, expected=%0d", tohost_value, expect_tohost);
            end
        end

        $finish;
    end
endmodule
