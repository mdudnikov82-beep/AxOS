// ASIC-flow top level for cpu_core.v (OpenLane2/sky130).
//
// v2.1 (2026-10-28): the program is LOADED through instr_mem's load port
// (imem_load_*), not baked in as a ROM. The previous wrapper baked
// sw/test1.hex into instr_mem as a constant; Yosys then proved every
// instruction that 15-word program never uses unreachable and deleted it
// - the September 2026 run kept only 982 flip-flops: no data memory at
// all, no trap state, half of the G/B register banks. Those numbers
// described a pruned core, not AxISA. With a loadable program nothing
// is provably dead, so the full core gets synthesized.
//
// Memory sizes are ASIC-only parameters: the flow has no SRAM macro, so
// every memory bit is a flip-flop. 128 words each (512 bytes) keeps the
// die sane while every piece of logic - decode, datapath, sequencers,
// FPU, MTE tag memory (DATA_MEM_WORDS / 4 granules) - is still there.
// The simulations keep cpu_core.v's own defaults (1024 / 2048 words).
`timescale 1ns/1ps

module cpu_core_top (
    input  wire        clk,
    input  wire        reset,
    // program load (write instr_mem while reset is held)
    input  wire        imem_load_we,
    input  wire [31:0] imem_load_addr,
    input  wire [31:0] imem_load_data,
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
    output wire        uart_rx_ack,
    // v2.3 HOP links - pins, so synthesis keeps the link logic (tied-off
    // inputs would let Yosys prune it, the September lesson)
    output wire [3:0]   hop_out_valid,
    output wire [31:0]  hop_out_data,
    input  wire [3:0]   hop_out_ready,
    input  wire [3:0]   hop_in_valid,
    input  wire [127:0] hop_in_data,
    output wire [3:0]   hop_in_ready
);
    cpu_core #(
        .INSTR_MEM_WORDS(128),
        .DATA_MEM_WORDS(128),
        .INSTR_INIT_FILE("")
    ) core (
        .clk(clk), .reset(reset),
        .imem_load_we(imem_load_we), .imem_load_addr(imem_load_addr), .imem_load_data(imem_load_data),
        .halted(halted), .tohost_value(tohost_value),
        .irq_in(irq_in),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(bus_grant), .bus_read_data(bus_read_data),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(uart_rx_data_in), .uart_rx_ready_in(uart_rx_ready_in), .uart_rx_ack(uart_rx_ack),
        .hop_out_valid(hop_out_valid), .hop_out_data(hop_out_data), .hop_out_ready(hop_out_ready),
        .hop_in_valid(hop_in_valid), .hop_in_data(hop_in_data), .hop_in_ready(hop_in_ready)
    );
endmodule
