// AxISA traps, step 3 of 3 (see sw/trap_irq.axasm and docs/ISA.md's
// "Traps" section): external interrupt, basic case (ordinary
// instruction execution, not mid-mem_stall - see tb_trap_irq_stall.v
// for that specific, riskier interaction). Pulses irq_in once the
// core has had time to reach its spin loop, then confirms the trap
// fired, EPC captured the not-yet-executed loop instruction's own
// address (no +4 needed for an IRQ, unlike a synchronous trap), and
// the handler's own EPC redirect (to `finish`, not back into the
// loop) was honored exactly.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/trap_irq.hex"
`endif

module tb_trap_irq;
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

        // Give the core time to run the bootstrap (6 instructions) and
        // settle into the spin loop before pulsing irq_in - by then
        // pc is guaranteed to be sitting at `loop`'s own address every
        // single cycle (BEQ n0,n0,loop always re-targets itself), so
        // the exact cycle the pulse lands doesn't matter for EPC's
        // expected value.
        repeat (10) @(posedge clk);
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
            check(dut.n_bank.regs[4], 32'd28, "n4 (EPC, expect loop's own address 0x1C)");
        end

        if (errors == 0) $display("ALL AXISA TRAP-IRQ TESTS PASSED");
        else $display("%0d AXISA TRAP-IRQ TEST(S) FAILED", errors);
        $finish;
    end
endmodule
