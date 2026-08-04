// Network-on-Chip version of the mini-SoC (hardware/rv32i_core) -
// replaces shared_bus.v's single centralized arbiter with a real
// 5x5 mesh of XY-routed routers (router.v), each grid
// position connected to its N/E/S/W neighbors plus a Local port for
// whatever core or memory endpoint sits there. TWO independent router
// networks span the whole grid - REQUEST (core -> memory, FLIT_WIDTH=
// 80) and RESPONSE (memory -> core, FLIT_WIDTH=38) - kept as fully
// separate router instances with zero shared state, specifically to
// sidestep request/response protocol deadlock rather than solve it (a
// design-review recommendation - see [[project_noc_router]] for the
// full rationale, including a real grant-timing bug the review caught
// before any RTL was written).
//
// Scaled up from the earlier 4x4/12-core mesh purely by widening the
// grid and COORD_BITS (2->3 - 2 bits can only express coordinates
// 0-3, but a 5x5 grid needs 0-4) - router.v,
// noc_core_adapter.v, and noc_mem_adapter.v needed no OTHER changes,
// since COORD_BITS was designed as a parameter specifically for this.
//
// Memory lives at the CENTER of the grid (2,2), not a
// corner - the original design review found corner placement costs
// meaningfully higher average/worst-case latency for a single fixed
// memory sink that literally every request must reach.
// 24 of the 24 remaining positions host the 12 P-cores
// (cpu_core_pipelined) and 12 E-cores (cpu_core); 0 are spare,
// pass-through-only routers with no local endpoint.
//
// External module interface (parameters and ports) is UNCHANGED from
// the shared-bus soc_top.v - only what's wired INSIDE differs - so
// tb_soc.v/tb_shared_soc.v needed zero modifications to run against
// this version.
//
// Grid layout (x,y), MEM at center:

//   p0      p1      p2      p3      p4    
//   p5      p6      p7      p8      p9    
//   p10     p11     MEM     e0      e1    
//   e2      e3      e4      e5      e6    
//   e7      e8      e9      e10     e11   
`timescale 1ns/1ps

module soc_top #(
    parameter P0_INSTR_HEX     = "",
    parameter P1_INSTR_HEX     = "",
    parameter P2_INSTR_HEX     = "",
    parameter P3_INSTR_HEX     = "",
    parameter P4_INSTR_HEX     = "",
    parameter P5_INSTR_HEX     = "",
    parameter P6_INSTR_HEX     = "",
    parameter P7_INSTR_HEX     = "",
    parameter P8_INSTR_HEX     = "",
    parameter P9_INSTR_HEX     = "",
    parameter P10_INSTR_HEX     = "",
    parameter P11_INSTR_HEX     = "",
    parameter E0_INSTR_HEX     = "",
    parameter E1_INSTR_HEX     = "",
    parameter E2_INSTR_HEX     = "",
    parameter E3_INSTR_HEX     = "",
    parameter E4_INSTR_HEX     = "",
    parameter E5_INSTR_HEX     = "",
    parameter E6_INSTR_HEX     = "",
    parameter E7_INSTR_HEX     = "",
    parameter E8_INSTR_HEX     = "",
    parameter E9_INSTR_HEX     = "",
    parameter E10_INSTR_HEX     = "",
    parameter E11_INSTR_HEX     = "",
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
    output wire        p6_halted,
    output wire [31:0]  p6_tohost,
    output wire        p7_halted,
    output wire [31:0]  p7_tohost,
    output wire        p8_halted,
    output wire [31:0]  p8_tohost,
    output wire        p9_halted,
    output wire [31:0]  p9_tohost,
    output wire        p10_halted,
    output wire [31:0]  p10_tohost,
    output wire        p11_halted,
    output wire [31:0]  p11_tohost,
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
    output wire        e6_halted,
    output wire [31:0]  e6_tohost,
    output wire        e7_halted,
    output wire [31:0]  e7_tohost,
    output wire        e8_halted,
    output wire [31:0]  e8_tohost,
    output wire        e9_halted,
    output wire [31:0]  e9_tohost,
    output wire        e10_halted,
    output wire [31:0]  e10_tohost,
    output wire        e11_halted,
    output wire [31:0]  e11_tohost,
    output wire        all_halted
);

    // ==================== Mesh link wires ====================
    // One {valid,flit,ready} triple per (node, direction) that has a
    // real neighbor, representing THAT node's own outgoing flow in
    // that direction - referenced directly (shared wire names, no
    // extra `assign`s needed) from both this node's *_out_* ports and
    // the neighbor's opposite-direction *_in_* ports.
    wire req_00_E_v, req_00_E_r; wire [79:0] req_00_E_f;
    wire req_00_S_v, req_00_S_r; wire [79:0] req_00_S_f;
    wire req_10_E_v, req_10_E_r; wire [79:0] req_10_E_f;
    wire req_10_S_v, req_10_S_r; wire [79:0] req_10_S_f;
    wire req_10_W_v, req_10_W_r; wire [79:0] req_10_W_f;
    wire req_20_E_v, req_20_E_r; wire [79:0] req_20_E_f;
    wire req_20_S_v, req_20_S_r; wire [79:0] req_20_S_f;
    wire req_20_W_v, req_20_W_r; wire [79:0] req_20_W_f;
    wire req_30_E_v, req_30_E_r; wire [79:0] req_30_E_f;
    wire req_30_S_v, req_30_S_r; wire [79:0] req_30_S_f;
    wire req_30_W_v, req_30_W_r; wire [79:0] req_30_W_f;
    wire req_40_S_v, req_40_S_r; wire [79:0] req_40_S_f;
    wire req_40_W_v, req_40_W_r; wire [79:0] req_40_W_f;
    wire req_01_N_v, req_01_N_r; wire [79:0] req_01_N_f;
    wire req_01_E_v, req_01_E_r; wire [79:0] req_01_E_f;
    wire req_01_S_v, req_01_S_r; wire [79:0] req_01_S_f;
    wire req_11_N_v, req_11_N_r; wire [79:0] req_11_N_f;
    wire req_11_E_v, req_11_E_r; wire [79:0] req_11_E_f;
    wire req_11_S_v, req_11_S_r; wire [79:0] req_11_S_f;
    wire req_11_W_v, req_11_W_r; wire [79:0] req_11_W_f;
    wire req_21_N_v, req_21_N_r; wire [79:0] req_21_N_f;
    wire req_21_E_v, req_21_E_r; wire [79:0] req_21_E_f;
    wire req_21_S_v, req_21_S_r; wire [79:0] req_21_S_f;
    wire req_21_W_v, req_21_W_r; wire [79:0] req_21_W_f;
    wire req_31_N_v, req_31_N_r; wire [79:0] req_31_N_f;
    wire req_31_E_v, req_31_E_r; wire [79:0] req_31_E_f;
    wire req_31_S_v, req_31_S_r; wire [79:0] req_31_S_f;
    wire req_31_W_v, req_31_W_r; wire [79:0] req_31_W_f;
    wire req_41_N_v, req_41_N_r; wire [79:0] req_41_N_f;
    wire req_41_S_v, req_41_S_r; wire [79:0] req_41_S_f;
    wire req_41_W_v, req_41_W_r; wire [79:0] req_41_W_f;
    wire req_02_N_v, req_02_N_r; wire [79:0] req_02_N_f;
    wire req_02_E_v, req_02_E_r; wire [79:0] req_02_E_f;
    wire req_02_S_v, req_02_S_r; wire [79:0] req_02_S_f;
    wire req_12_N_v, req_12_N_r; wire [79:0] req_12_N_f;
    wire req_12_E_v, req_12_E_r; wire [79:0] req_12_E_f;
    wire req_12_S_v, req_12_S_r; wire [79:0] req_12_S_f;
    wire req_12_W_v, req_12_W_r; wire [79:0] req_12_W_f;
    wire req_22_N_v, req_22_N_r; wire [79:0] req_22_N_f;
    wire req_22_E_v, req_22_E_r; wire [79:0] req_22_E_f;
    wire req_22_S_v, req_22_S_r; wire [79:0] req_22_S_f;
    wire req_22_W_v, req_22_W_r; wire [79:0] req_22_W_f;
    wire req_32_N_v, req_32_N_r; wire [79:0] req_32_N_f;
    wire req_32_E_v, req_32_E_r; wire [79:0] req_32_E_f;
    wire req_32_S_v, req_32_S_r; wire [79:0] req_32_S_f;
    wire req_32_W_v, req_32_W_r; wire [79:0] req_32_W_f;
    wire req_42_N_v, req_42_N_r; wire [79:0] req_42_N_f;
    wire req_42_S_v, req_42_S_r; wire [79:0] req_42_S_f;
    wire req_42_W_v, req_42_W_r; wire [79:0] req_42_W_f;
    wire req_03_N_v, req_03_N_r; wire [79:0] req_03_N_f;
    wire req_03_E_v, req_03_E_r; wire [79:0] req_03_E_f;
    wire req_03_S_v, req_03_S_r; wire [79:0] req_03_S_f;
    wire req_13_N_v, req_13_N_r; wire [79:0] req_13_N_f;
    wire req_13_E_v, req_13_E_r; wire [79:0] req_13_E_f;
    wire req_13_S_v, req_13_S_r; wire [79:0] req_13_S_f;
    wire req_13_W_v, req_13_W_r; wire [79:0] req_13_W_f;
    wire req_23_N_v, req_23_N_r; wire [79:0] req_23_N_f;
    wire req_23_E_v, req_23_E_r; wire [79:0] req_23_E_f;
    wire req_23_S_v, req_23_S_r; wire [79:0] req_23_S_f;
    wire req_23_W_v, req_23_W_r; wire [79:0] req_23_W_f;
    wire req_33_N_v, req_33_N_r; wire [79:0] req_33_N_f;
    wire req_33_E_v, req_33_E_r; wire [79:0] req_33_E_f;
    wire req_33_S_v, req_33_S_r; wire [79:0] req_33_S_f;
    wire req_33_W_v, req_33_W_r; wire [79:0] req_33_W_f;
    wire req_43_N_v, req_43_N_r; wire [79:0] req_43_N_f;
    wire req_43_S_v, req_43_S_r; wire [79:0] req_43_S_f;
    wire req_43_W_v, req_43_W_r; wire [79:0] req_43_W_f;
    wire req_04_N_v, req_04_N_r; wire [79:0] req_04_N_f;
    wire req_04_E_v, req_04_E_r; wire [79:0] req_04_E_f;
    wire req_14_N_v, req_14_N_r; wire [79:0] req_14_N_f;
    wire req_14_E_v, req_14_E_r; wire [79:0] req_14_E_f;
    wire req_14_W_v, req_14_W_r; wire [79:0] req_14_W_f;
    wire req_24_N_v, req_24_N_r; wire [79:0] req_24_N_f;
    wire req_24_E_v, req_24_E_r; wire [79:0] req_24_E_f;
    wire req_24_W_v, req_24_W_r; wire [79:0] req_24_W_f;
    wire req_34_N_v, req_34_N_r; wire [79:0] req_34_N_f;
    wire req_34_E_v, req_34_E_r; wire [79:0] req_34_E_f;
    wire req_34_W_v, req_34_W_r; wire [79:0] req_34_W_f;
    wire req_44_N_v, req_44_N_r; wire [79:0] req_44_N_f;
    wire req_44_W_v, req_44_W_r; wire [79:0] req_44_W_f;
    wire resp_00_E_v, resp_00_E_r; wire [37:0] resp_00_E_f;
    wire resp_00_S_v, resp_00_S_r; wire [37:0] resp_00_S_f;
    wire resp_10_E_v, resp_10_E_r; wire [37:0] resp_10_E_f;
    wire resp_10_S_v, resp_10_S_r; wire [37:0] resp_10_S_f;
    wire resp_10_W_v, resp_10_W_r; wire [37:0] resp_10_W_f;
    wire resp_20_E_v, resp_20_E_r; wire [37:0] resp_20_E_f;
    wire resp_20_S_v, resp_20_S_r; wire [37:0] resp_20_S_f;
    wire resp_20_W_v, resp_20_W_r; wire [37:0] resp_20_W_f;
    wire resp_30_E_v, resp_30_E_r; wire [37:0] resp_30_E_f;
    wire resp_30_S_v, resp_30_S_r; wire [37:0] resp_30_S_f;
    wire resp_30_W_v, resp_30_W_r; wire [37:0] resp_30_W_f;
    wire resp_40_S_v, resp_40_S_r; wire [37:0] resp_40_S_f;
    wire resp_40_W_v, resp_40_W_r; wire [37:0] resp_40_W_f;
    wire resp_01_N_v, resp_01_N_r; wire [37:0] resp_01_N_f;
    wire resp_01_E_v, resp_01_E_r; wire [37:0] resp_01_E_f;
    wire resp_01_S_v, resp_01_S_r; wire [37:0] resp_01_S_f;
    wire resp_11_N_v, resp_11_N_r; wire [37:0] resp_11_N_f;
    wire resp_11_E_v, resp_11_E_r; wire [37:0] resp_11_E_f;
    wire resp_11_S_v, resp_11_S_r; wire [37:0] resp_11_S_f;
    wire resp_11_W_v, resp_11_W_r; wire [37:0] resp_11_W_f;
    wire resp_21_N_v, resp_21_N_r; wire [37:0] resp_21_N_f;
    wire resp_21_E_v, resp_21_E_r; wire [37:0] resp_21_E_f;
    wire resp_21_S_v, resp_21_S_r; wire [37:0] resp_21_S_f;
    wire resp_21_W_v, resp_21_W_r; wire [37:0] resp_21_W_f;
    wire resp_31_N_v, resp_31_N_r; wire [37:0] resp_31_N_f;
    wire resp_31_E_v, resp_31_E_r; wire [37:0] resp_31_E_f;
    wire resp_31_S_v, resp_31_S_r; wire [37:0] resp_31_S_f;
    wire resp_31_W_v, resp_31_W_r; wire [37:0] resp_31_W_f;
    wire resp_41_N_v, resp_41_N_r; wire [37:0] resp_41_N_f;
    wire resp_41_S_v, resp_41_S_r; wire [37:0] resp_41_S_f;
    wire resp_41_W_v, resp_41_W_r; wire [37:0] resp_41_W_f;
    wire resp_02_N_v, resp_02_N_r; wire [37:0] resp_02_N_f;
    wire resp_02_E_v, resp_02_E_r; wire [37:0] resp_02_E_f;
    wire resp_02_S_v, resp_02_S_r; wire [37:0] resp_02_S_f;
    wire resp_12_N_v, resp_12_N_r; wire [37:0] resp_12_N_f;
    wire resp_12_E_v, resp_12_E_r; wire [37:0] resp_12_E_f;
    wire resp_12_S_v, resp_12_S_r; wire [37:0] resp_12_S_f;
    wire resp_12_W_v, resp_12_W_r; wire [37:0] resp_12_W_f;
    wire resp_22_N_v, resp_22_N_r; wire [37:0] resp_22_N_f;
    wire resp_22_E_v, resp_22_E_r; wire [37:0] resp_22_E_f;
    wire resp_22_S_v, resp_22_S_r; wire [37:0] resp_22_S_f;
    wire resp_22_W_v, resp_22_W_r; wire [37:0] resp_22_W_f;
    wire resp_32_N_v, resp_32_N_r; wire [37:0] resp_32_N_f;
    wire resp_32_E_v, resp_32_E_r; wire [37:0] resp_32_E_f;
    wire resp_32_S_v, resp_32_S_r; wire [37:0] resp_32_S_f;
    wire resp_32_W_v, resp_32_W_r; wire [37:0] resp_32_W_f;
    wire resp_42_N_v, resp_42_N_r; wire [37:0] resp_42_N_f;
    wire resp_42_S_v, resp_42_S_r; wire [37:0] resp_42_S_f;
    wire resp_42_W_v, resp_42_W_r; wire [37:0] resp_42_W_f;
    wire resp_03_N_v, resp_03_N_r; wire [37:0] resp_03_N_f;
    wire resp_03_E_v, resp_03_E_r; wire [37:0] resp_03_E_f;
    wire resp_03_S_v, resp_03_S_r; wire [37:0] resp_03_S_f;
    wire resp_13_N_v, resp_13_N_r; wire [37:0] resp_13_N_f;
    wire resp_13_E_v, resp_13_E_r; wire [37:0] resp_13_E_f;
    wire resp_13_S_v, resp_13_S_r; wire [37:0] resp_13_S_f;
    wire resp_13_W_v, resp_13_W_r; wire [37:0] resp_13_W_f;
    wire resp_23_N_v, resp_23_N_r; wire [37:0] resp_23_N_f;
    wire resp_23_E_v, resp_23_E_r; wire [37:0] resp_23_E_f;
    wire resp_23_S_v, resp_23_S_r; wire [37:0] resp_23_S_f;
    wire resp_23_W_v, resp_23_W_r; wire [37:0] resp_23_W_f;
    wire resp_33_N_v, resp_33_N_r; wire [37:0] resp_33_N_f;
    wire resp_33_E_v, resp_33_E_r; wire [37:0] resp_33_E_f;
    wire resp_33_S_v, resp_33_S_r; wire [37:0] resp_33_S_f;
    wire resp_33_W_v, resp_33_W_r; wire [37:0] resp_33_W_f;
    wire resp_43_N_v, resp_43_N_r; wire [37:0] resp_43_N_f;
    wire resp_43_S_v, resp_43_S_r; wire [37:0] resp_43_S_f;
    wire resp_43_W_v, resp_43_W_r; wire [37:0] resp_43_W_f;
    wire resp_04_N_v, resp_04_N_r; wire [37:0] resp_04_N_f;
    wire resp_04_E_v, resp_04_E_r; wire [37:0] resp_04_E_f;
    wire resp_14_N_v, resp_14_N_r; wire [37:0] resp_14_N_f;
    wire resp_14_E_v, resp_14_E_r; wire [37:0] resp_14_E_f;
    wire resp_14_W_v, resp_14_W_r; wire [37:0] resp_14_W_f;
    wire resp_24_N_v, resp_24_N_r; wire [37:0] resp_24_N_f;
    wire resp_24_E_v, resp_24_E_r; wire [37:0] resp_24_E_f;
    wire resp_24_W_v, resp_24_W_r; wire [37:0] resp_24_W_f;
    wire resp_34_N_v, resp_34_N_r; wire [37:0] resp_34_N_f;
    wire resp_34_E_v, resp_34_E_r; wire [37:0] resp_34_E_f;
    wire resp_34_W_v, resp_34_W_r; wire [37:0] resp_34_W_f;
    wire resp_44_N_v, resp_44_N_r; wire [37:0] resp_44_N_f;
    wire resp_44_W_v, resp_44_W_r; wire [37:0] resp_44_W_f;

    // ==================== Core bus + adapter wires ====================
    wire p0_bus_req, p0_bus_mem_write, p0_bus_mem_unsigned, p0_bus_grant;
    wire [31:0] p0_bus_addr, p0_bus_write_data, p0_bus_read_data;
    wire [1:0] p0_bus_mem_size;
    wire p0_req_out_valid, p0_req_out_ready, p0_resp_in_valid, p0_resp_in_ready;
    wire [79:0] p0_req_out_flit;
    wire [37:0] p0_resp_in_flit;
    wire p1_bus_req, p1_bus_mem_write, p1_bus_mem_unsigned, p1_bus_grant;
    wire [31:0] p1_bus_addr, p1_bus_write_data, p1_bus_read_data;
    wire [1:0] p1_bus_mem_size;
    wire p1_req_out_valid, p1_req_out_ready, p1_resp_in_valid, p1_resp_in_ready;
    wire [79:0] p1_req_out_flit;
    wire [37:0] p1_resp_in_flit;
    wire p2_bus_req, p2_bus_mem_write, p2_bus_mem_unsigned, p2_bus_grant;
    wire [31:0] p2_bus_addr, p2_bus_write_data, p2_bus_read_data;
    wire [1:0] p2_bus_mem_size;
    wire p2_req_out_valid, p2_req_out_ready, p2_resp_in_valid, p2_resp_in_ready;
    wire [79:0] p2_req_out_flit;
    wire [37:0] p2_resp_in_flit;
    wire p3_bus_req, p3_bus_mem_write, p3_bus_mem_unsigned, p3_bus_grant;
    wire [31:0] p3_bus_addr, p3_bus_write_data, p3_bus_read_data;
    wire [1:0] p3_bus_mem_size;
    wire p3_req_out_valid, p3_req_out_ready, p3_resp_in_valid, p3_resp_in_ready;
    wire [79:0] p3_req_out_flit;
    wire [37:0] p3_resp_in_flit;
    wire p4_bus_req, p4_bus_mem_write, p4_bus_mem_unsigned, p4_bus_grant;
    wire [31:0] p4_bus_addr, p4_bus_write_data, p4_bus_read_data;
    wire [1:0] p4_bus_mem_size;
    wire p4_req_out_valid, p4_req_out_ready, p4_resp_in_valid, p4_resp_in_ready;
    wire [79:0] p4_req_out_flit;
    wire [37:0] p4_resp_in_flit;
    wire p5_bus_req, p5_bus_mem_write, p5_bus_mem_unsigned, p5_bus_grant;
    wire [31:0] p5_bus_addr, p5_bus_write_data, p5_bus_read_data;
    wire [1:0] p5_bus_mem_size;
    wire p5_req_out_valid, p5_req_out_ready, p5_resp_in_valid, p5_resp_in_ready;
    wire [79:0] p5_req_out_flit;
    wire [37:0] p5_resp_in_flit;
    wire p6_bus_req, p6_bus_mem_write, p6_bus_mem_unsigned, p6_bus_grant;
    wire [31:0] p6_bus_addr, p6_bus_write_data, p6_bus_read_data;
    wire [1:0] p6_bus_mem_size;
    wire p6_req_out_valid, p6_req_out_ready, p6_resp_in_valid, p6_resp_in_ready;
    wire [79:0] p6_req_out_flit;
    wire [37:0] p6_resp_in_flit;
    wire p7_bus_req, p7_bus_mem_write, p7_bus_mem_unsigned, p7_bus_grant;
    wire [31:0] p7_bus_addr, p7_bus_write_data, p7_bus_read_data;
    wire [1:0] p7_bus_mem_size;
    wire p7_req_out_valid, p7_req_out_ready, p7_resp_in_valid, p7_resp_in_ready;
    wire [79:0] p7_req_out_flit;
    wire [37:0] p7_resp_in_flit;
    wire p8_bus_req, p8_bus_mem_write, p8_bus_mem_unsigned, p8_bus_grant;
    wire [31:0] p8_bus_addr, p8_bus_write_data, p8_bus_read_data;
    wire [1:0] p8_bus_mem_size;
    wire p8_req_out_valid, p8_req_out_ready, p8_resp_in_valid, p8_resp_in_ready;
    wire [79:0] p8_req_out_flit;
    wire [37:0] p8_resp_in_flit;
    wire p9_bus_req, p9_bus_mem_write, p9_bus_mem_unsigned, p9_bus_grant;
    wire [31:0] p9_bus_addr, p9_bus_write_data, p9_bus_read_data;
    wire [1:0] p9_bus_mem_size;
    wire p9_req_out_valid, p9_req_out_ready, p9_resp_in_valid, p9_resp_in_ready;
    wire [79:0] p9_req_out_flit;
    wire [37:0] p9_resp_in_flit;
    wire p10_bus_req, p10_bus_mem_write, p10_bus_mem_unsigned, p10_bus_grant;
    wire [31:0] p10_bus_addr, p10_bus_write_data, p10_bus_read_data;
    wire [1:0] p10_bus_mem_size;
    wire p10_req_out_valid, p10_req_out_ready, p10_resp_in_valid, p10_resp_in_ready;
    wire [79:0] p10_req_out_flit;
    wire [37:0] p10_resp_in_flit;
    wire p11_bus_req, p11_bus_mem_write, p11_bus_mem_unsigned, p11_bus_grant;
    wire [31:0] p11_bus_addr, p11_bus_write_data, p11_bus_read_data;
    wire [1:0] p11_bus_mem_size;
    wire p11_req_out_valid, p11_req_out_ready, p11_resp_in_valid, p11_resp_in_ready;
    wire [79:0] p11_req_out_flit;
    wire [37:0] p11_resp_in_flit;
    wire e0_bus_req, e0_bus_mem_write, e0_bus_mem_unsigned, e0_bus_grant;
    wire [31:0] e0_bus_addr, e0_bus_write_data, e0_bus_read_data;
    wire [1:0] e0_bus_mem_size;
    wire e0_req_out_valid, e0_req_out_ready, e0_resp_in_valid, e0_resp_in_ready;
    wire [79:0] e0_req_out_flit;
    wire [37:0] e0_resp_in_flit;
    wire e1_bus_req, e1_bus_mem_write, e1_bus_mem_unsigned, e1_bus_grant;
    wire [31:0] e1_bus_addr, e1_bus_write_data, e1_bus_read_data;
    wire [1:0] e1_bus_mem_size;
    wire e1_req_out_valid, e1_req_out_ready, e1_resp_in_valid, e1_resp_in_ready;
    wire [79:0] e1_req_out_flit;
    wire [37:0] e1_resp_in_flit;
    wire e2_bus_req, e2_bus_mem_write, e2_bus_mem_unsigned, e2_bus_grant;
    wire [31:0] e2_bus_addr, e2_bus_write_data, e2_bus_read_data;
    wire [1:0] e2_bus_mem_size;
    wire e2_req_out_valid, e2_req_out_ready, e2_resp_in_valid, e2_resp_in_ready;
    wire [79:0] e2_req_out_flit;
    wire [37:0] e2_resp_in_flit;
    wire e3_bus_req, e3_bus_mem_write, e3_bus_mem_unsigned, e3_bus_grant;
    wire [31:0] e3_bus_addr, e3_bus_write_data, e3_bus_read_data;
    wire [1:0] e3_bus_mem_size;
    wire e3_req_out_valid, e3_req_out_ready, e3_resp_in_valid, e3_resp_in_ready;
    wire [79:0] e3_req_out_flit;
    wire [37:0] e3_resp_in_flit;
    wire e4_bus_req, e4_bus_mem_write, e4_bus_mem_unsigned, e4_bus_grant;
    wire [31:0] e4_bus_addr, e4_bus_write_data, e4_bus_read_data;
    wire [1:0] e4_bus_mem_size;
    wire e4_req_out_valid, e4_req_out_ready, e4_resp_in_valid, e4_resp_in_ready;
    wire [79:0] e4_req_out_flit;
    wire [37:0] e4_resp_in_flit;
    wire e5_bus_req, e5_bus_mem_write, e5_bus_mem_unsigned, e5_bus_grant;
    wire [31:0] e5_bus_addr, e5_bus_write_data, e5_bus_read_data;
    wire [1:0] e5_bus_mem_size;
    wire e5_req_out_valid, e5_req_out_ready, e5_resp_in_valid, e5_resp_in_ready;
    wire [79:0] e5_req_out_flit;
    wire [37:0] e5_resp_in_flit;
    wire e6_bus_req, e6_bus_mem_write, e6_bus_mem_unsigned, e6_bus_grant;
    wire [31:0] e6_bus_addr, e6_bus_write_data, e6_bus_read_data;
    wire [1:0] e6_bus_mem_size;
    wire e6_req_out_valid, e6_req_out_ready, e6_resp_in_valid, e6_resp_in_ready;
    wire [79:0] e6_req_out_flit;
    wire [37:0] e6_resp_in_flit;
    wire e7_bus_req, e7_bus_mem_write, e7_bus_mem_unsigned, e7_bus_grant;
    wire [31:0] e7_bus_addr, e7_bus_write_data, e7_bus_read_data;
    wire [1:0] e7_bus_mem_size;
    wire e7_req_out_valid, e7_req_out_ready, e7_resp_in_valid, e7_resp_in_ready;
    wire [79:0] e7_req_out_flit;
    wire [37:0] e7_resp_in_flit;
    wire e8_bus_req, e8_bus_mem_write, e8_bus_mem_unsigned, e8_bus_grant;
    wire [31:0] e8_bus_addr, e8_bus_write_data, e8_bus_read_data;
    wire [1:0] e8_bus_mem_size;
    wire e8_req_out_valid, e8_req_out_ready, e8_resp_in_valid, e8_resp_in_ready;
    wire [79:0] e8_req_out_flit;
    wire [37:0] e8_resp_in_flit;
    wire e9_bus_req, e9_bus_mem_write, e9_bus_mem_unsigned, e9_bus_grant;
    wire [31:0] e9_bus_addr, e9_bus_write_data, e9_bus_read_data;
    wire [1:0] e9_bus_mem_size;
    wire e9_req_out_valid, e9_req_out_ready, e9_resp_in_valid, e9_resp_in_ready;
    wire [79:0] e9_req_out_flit;
    wire [37:0] e9_resp_in_flit;
    wire e10_bus_req, e10_bus_mem_write, e10_bus_mem_unsigned, e10_bus_grant;
    wire [31:0] e10_bus_addr, e10_bus_write_data, e10_bus_read_data;
    wire [1:0] e10_bus_mem_size;
    wire e10_req_out_valid, e10_req_out_ready, e10_resp_in_valid, e10_resp_in_ready;
    wire [79:0] e10_req_out_flit;
    wire [37:0] e10_resp_in_flit;
    wire e11_bus_req, e11_bus_mem_write, e11_bus_mem_unsigned, e11_bus_grant;
    wire [31:0] e11_bus_addr, e11_bus_write_data, e11_bus_read_data;
    wire [1:0] e11_bus_mem_size;
    wire e11_req_out_valid, e11_req_out_ready, e11_resp_in_valid, e11_resp_in_ready;
    wire [79:0] e11_req_out_flit;
    wire [37:0] e11_resp_in_flit;
    wire mem_req_in_valid, mem_req_in_ready, mem_resp_out_valid, mem_resp_out_ready;
    wire [79:0] mem_req_in_flit;
    wire [37:0] mem_resp_out_flit;

    // ==================== Routers (2 networks x 25 grid positions) ====================
    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(0), .MY_Y(0)) req_r00 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_10_W_v), .e_in_flit(req_10_W_f), .e_in_ready(req_10_W_r),
        .e_out_valid(req_00_E_v), .e_out_flit(req_00_E_f), .e_out_ready(req_00_E_r),
        .s_in_valid(req_01_N_v), .s_in_flit(req_01_N_f), .s_in_ready(req_01_N_r),
        .s_out_valid(req_00_S_v), .s_out_flit(req_00_S_f), .s_out_ready(req_00_S_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(p0_req_out_valid), .l_in_flit(p0_req_out_flit), .l_in_ready(p0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(0), .MY_Y(0)) resp_r00 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_10_W_v), .e_in_flit(resp_10_W_f), .e_in_ready(resp_10_W_r),
        .e_out_valid(resp_00_E_v), .e_out_flit(resp_00_E_f), .e_out_ready(resp_00_E_r),
        .s_in_valid(resp_01_N_v), .s_in_flit(resp_01_N_f), .s_in_ready(resp_01_N_r),
        .s_out_valid(resp_00_S_v), .s_out_flit(resp_00_S_f), .s_out_ready(resp_00_S_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p0_resp_in_valid), .l_out_flit(p0_resp_in_flit), .l_out_ready(p0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(1), .MY_Y(0)) req_r10 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_20_W_v), .e_in_flit(req_20_W_f), .e_in_ready(req_20_W_r),
        .e_out_valid(req_10_E_v), .e_out_flit(req_10_E_f), .e_out_ready(req_10_E_r),
        .s_in_valid(req_11_N_v), .s_in_flit(req_11_N_f), .s_in_ready(req_11_N_r),
        .s_out_valid(req_10_S_v), .s_out_flit(req_10_S_f), .s_out_ready(req_10_S_r),
        .w_in_valid(req_00_E_v), .w_in_flit(req_00_E_f), .w_in_ready(req_00_E_r),
        .w_out_valid(req_10_W_v), .w_out_flit(req_10_W_f), .w_out_ready(req_10_W_r),
        .l_in_valid(p1_req_out_valid), .l_in_flit(p1_req_out_flit), .l_in_ready(p1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(1), .MY_Y(0)) resp_r10 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_20_W_v), .e_in_flit(resp_20_W_f), .e_in_ready(resp_20_W_r),
        .e_out_valid(resp_10_E_v), .e_out_flit(resp_10_E_f), .e_out_ready(resp_10_E_r),
        .s_in_valid(resp_11_N_v), .s_in_flit(resp_11_N_f), .s_in_ready(resp_11_N_r),
        .s_out_valid(resp_10_S_v), .s_out_flit(resp_10_S_f), .s_out_ready(resp_10_S_r),
        .w_in_valid(resp_00_E_v), .w_in_flit(resp_00_E_f), .w_in_ready(resp_00_E_r),
        .w_out_valid(resp_10_W_v), .w_out_flit(resp_10_W_f), .w_out_ready(resp_10_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p1_resp_in_valid), .l_out_flit(p1_resp_in_flit), .l_out_ready(p1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(2), .MY_Y(0)) req_r20 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_30_W_v), .e_in_flit(req_30_W_f), .e_in_ready(req_30_W_r),
        .e_out_valid(req_20_E_v), .e_out_flit(req_20_E_f), .e_out_ready(req_20_E_r),
        .s_in_valid(req_21_N_v), .s_in_flit(req_21_N_f), .s_in_ready(req_21_N_r),
        .s_out_valid(req_20_S_v), .s_out_flit(req_20_S_f), .s_out_ready(req_20_S_r),
        .w_in_valid(req_10_E_v), .w_in_flit(req_10_E_f), .w_in_ready(req_10_E_r),
        .w_out_valid(req_20_W_v), .w_out_flit(req_20_W_f), .w_out_ready(req_20_W_r),
        .l_in_valid(p2_req_out_valid), .l_in_flit(p2_req_out_flit), .l_in_ready(p2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(2), .MY_Y(0)) resp_r20 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_30_W_v), .e_in_flit(resp_30_W_f), .e_in_ready(resp_30_W_r),
        .e_out_valid(resp_20_E_v), .e_out_flit(resp_20_E_f), .e_out_ready(resp_20_E_r),
        .s_in_valid(resp_21_N_v), .s_in_flit(resp_21_N_f), .s_in_ready(resp_21_N_r),
        .s_out_valid(resp_20_S_v), .s_out_flit(resp_20_S_f), .s_out_ready(resp_20_S_r),
        .w_in_valid(resp_10_E_v), .w_in_flit(resp_10_E_f), .w_in_ready(resp_10_E_r),
        .w_out_valid(resp_20_W_v), .w_out_flit(resp_20_W_f), .w_out_ready(resp_20_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p2_resp_in_valid), .l_out_flit(p2_resp_in_flit), .l_out_ready(p2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(3), .MY_Y(0)) req_r30 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_40_W_v), .e_in_flit(req_40_W_f), .e_in_ready(req_40_W_r),
        .e_out_valid(req_30_E_v), .e_out_flit(req_30_E_f), .e_out_ready(req_30_E_r),
        .s_in_valid(req_31_N_v), .s_in_flit(req_31_N_f), .s_in_ready(req_31_N_r),
        .s_out_valid(req_30_S_v), .s_out_flit(req_30_S_f), .s_out_ready(req_30_S_r),
        .w_in_valid(req_20_E_v), .w_in_flit(req_20_E_f), .w_in_ready(req_20_E_r),
        .w_out_valid(req_30_W_v), .w_out_flit(req_30_W_f), .w_out_ready(req_30_W_r),
        .l_in_valid(p3_req_out_valid), .l_in_flit(p3_req_out_flit), .l_in_ready(p3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(3), .MY_Y(0)) resp_r30 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_40_W_v), .e_in_flit(resp_40_W_f), .e_in_ready(resp_40_W_r),
        .e_out_valid(resp_30_E_v), .e_out_flit(resp_30_E_f), .e_out_ready(resp_30_E_r),
        .s_in_valid(resp_31_N_v), .s_in_flit(resp_31_N_f), .s_in_ready(resp_31_N_r),
        .s_out_valid(resp_30_S_v), .s_out_flit(resp_30_S_f), .s_out_ready(resp_30_S_r),
        .w_in_valid(resp_20_E_v), .w_in_flit(resp_20_E_f), .w_in_ready(resp_20_E_r),
        .w_out_valid(resp_30_W_v), .w_out_flit(resp_30_W_f), .w_out_ready(resp_30_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p3_resp_in_valid), .l_out_flit(p3_resp_in_flit), .l_out_ready(p3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(4), .MY_Y(0)) req_r40 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_41_N_v), .s_in_flit(req_41_N_f), .s_in_ready(req_41_N_r),
        .s_out_valid(req_40_S_v), .s_out_flit(req_40_S_f), .s_out_ready(req_40_S_r),
        .w_in_valid(req_30_E_v), .w_in_flit(req_30_E_f), .w_in_ready(req_30_E_r),
        .w_out_valid(req_40_W_v), .w_out_flit(req_40_W_f), .w_out_ready(req_40_W_r),
        .l_in_valid(p4_req_out_valid), .l_in_flit(p4_req_out_flit), .l_in_ready(p4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(4), .MY_Y(0)) resp_r40 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_41_N_v), .s_in_flit(resp_41_N_f), .s_in_ready(resp_41_N_r),
        .s_out_valid(resp_40_S_v), .s_out_flit(resp_40_S_f), .s_out_ready(resp_40_S_r),
        .w_in_valid(resp_30_E_v), .w_in_flit(resp_30_E_f), .w_in_ready(resp_30_E_r),
        .w_out_valid(resp_40_W_v), .w_out_flit(resp_40_W_f), .w_out_ready(resp_40_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p4_resp_in_valid), .l_out_flit(p4_resp_in_flit), .l_out_ready(p4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(0), .MY_Y(1)) req_r01 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_00_S_v), .n_in_flit(req_00_S_f), .n_in_ready(req_00_S_r),
        .n_out_valid(req_01_N_v), .n_out_flit(req_01_N_f), .n_out_ready(req_01_N_r),
        .e_in_valid(req_11_W_v), .e_in_flit(req_11_W_f), .e_in_ready(req_11_W_r),
        .e_out_valid(req_01_E_v), .e_out_flit(req_01_E_f), .e_out_ready(req_01_E_r),
        .s_in_valid(req_02_N_v), .s_in_flit(req_02_N_f), .s_in_ready(req_02_N_r),
        .s_out_valid(req_01_S_v), .s_out_flit(req_01_S_f), .s_out_ready(req_01_S_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(p5_req_out_valid), .l_in_flit(p5_req_out_flit), .l_in_ready(p5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(0), .MY_Y(1)) resp_r01 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_00_S_v), .n_in_flit(resp_00_S_f), .n_in_ready(resp_00_S_r),
        .n_out_valid(resp_01_N_v), .n_out_flit(resp_01_N_f), .n_out_ready(resp_01_N_r),
        .e_in_valid(resp_11_W_v), .e_in_flit(resp_11_W_f), .e_in_ready(resp_11_W_r),
        .e_out_valid(resp_01_E_v), .e_out_flit(resp_01_E_f), .e_out_ready(resp_01_E_r),
        .s_in_valid(resp_02_N_v), .s_in_flit(resp_02_N_f), .s_in_ready(resp_02_N_r),
        .s_out_valid(resp_01_S_v), .s_out_flit(resp_01_S_f), .s_out_ready(resp_01_S_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p5_resp_in_valid), .l_out_flit(p5_resp_in_flit), .l_out_ready(p5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(1), .MY_Y(1)) req_r11 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_10_S_v), .n_in_flit(req_10_S_f), .n_in_ready(req_10_S_r),
        .n_out_valid(req_11_N_v), .n_out_flit(req_11_N_f), .n_out_ready(req_11_N_r),
        .e_in_valid(req_21_W_v), .e_in_flit(req_21_W_f), .e_in_ready(req_21_W_r),
        .e_out_valid(req_11_E_v), .e_out_flit(req_11_E_f), .e_out_ready(req_11_E_r),
        .s_in_valid(req_12_N_v), .s_in_flit(req_12_N_f), .s_in_ready(req_12_N_r),
        .s_out_valid(req_11_S_v), .s_out_flit(req_11_S_f), .s_out_ready(req_11_S_r),
        .w_in_valid(req_01_E_v), .w_in_flit(req_01_E_f), .w_in_ready(req_01_E_r),
        .w_out_valid(req_11_W_v), .w_out_flit(req_11_W_f), .w_out_ready(req_11_W_r),
        .l_in_valid(p6_req_out_valid), .l_in_flit(p6_req_out_flit), .l_in_ready(p6_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(1), .MY_Y(1)) resp_r11 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_10_S_v), .n_in_flit(resp_10_S_f), .n_in_ready(resp_10_S_r),
        .n_out_valid(resp_11_N_v), .n_out_flit(resp_11_N_f), .n_out_ready(resp_11_N_r),
        .e_in_valid(resp_21_W_v), .e_in_flit(resp_21_W_f), .e_in_ready(resp_21_W_r),
        .e_out_valid(resp_11_E_v), .e_out_flit(resp_11_E_f), .e_out_ready(resp_11_E_r),
        .s_in_valid(resp_12_N_v), .s_in_flit(resp_12_N_f), .s_in_ready(resp_12_N_r),
        .s_out_valid(resp_11_S_v), .s_out_flit(resp_11_S_f), .s_out_ready(resp_11_S_r),
        .w_in_valid(resp_01_E_v), .w_in_flit(resp_01_E_f), .w_in_ready(resp_01_E_r),
        .w_out_valid(resp_11_W_v), .w_out_flit(resp_11_W_f), .w_out_ready(resp_11_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p6_resp_in_valid), .l_out_flit(p6_resp_in_flit), .l_out_ready(p6_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(2), .MY_Y(1)) req_r21 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_20_S_v), .n_in_flit(req_20_S_f), .n_in_ready(req_20_S_r),
        .n_out_valid(req_21_N_v), .n_out_flit(req_21_N_f), .n_out_ready(req_21_N_r),
        .e_in_valid(req_31_W_v), .e_in_flit(req_31_W_f), .e_in_ready(req_31_W_r),
        .e_out_valid(req_21_E_v), .e_out_flit(req_21_E_f), .e_out_ready(req_21_E_r),
        .s_in_valid(req_22_N_v), .s_in_flit(req_22_N_f), .s_in_ready(req_22_N_r),
        .s_out_valid(req_21_S_v), .s_out_flit(req_21_S_f), .s_out_ready(req_21_S_r),
        .w_in_valid(req_11_E_v), .w_in_flit(req_11_E_f), .w_in_ready(req_11_E_r),
        .w_out_valid(req_21_W_v), .w_out_flit(req_21_W_f), .w_out_ready(req_21_W_r),
        .l_in_valid(p7_req_out_valid), .l_in_flit(p7_req_out_flit), .l_in_ready(p7_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(2), .MY_Y(1)) resp_r21 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_20_S_v), .n_in_flit(resp_20_S_f), .n_in_ready(resp_20_S_r),
        .n_out_valid(resp_21_N_v), .n_out_flit(resp_21_N_f), .n_out_ready(resp_21_N_r),
        .e_in_valid(resp_31_W_v), .e_in_flit(resp_31_W_f), .e_in_ready(resp_31_W_r),
        .e_out_valid(resp_21_E_v), .e_out_flit(resp_21_E_f), .e_out_ready(resp_21_E_r),
        .s_in_valid(resp_22_N_v), .s_in_flit(resp_22_N_f), .s_in_ready(resp_22_N_r),
        .s_out_valid(resp_21_S_v), .s_out_flit(resp_21_S_f), .s_out_ready(resp_21_S_r),
        .w_in_valid(resp_11_E_v), .w_in_flit(resp_11_E_f), .w_in_ready(resp_11_E_r),
        .w_out_valid(resp_21_W_v), .w_out_flit(resp_21_W_f), .w_out_ready(resp_21_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p7_resp_in_valid), .l_out_flit(p7_resp_in_flit), .l_out_ready(p7_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(3), .MY_Y(1)) req_r31 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_30_S_v), .n_in_flit(req_30_S_f), .n_in_ready(req_30_S_r),
        .n_out_valid(req_31_N_v), .n_out_flit(req_31_N_f), .n_out_ready(req_31_N_r),
        .e_in_valid(req_41_W_v), .e_in_flit(req_41_W_f), .e_in_ready(req_41_W_r),
        .e_out_valid(req_31_E_v), .e_out_flit(req_31_E_f), .e_out_ready(req_31_E_r),
        .s_in_valid(req_32_N_v), .s_in_flit(req_32_N_f), .s_in_ready(req_32_N_r),
        .s_out_valid(req_31_S_v), .s_out_flit(req_31_S_f), .s_out_ready(req_31_S_r),
        .w_in_valid(req_21_E_v), .w_in_flit(req_21_E_f), .w_in_ready(req_21_E_r),
        .w_out_valid(req_31_W_v), .w_out_flit(req_31_W_f), .w_out_ready(req_31_W_r),
        .l_in_valid(p8_req_out_valid), .l_in_flit(p8_req_out_flit), .l_in_ready(p8_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(3), .MY_Y(1)) resp_r31 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_30_S_v), .n_in_flit(resp_30_S_f), .n_in_ready(resp_30_S_r),
        .n_out_valid(resp_31_N_v), .n_out_flit(resp_31_N_f), .n_out_ready(resp_31_N_r),
        .e_in_valid(resp_41_W_v), .e_in_flit(resp_41_W_f), .e_in_ready(resp_41_W_r),
        .e_out_valid(resp_31_E_v), .e_out_flit(resp_31_E_f), .e_out_ready(resp_31_E_r),
        .s_in_valid(resp_32_N_v), .s_in_flit(resp_32_N_f), .s_in_ready(resp_32_N_r),
        .s_out_valid(resp_31_S_v), .s_out_flit(resp_31_S_f), .s_out_ready(resp_31_S_r),
        .w_in_valid(resp_21_E_v), .w_in_flit(resp_21_E_f), .w_in_ready(resp_21_E_r),
        .w_out_valid(resp_31_W_v), .w_out_flit(resp_31_W_f), .w_out_ready(resp_31_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p8_resp_in_valid), .l_out_flit(p8_resp_in_flit), .l_out_ready(p8_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(4), .MY_Y(1)) req_r41 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_40_S_v), .n_in_flit(req_40_S_f), .n_in_ready(req_40_S_r),
        .n_out_valid(req_41_N_v), .n_out_flit(req_41_N_f), .n_out_ready(req_41_N_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_42_N_v), .s_in_flit(req_42_N_f), .s_in_ready(req_42_N_r),
        .s_out_valid(req_41_S_v), .s_out_flit(req_41_S_f), .s_out_ready(req_41_S_r),
        .w_in_valid(req_31_E_v), .w_in_flit(req_31_E_f), .w_in_ready(req_31_E_r),
        .w_out_valid(req_41_W_v), .w_out_flit(req_41_W_f), .w_out_ready(req_41_W_r),
        .l_in_valid(p9_req_out_valid), .l_in_flit(p9_req_out_flit), .l_in_ready(p9_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(4), .MY_Y(1)) resp_r41 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_40_S_v), .n_in_flit(resp_40_S_f), .n_in_ready(resp_40_S_r),
        .n_out_valid(resp_41_N_v), .n_out_flit(resp_41_N_f), .n_out_ready(resp_41_N_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_42_N_v), .s_in_flit(resp_42_N_f), .s_in_ready(resp_42_N_r),
        .s_out_valid(resp_41_S_v), .s_out_flit(resp_41_S_f), .s_out_ready(resp_41_S_r),
        .w_in_valid(resp_31_E_v), .w_in_flit(resp_31_E_f), .w_in_ready(resp_31_E_r),
        .w_out_valid(resp_41_W_v), .w_out_flit(resp_41_W_f), .w_out_ready(resp_41_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p9_resp_in_valid), .l_out_flit(p9_resp_in_flit), .l_out_ready(p9_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(0), .MY_Y(2)) req_r02 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_01_S_v), .n_in_flit(req_01_S_f), .n_in_ready(req_01_S_r),
        .n_out_valid(req_02_N_v), .n_out_flit(req_02_N_f), .n_out_ready(req_02_N_r),
        .e_in_valid(req_12_W_v), .e_in_flit(req_12_W_f), .e_in_ready(req_12_W_r),
        .e_out_valid(req_02_E_v), .e_out_flit(req_02_E_f), .e_out_ready(req_02_E_r),
        .s_in_valid(req_03_N_v), .s_in_flit(req_03_N_f), .s_in_ready(req_03_N_r),
        .s_out_valid(req_02_S_v), .s_out_flit(req_02_S_f), .s_out_ready(req_02_S_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(p10_req_out_valid), .l_in_flit(p10_req_out_flit), .l_in_ready(p10_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(0), .MY_Y(2)) resp_r02 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_01_S_v), .n_in_flit(resp_01_S_f), .n_in_ready(resp_01_S_r),
        .n_out_valid(resp_02_N_v), .n_out_flit(resp_02_N_f), .n_out_ready(resp_02_N_r),
        .e_in_valid(resp_12_W_v), .e_in_flit(resp_12_W_f), .e_in_ready(resp_12_W_r),
        .e_out_valid(resp_02_E_v), .e_out_flit(resp_02_E_f), .e_out_ready(resp_02_E_r),
        .s_in_valid(resp_03_N_v), .s_in_flit(resp_03_N_f), .s_in_ready(resp_03_N_r),
        .s_out_valid(resp_02_S_v), .s_out_flit(resp_02_S_f), .s_out_ready(resp_02_S_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p10_resp_in_valid), .l_out_flit(p10_resp_in_flit), .l_out_ready(p10_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(1), .MY_Y(2)) req_r12 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_11_S_v), .n_in_flit(req_11_S_f), .n_in_ready(req_11_S_r),
        .n_out_valid(req_12_N_v), .n_out_flit(req_12_N_f), .n_out_ready(req_12_N_r),
        .e_in_valid(req_22_W_v), .e_in_flit(req_22_W_f), .e_in_ready(req_22_W_r),
        .e_out_valid(req_12_E_v), .e_out_flit(req_12_E_f), .e_out_ready(req_12_E_r),
        .s_in_valid(req_13_N_v), .s_in_flit(req_13_N_f), .s_in_ready(req_13_N_r),
        .s_out_valid(req_12_S_v), .s_out_flit(req_12_S_f), .s_out_ready(req_12_S_r),
        .w_in_valid(req_02_E_v), .w_in_flit(req_02_E_f), .w_in_ready(req_02_E_r),
        .w_out_valid(req_12_W_v), .w_out_flit(req_12_W_f), .w_out_ready(req_12_W_r),
        .l_in_valid(p11_req_out_valid), .l_in_flit(p11_req_out_flit), .l_in_ready(p11_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(1), .MY_Y(2)) resp_r12 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_11_S_v), .n_in_flit(resp_11_S_f), .n_in_ready(resp_11_S_r),
        .n_out_valid(resp_12_N_v), .n_out_flit(resp_12_N_f), .n_out_ready(resp_12_N_r),
        .e_in_valid(resp_22_W_v), .e_in_flit(resp_22_W_f), .e_in_ready(resp_22_W_r),
        .e_out_valid(resp_12_E_v), .e_out_flit(resp_12_E_f), .e_out_ready(resp_12_E_r),
        .s_in_valid(resp_13_N_v), .s_in_flit(resp_13_N_f), .s_in_ready(resp_13_N_r),
        .s_out_valid(resp_12_S_v), .s_out_flit(resp_12_S_f), .s_out_ready(resp_12_S_r),
        .w_in_valid(resp_02_E_v), .w_in_flit(resp_02_E_f), .w_in_ready(resp_02_E_r),
        .w_out_valid(resp_12_W_v), .w_out_flit(resp_12_W_f), .w_out_ready(resp_12_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p11_resp_in_valid), .l_out_flit(p11_resp_in_flit), .l_out_ready(p11_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(2), .MY_Y(2)) req_r22 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_21_S_v), .n_in_flit(req_21_S_f), .n_in_ready(req_21_S_r),
        .n_out_valid(req_22_N_v), .n_out_flit(req_22_N_f), .n_out_ready(req_22_N_r),
        .e_in_valid(req_32_W_v), .e_in_flit(req_32_W_f), .e_in_ready(req_32_W_r),
        .e_out_valid(req_22_E_v), .e_out_flit(req_22_E_f), .e_out_ready(req_22_E_r),
        .s_in_valid(req_23_N_v), .s_in_flit(req_23_N_f), .s_in_ready(req_23_N_r),
        .s_out_valid(req_22_S_v), .s_out_flit(req_22_S_f), .s_out_ready(req_22_S_r),
        .w_in_valid(req_12_E_v), .w_in_flit(req_12_E_f), .w_in_ready(req_12_E_r),
        .w_out_valid(req_22_W_v), .w_out_flit(req_22_W_f), .w_out_ready(req_22_W_r),
        .l_in_valid(1'b0), .l_in_flit({80{1'b0}}), .l_in_ready(),
        .l_out_valid(mem_req_in_valid), .l_out_flit(mem_req_in_flit), .l_out_ready(mem_req_in_ready)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(2), .MY_Y(2)) resp_r22 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_21_S_v), .n_in_flit(resp_21_S_f), .n_in_ready(resp_21_S_r),
        .n_out_valid(resp_22_N_v), .n_out_flit(resp_22_N_f), .n_out_ready(resp_22_N_r),
        .e_in_valid(resp_32_W_v), .e_in_flit(resp_32_W_f), .e_in_ready(resp_32_W_r),
        .e_out_valid(resp_22_E_v), .e_out_flit(resp_22_E_f), .e_out_ready(resp_22_E_r),
        .s_in_valid(resp_23_N_v), .s_in_flit(resp_23_N_f), .s_in_ready(resp_23_N_r),
        .s_out_valid(resp_22_S_v), .s_out_flit(resp_22_S_f), .s_out_ready(resp_22_S_r),
        .w_in_valid(resp_12_E_v), .w_in_flit(resp_12_E_f), .w_in_ready(resp_12_E_r),
        .w_out_valid(resp_22_W_v), .w_out_flit(resp_22_W_f), .w_out_ready(resp_22_W_r),
        .l_in_valid(mem_resp_out_valid), .l_in_flit(mem_resp_out_flit), .l_in_ready(mem_resp_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(3), .MY_Y(2)) req_r32 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_31_S_v), .n_in_flit(req_31_S_f), .n_in_ready(req_31_S_r),
        .n_out_valid(req_32_N_v), .n_out_flit(req_32_N_f), .n_out_ready(req_32_N_r),
        .e_in_valid(req_42_W_v), .e_in_flit(req_42_W_f), .e_in_ready(req_42_W_r),
        .e_out_valid(req_32_E_v), .e_out_flit(req_32_E_f), .e_out_ready(req_32_E_r),
        .s_in_valid(req_33_N_v), .s_in_flit(req_33_N_f), .s_in_ready(req_33_N_r),
        .s_out_valid(req_32_S_v), .s_out_flit(req_32_S_f), .s_out_ready(req_32_S_r),
        .w_in_valid(req_22_E_v), .w_in_flit(req_22_E_f), .w_in_ready(req_22_E_r),
        .w_out_valid(req_32_W_v), .w_out_flit(req_32_W_f), .w_out_ready(req_32_W_r),
        .l_in_valid(e0_req_out_valid), .l_in_flit(e0_req_out_flit), .l_in_ready(e0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(3), .MY_Y(2)) resp_r32 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_31_S_v), .n_in_flit(resp_31_S_f), .n_in_ready(resp_31_S_r),
        .n_out_valid(resp_32_N_v), .n_out_flit(resp_32_N_f), .n_out_ready(resp_32_N_r),
        .e_in_valid(resp_42_W_v), .e_in_flit(resp_42_W_f), .e_in_ready(resp_42_W_r),
        .e_out_valid(resp_32_E_v), .e_out_flit(resp_32_E_f), .e_out_ready(resp_32_E_r),
        .s_in_valid(resp_33_N_v), .s_in_flit(resp_33_N_f), .s_in_ready(resp_33_N_r),
        .s_out_valid(resp_32_S_v), .s_out_flit(resp_32_S_f), .s_out_ready(resp_32_S_r),
        .w_in_valid(resp_22_E_v), .w_in_flit(resp_22_E_f), .w_in_ready(resp_22_E_r),
        .w_out_valid(resp_32_W_v), .w_out_flit(resp_32_W_f), .w_out_ready(resp_32_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e0_resp_in_valid), .l_out_flit(e0_resp_in_flit), .l_out_ready(e0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(4), .MY_Y(2)) req_r42 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_41_S_v), .n_in_flit(req_41_S_f), .n_in_ready(req_41_S_r),
        .n_out_valid(req_42_N_v), .n_out_flit(req_42_N_f), .n_out_ready(req_42_N_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_43_N_v), .s_in_flit(req_43_N_f), .s_in_ready(req_43_N_r),
        .s_out_valid(req_42_S_v), .s_out_flit(req_42_S_f), .s_out_ready(req_42_S_r),
        .w_in_valid(req_32_E_v), .w_in_flit(req_32_E_f), .w_in_ready(req_32_E_r),
        .w_out_valid(req_42_W_v), .w_out_flit(req_42_W_f), .w_out_ready(req_42_W_r),
        .l_in_valid(e1_req_out_valid), .l_in_flit(e1_req_out_flit), .l_in_ready(e1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(4), .MY_Y(2)) resp_r42 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_41_S_v), .n_in_flit(resp_41_S_f), .n_in_ready(resp_41_S_r),
        .n_out_valid(resp_42_N_v), .n_out_flit(resp_42_N_f), .n_out_ready(resp_42_N_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_43_N_v), .s_in_flit(resp_43_N_f), .s_in_ready(resp_43_N_r),
        .s_out_valid(resp_42_S_v), .s_out_flit(resp_42_S_f), .s_out_ready(resp_42_S_r),
        .w_in_valid(resp_32_E_v), .w_in_flit(resp_32_E_f), .w_in_ready(resp_32_E_r),
        .w_out_valid(resp_42_W_v), .w_out_flit(resp_42_W_f), .w_out_ready(resp_42_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e1_resp_in_valid), .l_out_flit(e1_resp_in_flit), .l_out_ready(e1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(0), .MY_Y(3)) req_r03 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_02_S_v), .n_in_flit(req_02_S_f), .n_in_ready(req_02_S_r),
        .n_out_valid(req_03_N_v), .n_out_flit(req_03_N_f), .n_out_ready(req_03_N_r),
        .e_in_valid(req_13_W_v), .e_in_flit(req_13_W_f), .e_in_ready(req_13_W_r),
        .e_out_valid(req_03_E_v), .e_out_flit(req_03_E_f), .e_out_ready(req_03_E_r),
        .s_in_valid(req_04_N_v), .s_in_flit(req_04_N_f), .s_in_ready(req_04_N_r),
        .s_out_valid(req_03_S_v), .s_out_flit(req_03_S_f), .s_out_ready(req_03_S_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(e2_req_out_valid), .l_in_flit(e2_req_out_flit), .l_in_ready(e2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(0), .MY_Y(3)) resp_r03 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_02_S_v), .n_in_flit(resp_02_S_f), .n_in_ready(resp_02_S_r),
        .n_out_valid(resp_03_N_v), .n_out_flit(resp_03_N_f), .n_out_ready(resp_03_N_r),
        .e_in_valid(resp_13_W_v), .e_in_flit(resp_13_W_f), .e_in_ready(resp_13_W_r),
        .e_out_valid(resp_03_E_v), .e_out_flit(resp_03_E_f), .e_out_ready(resp_03_E_r),
        .s_in_valid(resp_04_N_v), .s_in_flit(resp_04_N_f), .s_in_ready(resp_04_N_r),
        .s_out_valid(resp_03_S_v), .s_out_flit(resp_03_S_f), .s_out_ready(resp_03_S_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e2_resp_in_valid), .l_out_flit(e2_resp_in_flit), .l_out_ready(e2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(1), .MY_Y(3)) req_r13 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_12_S_v), .n_in_flit(req_12_S_f), .n_in_ready(req_12_S_r),
        .n_out_valid(req_13_N_v), .n_out_flit(req_13_N_f), .n_out_ready(req_13_N_r),
        .e_in_valid(req_23_W_v), .e_in_flit(req_23_W_f), .e_in_ready(req_23_W_r),
        .e_out_valid(req_13_E_v), .e_out_flit(req_13_E_f), .e_out_ready(req_13_E_r),
        .s_in_valid(req_14_N_v), .s_in_flit(req_14_N_f), .s_in_ready(req_14_N_r),
        .s_out_valid(req_13_S_v), .s_out_flit(req_13_S_f), .s_out_ready(req_13_S_r),
        .w_in_valid(req_03_E_v), .w_in_flit(req_03_E_f), .w_in_ready(req_03_E_r),
        .w_out_valid(req_13_W_v), .w_out_flit(req_13_W_f), .w_out_ready(req_13_W_r),
        .l_in_valid(e3_req_out_valid), .l_in_flit(e3_req_out_flit), .l_in_ready(e3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(1), .MY_Y(3)) resp_r13 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_12_S_v), .n_in_flit(resp_12_S_f), .n_in_ready(resp_12_S_r),
        .n_out_valid(resp_13_N_v), .n_out_flit(resp_13_N_f), .n_out_ready(resp_13_N_r),
        .e_in_valid(resp_23_W_v), .e_in_flit(resp_23_W_f), .e_in_ready(resp_23_W_r),
        .e_out_valid(resp_13_E_v), .e_out_flit(resp_13_E_f), .e_out_ready(resp_13_E_r),
        .s_in_valid(resp_14_N_v), .s_in_flit(resp_14_N_f), .s_in_ready(resp_14_N_r),
        .s_out_valid(resp_13_S_v), .s_out_flit(resp_13_S_f), .s_out_ready(resp_13_S_r),
        .w_in_valid(resp_03_E_v), .w_in_flit(resp_03_E_f), .w_in_ready(resp_03_E_r),
        .w_out_valid(resp_13_W_v), .w_out_flit(resp_13_W_f), .w_out_ready(resp_13_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e3_resp_in_valid), .l_out_flit(e3_resp_in_flit), .l_out_ready(e3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(2), .MY_Y(3)) req_r23 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_22_S_v), .n_in_flit(req_22_S_f), .n_in_ready(req_22_S_r),
        .n_out_valid(req_23_N_v), .n_out_flit(req_23_N_f), .n_out_ready(req_23_N_r),
        .e_in_valid(req_33_W_v), .e_in_flit(req_33_W_f), .e_in_ready(req_33_W_r),
        .e_out_valid(req_23_E_v), .e_out_flit(req_23_E_f), .e_out_ready(req_23_E_r),
        .s_in_valid(req_24_N_v), .s_in_flit(req_24_N_f), .s_in_ready(req_24_N_r),
        .s_out_valid(req_23_S_v), .s_out_flit(req_23_S_f), .s_out_ready(req_23_S_r),
        .w_in_valid(req_13_E_v), .w_in_flit(req_13_E_f), .w_in_ready(req_13_E_r),
        .w_out_valid(req_23_W_v), .w_out_flit(req_23_W_f), .w_out_ready(req_23_W_r),
        .l_in_valid(e4_req_out_valid), .l_in_flit(e4_req_out_flit), .l_in_ready(e4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(2), .MY_Y(3)) resp_r23 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_22_S_v), .n_in_flit(resp_22_S_f), .n_in_ready(resp_22_S_r),
        .n_out_valid(resp_23_N_v), .n_out_flit(resp_23_N_f), .n_out_ready(resp_23_N_r),
        .e_in_valid(resp_33_W_v), .e_in_flit(resp_33_W_f), .e_in_ready(resp_33_W_r),
        .e_out_valid(resp_23_E_v), .e_out_flit(resp_23_E_f), .e_out_ready(resp_23_E_r),
        .s_in_valid(resp_24_N_v), .s_in_flit(resp_24_N_f), .s_in_ready(resp_24_N_r),
        .s_out_valid(resp_23_S_v), .s_out_flit(resp_23_S_f), .s_out_ready(resp_23_S_r),
        .w_in_valid(resp_13_E_v), .w_in_flit(resp_13_E_f), .w_in_ready(resp_13_E_r),
        .w_out_valid(resp_23_W_v), .w_out_flit(resp_23_W_f), .w_out_ready(resp_23_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e4_resp_in_valid), .l_out_flit(e4_resp_in_flit), .l_out_ready(e4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(3), .MY_Y(3)) req_r33 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_32_S_v), .n_in_flit(req_32_S_f), .n_in_ready(req_32_S_r),
        .n_out_valid(req_33_N_v), .n_out_flit(req_33_N_f), .n_out_ready(req_33_N_r),
        .e_in_valid(req_43_W_v), .e_in_flit(req_43_W_f), .e_in_ready(req_43_W_r),
        .e_out_valid(req_33_E_v), .e_out_flit(req_33_E_f), .e_out_ready(req_33_E_r),
        .s_in_valid(req_34_N_v), .s_in_flit(req_34_N_f), .s_in_ready(req_34_N_r),
        .s_out_valid(req_33_S_v), .s_out_flit(req_33_S_f), .s_out_ready(req_33_S_r),
        .w_in_valid(req_23_E_v), .w_in_flit(req_23_E_f), .w_in_ready(req_23_E_r),
        .w_out_valid(req_33_W_v), .w_out_flit(req_33_W_f), .w_out_ready(req_33_W_r),
        .l_in_valid(e5_req_out_valid), .l_in_flit(e5_req_out_flit), .l_in_ready(e5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(3), .MY_Y(3)) resp_r33 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_32_S_v), .n_in_flit(resp_32_S_f), .n_in_ready(resp_32_S_r),
        .n_out_valid(resp_33_N_v), .n_out_flit(resp_33_N_f), .n_out_ready(resp_33_N_r),
        .e_in_valid(resp_43_W_v), .e_in_flit(resp_43_W_f), .e_in_ready(resp_43_W_r),
        .e_out_valid(resp_33_E_v), .e_out_flit(resp_33_E_f), .e_out_ready(resp_33_E_r),
        .s_in_valid(resp_34_N_v), .s_in_flit(resp_34_N_f), .s_in_ready(resp_34_N_r),
        .s_out_valid(resp_33_S_v), .s_out_flit(resp_33_S_f), .s_out_ready(resp_33_S_r),
        .w_in_valid(resp_23_E_v), .w_in_flit(resp_23_E_f), .w_in_ready(resp_23_E_r),
        .w_out_valid(resp_33_W_v), .w_out_flit(resp_33_W_f), .w_out_ready(resp_33_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e5_resp_in_valid), .l_out_flit(e5_resp_in_flit), .l_out_ready(e5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(4), .MY_Y(3)) req_r43 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_42_S_v), .n_in_flit(req_42_S_f), .n_in_ready(req_42_S_r),
        .n_out_valid(req_43_N_v), .n_out_flit(req_43_N_f), .n_out_ready(req_43_N_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_44_N_v), .s_in_flit(req_44_N_f), .s_in_ready(req_44_N_r),
        .s_out_valid(req_43_S_v), .s_out_flit(req_43_S_f), .s_out_ready(req_43_S_r),
        .w_in_valid(req_33_E_v), .w_in_flit(req_33_E_f), .w_in_ready(req_33_E_r),
        .w_out_valid(req_43_W_v), .w_out_flit(req_43_W_f), .w_out_ready(req_43_W_r),
        .l_in_valid(e6_req_out_valid), .l_in_flit(e6_req_out_flit), .l_in_ready(e6_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(4), .MY_Y(3)) resp_r43 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_42_S_v), .n_in_flit(resp_42_S_f), .n_in_ready(resp_42_S_r),
        .n_out_valid(resp_43_N_v), .n_out_flit(resp_43_N_f), .n_out_ready(resp_43_N_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_44_N_v), .s_in_flit(resp_44_N_f), .s_in_ready(resp_44_N_r),
        .s_out_valid(resp_43_S_v), .s_out_flit(resp_43_S_f), .s_out_ready(resp_43_S_r),
        .w_in_valid(resp_33_E_v), .w_in_flit(resp_33_E_f), .w_in_ready(resp_33_E_r),
        .w_out_valid(resp_43_W_v), .w_out_flit(resp_43_W_f), .w_out_ready(resp_43_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e6_resp_in_valid), .l_out_flit(e6_resp_in_flit), .l_out_ready(e6_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(0), .MY_Y(4)) req_r04 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_03_S_v), .n_in_flit(req_03_S_f), .n_in_ready(req_03_S_r),
        .n_out_valid(req_04_N_v), .n_out_flit(req_04_N_f), .n_out_ready(req_04_N_r),
        .e_in_valid(req_14_W_v), .e_in_flit(req_14_W_f), .e_in_ready(req_14_W_r),
        .e_out_valid(req_04_E_v), .e_out_flit(req_04_E_f), .e_out_ready(req_04_E_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(e7_req_out_valid), .l_in_flit(e7_req_out_flit), .l_in_ready(e7_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(0), .MY_Y(4)) resp_r04 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_03_S_v), .n_in_flit(resp_03_S_f), .n_in_ready(resp_03_S_r),
        .n_out_valid(resp_04_N_v), .n_out_flit(resp_04_N_f), .n_out_ready(resp_04_N_r),
        .e_in_valid(resp_14_W_v), .e_in_flit(resp_14_W_f), .e_in_ready(resp_14_W_r),
        .e_out_valid(resp_04_E_v), .e_out_flit(resp_04_E_f), .e_out_ready(resp_04_E_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e7_resp_in_valid), .l_out_flit(e7_resp_in_flit), .l_out_ready(e7_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(1), .MY_Y(4)) req_r14 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_13_S_v), .n_in_flit(req_13_S_f), .n_in_ready(req_13_S_r),
        .n_out_valid(req_14_N_v), .n_out_flit(req_14_N_f), .n_out_ready(req_14_N_r),
        .e_in_valid(req_24_W_v), .e_in_flit(req_24_W_f), .e_in_ready(req_24_W_r),
        .e_out_valid(req_14_E_v), .e_out_flit(req_14_E_f), .e_out_ready(req_14_E_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_04_E_v), .w_in_flit(req_04_E_f), .w_in_ready(req_04_E_r),
        .w_out_valid(req_14_W_v), .w_out_flit(req_14_W_f), .w_out_ready(req_14_W_r),
        .l_in_valid(e8_req_out_valid), .l_in_flit(e8_req_out_flit), .l_in_ready(e8_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(1), .MY_Y(4)) resp_r14 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_13_S_v), .n_in_flit(resp_13_S_f), .n_in_ready(resp_13_S_r),
        .n_out_valid(resp_14_N_v), .n_out_flit(resp_14_N_f), .n_out_ready(resp_14_N_r),
        .e_in_valid(resp_24_W_v), .e_in_flit(resp_24_W_f), .e_in_ready(resp_24_W_r),
        .e_out_valid(resp_14_E_v), .e_out_flit(resp_14_E_f), .e_out_ready(resp_14_E_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_04_E_v), .w_in_flit(resp_04_E_f), .w_in_ready(resp_04_E_r),
        .w_out_valid(resp_14_W_v), .w_out_flit(resp_14_W_f), .w_out_ready(resp_14_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e8_resp_in_valid), .l_out_flit(e8_resp_in_flit), .l_out_ready(e8_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(2), .MY_Y(4)) req_r24 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_23_S_v), .n_in_flit(req_23_S_f), .n_in_ready(req_23_S_r),
        .n_out_valid(req_24_N_v), .n_out_flit(req_24_N_f), .n_out_ready(req_24_N_r),
        .e_in_valid(req_34_W_v), .e_in_flit(req_34_W_f), .e_in_ready(req_34_W_r),
        .e_out_valid(req_24_E_v), .e_out_flit(req_24_E_f), .e_out_ready(req_24_E_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_14_E_v), .w_in_flit(req_14_E_f), .w_in_ready(req_14_E_r),
        .w_out_valid(req_24_W_v), .w_out_flit(req_24_W_f), .w_out_ready(req_24_W_r),
        .l_in_valid(e9_req_out_valid), .l_in_flit(e9_req_out_flit), .l_in_ready(e9_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(2), .MY_Y(4)) resp_r24 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_23_S_v), .n_in_flit(resp_23_S_f), .n_in_ready(resp_23_S_r),
        .n_out_valid(resp_24_N_v), .n_out_flit(resp_24_N_f), .n_out_ready(resp_24_N_r),
        .e_in_valid(resp_34_W_v), .e_in_flit(resp_34_W_f), .e_in_ready(resp_34_W_r),
        .e_out_valid(resp_24_E_v), .e_out_flit(resp_24_E_f), .e_out_ready(resp_24_E_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_14_E_v), .w_in_flit(resp_14_E_f), .w_in_ready(resp_14_E_r),
        .w_out_valid(resp_24_W_v), .w_out_flit(resp_24_W_f), .w_out_ready(resp_24_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e9_resp_in_valid), .l_out_flit(e9_resp_in_flit), .l_out_ready(e9_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(3), .MY_Y(4)) req_r34 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_33_S_v), .n_in_flit(req_33_S_f), .n_in_ready(req_33_S_r),
        .n_out_valid(req_34_N_v), .n_out_flit(req_34_N_f), .n_out_ready(req_34_N_r),
        .e_in_valid(req_44_W_v), .e_in_flit(req_44_W_f), .e_in_ready(req_44_W_r),
        .e_out_valid(req_34_E_v), .e_out_flit(req_34_E_f), .e_out_ready(req_34_E_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_24_E_v), .w_in_flit(req_24_E_f), .w_in_ready(req_24_E_r),
        .w_out_valid(req_34_W_v), .w_out_flit(req_34_W_f), .w_out_ready(req_34_W_r),
        .l_in_valid(e10_req_out_valid), .l_in_flit(e10_req_out_flit), .l_in_ready(e10_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(3), .MY_Y(4)) resp_r34 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_33_S_v), .n_in_flit(resp_33_S_f), .n_in_ready(resp_33_S_r),
        .n_out_valid(resp_34_N_v), .n_out_flit(resp_34_N_f), .n_out_ready(resp_34_N_r),
        .e_in_valid(resp_44_W_v), .e_in_flit(resp_44_W_f), .e_in_ready(resp_44_W_r),
        .e_out_valid(resp_34_E_v), .e_out_flit(resp_34_E_f), .e_out_ready(resp_34_E_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_24_E_v), .w_in_flit(resp_24_E_f), .w_in_ready(resp_24_E_r),
        .w_out_valid(resp_34_W_v), .w_out_flit(resp_34_W_f), .w_out_ready(resp_34_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e10_resp_in_valid), .l_out_flit(e10_resp_in_flit), .l_out_ready(e10_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(3), .MY_X(4), .MY_Y(4)) req_r44 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_43_S_v), .n_in_flit(req_43_S_f), .n_in_ready(req_43_S_r),
        .n_out_valid(req_44_N_v), .n_out_flit(req_44_N_f), .n_out_ready(req_44_N_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_34_E_v), .w_in_flit(req_34_E_f), .w_in_ready(req_34_E_r),
        .w_out_valid(req_44_W_v), .w_out_flit(req_44_W_f), .w_out_ready(req_44_W_r),
        .l_in_valid(e11_req_out_valid), .l_in_flit(e11_req_out_flit), .l_in_ready(e11_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(3), .MY_X(4), .MY_Y(4)) resp_r44 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_43_S_v), .n_in_flit(resp_43_S_f), .n_in_ready(resp_43_S_r),
        .n_out_valid(resp_44_N_v), .n_out_flit(resp_44_N_f), .n_out_ready(resp_44_N_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_34_E_v), .w_in_flit(resp_34_E_f), .w_in_ready(resp_34_E_r),
        .w_out_valid(resp_44_W_v), .w_out_flit(resp_44_W_f), .w_out_ready(resp_44_W_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e11_resp_in_valid), .l_out_flit(e11_resp_in_flit), .l_out_ready(e11_resp_in_ready)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(2), .MY_Y(0), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(3), .MY_Y(0), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(4), .MY_Y(0), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p5_adap (
        .clk(clk), .reset(reset),
        .bus_req(p5_bus_req), .bus_addr(p5_bus_addr), .bus_write_data(p5_bus_write_data),
        .bus_mem_write(p5_bus_mem_write), .bus_mem_size(p5_bus_mem_size), .bus_mem_unsigned(p5_bus_mem_unsigned),
        .bus_grant(p5_bus_grant), .bus_read_data(p5_bus_read_data),
        .req_out_valid(p5_req_out_valid), .req_out_flit(p5_req_out_flit), .req_out_ready(p5_req_out_ready),
        .resp_in_valid(p5_resp_in_valid), .resp_in_flit(p5_resp_in_flit), .resp_in_ready(p5_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P6_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p6_core (
        .clk(clk), .reset(reset),
        .halted(p6_halted), .tohost_value(p6_tohost),
        .bus_req(p6_bus_req), .bus_addr(p6_bus_addr),
        .bus_write_data(p6_bus_write_data), .bus_mem_write(p6_bus_mem_write),
        .bus_mem_size(p6_bus_mem_size), .bus_mem_unsigned(p6_bus_mem_unsigned),
        .bus_grant(p6_bus_grant), .bus_read_data(p6_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p6_adap (
        .clk(clk), .reset(reset),
        .bus_req(p6_bus_req), .bus_addr(p6_bus_addr), .bus_write_data(p6_bus_write_data),
        .bus_mem_write(p6_bus_mem_write), .bus_mem_size(p6_bus_mem_size), .bus_mem_unsigned(p6_bus_mem_unsigned),
        .bus_grant(p6_bus_grant), .bus_read_data(p6_bus_read_data),
        .req_out_valid(p6_req_out_valid), .req_out_flit(p6_req_out_flit), .req_out_ready(p6_req_out_ready),
        .resp_in_valid(p6_resp_in_valid), .resp_in_flit(p6_resp_in_flit), .resp_in_ready(p6_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P7_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p7_core (
        .clk(clk), .reset(reset),
        .halted(p7_halted), .tohost_value(p7_tohost),
        .bus_req(p7_bus_req), .bus_addr(p7_bus_addr),
        .bus_write_data(p7_bus_write_data), .bus_mem_write(p7_bus_mem_write),
        .bus_mem_size(p7_bus_mem_size), .bus_mem_unsigned(p7_bus_mem_unsigned),
        .bus_grant(p7_bus_grant), .bus_read_data(p7_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(2), .MY_Y(1), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p7_adap (
        .clk(clk), .reset(reset),
        .bus_req(p7_bus_req), .bus_addr(p7_bus_addr), .bus_write_data(p7_bus_write_data),
        .bus_mem_write(p7_bus_mem_write), .bus_mem_size(p7_bus_mem_size), .bus_mem_unsigned(p7_bus_mem_unsigned),
        .bus_grant(p7_bus_grant), .bus_read_data(p7_bus_read_data),
        .req_out_valid(p7_req_out_valid), .req_out_flit(p7_req_out_flit), .req_out_ready(p7_req_out_ready),
        .resp_in_valid(p7_resp_in_valid), .resp_in_flit(p7_resp_in_flit), .resp_in_ready(p7_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P8_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p8_core (
        .clk(clk), .reset(reset),
        .halted(p8_halted), .tohost_value(p8_tohost),
        .bus_req(p8_bus_req), .bus_addr(p8_bus_addr),
        .bus_write_data(p8_bus_write_data), .bus_mem_write(p8_bus_mem_write),
        .bus_mem_size(p8_bus_mem_size), .bus_mem_unsigned(p8_bus_mem_unsigned),
        .bus_grant(p8_bus_grant), .bus_read_data(p8_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(3), .MY_Y(1), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p8_adap (
        .clk(clk), .reset(reset),
        .bus_req(p8_bus_req), .bus_addr(p8_bus_addr), .bus_write_data(p8_bus_write_data),
        .bus_mem_write(p8_bus_mem_write), .bus_mem_size(p8_bus_mem_size), .bus_mem_unsigned(p8_bus_mem_unsigned),
        .bus_grant(p8_bus_grant), .bus_read_data(p8_bus_read_data),
        .req_out_valid(p8_req_out_valid), .req_out_flit(p8_req_out_flit), .req_out_ready(p8_req_out_ready),
        .resp_in_valid(p8_resp_in_valid), .resp_in_flit(p8_resp_in_flit), .resp_in_ready(p8_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P9_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p9_core (
        .clk(clk), .reset(reset),
        .halted(p9_halted), .tohost_value(p9_tohost),
        .bus_req(p9_bus_req), .bus_addr(p9_bus_addr),
        .bus_write_data(p9_bus_write_data), .bus_mem_write(p9_bus_mem_write),
        .bus_mem_size(p9_bus_mem_size), .bus_mem_unsigned(p9_bus_mem_unsigned),
        .bus_grant(p9_bus_grant), .bus_read_data(p9_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(4), .MY_Y(1), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p9_adap (
        .clk(clk), .reset(reset),
        .bus_req(p9_bus_req), .bus_addr(p9_bus_addr), .bus_write_data(p9_bus_write_data),
        .bus_mem_write(p9_bus_mem_write), .bus_mem_size(p9_bus_mem_size), .bus_mem_unsigned(p9_bus_mem_unsigned),
        .bus_grant(p9_bus_grant), .bus_read_data(p9_bus_read_data),
        .req_out_valid(p9_req_out_valid), .req_out_flit(p9_req_out_flit), .req_out_ready(p9_req_out_ready),
        .resp_in_valid(p9_resp_in_valid), .resp_in_flit(p9_resp_in_flit), .resp_in_ready(p9_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P10_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p10_core (
        .clk(clk), .reset(reset),
        .halted(p10_halted), .tohost_value(p10_tohost),
        .bus_req(p10_bus_req), .bus_addr(p10_bus_addr),
        .bus_write_data(p10_bus_write_data), .bus_mem_write(p10_bus_mem_write),
        .bus_mem_size(p10_bus_mem_size), .bus_mem_unsigned(p10_bus_mem_unsigned),
        .bus_grant(p10_bus_grant), .bus_read_data(p10_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p10_adap (
        .clk(clk), .reset(reset),
        .bus_req(p10_bus_req), .bus_addr(p10_bus_addr), .bus_write_data(p10_bus_write_data),
        .bus_mem_write(p10_bus_mem_write), .bus_mem_size(p10_bus_mem_size), .bus_mem_unsigned(p10_bus_mem_unsigned),
        .bus_grant(p10_bus_grant), .bus_read_data(p10_bus_read_data),
        .req_out_valid(p10_req_out_valid), .req_out_flit(p10_req_out_flit), .req_out_ready(p10_req_out_ready),
        .resp_in_valid(p10_resp_in_valid), .resp_in_flit(p10_resp_in_flit), .resp_in_ready(p10_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P11_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p11_core (
        .clk(clk), .reset(reset),
        .halted(p11_halted), .tohost_value(p11_tohost),
        .bus_req(p11_bus_req), .bus_addr(p11_bus_addr),
        .bus_write_data(p11_bus_write_data), .bus_mem_write(p11_bus_mem_write),
        .bus_mem_size(p11_bus_mem_size), .bus_mem_unsigned(p11_bus_mem_unsigned),
        .bus_grant(p11_bus_grant), .bus_read_data(p11_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p11_adap (
        .clk(clk), .reset(reset),
        .bus_req(p11_bus_req), .bus_addr(p11_bus_addr), .bus_write_data(p11_bus_write_data),
        .bus_mem_write(p11_bus_mem_write), .bus_mem_size(p11_bus_mem_size), .bus_mem_unsigned(p11_bus_mem_unsigned),
        .bus_grant(p11_bus_grant), .bus_read_data(p11_bus_read_data),
        .req_out_valid(p11_req_out_valid), .req_out_flit(p11_req_out_flit), .req_out_ready(p11_req_out_ready),
        .resp_in_valid(p11_resp_in_valid), .resp_in_flit(p11_resp_in_flit), .resp_in_ready(p11_resp_in_ready)
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
        .COORD_BITS(3), .MY_X(3), .MY_Y(2), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(4), .MY_Y(2), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(3), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(3), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(2), .MY_Y(3), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
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
        .COORD_BITS(3), .MY_X(3), .MY_Y(3), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e5_adap (
        .clk(clk), .reset(reset),
        .bus_req(e5_bus_req), .bus_addr(e5_bus_addr), .bus_write_data(e5_bus_write_data),
        .bus_mem_write(e5_bus_mem_write), .bus_mem_size(e5_bus_mem_size), .bus_mem_unsigned(e5_bus_mem_unsigned),
        .bus_grant(e5_bus_grant), .bus_read_data(e5_bus_read_data),
        .req_out_valid(e5_req_out_valid), .req_out_flit(e5_req_out_flit), .req_out_ready(e5_req_out_ready),
        .resp_in_valid(e5_resp_in_valid), .resp_in_flit(e5_resp_in_flit), .resp_in_ready(e5_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E6_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e6_core (
        .clk(clk), .reset(reset),
        .halted(e6_halted), .tohost_value(e6_tohost),
        .bus_req(e6_bus_req), .bus_addr(e6_bus_addr),
        .bus_write_data(e6_bus_write_data), .bus_mem_write(e6_bus_mem_write),
        .bus_mem_size(e6_bus_mem_size), .bus_mem_unsigned(e6_bus_mem_unsigned),
        .bus_grant(e6_bus_grant), .bus_read_data(e6_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(4), .MY_Y(3), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e6_adap (
        .clk(clk), .reset(reset),
        .bus_req(e6_bus_req), .bus_addr(e6_bus_addr), .bus_write_data(e6_bus_write_data),
        .bus_mem_write(e6_bus_mem_write), .bus_mem_size(e6_bus_mem_size), .bus_mem_unsigned(e6_bus_mem_unsigned),
        .bus_grant(e6_bus_grant), .bus_read_data(e6_bus_read_data),
        .req_out_valid(e6_req_out_valid), .req_out_flit(e6_req_out_flit), .req_out_ready(e6_req_out_ready),
        .resp_in_valid(e6_resp_in_valid), .resp_in_flit(e6_resp_in_flit), .resp_in_ready(e6_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E7_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e7_core (
        .clk(clk), .reset(reset),
        .halted(e7_halted), .tohost_value(e7_tohost),
        .bus_req(e7_bus_req), .bus_addr(e7_bus_addr),
        .bus_write_data(e7_bus_write_data), .bus_mem_write(e7_bus_mem_write),
        .bus_mem_size(e7_bus_mem_size), .bus_mem_unsigned(e7_bus_mem_unsigned),
        .bus_grant(e7_bus_grant), .bus_read_data(e7_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(4), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e7_adap (
        .clk(clk), .reset(reset),
        .bus_req(e7_bus_req), .bus_addr(e7_bus_addr), .bus_write_data(e7_bus_write_data),
        .bus_mem_write(e7_bus_mem_write), .bus_mem_size(e7_bus_mem_size), .bus_mem_unsigned(e7_bus_mem_unsigned),
        .bus_grant(e7_bus_grant), .bus_read_data(e7_bus_read_data),
        .req_out_valid(e7_req_out_valid), .req_out_flit(e7_req_out_flit), .req_out_ready(e7_req_out_ready),
        .resp_in_valid(e7_resp_in_valid), .resp_in_flit(e7_resp_in_flit), .resp_in_ready(e7_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E8_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e8_core (
        .clk(clk), .reset(reset),
        .halted(e8_halted), .tohost_value(e8_tohost),
        .bus_req(e8_bus_req), .bus_addr(e8_bus_addr),
        .bus_write_data(e8_bus_write_data), .bus_mem_write(e8_bus_mem_write),
        .bus_mem_size(e8_bus_mem_size), .bus_mem_unsigned(e8_bus_mem_unsigned),
        .bus_grant(e8_bus_grant), .bus_read_data(e8_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(4), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e8_adap (
        .clk(clk), .reset(reset),
        .bus_req(e8_bus_req), .bus_addr(e8_bus_addr), .bus_write_data(e8_bus_write_data),
        .bus_mem_write(e8_bus_mem_write), .bus_mem_size(e8_bus_mem_size), .bus_mem_unsigned(e8_bus_mem_unsigned),
        .bus_grant(e8_bus_grant), .bus_read_data(e8_bus_read_data),
        .req_out_valid(e8_req_out_valid), .req_out_flit(e8_req_out_flit), .req_out_ready(e8_req_out_ready),
        .resp_in_valid(e8_resp_in_valid), .resp_in_flit(e8_resp_in_flit), .resp_in_ready(e8_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E9_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e9_core (
        .clk(clk), .reset(reset),
        .halted(e9_halted), .tohost_value(e9_tohost),
        .bus_req(e9_bus_req), .bus_addr(e9_bus_addr),
        .bus_write_data(e9_bus_write_data), .bus_mem_write(e9_bus_mem_write),
        .bus_mem_size(e9_bus_mem_size), .bus_mem_unsigned(e9_bus_mem_unsigned),
        .bus_grant(e9_bus_grant), .bus_read_data(e9_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(2), .MY_Y(4), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e9_adap (
        .clk(clk), .reset(reset),
        .bus_req(e9_bus_req), .bus_addr(e9_bus_addr), .bus_write_data(e9_bus_write_data),
        .bus_mem_write(e9_bus_mem_write), .bus_mem_size(e9_bus_mem_size), .bus_mem_unsigned(e9_bus_mem_unsigned),
        .bus_grant(e9_bus_grant), .bus_read_data(e9_bus_read_data),
        .req_out_valid(e9_req_out_valid), .req_out_flit(e9_req_out_flit), .req_out_ready(e9_req_out_ready),
        .resp_in_valid(e9_resp_in_valid), .resp_in_flit(e9_resp_in_flit), .resp_in_ready(e9_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E10_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e10_core (
        .clk(clk), .reset(reset),
        .halted(e10_halted), .tohost_value(e10_tohost),
        .bus_req(e10_bus_req), .bus_addr(e10_bus_addr),
        .bus_write_data(e10_bus_write_data), .bus_mem_write(e10_bus_mem_write),
        .bus_mem_size(e10_bus_mem_size), .bus_mem_unsigned(e10_bus_mem_unsigned),
        .bus_grant(e10_bus_grant), .bus_read_data(e10_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(3), .MY_Y(4), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e10_adap (
        .clk(clk), .reset(reset),
        .bus_req(e10_bus_req), .bus_addr(e10_bus_addr), .bus_write_data(e10_bus_write_data),
        .bus_mem_write(e10_bus_mem_write), .bus_mem_size(e10_bus_mem_size), .bus_mem_unsigned(e10_bus_mem_unsigned),
        .bus_grant(e10_bus_grant), .bus_read_data(e10_bus_read_data),
        .req_out_valid(e10_req_out_valid), .req_out_flit(e10_req_out_flit), .req_out_ready(e10_req_out_ready),
        .resp_in_valid(e10_resp_in_valid), .resp_in_flit(e10_resp_in_flit), .resp_in_ready(e10_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E11_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e11_core (
        .clk(clk), .reset(reset),
        .halted(e11_halted), .tohost_value(e11_tohost),
        .bus_req(e11_bus_req), .bus_addr(e11_bus_addr),
        .bus_write_data(e11_bus_write_data), .bus_mem_write(e11_bus_mem_write),
        .bus_mem_size(e11_bus_mem_size), .bus_mem_unsigned(e11_bus_mem_unsigned),
        .bus_grant(e11_bus_grant), .bus_read_data(e11_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(4), .MY_Y(4), .MEM_X(2), .MEM_Y(2),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e11_adap (
        .clk(clk), .reset(reset),
        .bus_req(e11_bus_req), .bus_addr(e11_bus_addr), .bus_write_data(e11_bus_write_data),
        .bus_mem_write(e11_bus_mem_write), .bus_mem_size(e11_bus_mem_size), .bus_mem_unsigned(e11_bus_mem_unsigned),
        .bus_grant(e11_bus_grant), .bus_read_data(e11_bus_read_data),
        .req_out_valid(e11_req_out_valid), .req_out_flit(e11_req_out_flit), .req_out_ready(e11_req_out_ready),
        .resp_in_valid(e11_resp_in_valid), .resp_in_flit(e11_resp_in_flit), .resp_in_ready(e11_resp_in_ready)
    );

    // ==================== Memory node ====================
    noc_mem_adapter #(
        .COORD_BITS(3), .MEM_BYTES(SHARED_MEM_BYTES), .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) mem_adap (
        .clk(clk), .reset(reset),
        .req_in_valid(mem_req_in_valid), .req_in_flit(mem_req_in_flit), .req_in_ready(mem_req_in_ready),
        .resp_out_valid(mem_resp_out_valid), .resp_out_flit(mem_resp_out_flit), .resp_out_ready(mem_resp_out_ready)
    );

    assign all_halted = p0_halted && p1_halted && p2_halted && p3_halted && p4_halted && p5_halted && p6_halted && p7_halted && p8_halted && p9_halted && p10_halted && p11_halted && e0_halted && e1_halted && e2_halted && e3_halted && e4_halted && e5_halted && e6_halted && e7_halted && e8_halted && e9_halted && e10_halted && e11_halted;
endmodule
