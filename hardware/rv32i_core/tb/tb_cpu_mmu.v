// Real virtual-memory integration test for cpu_core.v + mmu.v (see
// sw/asm_mmu_test.py for the exact program and rationale). Builds a
// genuine 2-level page table directly in the core's own data_mem.v
// instance (hierarchical poke, same technique tb_mmu.v used against
// its own fake memory model - here against the REAL data_mem.v the
// core's LSU and the MMU's walker both actually share), proving the
// full integration (walker/data_mem port-sharing, mem_write forced off
// during a walk, mmu_stall correctly freezing the core) works, not
// just the MMU module in isolation.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/mmu_test.hex"
`endif

module tb_cpu_mmu;
    localparam DMB = 16384;
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
        .bus_req(), .bus_addr(), .bus_write_data(), .bus_mem_write(), .bus_mem_size(), .bus_mem_unsigned(),
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
        $dumpfile("tb_cpu_mmu.vcd");
        $dumpvars(0, tb_cpu_mmu);

        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 1234;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 100;

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk);

        // Page table: L1 at PT_BASE=0x1000 -> L0 table at PPN=2 (0x2000)
        // -> data page PPN=3 (0x3000), R=1,W=1. VA 0 (VPN1=0,VPN0=0)
        // therefore translates to physical 0x3000.
        poke32(PT_BASE + 0, {20'h0_0002, 9'h0, 3'b011}); // L1[0]: V=1, points at 0x2000
        poke32(32'h0000_2000 + 0, {20'h0_0003, 9'h0, 3'b111}); // L0[0]: V=1,R=1,W=1, points at 0x3000
        poke32(32'h0000_3000, 32'd1234); // the REAL data, only reachable via translation
        poke32(32'h0000_0000, 32'd9999); // sentinel at the UNTRANSLATED physical address - if the
                                          // test somehow reads this instead, translation was bypassed

        @(posedge clk);
        reset = 0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles", max_cycles);
        end else if (page_fault) begin
            $display("FAIL: unexpected page_fault - translation should have succeeded cleanly");
        end else begin
            $display("Halted after %0d cycles. tohost=%0d (0x%h)", cycle_count, tohost_value, tohost_value);
            if (tohost_value === expect_tohost) begin
                $display("PASS: tohost matches expected value %0d (real translation happened - the untranslated-address sentinel 9999 was NOT read)", expect_tohost);
            end else begin
                $display("FAIL: tohost=%0d, expected=%0d", tohost_value, expect_tohost);
            end
        end

        $finish;
    end
endmodule
