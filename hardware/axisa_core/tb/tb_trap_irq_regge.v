// AxISA v2.1 step 3 (see sw/trap_irq_regge.axasm): IRQ pulsed inside
// REGGE MASS.B. +IRQ_PHASE=0 first cycle, 1 mid-sqrt (3 cycles into
// RG_SQ), 2 terminal write cycle RG_W. Every phase must defer the trap
// until REGGE has written n2: EPC=0x28, n2 = the Delta(1232) mass bits.
`timescale 1ns/1ps
`ifndef INSTR_HEX
`define INSTR_HEX "sw/trap_irq_regge.hex"
`endif

module tb_trap_irq_regge;
    reg clk, reset;
    reg irq_in;
    integer irq_phase;
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

        if (!$value$plusargs("IRQ_PHASE=%d", irq_phase)) irq_phase = 2;
        if (irq_phase == 0)
            wait (dut.is_regge === 1'b1 && dut.rg_state_r === 3'd0);
        else if (irq_phase == 1) begin
            wait (dut.rg_state_r === 3'd4);
            repeat (3) @(posedge clk);
        end else
            wait (dut.rg_state_r === 3'd5);
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
            check(dut.n_bank.regs[4], 32'd40, "n4 (EPC=0x28, instr AFTER REGGE)");
            check(dut.n_bank.regs[2], 32'h3F9CC471, "n2 (REGGE's own result: Delta(1232) mass)");
            check(dut.n_bank.regs[6], 32'd0, "n6 (0x28 skipped by the handler redirect)");
        end

        if (errors == 0) $display("ALL AXISA TRAP-IRQ-REGGE TESTS PASSED");
        else $display("%0d AXISA TRAP-IRQ-REGGE TEST(S) FAILED", errors);
        $finish;
    end
endmodule
