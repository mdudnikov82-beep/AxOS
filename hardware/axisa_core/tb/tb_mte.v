// AxISA v2.1 step 1 (see sw/mte_test.axasm and docs/ISA.md's "Memory
// tagging"): tagged/untagged accesses, overflow and use-after-free
// caught by TAG_FAULT with no memory or register write, LDG, the
// untagged UART window, and the ILLEGAL/PRIV cases.
`timescale 1ns/1ps
`ifndef INSTR_HEX
`define INSTR_HEX "sw/mte_test.hex"
`endif

module tb_mte;
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

    integer uart_count;
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
        max_cycles = 200;

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
            check(tohost_value, 32'd2071, "tohost: 8 traps, causes sum 4*5+3 = 23");
            check(w(32'h500) & 32'h0FFFFFFF, 32'h400, "IRG kept the address bits");
            check(w(32'h500) >> 28 != 0, 1, "IRG tag is nonzero");
            check(w(32'h400), 32'd222, "[0x400] tagged store landed");
            check(w(32'h504), 32'd222, "tagged load read it back");
            check(w(32'h404), 32'd111, "[0x404] untagged store was blocked");
            check(dut.n_bank.regs[4], 32'd55, "n4: both faulting loads wrote nothing");
            check(w(32'h40C), 32'd333, "[0x40C] last word of the granule ok");
            check(w(32'h410), 32'd111, "[0x410] overflow store was blocked");
            check(w(32'h508), w(32'h500), "LDG rebuilt the same tagged pointer");
            check(w(32'h50C), 32'd222, "retagged pointer works after free");
            check(dut.g_mte.tag_mem[32'h400 >> 4], ((w(32'h500) >> 28) + 1) & 4'hF, "granule tag = t+1 after retag");
            check(dut.g_mte.tag_mem[32'h410 >> 4], 4'd0, "next granule still untagged");
            check(uart_count, 1, "tagged pointer to UART sent one byte");
            check(uart_byte, 8'hDE, "UART byte = 222");
            check(dut.n_bank.regs[5], 32'd222, "n5: illegal LDG wrote nothing");
            check(w(32'h510) & 32'h0FFFFFFF, 32'h400, "user-mode IRG kept the address");
            check(w(32'h510) >> 28 != 0, 1, "user-mode IRG tag is nonzero");
        end

        if (errors == 0) $display("ALL AXISA MTE TESTS PASSED");
        else $display("%0d AXISA MTE TEST(S) FAILED", errors);
        $finish;
    end
endmodule
