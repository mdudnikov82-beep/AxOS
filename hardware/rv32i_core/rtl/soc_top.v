// Heterogeneous SoC: 6 P-cores (cpu_core_pipelined, the 5-stage
// pipeline - performance) + 6 E-cores (cpu_core, the single-cycle
// design - efficiency), each with its own private instruction/data
// memory PLUS a shared memory region all 12 can reach through the
// N-way round-robin shared_bus - scaled up from the earlier 3P+3E SoC
// purely by instantiating 3 more P-cores and 3 more E-cores
// and widening the flattened bus vectors; shared_bus.v itself needed NO
// changes (already genuinely N-way, not hard-coded to any particular
// count). Core index mapping onto the bus: 0=p0, 1=p1, 2=p2, 3=p3, 4=p4, 5=p5, 6=e0, 7=e1, 8=e2, 9=e3, 10=e4, 11=e5
// (P-cores first, then E-cores) - an arbitrary but fixed, documented
// convention.
`timescale 1ns/1ps

module soc_top #(
    parameter P0_INSTR_HEX     = "",
    parameter P1_INSTR_HEX     = "",
    parameter P2_INSTR_HEX     = "",
    parameter P3_INSTR_HEX     = "",
    parameter P4_INSTR_HEX     = "",
    parameter P5_INSTR_HEX     = "",
    parameter E0_INSTR_HEX     = "",
    parameter E1_INSTR_HEX     = "",
    parameter E2_INSTR_HEX     = "",
    parameter E3_INSTR_HEX     = "",
    parameter E4_INSTR_HEX     = "",
    parameter E5_INSTR_HEX     = "",
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
    output wire        p2_halted,
    output wire [31:0]  p2_tohost,
    output wire        p3_halted,
    output wire [31:0]  p3_tohost,
    output wire        p4_halted,
    output wire [31:0]  p4_tohost,
    output wire        p5_halted,
    output wire [31:0]  p5_tohost,
    output wire        e0_halted,
    output wire [31:0]  e0_tohost,
    output wire        e1_halted,
    output wire [31:0]  e1_tohost,
    output wire        e2_halted,
    output wire [31:0]  e2_tohost,
    output wire        e3_halted,
    output wire [31:0]  e3_tohost,
    output wire        e4_halted,
    output wire [31:0]  e4_tohost,
    output wire        e5_halted,
    output wire [31:0]  e5_tohost,
    output wire        all_halted
);
    localparam NUM_CORES = 12;

    wire p0_bus_req, p1_bus_req, p2_bus_req, p3_bus_req, p4_bus_req, p5_bus_req, e0_bus_req, e1_bus_req, e2_bus_req, e3_bus_req, e4_bus_req, e5_bus_req;
    wire [31:0] p0_bus_addr, p1_bus_addr, p2_bus_addr, p3_bus_addr, p4_bus_addr, p5_bus_addr, e0_bus_addr, e1_bus_addr, e2_bus_addr, e3_bus_addr, e4_bus_addr, e5_bus_addr;
    wire [31:0] p0_bus_write_data, p1_bus_write_data, p2_bus_write_data, p3_bus_write_data, p4_bus_write_data, p5_bus_write_data, e0_bus_write_data, e1_bus_write_data, e2_bus_write_data, e3_bus_write_data, e4_bus_write_data, e5_bus_write_data;
    wire p0_bus_mem_write, p1_bus_mem_write, p2_bus_mem_write, p3_bus_mem_write, p4_bus_mem_write, p5_bus_mem_write, e0_bus_mem_write, e1_bus_mem_write, e2_bus_mem_write, e3_bus_mem_write, e4_bus_mem_write, e5_bus_mem_write;
    wire [1:0] p0_bus_mem_size, p1_bus_mem_size, p2_bus_mem_size, p3_bus_mem_size, p4_bus_mem_size, p5_bus_mem_size, e0_bus_mem_size, e1_bus_mem_size, e2_bus_mem_size, e3_bus_mem_size, e4_bus_mem_size, e5_bus_mem_size;
    wire p0_bus_mem_unsigned, p1_bus_mem_unsigned, p2_bus_mem_unsigned, p3_bus_mem_unsigned, p4_bus_mem_unsigned, p5_bus_mem_unsigned, e0_bus_mem_unsigned, e1_bus_mem_unsigned, e2_bus_mem_unsigned, e3_bus_mem_unsigned, e4_bus_mem_unsigned, e5_bus_mem_unsigned;
    wire p0_bus_grant, p1_bus_grant, p2_bus_grant, p3_bus_grant, p4_bus_grant, p5_bus_grant, e0_bus_grant, e1_bus_grant, e2_bus_grant, e3_bus_grant, e4_bus_grant, e5_bus_grant;
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

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P2_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p2_core (
        .clk(clk), .reset(reset),
        .halted(p2_halted), .tohost_value(p2_tohost),
        .bus_req(p2_bus_req), .bus_addr(p2_bus_addr),
        .bus_write_data(p2_bus_write_data), .bus_mem_write(p2_bus_mem_write),
        .bus_mem_size(p2_bus_mem_size), .bus_mem_unsigned(p2_bus_mem_unsigned),
        .bus_grant(p2_bus_grant), .bus_read_data(shared_read_data)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P3_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p3_core (
        .clk(clk), .reset(reset),
        .halted(p3_halted), .tohost_value(p3_tohost),
        .bus_req(p3_bus_req), .bus_addr(p3_bus_addr),
        .bus_write_data(p3_bus_write_data), .bus_mem_write(p3_bus_mem_write),
        .bus_mem_size(p3_bus_mem_size), .bus_mem_unsigned(p3_bus_mem_unsigned),
        .bus_grant(p3_bus_grant), .bus_read_data(shared_read_data)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P4_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p4_core (
        .clk(clk), .reset(reset),
        .halted(p4_halted), .tohost_value(p4_tohost),
        .bus_req(p4_bus_req), .bus_addr(p4_bus_addr),
        .bus_write_data(p4_bus_write_data), .bus_mem_write(p4_bus_mem_write),
        .bus_mem_size(p4_bus_mem_size), .bus_mem_unsigned(p4_bus_mem_unsigned),
        .bus_grant(p4_bus_grant), .bus_read_data(shared_read_data)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P5_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p5_core (
        .clk(clk), .reset(reset),
        .halted(p5_halted), .tohost_value(p5_tohost),
        .bus_req(p5_bus_req), .bus_addr(p5_bus_addr),
        .bus_write_data(p5_bus_write_data), .bus_mem_write(p5_bus_mem_write),
        .bus_mem_size(p5_bus_mem_size), .bus_mem_unsigned(p5_bus_mem_unsigned),
        .bus_grant(p5_bus_grant), .bus_read_data(shared_read_data)
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

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E2_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e2_core (
        .clk(clk), .reset(reset),
        .halted(e2_halted), .tohost_value(e2_tohost),
        .bus_req(e2_bus_req), .bus_addr(e2_bus_addr),
        .bus_write_data(e2_bus_write_data), .bus_mem_write(e2_bus_mem_write),
        .bus_mem_size(e2_bus_mem_size), .bus_mem_unsigned(e2_bus_mem_unsigned),
        .bus_grant(e2_bus_grant), .bus_read_data(shared_read_data)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E3_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e3_core (
        .clk(clk), .reset(reset),
        .halted(e3_halted), .tohost_value(e3_tohost),
        .bus_req(e3_bus_req), .bus_addr(e3_bus_addr),
        .bus_write_data(e3_bus_write_data), .bus_mem_write(e3_bus_mem_write),
        .bus_mem_size(e3_bus_mem_size), .bus_mem_unsigned(e3_bus_mem_unsigned),
        .bus_grant(e3_bus_grant), .bus_read_data(shared_read_data)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E4_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e4_core (
        .clk(clk), .reset(reset),
        .halted(e4_halted), .tohost_value(e4_tohost),
        .bus_req(e4_bus_req), .bus_addr(e4_bus_addr),
        .bus_write_data(e4_bus_write_data), .bus_mem_write(e4_bus_mem_write),
        .bus_mem_size(e4_bus_mem_size), .bus_mem_unsigned(e4_bus_mem_unsigned),
        .bus_grant(e4_bus_grant), .bus_read_data(shared_read_data)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E5_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e5_core (
        .clk(clk), .reset(reset),
        .halted(e5_halted), .tohost_value(e5_tohost),
        .bus_req(e5_bus_req), .bus_addr(e5_bus_addr),
        .bus_write_data(e5_bus_write_data), .bus_mem_write(e5_bus_mem_write),
        .bus_mem_size(e5_bus_mem_size), .bus_mem_unsigned(e5_bus_mem_unsigned),
        .bus_grant(e5_bus_grant), .bus_read_data(shared_read_data)
    );

    // Pack each core's individual bus signals into the flattened
    // vectors shared_bus.v expects - index mapping
    // 0=p0,1=p1,2=p2,3=p3,4=p4,5=p5,6=e0,7=e1,8=e2,9=e3,10=e4,11=e5.
    shared_bus #(.NUM_CORES(NUM_CORES), .MEM_BYTES(SHARED_MEM_BYTES)) sbus (
        .clk(clk), .reset(reset),
        .req({e5_bus_req, e4_bus_req, e3_bus_req, e2_bus_req, e1_bus_req, e0_bus_req, p5_bus_req, p4_bus_req, p3_bus_req, p2_bus_req, p1_bus_req, p0_bus_req}),
        .addr_flat({e5_bus_addr, e4_bus_addr, e3_bus_addr, e2_bus_addr, e1_bus_addr, e0_bus_addr, p5_bus_addr, p4_bus_addr, p3_bus_addr, p2_bus_addr, p1_bus_addr, p0_bus_addr}),
        .write_data_flat({e5_bus_write_data, e4_bus_write_data, e3_bus_write_data, e2_bus_write_data, e1_bus_write_data, e0_bus_write_data, p5_bus_write_data, p4_bus_write_data, p3_bus_write_data, p2_bus_write_data, p1_bus_write_data, p0_bus_write_data}),
        .mem_write({e5_bus_mem_write, e4_bus_mem_write, e3_bus_mem_write, e2_bus_mem_write, e1_bus_mem_write, e0_bus_mem_write, p5_bus_mem_write, p4_bus_mem_write, p3_bus_mem_write, p2_bus_mem_write, p1_bus_mem_write, p0_bus_mem_write}),
        .mem_size_flat({e5_bus_mem_size, e4_bus_mem_size, e3_bus_mem_size, e2_bus_mem_size, e1_bus_mem_size, e0_bus_mem_size, p5_bus_mem_size, p4_bus_mem_size, p3_bus_mem_size, p2_bus_mem_size, p1_bus_mem_size, p0_bus_mem_size}),
        .mem_unsigned({e5_bus_mem_unsigned, e4_bus_mem_unsigned, e3_bus_mem_unsigned, e2_bus_mem_unsigned, e1_bus_mem_unsigned, e0_bus_mem_unsigned, p5_bus_mem_unsigned, p4_bus_mem_unsigned, p3_bus_mem_unsigned, p2_bus_mem_unsigned, p1_bus_mem_unsigned, p0_bus_mem_unsigned}),
        .grant({e5_bus_grant, e4_bus_grant, e3_bus_grant, e2_bus_grant, e1_bus_grant, e0_bus_grant, p5_bus_grant, p4_bus_grant, p3_bus_grant, p2_bus_grant, p1_bus_grant, p0_bus_grant}),
        .read_data(shared_read_data)
    );

    assign all_halted = p0_halted && p1_halted && p2_halted && p3_halted && p4_halted && p5_halted && e0_halted && e1_halted && e2_halted && e3_halted && e4_halted && e5_halted;
endmodule
