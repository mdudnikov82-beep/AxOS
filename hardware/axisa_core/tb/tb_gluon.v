// AxISA v2.0 real gluons (see sw/gluon_test.axasm and docs/ISA.md's
// GLUON section): all 8 gluons plus both color-rule traps. Every
// gluon result is checked by direct hierarchical peek, the traceless
// invariant through BARYON, and the traps through tohost (= trap
// count) plus untouched sentinels.
`timescale 1ns/1ps
`ifndef INSTR_HEX
`define INSTR_HEX "sw/gluon_test.hex"
`endif

module tb_gluon;
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
            check(tohost_value, 32'd2, "tohost (n7 = traps taken, expect 2)");
            check(dut.n_bank.regs[6], 32'd0, "n6 (sum of trap causes, 0 = ILLEGAL)");
            check(dut.g_bank.regs[1], 32'd7, "g1 (GR: red r1 -> green)");
            check(dut.b_bank.regs[1], 32'd7, "b1 (BG: green g1 -> blue)");
            check(dut.r_bank.regs[2], 32'd7, "r2 (RB: blue b1 -> red)");
            check(dut.b_bank.regs[2], 32'd11, "b2 (BR: red r3 -> blue)");
            check(dut.g_bank.regs[2], 32'd11, "g2 (GB: blue b2 -> green)");
            check(dut.r_bank.regs[4], 32'd11, "r4 (RG: green g2 -> red)");
            check(dut.r_bank.regs[6], 32'd13, "r6 (L3 on red: x1)");
            check(dut.g_bank.regs[6], -32'sd13, "g6 (L3 on green: x-1)");
            check(dut.b_bank.regs[6], 32'd0, "b6 (L3 on blue: x0)");
            check(dut.n_bank.regs[2], 32'd0, "n2 (BARYON after L3: traceless = 0)");
            check(dut.n_bank.regs[1], 32'd26, "n1 (MESON r6-g6: L3 results not all 0)");
            check(dut.r_bank.regs[5], 32'd13, "r5 (L8 in place on red: x1)");
            check(dut.g_bank.regs[5], 32'd13, "g5 (L8 in place on green: x1)");
            check(dut.b_bank.regs[5], -32'sd26, "b5 (L8 in place on blue: x-2)");
            check(dut.n_bank.regs[4], 32'd0, "n4 (BARYON after L8: traceless = 0)");
            check(dut.r_bank.regs[7], 32'd99, "r7 (sentinel: wrong-color gluon wrote nothing)");
        end

        if (errors == 0) $display("ALL AXISA GLUON TESTS PASSED");
        else $display("%0d AXISA GLUON TEST(S) FAILED", errors);
        $finish;
    end
endmodule
