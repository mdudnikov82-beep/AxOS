// AxISA virtual memory (see rtl/mmu.v and docs/ISA.md's "Virtual
// memory" section, and sw/mmu_test.axasm for the full program layout).
// The ONE test in this project that turns MMU_ENABLE on - every other
// testbench leaves it at its default-off/bypass value, proving zero
// regression to the existing suite.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/mmu_test.hex"
`endif

module tb_mmu;
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

    cpu_core #(
        .INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX),
        .MMU_ENABLE(1)
    ) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .irq_in(1'b0),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(1'b0), .bus_read_data(32'b0),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(8'b0), .uart_rx_ready_in(1'b0), .uart_rx_ack()
    );

    always #5 clk = ~clk;

    task check(input [31:0] got, input [31:0] expected, input [64*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL: %0s got=%0d expected=%0d", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", name, got);
            end
        end
    endtask

    initial begin
        errors = 0;
        max_cycles = 200; // real translation costs a few extra stall cycles per miss - more headroom than the non-MMU trap tests

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
            check(tohost_value, 32'd342, "tohost (n3+n3 after a translated round trip AND surviving a real page fault)");
            check(dut.n_bank.regs[3], 32'd171, "n3 (0xAB loaded back through translation - PROVES the LOAD really re-read the translated physical address, not just echoed the STORE's own value)");
            // The real proof translation isn't a coincidental no-op:
            // vaddr 0x0100 (page index 0) was mapped to PPN=1 - the
            // value must have actually landed at PHYSICAL 0x1100
            // (word index 0x440), NOT at word index 0x40 (where a
            // broken/identity "translation" would have put it).
            check(dut.dmem.mem[11'h440], 32'd171, "dmem.mem[0x440] (physical 0x1100 - the TRANSLATED address actually written, confirms real non-identity translation)");
            check(dut.n_bank.regs[5], 32'd4, "n5 (CAUSE_PAGE_FAULT, expect 4 - the deliberately-unmapped index-3 LOAD)");
            check(dut.mode_r, 1'b0, "mode_r (final restored mode, expect USER - RFT correctly restored it after the page-fault round trip)");
        end

        if (errors == 0) $display("ALL AXISA MMU TESTS PASSED");
        else $display("%0d AXISA MMU TEST(S) FAILED", errors);
        $finish;
    end
endmodule
