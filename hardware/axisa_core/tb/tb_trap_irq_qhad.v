// AxISA traps: external IRQ arriving exactly on QHAD's terminal cycle
// (see sw/trap_irq_qhad.axasm, and cpu_core.v's own `any_trap` comment
// for the exact same-cycle race this guards against - the same class
// tb_trap_irq_stall.v already proved for LOAD/STORE, now for the new
// q-sequencer). This is the highest-risk test in the QHAD/QCNOT batch:
// the `any_trap` guard extension (`&& !is_qhad && !is_qcnot`) has no
// prior test pattern to copy exactly.
//
// Pulses irq_in directly on the cycle dut.q_state_r==4 (Q_S4, QHAD's
// terminal write cycle) - a whitebox peek, matching this project's own
// established style (tb_trap_irq_squash.v peeks dut.squash_r the same
// way). If cpu_core.v's fix is correct: (1) QHAD's own results (r0/r2)
// are the correct, uncorrupted amplitudes - proving the whole 5-cycle
// sequence completed for real before the trap was allowed to land: not
// just "didn't hang", but produced the right numbers; (2) EPC captures
// word index 10's address (0x28, the plain ADDI right after QHAD), NOT
// QHAD's own address (0x24) - proving the IRQ was deferred across the
// entire sequence, not taken mid-flight or against QHAD's own PC.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/trap_irq_qhad.hex"
`endif

module tb_trap_irq_qhad;
    reg clk, reset;
    reg irq_in;
    integer errors;
    integer max_cycles;
    integer cycle_count;

    wire halted;
    wire [31:0] tohost_value;
    wire        bus_req, bus_mem_write, bus_mem_unsigned;
    wire [31:0] bus_addr, bus_write_data;
    wire [1:0]  bus_mem_size;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .irq_in(irq_in),
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
        max_cycles = 400;
        irq_in = 1'b0;

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        // Wait for QHAD's terminal cycle (Q_S4=3'd4), then pulse
        // irq_in exactly then - the specific same-cycle race the
        // any_trap fix addresses.
        wait (dut.q_state_r === 3'd4);
        irq_in = 1'b1;
        @(posedge clk);
        irq_in = 1'b0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles", max_cycles);
            errors = errors + 1;
        end else begin
            $display("Halted after %0d cycles. tohost=%0d", cycle_count, tohost_value);
            check(tohost_value, 32'd66, "tohost (handler's EPC redirect worked)");
            check(dut.n_bank.regs[3], 32'd2, "n3 (cause, expect 2=external IRQ)");
            check(dut.n_bank.regs[4], 32'd40, "n4 (EPC=0x28, instr AFTER QHAD)");
            check(dut.r_bank.regs[0], 32'h3F3504F3, "r0 (QHAD's own result, uncorrupted)");
            check(dut.r_bank.regs[2], 32'h3F3504F3, "r2 (QHAD's own result, uncorrupted)");
        end

        if (errors == 0) $display("ALL AXISA TRAP-IRQ-QHAD TESTS PASSED");
        else $display("%0d AXISA TRAP-IRQ-QHAD TEST(S) FAILED", errors);
        $finish;
    end
endmodule
