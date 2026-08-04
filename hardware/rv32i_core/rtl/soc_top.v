// Network-on-Chip version of the mini-SoC (hardware/rv32i_core) -
// replaces shared_bus.v's single centralized arbiter with a real 4x4
// mesh of XY-routed routers (router.v), each grid position connected
// to its N/E/S/W neighbors plus a Local port for whatever core or
// memory endpoint sits there. TWO independent router networks span the
// whole grid - REQUEST (core -> memory, FLIT_WIDTH=76) and RESPONSE
// (memory -> core, FLIT_WIDTH=36) - kept as fully separate router
// instances with zero shared state, specifically to sidestep request/
// response protocol deadlock rather than solve it (a design-review
// recommendation - see [[project_noc_router]] for the full rationale,
// including a real grant-timing bug the review caught before any RTL
// was written).
//
// Memory lives at the CENTER of the grid (1,1), not a
// corner - the review found corner placement would cost roughly 33%
// higher average latency and a 6-vs-4-hop worse worst case, for a
// single fixed memory sink that literally every request must reach.
// 12 of the remaining 15 positions host the 6 P-cores (cpu_core_pipelined)
// and 6 E-cores (cpu_core) from the shared-bus version; 3 are spare,
// pass-through-only routers with no local endpoint - a legitimate,
// common real-NoC scenario, and it exercises genuine multi-hop routing
// more than a mesh sized exactly to core count would.
//
// External module interface (parameters and ports) is UNCHANGED from
// the shared-bus soc_top.v - only what's wired INSIDE differs - so
// tb_soc.v/tb_shared_soc.v needed zero modifications to run against
// this version.
//
// Grid layout (x,y), MEM at center:

//   p0      p4      e1      e5    
//   p1      MEM     e2      SPARE 
//   p2      p5      e3      SPARE 
//   p3      e0      e4      SPARE 
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

    // ==================== Mesh link wires ====================
    // One {valid,flit,ready} triple per (node, direction) that has a
    // real neighbor, representing THAT node's own outgoing flow in
    // that direction - referenced directly (shared wire names, no
    // extra `assign`s needed) from both this node's *_out_* ports and
    // the neighbor's opposite-direction *_in_* ports.
    wire req_00_E_v, req_00_E_r; wire [75:0] req_00_E_f;
    wire req_00_S_v, req_00_S_r; wire [75:0] req_00_S_f;
    wire req_10_E_v, req_10_E_r; wire [75:0] req_10_E_f;
    wire req_10_S_v, req_10_S_r; wire [75:0] req_10_S_f;
    wire req_10_W_v, req_10_W_r; wire [75:0] req_10_W_f;
    wire req_20_E_v, req_20_E_r; wire [75:0] req_20_E_f;
    wire req_20_S_v, req_20_S_r; wire [75:0] req_20_S_f;
    wire req_20_W_v, req_20_W_r; wire [75:0] req_20_W_f;
    wire req_30_S_v, req_30_S_r; wire [75:0] req_30_S_f;
    wire req_30_W_v, req_30_W_r; wire [75:0] req_30_W_f;
    wire req_01_N_v, req_01_N_r; wire [75:0] req_01_N_f;
    wire req_01_E_v, req_01_E_r; wire [75:0] req_01_E_f;
    wire req_01_S_v, req_01_S_r; wire [75:0] req_01_S_f;
    wire req_11_N_v, req_11_N_r; wire [75:0] req_11_N_f;
    wire req_11_E_v, req_11_E_r; wire [75:0] req_11_E_f;
    wire req_11_S_v, req_11_S_r; wire [75:0] req_11_S_f;
    wire req_11_W_v, req_11_W_r; wire [75:0] req_11_W_f;
    wire req_21_N_v, req_21_N_r; wire [75:0] req_21_N_f;
    wire req_21_E_v, req_21_E_r; wire [75:0] req_21_E_f;
    wire req_21_S_v, req_21_S_r; wire [75:0] req_21_S_f;
    wire req_21_W_v, req_21_W_r; wire [75:0] req_21_W_f;
    wire req_31_N_v, req_31_N_r; wire [75:0] req_31_N_f;
    wire req_31_S_v, req_31_S_r; wire [75:0] req_31_S_f;
    wire req_31_W_v, req_31_W_r; wire [75:0] req_31_W_f;
    wire req_02_N_v, req_02_N_r; wire [75:0] req_02_N_f;
    wire req_02_E_v, req_02_E_r; wire [75:0] req_02_E_f;
    wire req_02_S_v, req_02_S_r; wire [75:0] req_02_S_f;
    wire req_12_N_v, req_12_N_r; wire [75:0] req_12_N_f;
    wire req_12_E_v, req_12_E_r; wire [75:0] req_12_E_f;
    wire req_12_S_v, req_12_S_r; wire [75:0] req_12_S_f;
    wire req_12_W_v, req_12_W_r; wire [75:0] req_12_W_f;
    wire req_22_N_v, req_22_N_r; wire [75:0] req_22_N_f;
    wire req_22_E_v, req_22_E_r; wire [75:0] req_22_E_f;
    wire req_22_S_v, req_22_S_r; wire [75:0] req_22_S_f;
    wire req_22_W_v, req_22_W_r; wire [75:0] req_22_W_f;
    wire req_32_N_v, req_32_N_r; wire [75:0] req_32_N_f;
    wire req_32_S_v, req_32_S_r; wire [75:0] req_32_S_f;
    wire req_32_W_v, req_32_W_r; wire [75:0] req_32_W_f;
    wire req_03_N_v, req_03_N_r; wire [75:0] req_03_N_f;
    wire req_03_E_v, req_03_E_r; wire [75:0] req_03_E_f;
    wire req_13_N_v, req_13_N_r; wire [75:0] req_13_N_f;
    wire req_13_E_v, req_13_E_r; wire [75:0] req_13_E_f;
    wire req_13_W_v, req_13_W_r; wire [75:0] req_13_W_f;
    wire req_23_N_v, req_23_N_r; wire [75:0] req_23_N_f;
    wire req_23_E_v, req_23_E_r; wire [75:0] req_23_E_f;
    wire req_23_W_v, req_23_W_r; wire [75:0] req_23_W_f;
    wire req_33_N_v, req_33_N_r; wire [75:0] req_33_N_f;
    wire req_33_W_v, req_33_W_r; wire [75:0] req_33_W_f;
    wire resp_00_E_v, resp_00_E_r; wire [35:0] resp_00_E_f;
    wire resp_00_S_v, resp_00_S_r; wire [35:0] resp_00_S_f;
    wire resp_10_E_v, resp_10_E_r; wire [35:0] resp_10_E_f;
    wire resp_10_S_v, resp_10_S_r; wire [35:0] resp_10_S_f;
    wire resp_10_W_v, resp_10_W_r; wire [35:0] resp_10_W_f;
    wire resp_20_E_v, resp_20_E_r; wire [35:0] resp_20_E_f;
    wire resp_20_S_v, resp_20_S_r; wire [35:0] resp_20_S_f;
    wire resp_20_W_v, resp_20_W_r; wire [35:0] resp_20_W_f;
    wire resp_30_S_v, resp_30_S_r; wire [35:0] resp_30_S_f;
    wire resp_30_W_v, resp_30_W_r; wire [35:0] resp_30_W_f;
    wire resp_01_N_v, resp_01_N_r; wire [35:0] resp_01_N_f;
    wire resp_01_E_v, resp_01_E_r; wire [35:0] resp_01_E_f;
    wire resp_01_S_v, resp_01_S_r; wire [35:0] resp_01_S_f;
    wire resp_11_N_v, resp_11_N_r; wire [35:0] resp_11_N_f;
    wire resp_11_E_v, resp_11_E_r; wire [35:0] resp_11_E_f;
    wire resp_11_S_v, resp_11_S_r; wire [35:0] resp_11_S_f;
    wire resp_11_W_v, resp_11_W_r; wire [35:0] resp_11_W_f;
    wire resp_21_N_v, resp_21_N_r; wire [35:0] resp_21_N_f;
    wire resp_21_E_v, resp_21_E_r; wire [35:0] resp_21_E_f;
    wire resp_21_S_v, resp_21_S_r; wire [35:0] resp_21_S_f;
    wire resp_21_W_v, resp_21_W_r; wire [35:0] resp_21_W_f;
    wire resp_31_N_v, resp_31_N_r; wire [35:0] resp_31_N_f;
    wire resp_31_S_v, resp_31_S_r; wire [35:0] resp_31_S_f;
    wire resp_31_W_v, resp_31_W_r; wire [35:0] resp_31_W_f;
    wire resp_02_N_v, resp_02_N_r; wire [35:0] resp_02_N_f;
    wire resp_02_E_v, resp_02_E_r; wire [35:0] resp_02_E_f;
    wire resp_02_S_v, resp_02_S_r; wire [35:0] resp_02_S_f;
    wire resp_12_N_v, resp_12_N_r; wire [35:0] resp_12_N_f;
    wire resp_12_E_v, resp_12_E_r; wire [35:0] resp_12_E_f;
    wire resp_12_S_v, resp_12_S_r; wire [35:0] resp_12_S_f;
    wire resp_12_W_v, resp_12_W_r; wire [35:0] resp_12_W_f;
    wire resp_22_N_v, resp_22_N_r; wire [35:0] resp_22_N_f;
    wire resp_22_E_v, resp_22_E_r; wire [35:0] resp_22_E_f;
    wire resp_22_S_v, resp_22_S_r; wire [35:0] resp_22_S_f;
    wire resp_22_W_v, resp_22_W_r; wire [35:0] resp_22_W_f;
    wire resp_32_N_v, resp_32_N_r; wire [35:0] resp_32_N_f;
    wire resp_32_S_v, resp_32_S_r; wire [35:0] resp_32_S_f;
    wire resp_32_W_v, resp_32_W_r; wire [35:0] resp_32_W_f;
    wire resp_03_N_v, resp_03_N_r; wire [35:0] resp_03_N_f;
    wire resp_03_E_v, resp_03_E_r; wire [35:0] resp_03_E_f;
    wire resp_13_N_v, resp_13_N_r; wire [35:0] resp_13_N_f;
    wire resp_13_E_v, resp_13_E_r; wire [35:0] resp_13_E_f;
    wire resp_13_W_v, resp_13_W_r; wire [35:0] resp_13_W_f;
    wire resp_23_N_v, resp_23_N_r; wire [35:0] resp_23_N_f;
    wire resp_23_E_v, resp_23_E_r; wire [35:0] resp_23_E_f;
    wire resp_23_W_v, resp_23_W_r; wire [35:0] resp_23_W_f;
    wire resp_33_N_v, resp_33_N_r; wire [35:0] resp_33_N_f;
    wire resp_33_W_v, resp_33_W_r; wire [35:0] resp_33_W_f;

    // ==================== Core bus + adapter wires ====================
    wire p0_bus_req, p0_bus_mem_write, p0_bus_mem_unsigned, p0_bus_grant;
    wire [31:0] p0_bus_addr, p0_bus_write_data, p0_bus_read_data;
    wire [1:0] p0_bus_mem_size;
    wire p0_req_out_valid, p0_req_out_ready, p0_resp_in_valid, p0_resp_in_ready;
    wire [75:0] p0_req_out_flit;
    wire [35:0] p0_resp_in_flit;
    wire p1_bus_req, p1_bus_mem_write, p1_bus_mem_unsigned, p1_bus_grant;
    wire [31:0] p1_bus_addr, p1_bus_write_data, p1_bus_read_data;
    wire [1:0] p1_bus_mem_size;
    wire p1_req_out_valid, p1_req_out_ready, p1_resp_in_valid, p1_resp_in_ready;
    wire [75:0] p1_req_out_flit;
    wire [35:0] p1_resp_in_flit;
    wire p2_bus_req, p2_bus_mem_write, p2_bus_mem_unsigned, p2_bus_grant;
    wire [31:0] p2_bus_addr, p2_bus_write_data, p2_bus_read_data;
    wire [1:0] p2_bus_mem_size;
    wire p2_req_out_valid, p2_req_out_ready, p2_resp_in_valid, p2_resp_in_ready;
    wire [75:0] p2_req_out_flit;
    wire [35:0] p2_resp_in_flit;
    wire p3_bus_req, p3_bus_mem_write, p3_bus_mem_unsigned, p3_bus_grant;
    wire [31:0] p3_bus_addr, p3_bus_write_data, p3_bus_read_data;
    wire [1:0] p3_bus_mem_size;
    wire p3_req_out_valid, p3_req_out_ready, p3_resp_in_valid, p3_resp_in_ready;
    wire [75:0] p3_req_out_flit;
    wire [35:0] p3_resp_in_flit;
    wire p4_bus_req, p4_bus_mem_write, p4_bus_mem_unsigned, p4_bus_grant;
    wire [31:0] p4_bus_addr, p4_bus_write_data, p4_bus_read_data;
    wire [1:0] p4_bus_mem_size;
    wire p4_req_out_valid, p4_req_out_ready, p4_resp_in_valid, p4_resp_in_ready;
    wire [75:0] p4_req_out_flit;
    wire [35:0] p4_resp_in_flit;
    wire p5_bus_req, p5_bus_mem_write, p5_bus_mem_unsigned, p5_bus_grant;
    wire [31:0] p5_bus_addr, p5_bus_write_data, p5_bus_read_data;
    wire [1:0] p5_bus_mem_size;
    wire p5_req_out_valid, p5_req_out_ready, p5_resp_in_valid, p5_resp_in_ready;
    wire [75:0] p5_req_out_flit;
    wire [35:0] p5_resp_in_flit;
    wire e0_bus_req, e0_bus_mem_write, e0_bus_mem_unsigned, e0_bus_grant;
    wire [31:0] e0_bus_addr, e0_bus_write_data, e0_bus_read_data;
    wire [1:0] e0_bus_mem_size;
    wire e0_req_out_valid, e0_req_out_ready, e0_resp_in_valid, e0_resp_in_ready;
    wire [75:0] e0_req_out_flit;
    wire [35:0] e0_resp_in_flit;
    wire e1_bus_req, e1_bus_mem_write, e1_bus_mem_unsigned, e1_bus_grant;
    wire [31:0] e1_bus_addr, e1_bus_write_data, e1_bus_read_data;
    wire [1:0] e1_bus_mem_size;
    wire e1_req_out_valid, e1_req_out_ready, e1_resp_in_valid, e1_resp_in_ready;
    wire [75:0] e1_req_out_flit;
    wire [35:0] e1_resp_in_flit;
    wire e2_bus_req, e2_bus_mem_write, e2_bus_mem_unsigned, e2_bus_grant;
    wire [31:0] e2_bus_addr, e2_bus_write_data, e2_bus_read_data;
    wire [1:0] e2_bus_mem_size;
    wire e2_req_out_valid, e2_req_out_ready, e2_resp_in_valid, e2_resp_in_ready;
    wire [75:0] e2_req_out_flit;
    wire [35:0] e2_resp_in_flit;
    wire e3_bus_req, e3_bus_mem_write, e3_bus_mem_unsigned, e3_bus_grant;
    wire [31:0] e3_bus_addr, e3_bus_write_data, e3_bus_read_data;
    wire [1:0] e3_bus_mem_size;
    wire e3_req_out_valid, e3_req_out_ready, e3_resp_in_valid, e3_resp_in_ready;
    wire [75:0] e3_req_out_flit;
    wire [35:0] e3_resp_in_flit;
    wire e4_bus_req, e4_bus_mem_write, e4_bus_mem_unsigned, e4_bus_grant;
    wire [31:0] e4_bus_addr, e4_bus_write_data, e4_bus_read_data;
    wire [1:0] e4_bus_mem_size;
    wire e4_req_out_valid, e4_req_out_ready, e4_resp_in_valid, e4_resp_in_ready;
    wire [75:0] e4_req_out_flit;
    wire [35:0] e4_resp_in_flit;
    wire e5_bus_req, e5_bus_mem_write, e5_bus_mem_unsigned, e5_bus_grant;
    wire [31:0] e5_bus_addr, e5_bus_write_data, e5_bus_read_data;
    wire [1:0] e5_bus_mem_size;
    wire e5_req_out_valid, e5_req_out_ready, e5_resp_in_valid, e5_resp_in_ready;
    wire [75:0] e5_req_out_flit;
    wire [35:0] e5_resp_in_flit;
    wire mem_req_in_valid, mem_req_in_ready, mem_resp_out_valid, mem_resp_out_ready;
    wire [75:0] mem_req_in_flit;
    wire [35:0] mem_resp_out_flit;

    // ==================== Routers (2 networks x 16 grid positions) ====================
    router #(.FLIT_WIDTH(76), .MY_X(0), .MY_Y(0)) req_r00 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({76{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_10_W_v), .e_in_flit(req_10_W_f), .e_in_ready(req_10_W_r),
        .e_out_valid(req_00_E_v), .e_out_flit(req_00_E_f), .e_out_ready(req_00_E_r),
        .s_in_valid(req_01_N_v), .s_in_flit(req_01_N_f), .s_in_ready(req_01_N_r),
        .s_out_valid(req_00_S_v), .s_out_flit(req_00_S_f), .s_out_ready(req_00_S_r),
        .w_in_valid(1'b0), .w_in_flit({76{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(p0_req_out_valid), .l_in_flit(p0_req_out_flit), .l_in_ready(p0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(0), .MY_Y(0)) resp_r00 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({36{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_10_W_v), .e_in_flit(resp_10_W_f), .e_in_ready(resp_10_W_r),
        .e_out_valid(resp_00_E_v), .e_out_flit(resp_00_E_f), .e_out_ready(resp_00_E_r),
        .s_in_valid(resp_01_N_v), .s_in_flit(resp_01_N_f), .s_in_ready(resp_01_N_r),
        .s_out_valid(resp_00_S_v), .s_out_flit(resp_00_S_f), .s_out_ready(resp_00_S_r),
        .w_in_valid(1'b0), .w_in_flit({36{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(p0_resp_in_valid), .l_out_flit(p0_resp_in_flit), .l_out_ready(p0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(1), .MY_Y(0)) req_r10 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({76{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_20_W_v), .e_in_flit(req_20_W_f), .e_in_ready(req_20_W_r),
        .e_out_valid(req_10_E_v), .e_out_flit(req_10_E_f), .e_out_ready(req_10_E_r),
        .s_in_valid(req_11_N_v), .s_in_flit(req_11_N_f), .s_in_ready(req_11_N_r),
        .s_out_valid(req_10_S_v), .s_out_flit(req_10_S_f), .s_out_ready(req_10_S_r),
        .w_in_valid(req_00_E_v), .w_in_flit(req_00_E_f), .w_in_ready(req_00_E_r),
        .w_out_valid(req_10_W_v), .w_out_flit(req_10_W_f), .w_out_ready(req_10_W_r),
        .l_in_valid(p4_req_out_valid), .l_in_flit(p4_req_out_flit), .l_in_ready(p4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(1), .MY_Y(0)) resp_r10 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({36{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_20_W_v), .e_in_flit(resp_20_W_f), .e_in_ready(resp_20_W_r),
        .e_out_valid(resp_10_E_v), .e_out_flit(resp_10_E_f), .e_out_ready(resp_10_E_r),
        .s_in_valid(resp_11_N_v), .s_in_flit(resp_11_N_f), .s_in_ready(resp_11_N_r),
        .s_out_valid(resp_10_S_v), .s_out_flit(resp_10_S_f), .s_out_ready(resp_10_S_r),
        .w_in_valid(resp_00_E_v), .w_in_flit(resp_00_E_f), .w_in_ready(resp_00_E_r),
        .w_out_valid(resp_10_W_v), .w_out_flit(resp_10_W_f), .w_out_ready(resp_10_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(p4_resp_in_valid), .l_out_flit(p4_resp_in_flit), .l_out_ready(p4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(2), .MY_Y(0)) req_r20 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({76{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_30_W_v), .e_in_flit(req_30_W_f), .e_in_ready(req_30_W_r),
        .e_out_valid(req_20_E_v), .e_out_flit(req_20_E_f), .e_out_ready(req_20_E_r),
        .s_in_valid(req_21_N_v), .s_in_flit(req_21_N_f), .s_in_ready(req_21_N_r),
        .s_out_valid(req_20_S_v), .s_out_flit(req_20_S_f), .s_out_ready(req_20_S_r),
        .w_in_valid(req_10_E_v), .w_in_flit(req_10_E_f), .w_in_ready(req_10_E_r),
        .w_out_valid(req_20_W_v), .w_out_flit(req_20_W_f), .w_out_ready(req_20_W_r),
        .l_in_valid(e1_req_out_valid), .l_in_flit(e1_req_out_flit), .l_in_ready(e1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(2), .MY_Y(0)) resp_r20 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({36{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_30_W_v), .e_in_flit(resp_30_W_f), .e_in_ready(resp_30_W_r),
        .e_out_valid(resp_20_E_v), .e_out_flit(resp_20_E_f), .e_out_ready(resp_20_E_r),
        .s_in_valid(resp_21_N_v), .s_in_flit(resp_21_N_f), .s_in_ready(resp_21_N_r),
        .s_out_valid(resp_20_S_v), .s_out_flit(resp_20_S_f), .s_out_ready(resp_20_S_r),
        .w_in_valid(resp_10_E_v), .w_in_flit(resp_10_E_f), .w_in_ready(resp_10_E_r),
        .w_out_valid(resp_20_W_v), .w_out_flit(resp_20_W_f), .w_out_ready(resp_20_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(e1_resp_in_valid), .l_out_flit(e1_resp_in_flit), .l_out_ready(e1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(3), .MY_Y(0)) req_r30 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({76{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({76{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_31_N_v), .s_in_flit(req_31_N_f), .s_in_ready(req_31_N_r),
        .s_out_valid(req_30_S_v), .s_out_flit(req_30_S_f), .s_out_ready(req_30_S_r),
        .w_in_valid(req_20_E_v), .w_in_flit(req_20_E_f), .w_in_ready(req_20_E_r),
        .w_out_valid(req_30_W_v), .w_out_flit(req_30_W_f), .w_out_ready(req_30_W_r),
        .l_in_valid(e5_req_out_valid), .l_in_flit(e5_req_out_flit), .l_in_ready(e5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(3), .MY_Y(0)) resp_r30 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({36{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({36{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_31_N_v), .s_in_flit(resp_31_N_f), .s_in_ready(resp_31_N_r),
        .s_out_valid(resp_30_S_v), .s_out_flit(resp_30_S_f), .s_out_ready(resp_30_S_r),
        .w_in_valid(resp_20_E_v), .w_in_flit(resp_20_E_f), .w_in_ready(resp_20_E_r),
        .w_out_valid(resp_30_W_v), .w_out_flit(resp_30_W_f), .w_out_ready(resp_30_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(e5_resp_in_valid), .l_out_flit(e5_resp_in_flit), .l_out_ready(e5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(0), .MY_Y(1)) req_r01 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_00_S_v), .n_in_flit(req_00_S_f), .n_in_ready(req_00_S_r),
        .n_out_valid(req_01_N_v), .n_out_flit(req_01_N_f), .n_out_ready(req_01_N_r),
        .e_in_valid(req_11_W_v), .e_in_flit(req_11_W_f), .e_in_ready(req_11_W_r),
        .e_out_valid(req_01_E_v), .e_out_flit(req_01_E_f), .e_out_ready(req_01_E_r),
        .s_in_valid(req_02_N_v), .s_in_flit(req_02_N_f), .s_in_ready(req_02_N_r),
        .s_out_valid(req_01_S_v), .s_out_flit(req_01_S_f), .s_out_ready(req_01_S_r),
        .w_in_valid(1'b0), .w_in_flit({76{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(p1_req_out_valid), .l_in_flit(p1_req_out_flit), .l_in_ready(p1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(0), .MY_Y(1)) resp_r01 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_00_S_v), .n_in_flit(resp_00_S_f), .n_in_ready(resp_00_S_r),
        .n_out_valid(resp_01_N_v), .n_out_flit(resp_01_N_f), .n_out_ready(resp_01_N_r),
        .e_in_valid(resp_11_W_v), .e_in_flit(resp_11_W_f), .e_in_ready(resp_11_W_r),
        .e_out_valid(resp_01_E_v), .e_out_flit(resp_01_E_f), .e_out_ready(resp_01_E_r),
        .s_in_valid(resp_02_N_v), .s_in_flit(resp_02_N_f), .s_in_ready(resp_02_N_r),
        .s_out_valid(resp_01_S_v), .s_out_flit(resp_01_S_f), .s_out_ready(resp_01_S_r),
        .w_in_valid(1'b0), .w_in_flit({36{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(p1_resp_in_valid), .l_out_flit(p1_resp_in_flit), .l_out_ready(p1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(1), .MY_Y(1)) req_r11 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_10_S_v), .n_in_flit(req_10_S_f), .n_in_ready(req_10_S_r),
        .n_out_valid(req_11_N_v), .n_out_flit(req_11_N_f), .n_out_ready(req_11_N_r),
        .e_in_valid(req_21_W_v), .e_in_flit(req_21_W_f), .e_in_ready(req_21_W_r),
        .e_out_valid(req_11_E_v), .e_out_flit(req_11_E_f), .e_out_ready(req_11_E_r),
        .s_in_valid(req_12_N_v), .s_in_flit(req_12_N_f), .s_in_ready(req_12_N_r),
        .s_out_valid(req_11_S_v), .s_out_flit(req_11_S_f), .s_out_ready(req_11_S_r),
        .w_in_valid(req_01_E_v), .w_in_flit(req_01_E_f), .w_in_ready(req_01_E_r),
        .w_out_valid(req_11_W_v), .w_out_flit(req_11_W_f), .w_out_ready(req_11_W_r),
        .l_in_valid(1'b0), .l_in_flit({76{1'b0}}), .l_in_ready(),
        .l_out_valid(mem_req_in_valid), .l_out_flit(mem_req_in_flit), .l_out_ready(mem_req_in_ready)
    );

    router #(.FLIT_WIDTH(36), .MY_X(1), .MY_Y(1)) resp_r11 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_10_S_v), .n_in_flit(resp_10_S_f), .n_in_ready(resp_10_S_r),
        .n_out_valid(resp_11_N_v), .n_out_flit(resp_11_N_f), .n_out_ready(resp_11_N_r),
        .e_in_valid(resp_21_W_v), .e_in_flit(resp_21_W_f), .e_in_ready(resp_21_W_r),
        .e_out_valid(resp_11_E_v), .e_out_flit(resp_11_E_f), .e_out_ready(resp_11_E_r),
        .s_in_valid(resp_12_N_v), .s_in_flit(resp_12_N_f), .s_in_ready(resp_12_N_r),
        .s_out_valid(resp_11_S_v), .s_out_flit(resp_11_S_f), .s_out_ready(resp_11_S_r),
        .w_in_valid(resp_01_E_v), .w_in_flit(resp_01_E_f), .w_in_ready(resp_01_E_r),
        .w_out_valid(resp_11_W_v), .w_out_flit(resp_11_W_f), .w_out_ready(resp_11_W_r),
        .l_in_valid(mem_resp_out_valid), .l_in_flit(mem_resp_out_flit), .l_in_ready(mem_resp_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(76), .MY_X(2), .MY_Y(1)) req_r21 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_20_S_v), .n_in_flit(req_20_S_f), .n_in_ready(req_20_S_r),
        .n_out_valid(req_21_N_v), .n_out_flit(req_21_N_f), .n_out_ready(req_21_N_r),
        .e_in_valid(req_31_W_v), .e_in_flit(req_31_W_f), .e_in_ready(req_31_W_r),
        .e_out_valid(req_21_E_v), .e_out_flit(req_21_E_f), .e_out_ready(req_21_E_r),
        .s_in_valid(req_22_N_v), .s_in_flit(req_22_N_f), .s_in_ready(req_22_N_r),
        .s_out_valid(req_21_S_v), .s_out_flit(req_21_S_f), .s_out_ready(req_21_S_r),
        .w_in_valid(req_11_E_v), .w_in_flit(req_11_E_f), .w_in_ready(req_11_E_r),
        .w_out_valid(req_21_W_v), .w_out_flit(req_21_W_f), .w_out_ready(req_21_W_r),
        .l_in_valid(e2_req_out_valid), .l_in_flit(e2_req_out_flit), .l_in_ready(e2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(2), .MY_Y(1)) resp_r21 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_20_S_v), .n_in_flit(resp_20_S_f), .n_in_ready(resp_20_S_r),
        .n_out_valid(resp_21_N_v), .n_out_flit(resp_21_N_f), .n_out_ready(resp_21_N_r),
        .e_in_valid(resp_31_W_v), .e_in_flit(resp_31_W_f), .e_in_ready(resp_31_W_r),
        .e_out_valid(resp_21_E_v), .e_out_flit(resp_21_E_f), .e_out_ready(resp_21_E_r),
        .s_in_valid(resp_22_N_v), .s_in_flit(resp_22_N_f), .s_in_ready(resp_22_N_r),
        .s_out_valid(resp_21_S_v), .s_out_flit(resp_21_S_f), .s_out_ready(resp_21_S_r),
        .w_in_valid(resp_11_E_v), .w_in_flit(resp_11_E_f), .w_in_ready(resp_11_E_r),
        .w_out_valid(resp_21_W_v), .w_out_flit(resp_21_W_f), .w_out_ready(resp_21_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(e2_resp_in_valid), .l_out_flit(e2_resp_in_flit), .l_out_ready(e2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(3), .MY_Y(1)) req_r31 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_30_S_v), .n_in_flit(req_30_S_f), .n_in_ready(req_30_S_r),
        .n_out_valid(req_31_N_v), .n_out_flit(req_31_N_f), .n_out_ready(req_31_N_r),
        .e_in_valid(1'b0), .e_in_flit({76{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_32_N_v), .s_in_flit(req_32_N_f), .s_in_ready(req_32_N_r),
        .s_out_valid(req_31_S_v), .s_out_flit(req_31_S_f), .s_out_ready(req_31_S_r),
        .w_in_valid(req_21_E_v), .w_in_flit(req_21_E_f), .w_in_ready(req_21_E_r),
        .w_out_valid(req_31_W_v), .w_out_flit(req_31_W_f), .w_out_ready(req_31_W_r),
        .l_in_valid(1'b0), .l_in_flit({76{1'b0}}), .l_in_ready(),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(3), .MY_Y(1)) resp_r31 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_30_S_v), .n_in_flit(resp_30_S_f), .n_in_ready(resp_30_S_r),
        .n_out_valid(resp_31_N_v), .n_out_flit(resp_31_N_f), .n_out_ready(resp_31_N_r),
        .e_in_valid(1'b0), .e_in_flit({36{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_32_N_v), .s_in_flit(resp_32_N_f), .s_in_ready(resp_32_N_r),
        .s_out_valid(resp_31_S_v), .s_out_flit(resp_31_S_f), .s_out_ready(resp_31_S_r),
        .w_in_valid(resp_21_E_v), .w_in_flit(resp_21_E_f), .w_in_ready(resp_21_E_r),
        .w_out_valid(resp_31_W_v), .w_out_flit(resp_31_W_f), .w_out_ready(resp_31_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(76), .MY_X(0), .MY_Y(2)) req_r02 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_01_S_v), .n_in_flit(req_01_S_f), .n_in_ready(req_01_S_r),
        .n_out_valid(req_02_N_v), .n_out_flit(req_02_N_f), .n_out_ready(req_02_N_r),
        .e_in_valid(req_12_W_v), .e_in_flit(req_12_W_f), .e_in_ready(req_12_W_r),
        .e_out_valid(req_02_E_v), .e_out_flit(req_02_E_f), .e_out_ready(req_02_E_r),
        .s_in_valid(req_03_N_v), .s_in_flit(req_03_N_f), .s_in_ready(req_03_N_r),
        .s_out_valid(req_02_S_v), .s_out_flit(req_02_S_f), .s_out_ready(req_02_S_r),
        .w_in_valid(1'b0), .w_in_flit({76{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(p2_req_out_valid), .l_in_flit(p2_req_out_flit), .l_in_ready(p2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(0), .MY_Y(2)) resp_r02 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_01_S_v), .n_in_flit(resp_01_S_f), .n_in_ready(resp_01_S_r),
        .n_out_valid(resp_02_N_v), .n_out_flit(resp_02_N_f), .n_out_ready(resp_02_N_r),
        .e_in_valid(resp_12_W_v), .e_in_flit(resp_12_W_f), .e_in_ready(resp_12_W_r),
        .e_out_valid(resp_02_E_v), .e_out_flit(resp_02_E_f), .e_out_ready(resp_02_E_r),
        .s_in_valid(resp_03_N_v), .s_in_flit(resp_03_N_f), .s_in_ready(resp_03_N_r),
        .s_out_valid(resp_02_S_v), .s_out_flit(resp_02_S_f), .s_out_ready(resp_02_S_r),
        .w_in_valid(1'b0), .w_in_flit({36{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(p2_resp_in_valid), .l_out_flit(p2_resp_in_flit), .l_out_ready(p2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(1), .MY_Y(2)) req_r12 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_11_S_v), .n_in_flit(req_11_S_f), .n_in_ready(req_11_S_r),
        .n_out_valid(req_12_N_v), .n_out_flit(req_12_N_f), .n_out_ready(req_12_N_r),
        .e_in_valid(req_22_W_v), .e_in_flit(req_22_W_f), .e_in_ready(req_22_W_r),
        .e_out_valid(req_12_E_v), .e_out_flit(req_12_E_f), .e_out_ready(req_12_E_r),
        .s_in_valid(req_13_N_v), .s_in_flit(req_13_N_f), .s_in_ready(req_13_N_r),
        .s_out_valid(req_12_S_v), .s_out_flit(req_12_S_f), .s_out_ready(req_12_S_r),
        .w_in_valid(req_02_E_v), .w_in_flit(req_02_E_f), .w_in_ready(req_02_E_r),
        .w_out_valid(req_12_W_v), .w_out_flit(req_12_W_f), .w_out_ready(req_12_W_r),
        .l_in_valid(p5_req_out_valid), .l_in_flit(p5_req_out_flit), .l_in_ready(p5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(1), .MY_Y(2)) resp_r12 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_11_S_v), .n_in_flit(resp_11_S_f), .n_in_ready(resp_11_S_r),
        .n_out_valid(resp_12_N_v), .n_out_flit(resp_12_N_f), .n_out_ready(resp_12_N_r),
        .e_in_valid(resp_22_W_v), .e_in_flit(resp_22_W_f), .e_in_ready(resp_22_W_r),
        .e_out_valid(resp_12_E_v), .e_out_flit(resp_12_E_f), .e_out_ready(resp_12_E_r),
        .s_in_valid(resp_13_N_v), .s_in_flit(resp_13_N_f), .s_in_ready(resp_13_N_r),
        .s_out_valid(resp_12_S_v), .s_out_flit(resp_12_S_f), .s_out_ready(resp_12_S_r),
        .w_in_valid(resp_02_E_v), .w_in_flit(resp_02_E_f), .w_in_ready(resp_02_E_r),
        .w_out_valid(resp_12_W_v), .w_out_flit(resp_12_W_f), .w_out_ready(resp_12_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(p5_resp_in_valid), .l_out_flit(p5_resp_in_flit), .l_out_ready(p5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(2), .MY_Y(2)) req_r22 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_21_S_v), .n_in_flit(req_21_S_f), .n_in_ready(req_21_S_r),
        .n_out_valid(req_22_N_v), .n_out_flit(req_22_N_f), .n_out_ready(req_22_N_r),
        .e_in_valid(req_32_W_v), .e_in_flit(req_32_W_f), .e_in_ready(req_32_W_r),
        .e_out_valid(req_22_E_v), .e_out_flit(req_22_E_f), .e_out_ready(req_22_E_r),
        .s_in_valid(req_23_N_v), .s_in_flit(req_23_N_f), .s_in_ready(req_23_N_r),
        .s_out_valid(req_22_S_v), .s_out_flit(req_22_S_f), .s_out_ready(req_22_S_r),
        .w_in_valid(req_12_E_v), .w_in_flit(req_12_E_f), .w_in_ready(req_12_E_r),
        .w_out_valid(req_22_W_v), .w_out_flit(req_22_W_f), .w_out_ready(req_22_W_r),
        .l_in_valid(e3_req_out_valid), .l_in_flit(e3_req_out_flit), .l_in_ready(e3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(2), .MY_Y(2)) resp_r22 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_21_S_v), .n_in_flit(resp_21_S_f), .n_in_ready(resp_21_S_r),
        .n_out_valid(resp_22_N_v), .n_out_flit(resp_22_N_f), .n_out_ready(resp_22_N_r),
        .e_in_valid(resp_32_W_v), .e_in_flit(resp_32_W_f), .e_in_ready(resp_32_W_r),
        .e_out_valid(resp_22_E_v), .e_out_flit(resp_22_E_f), .e_out_ready(resp_22_E_r),
        .s_in_valid(resp_23_N_v), .s_in_flit(resp_23_N_f), .s_in_ready(resp_23_N_r),
        .s_out_valid(resp_22_S_v), .s_out_flit(resp_22_S_f), .s_out_ready(resp_22_S_r),
        .w_in_valid(resp_12_E_v), .w_in_flit(resp_12_E_f), .w_in_ready(resp_12_E_r),
        .w_out_valid(resp_22_W_v), .w_out_flit(resp_22_W_f), .w_out_ready(resp_22_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(e3_resp_in_valid), .l_out_flit(e3_resp_in_flit), .l_out_ready(e3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(3), .MY_Y(2)) req_r32 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_31_S_v), .n_in_flit(req_31_S_f), .n_in_ready(req_31_S_r),
        .n_out_valid(req_32_N_v), .n_out_flit(req_32_N_f), .n_out_ready(req_32_N_r),
        .e_in_valid(1'b0), .e_in_flit({76{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_33_N_v), .s_in_flit(req_33_N_f), .s_in_ready(req_33_N_r),
        .s_out_valid(req_32_S_v), .s_out_flit(req_32_S_f), .s_out_ready(req_32_S_r),
        .w_in_valid(req_22_E_v), .w_in_flit(req_22_E_f), .w_in_ready(req_22_E_r),
        .w_out_valid(req_32_W_v), .w_out_flit(req_32_W_f), .w_out_ready(req_32_W_r),
        .l_in_valid(1'b0), .l_in_flit({76{1'b0}}), .l_in_ready(),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(3), .MY_Y(2)) resp_r32 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_31_S_v), .n_in_flit(resp_31_S_f), .n_in_ready(resp_31_S_r),
        .n_out_valid(resp_32_N_v), .n_out_flit(resp_32_N_f), .n_out_ready(resp_32_N_r),
        .e_in_valid(1'b0), .e_in_flit({36{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_33_N_v), .s_in_flit(resp_33_N_f), .s_in_ready(resp_33_N_r),
        .s_out_valid(resp_32_S_v), .s_out_flit(resp_32_S_f), .s_out_ready(resp_32_S_r),
        .w_in_valid(resp_22_E_v), .w_in_flit(resp_22_E_f), .w_in_ready(resp_22_E_r),
        .w_out_valid(resp_32_W_v), .w_out_flit(resp_32_W_f), .w_out_ready(resp_32_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(76), .MY_X(0), .MY_Y(3)) req_r03 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_02_S_v), .n_in_flit(req_02_S_f), .n_in_ready(req_02_S_r),
        .n_out_valid(req_03_N_v), .n_out_flit(req_03_N_f), .n_out_ready(req_03_N_r),
        .e_in_valid(req_13_W_v), .e_in_flit(req_13_W_f), .e_in_ready(req_13_W_r),
        .e_out_valid(req_03_E_v), .e_out_flit(req_03_E_f), .e_out_ready(req_03_E_r),
        .s_in_valid(1'b0), .s_in_flit({76{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({76{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(p3_req_out_valid), .l_in_flit(p3_req_out_flit), .l_in_ready(p3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(0), .MY_Y(3)) resp_r03 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_02_S_v), .n_in_flit(resp_02_S_f), .n_in_ready(resp_02_S_r),
        .n_out_valid(resp_03_N_v), .n_out_flit(resp_03_N_f), .n_out_ready(resp_03_N_r),
        .e_in_valid(resp_13_W_v), .e_in_flit(resp_13_W_f), .e_in_ready(resp_13_W_r),
        .e_out_valid(resp_03_E_v), .e_out_flit(resp_03_E_f), .e_out_ready(resp_03_E_r),
        .s_in_valid(1'b0), .s_in_flit({36{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({36{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(p3_resp_in_valid), .l_out_flit(p3_resp_in_flit), .l_out_ready(p3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(1), .MY_Y(3)) req_r13 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_12_S_v), .n_in_flit(req_12_S_f), .n_in_ready(req_12_S_r),
        .n_out_valid(req_13_N_v), .n_out_flit(req_13_N_f), .n_out_ready(req_13_N_r),
        .e_in_valid(req_23_W_v), .e_in_flit(req_23_W_f), .e_in_ready(req_23_W_r),
        .e_out_valid(req_13_E_v), .e_out_flit(req_13_E_f), .e_out_ready(req_13_E_r),
        .s_in_valid(1'b0), .s_in_flit({76{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_03_E_v), .w_in_flit(req_03_E_f), .w_in_ready(req_03_E_r),
        .w_out_valid(req_13_W_v), .w_out_flit(req_13_W_f), .w_out_ready(req_13_W_r),
        .l_in_valid(e0_req_out_valid), .l_in_flit(e0_req_out_flit), .l_in_ready(e0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(1), .MY_Y(3)) resp_r13 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_12_S_v), .n_in_flit(resp_12_S_f), .n_in_ready(resp_12_S_r),
        .n_out_valid(resp_13_N_v), .n_out_flit(resp_13_N_f), .n_out_ready(resp_13_N_r),
        .e_in_valid(resp_23_W_v), .e_in_flit(resp_23_W_f), .e_in_ready(resp_23_W_r),
        .e_out_valid(resp_13_E_v), .e_out_flit(resp_13_E_f), .e_out_ready(resp_13_E_r),
        .s_in_valid(1'b0), .s_in_flit({36{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_03_E_v), .w_in_flit(resp_03_E_f), .w_in_ready(resp_03_E_r),
        .w_out_valid(resp_13_W_v), .w_out_flit(resp_13_W_f), .w_out_ready(resp_13_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(e0_resp_in_valid), .l_out_flit(e0_resp_in_flit), .l_out_ready(e0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(2), .MY_Y(3)) req_r23 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_22_S_v), .n_in_flit(req_22_S_f), .n_in_ready(req_22_S_r),
        .n_out_valid(req_23_N_v), .n_out_flit(req_23_N_f), .n_out_ready(req_23_N_r),
        .e_in_valid(req_33_W_v), .e_in_flit(req_33_W_f), .e_in_ready(req_33_W_r),
        .e_out_valid(req_23_E_v), .e_out_flit(req_23_E_f), .e_out_ready(req_23_E_r),
        .s_in_valid(1'b0), .s_in_flit({76{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_13_E_v), .w_in_flit(req_13_E_f), .w_in_ready(req_13_E_r),
        .w_out_valid(req_23_W_v), .w_out_flit(req_23_W_f), .w_out_ready(req_23_W_r),
        .l_in_valid(e4_req_out_valid), .l_in_flit(e4_req_out_flit), .l_in_ready(e4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(2), .MY_Y(3)) resp_r23 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_22_S_v), .n_in_flit(resp_22_S_f), .n_in_ready(resp_22_S_r),
        .n_out_valid(resp_23_N_v), .n_out_flit(resp_23_N_f), .n_out_ready(resp_23_N_r),
        .e_in_valid(resp_33_W_v), .e_in_flit(resp_33_W_f), .e_in_ready(resp_33_W_r),
        .e_out_valid(resp_23_E_v), .e_out_flit(resp_23_E_f), .e_out_ready(resp_23_E_r),
        .s_in_valid(1'b0), .s_in_flit({36{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_13_E_v), .w_in_flit(resp_13_E_f), .w_in_ready(resp_13_E_r),
        .w_out_valid(resp_23_W_v), .w_out_flit(resp_23_W_f), .w_out_ready(resp_23_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(e4_resp_in_valid), .l_out_flit(e4_resp_in_flit), .l_out_ready(e4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(76), .MY_X(3), .MY_Y(3)) req_r33 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_32_S_v), .n_in_flit(req_32_S_f), .n_in_ready(req_32_S_r),
        .n_out_valid(req_33_N_v), .n_out_flit(req_33_N_f), .n_out_ready(req_33_N_r),
        .e_in_valid(1'b0), .e_in_flit({76{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({76{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_23_E_v), .w_in_flit(req_23_E_f), .w_in_ready(req_23_E_r),
        .w_out_valid(req_33_W_v), .w_out_flit(req_33_W_f), .w_out_ready(req_33_W_r),
        .l_in_valid(1'b0), .l_in_flit({76{1'b0}}), .l_in_ready(),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(36), .MY_X(3), .MY_Y(3)) resp_r33 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_32_S_v), .n_in_flit(resp_32_S_f), .n_in_ready(resp_32_S_r),
        .n_out_valid(resp_33_N_v), .n_out_flit(resp_33_N_f), .n_out_ready(resp_33_N_r),
        .e_in_valid(1'b0), .e_in_flit({36{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({36{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_23_E_v), .w_in_flit(resp_23_E_f), .w_in_ready(resp_23_E_r),
        .w_out_valid(resp_33_W_v), .w_out_flit(resp_33_W_f), .w_out_ready(resp_33_W_r),
        .l_in_valid(1'b0), .l_in_flit({36{1'b0}}), .l_in_ready(),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    // ==================== Cores + adapters ====================
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
        .bus_grant(p0_bus_grant), .bus_read_data(p0_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(0), .MY_Y(0), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) p0_adap (
        .clk(clk), .reset(reset),
        .bus_req(p0_bus_req), .bus_addr(p0_bus_addr), .bus_write_data(p0_bus_write_data),
        .bus_mem_write(p0_bus_mem_write), .bus_mem_size(p0_bus_mem_size), .bus_mem_unsigned(p0_bus_mem_unsigned),
        .bus_grant(p0_bus_grant), .bus_read_data(p0_bus_read_data),
        .req_out_valid(p0_req_out_valid), .req_out_flit(p0_req_out_flit), .req_out_ready(p0_req_out_ready),
        .resp_in_valid(p0_resp_in_valid), .resp_in_flit(p0_resp_in_flit), .resp_in_ready(p0_resp_in_ready)
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
        .bus_grant(p1_bus_grant), .bus_read_data(p1_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(0), .MY_Y(1), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) p1_adap (
        .clk(clk), .reset(reset),
        .bus_req(p1_bus_req), .bus_addr(p1_bus_addr), .bus_write_data(p1_bus_write_data),
        .bus_mem_write(p1_bus_mem_write), .bus_mem_size(p1_bus_mem_size), .bus_mem_unsigned(p1_bus_mem_unsigned),
        .bus_grant(p1_bus_grant), .bus_read_data(p1_bus_read_data),
        .req_out_valid(p1_req_out_valid), .req_out_flit(p1_req_out_flit), .req_out_ready(p1_req_out_ready),
        .resp_in_valid(p1_resp_in_valid), .resp_in_flit(p1_resp_in_flit), .resp_in_ready(p1_resp_in_ready)
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
        .bus_grant(p2_bus_grant), .bus_read_data(p2_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(0), .MY_Y(2), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) p2_adap (
        .clk(clk), .reset(reset),
        .bus_req(p2_bus_req), .bus_addr(p2_bus_addr), .bus_write_data(p2_bus_write_data),
        .bus_mem_write(p2_bus_mem_write), .bus_mem_size(p2_bus_mem_size), .bus_mem_unsigned(p2_bus_mem_unsigned),
        .bus_grant(p2_bus_grant), .bus_read_data(p2_bus_read_data),
        .req_out_valid(p2_req_out_valid), .req_out_flit(p2_req_out_flit), .req_out_ready(p2_req_out_ready),
        .resp_in_valid(p2_resp_in_valid), .resp_in_flit(p2_resp_in_flit), .resp_in_ready(p2_resp_in_ready)
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
        .bus_grant(p3_bus_grant), .bus_read_data(p3_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(0), .MY_Y(3), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) p3_adap (
        .clk(clk), .reset(reset),
        .bus_req(p3_bus_req), .bus_addr(p3_bus_addr), .bus_write_data(p3_bus_write_data),
        .bus_mem_write(p3_bus_mem_write), .bus_mem_size(p3_bus_mem_size), .bus_mem_unsigned(p3_bus_mem_unsigned),
        .bus_grant(p3_bus_grant), .bus_read_data(p3_bus_read_data),
        .req_out_valid(p3_req_out_valid), .req_out_flit(p3_req_out_flit), .req_out_ready(p3_req_out_ready),
        .resp_in_valid(p3_resp_in_valid), .resp_in_flit(p3_resp_in_flit), .resp_in_ready(p3_resp_in_ready)
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
        .bus_grant(p4_bus_grant), .bus_read_data(p4_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(1), .MY_Y(0), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) p4_adap (
        .clk(clk), .reset(reset),
        .bus_req(p4_bus_req), .bus_addr(p4_bus_addr), .bus_write_data(p4_bus_write_data),
        .bus_mem_write(p4_bus_mem_write), .bus_mem_size(p4_bus_mem_size), .bus_mem_unsigned(p4_bus_mem_unsigned),
        .bus_grant(p4_bus_grant), .bus_read_data(p4_bus_read_data),
        .req_out_valid(p4_req_out_valid), .req_out_flit(p4_req_out_flit), .req_out_ready(p4_req_out_ready),
        .resp_in_valid(p4_resp_in_valid), .resp_in_flit(p4_resp_in_flit), .resp_in_ready(p4_resp_in_ready)
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
        .bus_grant(p5_bus_grant), .bus_read_data(p5_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(1), .MY_Y(2), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) p5_adap (
        .clk(clk), .reset(reset),
        .bus_req(p5_bus_req), .bus_addr(p5_bus_addr), .bus_write_data(p5_bus_write_data),
        .bus_mem_write(p5_bus_mem_write), .bus_mem_size(p5_bus_mem_size), .bus_mem_unsigned(p5_bus_mem_unsigned),
        .bus_grant(p5_bus_grant), .bus_read_data(p5_bus_read_data),
        .req_out_valid(p5_req_out_valid), .req_out_flit(p5_req_out_flit), .req_out_ready(p5_req_out_ready),
        .resp_in_valid(p5_resp_in_valid), .resp_in_flit(p5_resp_in_flit), .resp_in_ready(p5_resp_in_ready)
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
        .bus_grant(e0_bus_grant), .bus_read_data(e0_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(1), .MY_Y(3), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) e0_adap (
        .clk(clk), .reset(reset),
        .bus_req(e0_bus_req), .bus_addr(e0_bus_addr), .bus_write_data(e0_bus_write_data),
        .bus_mem_write(e0_bus_mem_write), .bus_mem_size(e0_bus_mem_size), .bus_mem_unsigned(e0_bus_mem_unsigned),
        .bus_grant(e0_bus_grant), .bus_read_data(e0_bus_read_data),
        .req_out_valid(e0_req_out_valid), .req_out_flit(e0_req_out_flit), .req_out_ready(e0_req_out_ready),
        .resp_in_valid(e0_resp_in_valid), .resp_in_flit(e0_resp_in_flit), .resp_in_ready(e0_resp_in_ready)
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
        .bus_grant(e1_bus_grant), .bus_read_data(e1_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(2), .MY_Y(0), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) e1_adap (
        .clk(clk), .reset(reset),
        .bus_req(e1_bus_req), .bus_addr(e1_bus_addr), .bus_write_data(e1_bus_write_data),
        .bus_mem_write(e1_bus_mem_write), .bus_mem_size(e1_bus_mem_size), .bus_mem_unsigned(e1_bus_mem_unsigned),
        .bus_grant(e1_bus_grant), .bus_read_data(e1_bus_read_data),
        .req_out_valid(e1_req_out_valid), .req_out_flit(e1_req_out_flit), .req_out_ready(e1_req_out_ready),
        .resp_in_valid(e1_resp_in_valid), .resp_in_flit(e1_resp_in_flit), .resp_in_ready(e1_resp_in_ready)
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
        .bus_grant(e2_bus_grant), .bus_read_data(e2_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(2), .MY_Y(1), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) e2_adap (
        .clk(clk), .reset(reset),
        .bus_req(e2_bus_req), .bus_addr(e2_bus_addr), .bus_write_data(e2_bus_write_data),
        .bus_mem_write(e2_bus_mem_write), .bus_mem_size(e2_bus_mem_size), .bus_mem_unsigned(e2_bus_mem_unsigned),
        .bus_grant(e2_bus_grant), .bus_read_data(e2_bus_read_data),
        .req_out_valid(e2_req_out_valid), .req_out_flit(e2_req_out_flit), .req_out_ready(e2_req_out_ready),
        .resp_in_valid(e2_resp_in_valid), .resp_in_flit(e2_resp_in_flit), .resp_in_ready(e2_resp_in_ready)
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
        .bus_grant(e3_bus_grant), .bus_read_data(e3_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(2), .MY_Y(2), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) e3_adap (
        .clk(clk), .reset(reset),
        .bus_req(e3_bus_req), .bus_addr(e3_bus_addr), .bus_write_data(e3_bus_write_data),
        .bus_mem_write(e3_bus_mem_write), .bus_mem_size(e3_bus_mem_size), .bus_mem_unsigned(e3_bus_mem_unsigned),
        .bus_grant(e3_bus_grant), .bus_read_data(e3_bus_read_data),
        .req_out_valid(e3_req_out_valid), .req_out_flit(e3_req_out_flit), .req_out_ready(e3_req_out_ready),
        .resp_in_valid(e3_resp_in_valid), .resp_in_flit(e3_resp_in_flit), .resp_in_ready(e3_resp_in_ready)
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
        .bus_grant(e4_bus_grant), .bus_read_data(e4_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(2), .MY_Y(3), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) e4_adap (
        .clk(clk), .reset(reset),
        .bus_req(e4_bus_req), .bus_addr(e4_bus_addr), .bus_write_data(e4_bus_write_data),
        .bus_mem_write(e4_bus_mem_write), .bus_mem_size(e4_bus_mem_size), .bus_mem_unsigned(e4_bus_mem_unsigned),
        .bus_grant(e4_bus_grant), .bus_read_data(e4_bus_read_data),
        .req_out_valid(e4_req_out_valid), .req_out_flit(e4_req_out_flit), .req_out_ready(e4_req_out_ready),
        .resp_in_valid(e4_resp_in_valid), .resp_in_flit(e4_resp_in_flit), .resp_in_ready(e4_resp_in_ready)
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
        .bus_grant(e5_bus_grant), .bus_read_data(e5_bus_read_data)
    );

    noc_core_adapter #(
        .MY_X(3), .MY_Y(0), .MEM_X(1), .MEM_Y(1),
        .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) e5_adap (
        .clk(clk), .reset(reset),
        .bus_req(e5_bus_req), .bus_addr(e5_bus_addr), .bus_write_data(e5_bus_write_data),
        .bus_mem_write(e5_bus_mem_write), .bus_mem_size(e5_bus_mem_size), .bus_mem_unsigned(e5_bus_mem_unsigned),
        .bus_grant(e5_bus_grant), .bus_read_data(e5_bus_read_data),
        .req_out_valid(e5_req_out_valid), .req_out_flit(e5_req_out_flit), .req_out_ready(e5_req_out_ready),
        .resp_in_valid(e5_resp_in_valid), .resp_in_flit(e5_resp_in_flit), .resp_in_ready(e5_resp_in_ready)
    );

    // ==================== Memory node ====================
    noc_mem_adapter #(
        .MEM_BYTES(SHARED_MEM_BYTES), .REQ_FLIT_WIDTH(76), .RESP_FLIT_WIDTH(36)
    ) mem_adap (
        .clk(clk), .reset(reset),
        .req_in_valid(mem_req_in_valid), .req_in_flit(mem_req_in_flit), .req_in_ready(mem_req_in_ready),
        .resp_out_valid(mem_resp_out_valid), .resp_out_flit(mem_resp_out_flit), .resp_out_ready(mem_resp_out_ready)
    );

    assign all_halted = p0_halted && p1_halted && p2_halted && p3_halted && p4_halted && p5_halted && e0_halted && e1_halted && e2_halted && e3_halted && e4_halted && e5_halted;
endmodule
