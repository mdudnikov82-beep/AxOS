// AxISA traps: external IRQ landing exactly on a post-redirect squash
// cycle (see cpu_core.v's own `squash_r` comment) - a NEW race
// introduced by the registered-fetch redesign, not covered by
// tb_trap_irq.v (which pulses irq_in at an arbitrary point in the spin
// loop - by its own comment, "the exact cycle the pulse lands doesn't
// matter" for THAT test's purposes, so it doesn't reliably hit this
// specific window) or tb_trap_irq_stall.v (a different race,
// mem_stall not squash_r).
//
// Reuses sw/trap_irq.hex unmodified - its bootstrap already lands in a
// tight self-branching spin loop (`loop: BEQ N0, N0, loop`), which
// means EVERY taken-branch commit is immediately followed by a real
// squash_r=1 cycle. This test synchronizes irq_in's pulse directly to
// `dut.squash_r` (hierarchical whitebox access, same convention this
// project already uses for `dut.n_bank.regs[N]`) instead of a fixed
// cycle count, to deterministically land the IRQ inside that window
// every run rather than relying on chance.
//
// If cpu_core.v's squash_r-aware trap gating is correct, EPC still
// captures `loop`'s own real address (0x1C) - proving the pending IRQ
// was correctly deferred past the meaningless squash cycle and taken
// on a later, real re-decode of the same (still-real) BEQ instruction,
// not committed against a wrong-path/bubble pc_r.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/trap_irq.hex"
`endif

module tb_trap_irq_squash;
    reg clk, reset;
    reg irq_in;
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

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        // Give the core time to run the bootstrap and settle into the
        // spin loop, THEN wait for a real squash_r=1 cycle (the loop's
        // own self-branch guarantees one every 2 cycles once settled)
        // before pulsing irq_in - deterministically targeting the exact
        // race, not hoping to land in it by chance.
        repeat (10) @(posedge clk);
        wait (dut.squash_r === 1'b1);
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
            check(tohost_value, 32'd42, "tohost (handler's EPC redirect worked)");
            check(dut.n_bank.regs[3], 32'd2, "n3 (cause, expect 2=external IRQ)");
            check(dut.n_bank.regs[4], 32'd28, "n4 (EPC, expect loop's own real address 0x1C - NOT a squash-bubble address)");
        end

        if (errors == 0) $display("ALL AXISA TRAP-IRQ-SQUASH TESTS PASSED");
        else $display("%0d AXISA TRAP-IRQ-SQUASH TEST(S) FAILED", errors);
        $finish;
    end
endmodule
