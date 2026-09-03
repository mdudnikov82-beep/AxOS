// QHAD numeric correctness (see sw/qhad_test.axasm, docs/ISA.md's
// QHAD section). Direct peek at dut.r_bank.regs[i], matching this
// project's established style.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/qhad_test.hex"
`endif

module tb_qhad;
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
            // amp0=(r0,r1)=1.0+0i, amp1=(r2,r3)=0+0i (reset value) ->
            // QHAD qubit=0,half=0: both new amplitudes are exactly
            // k=1/sqrt(2) (Re) and exactly 0 (Im) - no rounding
            // ambiguity (one operand is always exact 0 or exact 1.0).
            check(dut.r_bank.regs[0], 32'h3F3504F3, "r0 (new amp0 Re = k)");
            check(dut.r_bank.regs[1], 32'h00000000, "r1 (new amp0 Im = 0)");
            check(dut.r_bank.regs[2], 32'h3F3504F3, "r2 (new amp1 Re = k)");
            check(dut.r_bank.regs[3], 32'h00000000, "r3 (new amp1 Im = 0)");
        end

        if (errors == 0) $display("ALL AXISA QHAD TESTS PASSED");
        else $display("%0d AXISA QHAD TEST(S) FAILED", errors);
        $finish;
    end
endmodule
