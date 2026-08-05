// AxISA traps, step 2 of 3 (see sw/trap_syscall.axasm and docs/ISA.md's
// "Traps" section): SYSCALL + a real first-ever user-mode transition
// + PRIV_VIOLATION. Checks tohost AND direct hierarchical peeks into
// BOTH architectural N registers and cpu_core.v's own internal trap
// state (mode_r - not a bank register, a plain reg inside the module,
// hierarchically visible from the testbench like every other internal
// signal in this project's history).
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/trap_syscall.hex"
`endif

module tb_trap_syscall;
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
            check(tohost_value, 32'd110, "tohost (n2+n2 after 2 real trap round trips)");
            check(dut.n_bank.regs[2], 32'd55, "n2 (user's value, survived both round trips)");
            check(dut.n_bank.regs[3], 32'd1, "n3 (SYSCALL cause, expect 1)");
            check(dut.n_bank.regs[4], 32'd3, "n4 (PRIV_VIOLATION cause, expect 3)");
            check(dut.n_bank.regs[5], 32'd0, "n5 (saved_mode at SYSCALL trap, expect 0=USER)");
            check(dut.mode_r, 1'b0, "mode_r (final restored mode, expect USER)");
        end

        if (errors == 0) $display("ALL AXISA TRAP-SYSCALL TESTS PASSED");
        else $display("%0d AXISA TRAP-SYSCALL TEST(S) FAILED", errors);
        $finish;
    end
endmodule
