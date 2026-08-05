// AxISA traps: external IRQ arriving mid-mem_stall (see
// sw/trap_irq_stall.axasm) - the one genuinely risky interaction this
// feature has, per design review, and the one that actually caught a
// real same-cycle race during implementation (see cpu_core.v's own
// `any_trap` comment): an IRQ preempting a LOAD/STORE on the exact
// cycle it completes would make RFT re-execute (double-commit) an
// access that already happened for real.
//
// Drives bus_grant directly (no real NoC needed for this test) - holds
// it low for several cycles after the STORE's bus_req asserts,
// pulsing irq_in mid-stall, then grants it. If cpu_core.v's fix is
// correct, EPC captures the address of the instruction AFTER the
// store (0x28) - proving the store was allowed to complete first.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/trap_irq_stall.hex"
`endif

module tb_trap_irq_stall;
    reg clk, reset;
    reg irq_in;
    reg bus_grant_r;
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
        .bus_grant(bus_grant_r), .bus_read_data(32'b0),
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
        irq_in = 1'b0;
        bus_grant_r = 1'b0;

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        // Wait for the STORE's bus_req to assert, then hold it stalled
        // for several cycles, pulsing irq_in partway through.
        wait (bus_req === 1'b1);
        @(posedge clk); // cycle 1 stalled
        @(posedge clk); // cycle 2 stalled
        irq_in = 1'b1;
        @(posedge clk); // cycle 3 stalled - irq_in sampled/latched here
        irq_in = 1'b0;
        @(posedge clk); // cycle 4 stalled - irq_pending stays latched, mem_stall still high
        check(halted, 1'b0, "not halted yet (still mid-stall, trap deferred)");
        bus_grant_r = 1'b1;
        @(posedge clk); // mem_stall clears THIS edge - the store must complete, not the trap
        bus_grant_r = 1'b0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles", max_cycles);
            errors = errors + 1;
        end else begin
            $display("Halted after %0d cycles. tohost=%0d", cycle_count, tohost_value);
            check(tohost_value, 32'd55, "tohost (handler's EPC redirect worked)");
            check(dut.n_bank.regs[3], 32'd2, "n3 (cause, expect 2=external IRQ)");
            check(dut.n_bank.regs[4], 32'd40, "n4 (EPC=0x28, instr AFTER the store)");
        end

        if (errors == 0) $display("ALL AXISA TRAP-IRQ-STALL TESTS PASSED");
        else $display("%0d AXISA TRAP-IRQ-STALL TEST(S) FAILED", errors);
        $finish;
    end
endmodule
