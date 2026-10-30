// AxISA v2.3 step 1 (see sw/trap_irq_linkmul.axasm): IRQ pulsed inside
// LINKMUL. +IRQ_PHASE=0 pulses on its first (decode) cycle, 1 mid-sequence
// (a column-1 term at pipeline stage 8), 2 on its last result write (MW, word 17). Every
// phase must defer the trap until all of C is written: EPC=0x28.
`timescale 1ns/1ps
`ifndef INSTR_HEX
`define INSTR_HEX "sw/trap_irq_linkmul.hex"
`endif

module tb_trap_irq_linkmul;
    reg clk, reset;
    reg irq_in;
    integer irq_phase;
    integer errors;
    integer max_cycles;
    integer cycle_count;
    integer m;

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

    // Watchdog: the stimulus below wait()s for a specific internal state;
    // if a bug means that state is never reached, fail instead of hanging.
    initial begin
        #200000;
        $display("FAIL: watchdog - the test never finished (a wait() never fired)");
        $finish;
    end

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
        max_cycles = 1500;
        irq_in = 1'b0;

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        // A = 1 at 0x0, B = diag(1.5, 1, 1) at 0x80 (word 32)
        m = 0;
        dut.dmem.mem[0] = 32'h3F800000; dut.dmem.mem[8] = 32'h3F800000; dut.dmem.mem[16] = 32'h3F800000;
        dut.dmem.mem[32] = 32'h3FC00000; dut.dmem.mem[40] = 32'h3F800000; dut.dmem.mem[48] = 32'h3F800000;
        reset = 0;

        if (!$value$plusargs("IRQ_PHASE=%d", irq_phase)) irq_phase = 2;
        if (irq_phase == 0)
            wait (dut.is_linkmul === 1'b1 && dut.su_state_r === 5'd0);
        else if (irq_phase == 1)
            wait (dut.tk_v[8] === 1'b1 && dut.tk_kk[8] === 2'd1); // a column-1 term at pipeline stage 8
        else
            wait (dut.su_state_r === 5'd17 && dut.su_w_r === 5'd17);
        #1; // just after the edge, inside the chosen cycle
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
            check(tohost_value, 32'd77, "tohost (handler's EPC redirect worked)");
            check(dut.n_bank.regs[3], 32'd2, "n3 (cause, expect 2=external IRQ)");
            check(dut.n_bank.regs[4], 32'd40, "n4 (EPC=0x28, instr AFTER LINKMUL)");
            check(dut.dmem.mem[64], 32'h3FC00000, "C[0][0] = 1.5 (LINKMUL's first word)");
            check(dut.dmem.mem[80], 32'h3F800000, "C[2][2] = 1.0 (word 16, just before the last)");
            check(dut.dmem.mem[81], 32'h00000000, "C[2][2] Im = 0 (word 17, the terminal write)");
            check(dut.n_bank.regs[6], 32'd0, "n6 (0x28 skipped by the handler redirect)");
        end

        if (errors == 0) $display("ALL AXISA TRAP-IRQ-LINKMUL TESTS PASSED");
        else $display("%0d AXISA TRAP-IRQ-LINKMUL TEST(S) FAILED", errors);
        $finish;
    end
endmodule
