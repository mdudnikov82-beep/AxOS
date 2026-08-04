// Pipelined-core counterpart of tb_cpu_mmu_store_miss.v - same
// corruption regression, same program, must match the E-core exactly.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/mmu_store_miss_test.hex"
`endif

module tb_cpu_pipelined_mmu_store_miss;
    localparam DMB = 16384;
    localparam PT_BASE = 32'h0000_1000;

    reg clk, reset;
    wire halted, page_fault;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;
    reg [31:0] phys0_before, phys0_after;

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
        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 32'hABCDE000;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 100;

        clk = 0; reset = 1; cycle_count = 0;
        @(posedge clk);

        poke32(PT_BASE + 0, {20'h0_0002, 9'h0, 3'b011});
        poke32(32'h0000_2000 + 0, {20'h0_0003, 9'h0, 3'b111});
        poke32(32'h0000_0000, 32'd9999);

        phys0_before = {dut.dmem.mem[3], dut.dmem.mem[2], dut.dmem.mem[1], dut.dmem.mem[0]};

        @(posedge clk);
        reset = 0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        phys0_after = {dut.dmem.mem[3], dut.dmem.mem[2], dut.dmem.mem[1], dut.dmem.mem[0]};

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles", max_cycles);
        end else if (page_fault) begin
            $display("FAIL: unexpected page_fault");
        end else if (phys0_after !== phys0_before) begin
            $display("FAIL: physical page 0 corrupted by the store's TLB-miss handling (before=0x%h after=0x%h)", phys0_before, phys0_after);
        end else if (tohost_value !== expect_tohost) begin
            $display("FAIL: tohost=0x%h, expected=0x%h", tohost_value, expect_tohost);
        end else begin
            $display("Halted after %0d cycles. tohost=0x%h, physical page 0 unchanged.", cycle_count, tohost_value);
            $display("PASS: tohost matches expected value 0x%h", expect_tohost);
        end

        $finish;
    end
endmodule
