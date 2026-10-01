// QMEASURE degenerate test 1/2: P0=1.0 (see sw/qmeasure_test_p1.axasm,
// docs/ISA.md's QMEASURE section). Direct peek at dut.r_bank.regs[i]/
// dut.n_bank.regs[i], matching this project's established style.
// max_cycles is generous - QMEASURE alone is ~96 cycles (dominated by
// fp_sqrt/fp_div), plus bootstrap/HALT overhead.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/qmeasure_test_p1.hex"
`endif

module tb_qmeasure_p1;
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
                $display("FAIL: %0s got=0x%h expected=0x%h", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = 0x%h", name, got);
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
            $display("Halted after %0d cycles. tohost(outcome)=%0d", cycle_count, tohost_value);
            // P0=1.0 forces outcome=0 (the A group: amp0,amp2 survives).
            // scale=1/sqrt(1.0)=1.0 exactly, so survivors are UNCHANGED;
            // losers (amp1,amp3) are explicitly zeroed (already 0).
            check(tohost_value, 32'd0, "outcome (forced 0, P0=1.0)");
            check(dut.n_bank.regs[1], 32'd0, "n1 (outcome, direct peek)");
            check(dut.r_bank.regs[0], 32'h3F800000, "r0 (amp0 Re, unchanged)");
            check(dut.r_bank.regs[1], 32'h00000000, "r1 (amp0 Im, unchanged)");
            check(dut.r_bank.regs[4], 32'h00000000, "r4 (amp2 Re, unchanged)");
            check(dut.r_bank.regs[5], 32'h00000000, "r5 (amp2 Im, unchanged)");
            check(dut.r_bank.regs[2], 32'h00000000, "r2 (amp1 Re, zeroed - losing group)");
            check(dut.r_bank.regs[3], 32'h00000000, "r3 (amp1 Im, zeroed - losing group)");
            check(dut.r_bank.regs[6], 32'h00000000, "r6 (amp3 Re, zeroed - losing group)");
            check(dut.r_bank.regs[7], 32'h00000000, "r7 (amp3 Im, zeroed - losing group)");
        end

        if (errors == 0) $display("ALL AXISA QMEASURE P1 TESTS PASSED");
        else $display("%0d AXISA QMEASURE P1 TEST(S) FAILED", errors);
        $finish;
    end
endmodule
