// AxISA v2.1 step 2 (see sw/hmalloc_test.axasm and sw/lib/hmalloc.axasm):
// the hardened malloc's results, its trap count, and heap invariants
// read straight out of data memory and the MTE tag memory - every slot
// handed out exactly once, every pointer's tag matching its granule,
// no tag 0, adjacent slots never sharing a tag, and a non-sequential
// (randomized) allocation order.
`timescale 1ns/1ps
`ifndef INSTR_HEX
`define INSTR_HEX "sw/hmalloc_test.hex"
`endif

module tb_hmalloc;
    reg clk, reset;
    integer errors;
    integer max_cycles;
    integer cycle_count;

    wire halted;
    wire [31:0] tohost_value;
    wire        bus_req, bus_mem_write, bus_mem_unsigned, bus_grant;
    wire [31:0] bus_addr, bus_write_data, bus_read_data;
    wire [1:0]  bus_mem_size;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .irq_in(1'b0),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(1'b0), .bus_read_data(32'b0),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(8'b0), .uart_rx_ready_in(1'b0), .uart_rx_ack()
    );

    always #5 clk = ~clk;

    integer uart_count, k, adjacent_same, stg_heap, stg_bad, stg_alloc, stg_free;
    reg [31:0] gi;
    reg [4:0] last_alloc [0:15]; // slot's previous ALLOCATION tag (bit 4 = valid)
    reg [4:0] last_any   [0:15]; // slot's current tag before this STG (bit 4 = valid)
    initial begin
        stg_heap = 0; stg_bad = 0; stg_alloc = 0; stg_free = 0;
        for (k = 0; k < 16; k = k + 1) begin last_alloc[k] = 5'd0; last_any[k] = 5'd0; end
    end
    // STG monitor: every retag inside the heap (granules 0x80..0x8F)
    // must pick a nonzero tag different from both neighbours' current tags
    always @(posedge clk) if (!reset && dut.stg_commit) begin
        gi = dut.mtag_gidx;
        if (gi >= 32'h80 && gi <= 32'h8F) begin
            stg_heap = stg_heap + 1;
            if (dut.mtag_ptr_tag == 4'd0 || dut.mtag_ptr_tag == dut.g_mte.tag_mem[gi - 1] ||
                dut.mtag_ptr_tag == dut.g_mte.tag_mem[gi + 1]) begin
                stg_bad = stg_bad + 1;
                $display("FAIL: STG granule %h tag %0d next to %0d / %0d", gi, dut.mtag_ptr_tag,
                         dut.g_mte.tag_mem[gi - 1], dut.g_mte.tag_mem[gi + 1]);
            end
            // malloc's STG runs after it sets the bitmap bit, free's after it clears it
            if (dut.dmem.mem[32'h700 >> 2][gi - 32'h80]) begin
                stg_alloc = stg_alloc + 1;
                if ((last_alloc[gi - 32'h80][4] && dut.mtag_ptr_tag == last_alloc[gi - 32'h80][3:0]) ||
                    (last_any[gi - 32'h80][4]   && dut.mtag_ptr_tag == last_any[gi - 32'h80][3:0])) begin
                    stg_bad = stg_bad + 1;
                    $display("FAIL: malloc reused tag %0d on slot %0d", dut.mtag_ptr_tag, gi - 32'h80);
                end
                last_alloc[gi - 32'h80] = {1'b1, dut.mtag_ptr_tag};
            end else begin
                stg_free = stg_free + 1;
                if (last_alloc[gi - 32'h80][4] && dut.mtag_ptr_tag == last_alloc[gi - 32'h80][3:0]) begin
                    stg_bad = stg_bad + 1;
                    $display("FAIL: free kept the freed pointer's tag %0d on slot %0d", dut.mtag_ptr_tag, gi - 32'h80);
                end
            end
            last_any[gi - 32'h80] = {1'b1, dut.mtag_ptr_tag};
        end
    end
    reg [31:0] p;
    reg [3:0] slot;
    reg [15:0] seen;
    reg sequential;
    reg [7:0] uart_byte;
    initial begin uart_count = 0; uart_byte = 8'h00; end
    always @(posedge clk) if (!reset && uart_tx_valid) begin uart_byte = uart_tx_data; uart_count = uart_count + 1; end

    function [31:0] w; input [31:0] addr; w = dut.dmem.mem[addr >> 2]; endfunction

    task check(input [31:0] got, input [31:0] expected, input [56*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL: %0s got=%0d (0x%h) expected=%0d (0x%h)", name, got, got, expected, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d (0x%h)", name, got, got);
            end
        end
    endtask

    initial begin
        errors = 0;
        max_cycles = 150000;

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
            check(tohost_value, 32'd15, "tohost: 15 more blocks fit next to p2");
            check(w(32'h608), 32'd0, "malloc(17) = 0");
            check(w(32'h60C), 32'd123, "p1 read back what was written");
            check(w(32'h610), 32'd0, "free(p1) = 0");
            check(w(32'h614), 32'd55, "use-after-free load wrote nothing");
            check(w(32'h618), 32'd2, "double free = 2");
            check(w(32'h61C), 32'd1, "free(outside heap) = 1");
            check(w(32'h620), 32'd1, "free(middle of a block) = 1");
            check(w(32'h624), 32'd0, "freed block was zeroed");
            check(w(32'h628), 32'd2, "free(never-allocated slot) = 2");
            check(w(32'h634), 32'd1, "free(one past the heap) = 1");
            check(w(32'h638), 32'd2, "free(stale p1 after its slot was reused) = 2");
            check(stg_alloc, 217, "malloc STGs: 17 + 200 churn");
            check(stg_free, 201, "free STGs: 1 + 200 churn");
            check(stg_bad, 0, "every heap STG obeys the tag rules");
            check(w(32'h6F8), 32'd522, "2 traps, both TAG_FAULT (2*256 + 2*5)");
            check(w(32'h700), 32'h0000FFFF, "bitmap: all 16 slots in use");
            check(w(32'h600) >> 28 != 0 && (w(32'h600) & 32'h0FFFFF0F) == 32'h800, 1, "p1: tagged, a slot start");
            check(w(32'h604) >> 28 != 0 && (w(32'h604) & 32'h0FFFFF0F) == 32'h800, 1, "p2: tagged, a slot start");
            check(((w(32'h600) >> 4) & 15) != ((w(32'h604) >> 4) & 15), 1, "p1 and p2 are different slots");

            // live pointers: p2 + the 15 from the loop
            seen = 0; sequential = 1;
            for (k = 0; k < 16; k = k + 1) begin
                p = (k == 15) ? w(32'h604) : w(32'h640 + 4 * k);
                slot = (p >> 4) & 15;
                if ((p & 32'h0FFFFF0F) != 32'h800) begin $display("FAIL: pointer %0d = %h not a slot", k, p); errors = errors + 1; end
                if (p >> 28 == 0) begin $display("FAIL: pointer %0d untagged", k); errors = errors + 1; end
                if ((p >> 28) != dut.g_mte.tag_mem[(p & 32'h0FFFFFFF) >> 4]) begin
                    $display("FAIL: pointer %0d tag %0d != granule tag %0d", k, p >> 28, dut.g_mte.tag_mem[(p & 32'h0FFFFFFF) >> 4]);
                    errors = errors + 1;
                end
                if (seen[slot]) begin $display("FAIL: slot %0d handed out twice", slot); errors = errors + 1; end
                seen[slot] = 1'b1;
                if (k > 0 && k < 15 && slot <= (((w(32'h640 + 4 * (k - 1))) >> 4) & 15)) sequential = 0;
            end
            check(seen, 16'hFFFF, "every slot handed out exactly once");
            check(sequential, 0, "allocation order is randomized, not ascending");
            adjacent_same = 0;
            for (k = 0; k < 15; k = k + 1)
                if (dut.g_mte.tag_mem[(32'h800 >> 4) + k] == dut.g_mte.tag_mem[(32'h800 >> 4) + k + 1]) adjacent_same = adjacent_same + 1;
            check(adjacent_same, 0, "no two neighbouring slots share a tag");
        end

        if (errors == 0) $display("ALL AXISA HMALLOC TESTS PASSED");
        else $display("%0d AXISA HMALLOC TEST(S) FAILED", errors);
        $finish;
    end
endmodule
