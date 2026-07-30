// Heterogeneous SoC: 2 P-cores (cpu_core_pipelined, the 5-stage
// pipeline - performance) + 2 E-cores (cpu_core, the single-cycle
// design - efficiency), each with its own private instruction/data
// memory PLUS a shared memory region all four can reach through the
// N-way round-robin shared_bus - scaled up from the original 1P+1E
// mini-SoC now that the arbiter is genuinely N-way, not hard-coded to
// 2 participants. Core index mapping onto the bus: 0=p0, 1=p1, 2=e0,
// 3=e1 (P-cores first, then E-cores) - an arbitrary but fixed,
// documented convention.
`timescale 1ns/1ps

module soc_top #(
    parameter P0_INSTR_HEX     = "",
    parameter P1_INSTR_HEX     = "",
    parameter E0_INSTR_HEX     = "",
    parameter E1_INSTR_HEX     = "",
    parameter INSTR_MEM_WORDS  = 1024,
    parameter DATA_MEM_BYTES   = 8192,
    parameter SHARED_MEM_BASE  = 32'h0000_2000,
    parameter SHARED_MEM_BYTES = 256
) (
    input  wire        clk,
    input  wire        reset,
    output wire        p0_halted,
    output wire [31:0]  p0_tohost,
    output wire        p1_halted,
    output wire [31:0]  p1_tohost,
    output wire        e0_halted,
    output wire [31:0]  e0_tohost,
    output wire        e1_halted,
    output wire [31:0]  e1_tohost,
    output wire        all_halted
);
    localparam NUM_CORES = 4;

    wire        p0_bus_req, p1_bus_req, e0_bus_req, e1_bus_req;
    wire [31:0] p0_bus_addr, p1_bus_addr, e0_bus_addr, e1_bus_addr;
    wire [31:0] p0_bus_write_data, p1_bus_write_data, e0_bus_write_data, e1_bus_write_data;
    wire        p0_bus_mem_write, p1_bus_mem_write, e0_bus_mem_write, e1_bus_mem_write;
    wire [1:0]  p0_bus_mem_size, p1_bus_mem_size, e0_bus_mem_size, e1_bus_mem_size;
    wire        p0_bus_mem_unsigned, p1_bus_mem_unsigned, e0_bus_mem_unsigned, e1_bus_mem_unsigned;
    wire        p0_bus_grant, p1_bus_grant, e0_bus_grant, e1_bus_grant;
    wire [31:0] shared_read_data;

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P0_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p0_core (
        .clk(clk), .reset(reset),
        .halted(p0_halted), .tohost_value(p0_tohost),
        .bus_req(p0_bus_req), .bus_addr(p0_bus_addr),
        .bus_write_data(p0_bus_write_data), .bus_mem_write(p0_bus_mem_write),
        .bus_mem_size(p0_bus_mem_size), .bus_mem_unsigned(p0_bus_mem_unsigned),
        .bus_grant(p0_bus_grant), .bus_read_data(shared_read_data)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P1_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p1_core (
        .clk(clk), .reset(reset),
        .halted(p1_halted), .tohost_value(p1_tohost),
        .bus_req(p1_bus_req), .bus_addr(p1_bus_addr),
        .bus_write_data(p1_bus_write_data), .bus_mem_write(p1_bus_mem_write),
        .bus_mem_size(p1_bus_mem_size), .bus_mem_unsigned(p1_bus_mem_unsigned),
        .bus_grant(p1_bus_grant), .bus_read_data(shared_read_data)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E0_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e0_core (
        .clk(clk), .reset(reset),
        .halted(e0_halted), .tohost_value(e0_tohost),
        .bus_req(e0_bus_req), .bus_addr(e0_bus_addr),
        .bus_write_data(e0_bus_write_data), .bus_mem_write(e0_bus_mem_write),
        .bus_mem_size(e0_bus_mem_size), .bus_mem_unsigned(e0_bus_mem_unsigned),
        .bus_grant(e0_bus_grant), .bus_read_data(shared_read_data)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E1_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e1_core (
        .clk(clk), .reset(reset),
        .halted(e1_halted), .tohost_value(e1_tohost),
        .bus_req(e1_bus_req), .bus_addr(e1_bus_addr),
        .bus_write_data(e1_bus_write_data), .bus_mem_write(e1_bus_mem_write),
        .bus_mem_size(e1_bus_mem_size), .bus_mem_unsigned(e1_bus_mem_unsigned),
        .bus_grant(e1_bus_grant), .bus_read_data(shared_read_data)
    );

    // Pack each core's individual bus signals into the flattened
    // vectors shared_bus.v expects - index mapping 0=p0,1=p1,2=e0,3=e1.
    shared_bus #(.NUM_CORES(NUM_CORES), .MEM_BYTES(SHARED_MEM_BYTES)) sbus (
        .clk(clk), .reset(reset),
        .req({e1_bus_req, e0_bus_req, p1_bus_req, p0_bus_req}),
        .addr_flat({e1_bus_addr, e0_bus_addr, p1_bus_addr, p0_bus_addr}),
        .write_data_flat({e1_bus_write_data, e0_bus_write_data, p1_bus_write_data, p0_bus_write_data}),
        .mem_write({e1_bus_mem_write, e0_bus_mem_write, p1_bus_mem_write, p0_bus_mem_write}),
        .mem_size_flat({e1_bus_mem_size, e0_bus_mem_size, p1_bus_mem_size, p0_bus_mem_size}),
        .mem_unsigned({e1_bus_mem_unsigned, e0_bus_mem_unsigned, p1_bus_mem_unsigned, p0_bus_mem_unsigned}),
        .grant({e1_bus_grant, e0_bus_grant, p1_bus_grant, p0_bus_grant}),
        .read_data(shared_read_data)
    );

    assign all_halted = p0_halted && p1_halted && e0_halted && e1_halted;
endmodule
