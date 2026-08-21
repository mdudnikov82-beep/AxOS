// ASIC-flow top level for cpu_core.v (OpenLane2/sky130) - a real
// program MUST be loaded into instr_mem, or Yosys's X-optimism proves
// the fetched instruction is a constant forever (empty ROM = all
// zeros = the same instruction every cycle) and deletes almost the
// entire clocked datapath as "unreachable" - confirmed live via a
// real synth attempt: OpenROAD's CTS stage reported "Net 'clk' has 0
// sinks" and "No clock nets have been found", and the disconnected-
// pins checker flagged 45 critical disconnected output pins (every
// output whose driving logic had been optimized away). Exact same bug
// class this project already hit and fixed on the FPGA side (see
// [[project_axisa_synthesis_check]], instr_mem_worstcase.v's own
// header comment) - the fix here is the same idea (load a real
// program), just via a plain wrapper instead of a blackbox, since
// OpenLane needs a fully concrete netlist same as real FPGA PnR does.
//
// Path for INSTR_INIT_FILE is a real open, empirically-untested
// question the first time this is tried: $readmemh resolves paths
// relative to Yosys's OWN process cwd inside OpenLane's flow, not to
// this .v file or to config.json's location - unlike OpenLane's own
// `dir::` config-key mechanism (VERILOG_FILES etc.), which IS resolved
// relative to config.json but does not apply to arbitrary Verilog
// $readmemh calls. "../sw/test1.hex" is a first, structurally-motivated
// guess (mirrors this project's own FPGA convention exactly:
// fpga/cpu_core_fpga_top_pnr.v uses "sw/test1.hex" when yosys is
// invoked with cwd=hardware/axisa_core, i.e. one level above where
// that wrapper lives - same relative relationship applies here between
// this asic/ directory and its sw/ sibling) - to be corrected with a
// real path from a real error if this guess is wrong.
`timescale 1ns/1ps

module cpu_core_top (
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
        .INSTR_INIT_FILE("../sw/test1.hex")
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
