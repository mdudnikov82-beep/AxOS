// Real TLB-invalidation test for cpu_core.v + mmu.v (see
// sw/asm_sfence_test.py for the exact program and rationale). The
// program legitimately self-modifies its own page table via a real,
// translated store (through an identity-mapped alias of the L0 table's
// own physical page), then executes SFENCE.VMA, then re-reads the same
// VA - a passing test proves the stale TLB entry was genuinely
// discarded, not merely that the instruction decodes.
//
// EXPECT_TOHOST is NOT hardcoded here - it's driven by which hex variant
// is loaded (sfence_test.hex expects SENTINEL_B=2222 - invalidation
// worked; sfence_test_neg.hex, with the SFENCE.VMA instruction physically
// removed, expects the STALE SENTINEL_A=1111 - the negative control that
// proves this test genuinely discriminates, not a coincidence).
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/sfence_test.hex"
`endif

module tb_cpu_sfence;
    localparam DMB = 32768;
    localparam PT_BASE = 32'h0000_1000;

    reg clk, reset;
    wire halted, page_fault;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;

    cpu_core #(
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
        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 2222;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 100;

        clk = 0; reset = 1; cycle_count = 0;
        @(posedge clk);

        poke32(PT_BASE + 0*4, {20'h0_0002, 9'h0, 3'b011});     // L1[0] -> L0 table @0x2000
        poke32(32'h0000_2000 + 0*4, {20'h0_0003, 9'h0, 3'b111}); // L0[0] -> physical 0x3000, RW
        poke32(32'h0000_2000 + 5*4, {20'h0_0002, 9'h0, 3'b111}); // L0[5] (VA 0x5000) -> physical 0x2000, RW (identity alias, kept clear of the shared-bus window)
        poke32(32'h0000_3000, 32'd1111); // SENTINEL_A
        poke32(32'h0000_4000, 32'd2222); // SENTINEL_B

        @(posedge clk);
        reset = 0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles", max_cycles);
        end else if (page_fault) begin
            $display("FAIL: unexpected page_fault");
        end else begin
            $display("Halted after %0d cycles. tohost=%0d", cycle_count, tohost_value);
            if (tohost_value === expect_tohost) begin
                $display("PASS: tohost matches expected value %0d", expect_tohost);
            end else begin
                $display("FAIL: tohost=%0d, expected=%0d", tohost_value, expect_tohost);
            end
        end

        $finish;
    end
endmodule
