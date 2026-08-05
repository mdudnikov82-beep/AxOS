// AxISA traps, step 1 of 3 (see sw/trap_illegal.axasm and docs/ISA.md's
// "Traps" section): illegal-instruction trap. Checks tohost AND
// several direct hierarchical peeks (R/G/B/N register survival, the
// captured CAUSE, the captured EPC) - not just a final tohost value,
// matching this project's own established rigor (tb_cpu.v/tb_cpu2.v/
// tb_uart_shell.v all do the same).
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/trap_illegal.hex"
`endif

module tb_trap_illegal;
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
        max_cycles = 100;

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
            check(tohost_value, 32'd88, "tohost (n1+n1 after successful trap round trip)");
            check(dut.r_bank.regs[1], 32'd11, "r1 (survived the trap round trip, direct peek)");
            check(dut.g_bank.regs[1], 32'd22, "g1 (survived the trap round trip, direct peek)");
            check(dut.b_bank.regs[1], 32'd33, "b1 (survived the trap round trip, direct peek)");
            check(dut.n_bank.regs[1], 32'd44, "n1 (survived the trap round trip, direct peek)");
            check(dut.n_bank.regs[3], 32'd0, "n3 (CAUSE, expect 0=illegal instr)");
            check(dut.n_bank.regs[5], 32'd16, "n5 (EPC, expect .word's own addr 0x10)");
        end

        if (errors == 0) $display("ALL AXISA TRAP-ILLEGAL TESTS PASSED");
        else $display("%0d AXISA TRAP-ILLEGAL TEST(S) FAILED", errors);
        $finish;
    end
endmodule
