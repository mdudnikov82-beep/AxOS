// Standalone mmu.v testbench - a behavioral fake memory model stands in
// for data_mem.v (this test is about the MMU's own translation/fault/
// TLB logic in isolation, not the real port-sharing wiring, which is
// exercised instead by the full cpu_core.v/cpu_core_pipelined.v
// integration tests). Builds real page tables byte-by-byte in the fake
// memory and drives real virtual addresses through the DUT.
`timescale 1ns/1ps

module tb_mmu;
    localparam DMB = 16384;
    localparam PT_BASE = 32'h0000_0000;

    reg clk, reset;
    integer errors;

    reg  [31:0] vaddr;
    reg         is_access, is_write;
    reg  [31:0] page_table_base;
    wire [31:0] paddr;
    wire        mmu_stall, page_fault;
    wire [31:0] fault_vaddr;
    wire        walk_active;
    wire [31:0] walk_addr;
    reg  [31:0] walk_read_data;

    mmu #(.MMU_ENABLE(1), .TLB_ENTRIES(4), .DATA_MEM_BYTES(DMB)) dut (
        .clk(clk), .reset(reset),
        .vaddr(vaddr), .is_access(is_access), .is_write(is_write),
        .page_table_base(page_table_base),
        .paddr(paddr), .mmu_stall(mmu_stall), .page_fault(page_fault), .fault_vaddr(fault_vaddr),
        .walk_active(walk_active), .walk_addr(walk_addr), .walk_read_data(walk_read_data)
    );

    // Fake byte-addressable memory (behavioral, word-aligned reads only
    // - all the walker ever does).
    reg [7:0] mem [0:DMB-1];
    always @(*) begin
        if (walk_active)
            walk_read_data = {mem[walk_addr+3], mem[walk_addr+2], mem[walk_addr+1], mem[walk_addr]};
        else
            walk_read_data = 32'hDEADBEEF; // shouldn't ever be consulted when !walk_active
    end

    task poke32(input [31:0] addr, input [31:0] val);
        begin
            mem[addr]   = val[7:0];
            mem[addr+1] = val[15:8];
            mem[addr+2] = val[23:16];
            mem[addr+3] = val[31:24];
        end
    endtask

    always #5 clk = ~clk;

    task check(input cond, input [200*8-1:0] msg);
        begin
            if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
            else $display("PASS: %0s", msg);
        end
    endtask

    // Drives one access and waits (up to `timeout` cycles) for either a
    // TLB hit (mmu_stall deasserts with is_access still held) or a
    // fault. The #1 before the first check matters - without it, an
    // immediate combinational re-evaluation of mmu_stall in response to
    // THIS SAME statement's blocking assignments can race the always@(*)
    // blocks that compute it, reading a stale (pre-update) value in the
    // same delta cycle - a real testbench bug caught live while first
    // writing this test (the very first access appeared to hit the TLB
    // instantly with garbage paddr, before any walk ever ran).
    task do_access(input [31:0] a, input wr, output got_fault, output [31:0] got_paddr);
        integer cyc;
        begin
            vaddr = a; is_write = wr; is_access = 1;
            #1;
            cyc = 0;
            while (mmu_stall && !page_fault && cyc < 100) begin
                @(posedge clk);
                #1;
                cyc = cyc + 1;
            end
            got_fault = page_fault;
            got_paddr = paddr;
            is_access = 0;
            @(posedge clk);
        end
    endtask

    reg gf;
    reg [31:0] gp;

    initial begin
        clk = 0; reset = 1; errors = 0;
        vaddr = 0; is_access = 0; is_write = 0;
        page_table_base = PT_BASE;

        // ---- Build a real 2-level page table ----
        // Layout: L1 table at 0x0000 (1 page), L0 table at 0x1000 (page 1),
        // data page for VA (VPN1=0,VPN0=0) at 0x2000 (page 2, RW),
        // a SEPARATE data page for (VPN1=0,VPN0=1) at 0x3000 (page 3, R-only),
        // (VPN1=0,VPN0=2) intentionally left with V=0 (never written - invalid),
        // (VPN1=1,...) intentionally left with V=0 at the L1 level.
        for (gp = 0; gp < DMB; gp = gp + 1) mem[gp] = 8'b0; // zero = V=0 everywhere by default

        poke32(PT_BASE + 0*4, {20'h0000_1, 9'h0, 3'b011}); // L1[0] -> L0 table at PPN=0x00001 (0x1000), V=1,R=1(unused for pointer)
        poke32(32'h0000_1000 + 0*4, {20'h0000_2, 9'h0, 3'b111}); // L0[0] -> data page PPN=0x00002 (0x2000), V=1,R=1,W=1
        poke32(32'h0000_1000 + 1*4, {20'h0000_3, 9'h0, 3'b011}); // L0[1] -> data page PPN=0x00003 (0x3000), V=1,R=1,W=0 (read-only)
        // L0[2] left at 0 (V=0) - intentional invalid leaf.
        // L1[1] left at 0 (V=0) - intentional invalid L1 entry, used below.

        mem[32'h0000_2000] = 8'hAB; // a recognizable byte at the RW data page

        @(posedge clk); @(posedge clk);
        reset = 0;
        @(posedge clk);

        // ---- Test 1: TLB miss -> real 2-level walk -> correct paddr ----
        do_access(32'h0000_0000, 0, gf, gp); // VPN1=0,VPN0=0, offset=0
        check(!gf, "clean read of a valid, RW-mapped page does not fault");
        check(gp == 32'h0000_2000, "walked translation produces the correct physical address");

        // ---- Test 2: same VA again - must now be a TLB HIT (no stall at all) ----
        vaddr = 32'h0000_0000; is_write = 0; is_access = 1;
        #1;
        check(!mmu_stall, "second access to the same VA hits the TLB combinationally (no walk needed)");
        is_access = 0; @(posedge clk);

        // ---- Test 3: read-only page - read succeeds, write faults ----
        do_access(32'h0000_1000, 0, gf, gp); // VPN0=1 -> offset 0x1000 in VA space (VPN1=0,VPN0=1,off=0)
        check(!gf, "read of a read-only page succeeds");
        check(gp == 32'h0000_3000, "read-only page translation is correct");

        do_access(32'h0000_1004, 1, gf, gp); // same page, different offset, but SAME VPN -> should still be a TLB hit, now checked for WRITE permission
        check(gf, "write to a read-only page (cached TLB hit) correctly faults");

        // ---- Test 4: invalid leaf PTE (V=0) ----
        do_access(32'h0000_2000, 0, gf, gp); // VPN0=2 -> VA offset 0x2000 (VPN1=0,VPN0=2)
        check(gf, "read through an invalid (V=0) leaf PTE faults");

        // ---- Test 5: invalid L1 PTE (V=0) ----
        do_access(32'h0040_0000, 0, gf, gp); // VPN1=1 (VA bit 22 set), L1[1] was left V=0
        check(gf, "read through an invalid (V=0) level-1 PTE faults");

        // ---- Test 6: PPN-range fault ----
        poke32(32'h0000_1000 + 3*4, {20'hFFFFF, 9'h0, 3'b011}); // L0[3] -> PPN way beyond DATA_MEM_BYTES
        do_access(32'h0000_3000, 0, gf, gp); // VPN0=3
        check(gf, "a translation landing beyond DATA_MEM_BYTES faults instead of reading out of range");

        if (errors == 0) $display("ALL MMU TESTS PASSED");
        else $display("%0d MMU TEST(S) FAILED", errors);
        $finish;
    end
endmodule
