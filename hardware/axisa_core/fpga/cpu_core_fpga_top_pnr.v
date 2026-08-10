// Real place-and-route variant of cpu_core_fpga_top.v - loads an
// actual program (sw/test1.hex) instead of leaving instr_mem
// blackboxed. Place-and-route needs a fully concrete netlist: a
// blackboxed module has no internal implementation at all, so
// nextpnr has nothing to place for it (unlike synth_ecp5's `stat`,
// which only needs a cell-count tally and can work around a
// blackboxed submodule fine). Use this file INSTEAD OF
// cpu_core_fpga_top.v for real nextpnr-ecp5 place-and-route runs.
`timescale 1ns/1ps

module cpu_core_fpga_top (
    input  wire        clk,
    input  wire        reset,
    output wire        halted,
    output wire [31:0] tohost_value,

    input  wire        irq_in,

    output wire        bus_req,
    output wire [31:0] bus_addr,
    output wire [31:0] bus_write_data,
    output wire        bus_mem_write,
    output wire [1:0]  bus_mem_size,
    output wire        bus_mem_unsigned,
    input  wire        bus_grant,
    input  wire [31:0] bus_read_data,

    output wire        uart_tx_valid,
    output wire [7:0]  uart_tx_data,
    input  wire [7:0]  uart_rx_data_in,
    input  wire        uart_rx_ready_in,
    output wire        uart_rx_ack
);
    cpu_core #(
        .INSTR_INIT_FILE("sw/test1.hex")
    ) core (
        .clk(clk), .reset(reset),
        .halted(halted), .tohost_value(tohost_value),
        .irq_in(irq_in),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(bus_grant), .bus_read_data(bus_read_data),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(uart_rx_data_in), .uart_rx_ready_in(uart_rx_ready_in), .uart_rx_ack(uart_rx_ack)
    );
endmodule
