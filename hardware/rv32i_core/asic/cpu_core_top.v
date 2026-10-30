// ASIC-flow top level for the 5-stage RV32I(F) core (OpenLane2/sky130) -
// the opponent in hardware/bench's fair fight against AxISA. Same rules as
// hardware/axisa_core/asic/cpu_core_top.v, so the two numbers compare:
// same flow and config (100 ns, relative sizing, 40% utilization), the
// same memory sizes (128 instruction words, 512 data bytes - flip-flops,
// no SRAM macro in this flow), and the program LOADED through instr_mem's
// load port rather than baked in as a ROM, so synthesis cannot prune away
// the parts a particular program does not use. Every core port is a pin.
// MMU_ENABLE stays 0 (the core's default): no TLB on this side, which
// if anything favours RV32I's clock.
`timescale 1ns/1ps

module cpu_core_top (
    input  wire        clk,
    input  wire        reset,
    input  wire        imem_load_we,
    input  wire [31:0] imem_load_addr,
    input  wire [31:0] imem_load_data,
    output wire        halted,
    output wire [31:0] tohost_value,
    output wire        page_fault,
    output wire        bus_req,
    output wire [31:0] bus_addr,
    output wire [31:0] bus_write_data,
    output wire        bus_mem_write,
    output wire [1:0]  bus_mem_size,
    output wire        bus_mem_unsigned,
    input  wire        bus_grant,
    input  wire [31:0] bus_read_data
);
    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(128),
        .DATA_MEM_BYTES(512),
        .INSTR_INIT_FILE("")
    ) core (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value), .page_fault(page_fault),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(bus_grant), .bus_read_data(bus_read_data),
        .imem_load_we(imem_load_we), .imem_load_addr(imem_load_addr), .imem_load_data(imem_load_data)
    );
endmodule
