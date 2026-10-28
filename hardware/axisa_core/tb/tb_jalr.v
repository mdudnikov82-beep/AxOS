// AxISA v2.1 step 2 (see sw/jalr_test.axasm): JALR returns to two
// different call sites, an indirect call through a function pointer,
// low-bit clearing, and the link value.
`timescale 1ns/1ps
`ifndef INSTR_HEX
`define INSTR_HEX "sw/jalr_test.hex"
`endif

module tb_jalr;
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

    task check(input [31:0] got, input [31:0] expected, input [48*8-1:0] name);
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
            check(tohost_value, 32'd45, "tohost: 15+21+6+3 from 4 calls");
            check(dut.n_bank.regs[5], 32'd0, "n5: link right AND pc re-aligned");
            check(dut.n_bank.regs[2], 32'd45, "n2 (the 999 writes were skipped)");
        end

        if (errors == 0) $display("ALL AXISA JALR TESTS PASSED");
        else $display("%0d AXISA JALR TEST(S) FAILED", errors);
        $finish;
    end
endmodule
