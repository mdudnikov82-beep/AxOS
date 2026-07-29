// Minimal heterogeneous SoC: one P-core (cpu_core_pipelined, the
// 5-stage pipeline - performance) and one E-core (cpu_core, the
// single-cycle design - efficiency) side by side, each with its own
// private instruction/data memory PLUS a shared memory region both can
// reach through the arbitrated shared_bus - real inter-core
// communication, not just two cores that happen to share a clock.
// This whole bus is an internal implementation detail: soc_top's own
// external port list is unchanged from before the bus existed.
`timescale 1ns/1ps

module soc_top #(
    parameter P_INSTR_HEX      = "",
    parameter E_INSTR_HEX      = "",
    parameter INSTR_MEM_WORDS  = 1024,
    parameter DATA_MEM_BYTES   = 8192,
    parameter SHARED_MEM_BASE  = 32'h0000_2000,
    parameter SHARED_MEM_BYTES = 256
) (
    input  wire        clk,
    input  wire        reset,
    output wire        p_halted,
    output wire [31:0]  p_tohost,
    output wire        e_halted,
    output wire [31:0]  e_tohost,
    output wire        both_halted
);
    wire        p_bus_req, e_bus_req;
    wire [31:0] p_bus_addr, e_bus_addr;
    wire [31:0] p_bus_write_data, e_bus_write_data;
    wire        p_bus_mem_write, e_bus_mem_write;
    wire [1:0]  p_bus_mem_size, e_bus_mem_size;
    wire        p_bus_mem_unsigned, e_bus_mem_unsigned;
    wire        p_bus_grant, e_bus_grant;
    wire [31:0] p_bus_read_data, e_bus_read_data;

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS),
        .INSTR_INIT_FILE(P_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE),
        .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p_core (
        .clk(clk), .reset(reset),
        .halted(p_halted), .tohost_value(p_tohost),
        .bus_req(p_bus_req), .bus_addr(p_bus_addr),
        .bus_write_data(p_bus_write_data), .bus_mem_write(p_bus_mem_write),
        .bus_mem_size(p_bus_mem_size), .bus_mem_unsigned(p_bus_mem_unsigned),
        .bus_grant(p_bus_grant), .bus_read_data(p_bus_read_data)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS),
        .INSTR_INIT_FILE(E_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE),
        .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e_core (
        .clk(clk), .reset(reset),
        .halted(e_halted), .tohost_value(e_tohost),
        .bus_req(e_bus_req), .bus_addr(e_bus_addr),
        .bus_write_data(e_bus_write_data), .bus_mem_write(e_bus_mem_write),
        .bus_mem_size(e_bus_mem_size), .bus_mem_unsigned(e_bus_mem_unsigned),
        .bus_grant(e_bus_grant), .bus_read_data(e_bus_read_data)
    );

    shared_bus #(.MEM_BYTES(SHARED_MEM_BYTES)) sbus (
        .clk(clk),
        .p_req(p_bus_req), .p_addr(p_bus_addr), .p_write_data(p_bus_write_data),
        .p_mem_write(p_bus_mem_write), .p_mem_size(p_bus_mem_size),
        .p_mem_unsigned(p_bus_mem_unsigned), .p_grant(p_bus_grant), .p_read_data(p_bus_read_data),
        .e_req(e_bus_req), .e_addr(e_bus_addr), .e_write_data(e_bus_write_data),
        .e_mem_write(e_bus_mem_write), .e_mem_size(e_bus_mem_size),
        .e_mem_unsigned(e_bus_mem_unsigned), .e_grant(e_bus_grant), .e_read_data(e_bus_read_data)
    );

    assign both_halted = p_halted && e_halted;
endmodule
