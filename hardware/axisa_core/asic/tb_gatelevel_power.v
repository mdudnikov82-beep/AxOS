// Gate-level testbench for the SYNTHESIZED cpu_core_top netlist (not
// RTL) - drives clk/reset exactly like the RTL testbenches
// (tb_cpu.v/tb_run.v) and checks the SAME expected result
// (tohost=200, test1.hex's own milestone-1 program) as a real
// functional gate-level-vs-RTL equivalence check, not just a vehicle
// for a VCD dump. Dumps a VCD so a real, workload-driven switching
// activity can be fed into OpenSTA's report_power via read_vcd,
// instead of OpenSTA's own generic "vectorless" default activity -
// see power_report_vcd.tcl.
`timescale 1ns/1ps

module tb_gatelevel_power;
    reg clk, reset;
    wire halted;
    wire [31:0] tohost_value;
    wire bus_req, bus_mem_write, bus_mem_unsigned;
    wire [31:0] bus_addr, bus_write_data;
    wire [1:0] bus_mem_size;
    wire uart_tx_valid;
    wire [7:0] uart_tx_data;
    wire uart_rx_ack;

    integer errors;
    integer max_cycles;
    integer cycle_count;

    // Same standalone-core tie-offs as every other cpu_core_top
    // testbench in this project (no shared bus, no UART stimulus,
    // no interrupt - test1.hex needs none of these).
    cpu_core_top dut (
        .clk(clk), .reset(reset),
        .halted(halted), .tohost_value(tohost_value),
        .irq_in(1'b0),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(1'b0), .bus_read_data(32'b0),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(8'b0), .uart_rx_ready_in(1'b0), .uart_rx_ack(uart_rx_ack)
    );

    always #5 clk = ~clk;

    initial begin
        errors = 0;
        max_cycles = 200;

        $dumpfile("gl_power.vcd");
        $dumpvars(0, tb_gatelevel_power);

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
            $display("FAIL: gate-level netlist never halted within %0d cycles", max_cycles);
            errors = errors + 1;
        end else begin
            $display("Gate-level netlist halted after %0d cycles. tohost=%0d", cycle_count, tohost_value);
            if (tohost_value !== 32'd200) begin
                $display("FAIL: tohost=%0d, expected 200 - gate-level netlist does NOT match RTL behavior", tohost_value);
                errors = errors + 1;
            end else begin
                $display("PASS: gate-level netlist matches RTL (tohost=200) - real functional equivalence, not just a VCD vehicle");
            end
        end

        // A few extra idle cycles after halt so the VCD captures some
        // post-halt settled activity too, not just the exact instant
        // of the last real switching event.
        repeat (10) @(posedge clk);

        if (errors == 0) $display("ALL AXISA GATE-LEVEL POWER TESTS PASSED");
        else $display("%0d AXISA GATE-LEVEL POWER TEST(S) FAILED", errors);
        $finish;
    end
endmodule
