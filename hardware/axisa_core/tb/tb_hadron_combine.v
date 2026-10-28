// AxISA v2.0 step 2 (see sw/hadron_combine_test.axasm and docs/ISA.md's
// BARYON/MESON sections): BARYON MAJ/EPS, ANTI + MESON SINGLET, and four
// illegal combines. Results are read back from data memory (the program
// STOREs each one to its own word at 0x400+), traps through tohost
// (= trap count) plus an untouched sentinel.
`timescale 1ns/1ps
`ifndef INSTR_HEX
`define INSTR_HEX "sw/hadron_combine_test.hex"
`endif

module tb_hadron_combine;
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
        max_cycles = 400;

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
            check(tohost_value, 32'd4, "tohost (n7 = traps taken, expect 4)");
            check(dut.n_bank.regs[6], 32'd0, "n6 (sum of trap causes, 0 = ILLEGAL)");
            check(dut.n_bank.regs[4], 32'd55, "n4 (sentinel: no illegal combine wrote)");
            check(dut.dmem.mem[11'h100], 32'hE8, "MAJ(F0,CC,AA) full truth table = E8");
            check(dut.dmem.mem[11'h101], 32'd1, "EPS(1,2,3) sorted = +1");
            check(dut.dmem.mem[11'h102], 32'd1, "EPS(3,1,2) cyclic = +1");
            check(dut.dmem.mem[11'h103], -32'sd1, "EPS(2,1,3) one swap = -1");
            check(dut.dmem.mem[11'h104], 32'd0, "EPS(4,4,9) two equal = 0");
            check(dut.dmem.mem[11'h105], -32'sd1, "EPS(-5,7,0) signed = -1");
            check(dut.dmem.mem[11'h106], 32'd0, "SINGLET(r1, ANTI r1) = 0");
            check(dut.dmem.mem[11'h107], -32'sd2, "SINGLET(r2, ANTI r3) = -2");
            check(dut.dmem.mem[11'h108], -32'sd2, "DIFF(r2, r3) = -2 (== SINGLET)");
            check(dut.dmem.mem[11'h109], 32'd0, "end-marker slot stays 0");
        end

        if (errors == 0) $display("ALL AXISA HADRON-COMBINE TESTS PASSED");
        else $display("%0d AXISA HADRON-COMBINE TEST(S) FAILED", errors);
        $finish;
    end
endmodule
