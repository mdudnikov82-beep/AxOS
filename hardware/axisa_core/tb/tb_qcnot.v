// QCNOT swap correctness (see sw/qcnot_test.axasm, docs/ISA.md's
// QCNOT section). Direct peek at dut.r_bank.regs[i] - matches this
// project's established style (e.g. tb_trap_irq_stall.v's own
// dut.n_bank.regs[i] peeks) - since QCNOT has no other observable
// side effect (no UART, no memory write outside the R bank).
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/qcnot_test.hex"
`endif

module tb_qcnot;
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
                $display("FAIL: %0s got=%0d expected=%0d", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", name, got);
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
            $display("Halted after %0d cycles.", cycle_count);
            check(dut.r_bank.regs[2], 32'd33, "r2 (amp1 Re, expect old amp3 Re)");
            check(dut.r_bank.regs[3], 32'd44, "r3 (amp1 Im, expect old amp3 Im)");
            check(dut.r_bank.regs[6], 32'd11, "r6 (amp3 Re, expect old amp1 Re)");
            check(dut.r_bank.regs[7], 32'd22, "r7 (amp3 Im, expect old amp1 Im)");
        end

        if (errors == 0) $display("ALL AXISA QCNOT TESTS PASSED");
        else $display("%0d AXISA QCNOT TEST(S) FAILED", errors);
        $finish;
    end
endmodule
