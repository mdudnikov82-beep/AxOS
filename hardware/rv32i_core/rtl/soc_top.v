// Network-on-Chip mini-SoC (hardware/rv32i_core) - a real 3D 3x4x3 mesh
// of XYZ-routed routers (router.v), each grid position connected to its
// N/E/S/W/Up/Down neighbors plus a Local port for whatever core or
// memory endpoint sits there. TWO independent router networks span the
// whole grid - REQUEST (core -> memory, FLIT_WIDTH=80) and RESPONSE
// (memory -> core, FLIT_WIDTH=38) - kept as fully separate router
// instances with zero shared state (see [[project_noc_router]]).
//
// First 3D NoC in this project (prior meshes were 2D NxN) - extended via
// a real design review before any RTL: router.v gained Up/Down ports and
// a third XYZ routing tier (dimension-order routing's deadlock-freedom
// proof generalizes to any dimension count, confirmed rather than
// assumed), and the flit format gained a third coordinate field
// end-to-end (noc_core_adapter.v/noc_mem_adapter.v).
//
// COORD_BITS=2 is shared across all three axes even though they're
// different sizes (X,Z have 3 values, Y has 4) - confirmed numerically
// safe by design review as long as every axis's real range fits, not
// just the largest one (2 bits covers 0-3, comfortably covering all
// three axes here).
//
// Memory lives at (1,1,1) - the exact center on the two size-3
// axes (X,Z), and one of the two symmetric center positions on the
// size-4 Y axis (Y=1 and Y=2 are provably identical by symmetry, per
// design review) - not a corner. 35 of the 36 remaining positions host
// 18 P-cores (cpu_core_pipelined) and 17 E-cores (cpu_core); 0 are spare,
// pass-through-only routers with no local endpoint.
//
// External module interface (parameters and ports) follows the same
// shape as the prior 2D soc_top.v (per-core INSTR_HEX parameter, per-core
// halted/tohost outputs, all_halted) - only the grid topology and
// dimensionality differ.
//
// Grid layout (x,y,z), MEM at center - shown as Z-layer slices since one
// 2D picture can't show a cube:
//
//   Z=0:
//     p0     p12    e5   
//     p3     p15    e8   
//     p6     p17    e11  
//     p9     e2     e14  
//   Z=1:
//     p1     p13    e6   
//     p4     MEM    e9   
//     p7     e0     e12  
//     p10    e3     e15  
//   Z=2:
//     p2     p14    e7   
//     p5     p16    e10  
//     p8     e1     e13  
//     p11    e4     e16  
`timescale 1ns/1ps

module soc_top #(
    parameter P0_INSTR_HEX = "",
    parameter P1_INSTR_HEX = "",
    parameter P2_INSTR_HEX = "",
    parameter P3_INSTR_HEX = "",
    parameter P4_INSTR_HEX = "",
    parameter P5_INSTR_HEX = "",
    parameter P6_INSTR_HEX = "",
    parameter P7_INSTR_HEX = "",
    parameter P8_INSTR_HEX = "",
    parameter P9_INSTR_HEX = "",
    parameter P10_INSTR_HEX = "",
    parameter P11_INSTR_HEX = "",
    parameter P12_INSTR_HEX = "",
    parameter P13_INSTR_HEX = "",
    parameter P14_INSTR_HEX = "",
    parameter P15_INSTR_HEX = "",
    parameter P16_INSTR_HEX = "",
    parameter P17_INSTR_HEX = "",
    parameter E0_INSTR_HEX = "",
    parameter E1_INSTR_HEX = "",
    parameter E2_INSTR_HEX = "",
    parameter E3_INSTR_HEX = "",
    parameter E4_INSTR_HEX = "",
    parameter E5_INSTR_HEX = "",
    parameter E6_INSTR_HEX = "",
    parameter E7_INSTR_HEX = "",
    parameter E8_INSTR_HEX = "",
    parameter E9_INSTR_HEX = "",
    parameter E10_INSTR_HEX = "",
    parameter E11_INSTR_HEX = "",
    parameter E12_INSTR_HEX = "",
    parameter E13_INSTR_HEX = "",
    parameter E14_INSTR_HEX = "",
    parameter E15_INSTR_HEX = "",
    parameter E16_INSTR_HEX = "",
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
    output wire        p12_halted,
    output wire [31:0]  p12_tohost,
    output wire        p13_halted,
    output wire [31:0]  p13_tohost,
    output wire        p14_halted,
    output wire [31:0]  p14_tohost,
    output wire        p15_halted,
    output wire [31:0]  p15_tohost,
    output wire        p16_halted,
    output wire [31:0]  p16_tohost,
    output wire        p17_halted,
    output wire [31:0]  p17_tohost,
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
    output wire        e12_halted,
    output wire [31:0]  e12_tohost,
    output wire        e13_halted,
    output wire [31:0]  e13_tohost,
    output wire        e14_halted,
    output wire [31:0]  e14_tohost,
    output wire        e15_halted,
    output wire [31:0]  e15_tohost,
    output wire        e16_halted,
    output wire [31:0]  e16_tohost,
    output wire        all_halted
);

    // ==================== Mesh link wires ====================
    // One {valid,flit,ready} triple per (node, direction) that has a
    // real neighbor, representing THAT node's own outgoing flow in that
    // direction - referenced directly (shared wire names, no extra
    // `assign`s needed) from both this node's *_out_* ports and the
    // neighbor's opposite-direction *_in_* ports.
    wire req_0_0_0_S_v, req_0_0_0_S_r; wire [79:0] req_0_0_0_S_f;
    wire req_0_0_0_E_v, req_0_0_0_E_r; wire [79:0] req_0_0_0_E_f;
    wire req_0_0_0_D_v, req_0_0_0_D_r; wire [79:0] req_0_0_0_D_f;
    wire req_0_0_1_S_v, req_0_0_1_S_r; wire [79:0] req_0_0_1_S_f;
    wire req_0_0_1_E_v, req_0_0_1_E_r; wire [79:0] req_0_0_1_E_f;
    wire req_0_0_1_U_v, req_0_0_1_U_r; wire [79:0] req_0_0_1_U_f;
    wire req_0_0_1_D_v, req_0_0_1_D_r; wire [79:0] req_0_0_1_D_f;
    wire req_0_0_2_S_v, req_0_0_2_S_r; wire [79:0] req_0_0_2_S_f;
    wire req_0_0_2_E_v, req_0_0_2_E_r; wire [79:0] req_0_0_2_E_f;
    wire req_0_0_2_U_v, req_0_0_2_U_r; wire [79:0] req_0_0_2_U_f;
    wire req_0_1_0_N_v, req_0_1_0_N_r; wire [79:0] req_0_1_0_N_f;
    wire req_0_1_0_S_v, req_0_1_0_S_r; wire [79:0] req_0_1_0_S_f;
    wire req_0_1_0_E_v, req_0_1_0_E_r; wire [79:0] req_0_1_0_E_f;
    wire req_0_1_0_D_v, req_0_1_0_D_r; wire [79:0] req_0_1_0_D_f;
    wire req_0_1_1_N_v, req_0_1_1_N_r; wire [79:0] req_0_1_1_N_f;
    wire req_0_1_1_S_v, req_0_1_1_S_r; wire [79:0] req_0_1_1_S_f;
    wire req_0_1_1_E_v, req_0_1_1_E_r; wire [79:0] req_0_1_1_E_f;
    wire req_0_1_1_U_v, req_0_1_1_U_r; wire [79:0] req_0_1_1_U_f;
    wire req_0_1_1_D_v, req_0_1_1_D_r; wire [79:0] req_0_1_1_D_f;
    wire req_0_1_2_N_v, req_0_1_2_N_r; wire [79:0] req_0_1_2_N_f;
    wire req_0_1_2_S_v, req_0_1_2_S_r; wire [79:0] req_0_1_2_S_f;
    wire req_0_1_2_E_v, req_0_1_2_E_r; wire [79:0] req_0_1_2_E_f;
    wire req_0_1_2_U_v, req_0_1_2_U_r; wire [79:0] req_0_1_2_U_f;
    wire req_0_2_0_N_v, req_0_2_0_N_r; wire [79:0] req_0_2_0_N_f;
    wire req_0_2_0_S_v, req_0_2_0_S_r; wire [79:0] req_0_2_0_S_f;
    wire req_0_2_0_E_v, req_0_2_0_E_r; wire [79:0] req_0_2_0_E_f;
    wire req_0_2_0_D_v, req_0_2_0_D_r; wire [79:0] req_0_2_0_D_f;
    wire req_0_2_1_N_v, req_0_2_1_N_r; wire [79:0] req_0_2_1_N_f;
    wire req_0_2_1_S_v, req_0_2_1_S_r; wire [79:0] req_0_2_1_S_f;
    wire req_0_2_1_E_v, req_0_2_1_E_r; wire [79:0] req_0_2_1_E_f;
    wire req_0_2_1_U_v, req_0_2_1_U_r; wire [79:0] req_0_2_1_U_f;
    wire req_0_2_1_D_v, req_0_2_1_D_r; wire [79:0] req_0_2_1_D_f;
    wire req_0_2_2_N_v, req_0_2_2_N_r; wire [79:0] req_0_2_2_N_f;
    wire req_0_2_2_S_v, req_0_2_2_S_r; wire [79:0] req_0_2_2_S_f;
    wire req_0_2_2_E_v, req_0_2_2_E_r; wire [79:0] req_0_2_2_E_f;
    wire req_0_2_2_U_v, req_0_2_2_U_r; wire [79:0] req_0_2_2_U_f;
    wire req_0_3_0_N_v, req_0_3_0_N_r; wire [79:0] req_0_3_0_N_f;
    wire req_0_3_0_E_v, req_0_3_0_E_r; wire [79:0] req_0_3_0_E_f;
    wire req_0_3_0_D_v, req_0_3_0_D_r; wire [79:0] req_0_3_0_D_f;
    wire req_0_3_1_N_v, req_0_3_1_N_r; wire [79:0] req_0_3_1_N_f;
    wire req_0_3_1_E_v, req_0_3_1_E_r; wire [79:0] req_0_3_1_E_f;
    wire req_0_3_1_U_v, req_0_3_1_U_r; wire [79:0] req_0_3_1_U_f;
    wire req_0_3_1_D_v, req_0_3_1_D_r; wire [79:0] req_0_3_1_D_f;
    wire req_0_3_2_N_v, req_0_3_2_N_r; wire [79:0] req_0_3_2_N_f;
    wire req_0_3_2_E_v, req_0_3_2_E_r; wire [79:0] req_0_3_2_E_f;
    wire req_0_3_2_U_v, req_0_3_2_U_r; wire [79:0] req_0_3_2_U_f;
    wire req_1_0_0_S_v, req_1_0_0_S_r; wire [79:0] req_1_0_0_S_f;
    wire req_1_0_0_E_v, req_1_0_0_E_r; wire [79:0] req_1_0_0_E_f;
    wire req_1_0_0_W_v, req_1_0_0_W_r; wire [79:0] req_1_0_0_W_f;
    wire req_1_0_0_D_v, req_1_0_0_D_r; wire [79:0] req_1_0_0_D_f;
    wire req_1_0_1_S_v, req_1_0_1_S_r; wire [79:0] req_1_0_1_S_f;
    wire req_1_0_1_E_v, req_1_0_1_E_r; wire [79:0] req_1_0_1_E_f;
    wire req_1_0_1_W_v, req_1_0_1_W_r; wire [79:0] req_1_0_1_W_f;
    wire req_1_0_1_U_v, req_1_0_1_U_r; wire [79:0] req_1_0_1_U_f;
    wire req_1_0_1_D_v, req_1_0_1_D_r; wire [79:0] req_1_0_1_D_f;
    wire req_1_0_2_S_v, req_1_0_2_S_r; wire [79:0] req_1_0_2_S_f;
    wire req_1_0_2_E_v, req_1_0_2_E_r; wire [79:0] req_1_0_2_E_f;
    wire req_1_0_2_W_v, req_1_0_2_W_r; wire [79:0] req_1_0_2_W_f;
    wire req_1_0_2_U_v, req_1_0_2_U_r; wire [79:0] req_1_0_2_U_f;
    wire req_1_1_0_N_v, req_1_1_0_N_r; wire [79:0] req_1_1_0_N_f;
    wire req_1_1_0_S_v, req_1_1_0_S_r; wire [79:0] req_1_1_0_S_f;
    wire req_1_1_0_E_v, req_1_1_0_E_r; wire [79:0] req_1_1_0_E_f;
    wire req_1_1_0_W_v, req_1_1_0_W_r; wire [79:0] req_1_1_0_W_f;
    wire req_1_1_0_D_v, req_1_1_0_D_r; wire [79:0] req_1_1_0_D_f;
    wire req_1_1_1_N_v, req_1_1_1_N_r; wire [79:0] req_1_1_1_N_f;
    wire req_1_1_1_S_v, req_1_1_1_S_r; wire [79:0] req_1_1_1_S_f;
    wire req_1_1_1_E_v, req_1_1_1_E_r; wire [79:0] req_1_1_1_E_f;
    wire req_1_1_1_W_v, req_1_1_1_W_r; wire [79:0] req_1_1_1_W_f;
    wire req_1_1_1_U_v, req_1_1_1_U_r; wire [79:0] req_1_1_1_U_f;
    wire req_1_1_1_D_v, req_1_1_1_D_r; wire [79:0] req_1_1_1_D_f;
    wire req_1_1_2_N_v, req_1_1_2_N_r; wire [79:0] req_1_1_2_N_f;
    wire req_1_1_2_S_v, req_1_1_2_S_r; wire [79:0] req_1_1_2_S_f;
    wire req_1_1_2_E_v, req_1_1_2_E_r; wire [79:0] req_1_1_2_E_f;
    wire req_1_1_2_W_v, req_1_1_2_W_r; wire [79:0] req_1_1_2_W_f;
    wire req_1_1_2_U_v, req_1_1_2_U_r; wire [79:0] req_1_1_2_U_f;
    wire req_1_2_0_N_v, req_1_2_0_N_r; wire [79:0] req_1_2_0_N_f;
    wire req_1_2_0_S_v, req_1_2_0_S_r; wire [79:0] req_1_2_0_S_f;
    wire req_1_2_0_E_v, req_1_2_0_E_r; wire [79:0] req_1_2_0_E_f;
    wire req_1_2_0_W_v, req_1_2_0_W_r; wire [79:0] req_1_2_0_W_f;
    wire req_1_2_0_D_v, req_1_2_0_D_r; wire [79:0] req_1_2_0_D_f;
    wire req_1_2_1_N_v, req_1_2_1_N_r; wire [79:0] req_1_2_1_N_f;
    wire req_1_2_1_S_v, req_1_2_1_S_r; wire [79:0] req_1_2_1_S_f;
    wire req_1_2_1_E_v, req_1_2_1_E_r; wire [79:0] req_1_2_1_E_f;
    wire req_1_2_1_W_v, req_1_2_1_W_r; wire [79:0] req_1_2_1_W_f;
    wire req_1_2_1_U_v, req_1_2_1_U_r; wire [79:0] req_1_2_1_U_f;
    wire req_1_2_1_D_v, req_1_2_1_D_r; wire [79:0] req_1_2_1_D_f;
    wire req_1_2_2_N_v, req_1_2_2_N_r; wire [79:0] req_1_2_2_N_f;
    wire req_1_2_2_S_v, req_1_2_2_S_r; wire [79:0] req_1_2_2_S_f;
    wire req_1_2_2_E_v, req_1_2_2_E_r; wire [79:0] req_1_2_2_E_f;
    wire req_1_2_2_W_v, req_1_2_2_W_r; wire [79:0] req_1_2_2_W_f;
    wire req_1_2_2_U_v, req_1_2_2_U_r; wire [79:0] req_1_2_2_U_f;
    wire req_1_3_0_N_v, req_1_3_0_N_r; wire [79:0] req_1_3_0_N_f;
    wire req_1_3_0_E_v, req_1_3_0_E_r; wire [79:0] req_1_3_0_E_f;
    wire req_1_3_0_W_v, req_1_3_0_W_r; wire [79:0] req_1_3_0_W_f;
    wire req_1_3_0_D_v, req_1_3_0_D_r; wire [79:0] req_1_3_0_D_f;
    wire req_1_3_1_N_v, req_1_3_1_N_r; wire [79:0] req_1_3_1_N_f;
    wire req_1_3_1_E_v, req_1_3_1_E_r; wire [79:0] req_1_3_1_E_f;
    wire req_1_3_1_W_v, req_1_3_1_W_r; wire [79:0] req_1_3_1_W_f;
    wire req_1_3_1_U_v, req_1_3_1_U_r; wire [79:0] req_1_3_1_U_f;
    wire req_1_3_1_D_v, req_1_3_1_D_r; wire [79:0] req_1_3_1_D_f;
    wire req_1_3_2_N_v, req_1_3_2_N_r; wire [79:0] req_1_3_2_N_f;
    wire req_1_3_2_E_v, req_1_3_2_E_r; wire [79:0] req_1_3_2_E_f;
    wire req_1_3_2_W_v, req_1_3_2_W_r; wire [79:0] req_1_3_2_W_f;
    wire req_1_3_2_U_v, req_1_3_2_U_r; wire [79:0] req_1_3_2_U_f;
    wire req_2_0_0_S_v, req_2_0_0_S_r; wire [79:0] req_2_0_0_S_f;
    wire req_2_0_0_W_v, req_2_0_0_W_r; wire [79:0] req_2_0_0_W_f;
    wire req_2_0_0_D_v, req_2_0_0_D_r; wire [79:0] req_2_0_0_D_f;
    wire req_2_0_1_S_v, req_2_0_1_S_r; wire [79:0] req_2_0_1_S_f;
    wire req_2_0_1_W_v, req_2_0_1_W_r; wire [79:0] req_2_0_1_W_f;
    wire req_2_0_1_U_v, req_2_0_1_U_r; wire [79:0] req_2_0_1_U_f;
    wire req_2_0_1_D_v, req_2_0_1_D_r; wire [79:0] req_2_0_1_D_f;
    wire req_2_0_2_S_v, req_2_0_2_S_r; wire [79:0] req_2_0_2_S_f;
    wire req_2_0_2_W_v, req_2_0_2_W_r; wire [79:0] req_2_0_2_W_f;
    wire req_2_0_2_U_v, req_2_0_2_U_r; wire [79:0] req_2_0_2_U_f;
    wire req_2_1_0_N_v, req_2_1_0_N_r; wire [79:0] req_2_1_0_N_f;
    wire req_2_1_0_S_v, req_2_1_0_S_r; wire [79:0] req_2_1_0_S_f;
    wire req_2_1_0_W_v, req_2_1_0_W_r; wire [79:0] req_2_1_0_W_f;
    wire req_2_1_0_D_v, req_2_1_0_D_r; wire [79:0] req_2_1_0_D_f;
    wire req_2_1_1_N_v, req_2_1_1_N_r; wire [79:0] req_2_1_1_N_f;
    wire req_2_1_1_S_v, req_2_1_1_S_r; wire [79:0] req_2_1_1_S_f;
    wire req_2_1_1_W_v, req_2_1_1_W_r; wire [79:0] req_2_1_1_W_f;
    wire req_2_1_1_U_v, req_2_1_1_U_r; wire [79:0] req_2_1_1_U_f;
    wire req_2_1_1_D_v, req_2_1_1_D_r; wire [79:0] req_2_1_1_D_f;
    wire req_2_1_2_N_v, req_2_1_2_N_r; wire [79:0] req_2_1_2_N_f;
    wire req_2_1_2_S_v, req_2_1_2_S_r; wire [79:0] req_2_1_2_S_f;
    wire req_2_1_2_W_v, req_2_1_2_W_r; wire [79:0] req_2_1_2_W_f;
    wire req_2_1_2_U_v, req_2_1_2_U_r; wire [79:0] req_2_1_2_U_f;
    wire req_2_2_0_N_v, req_2_2_0_N_r; wire [79:0] req_2_2_0_N_f;
    wire req_2_2_0_S_v, req_2_2_0_S_r; wire [79:0] req_2_2_0_S_f;
    wire req_2_2_0_W_v, req_2_2_0_W_r; wire [79:0] req_2_2_0_W_f;
    wire req_2_2_0_D_v, req_2_2_0_D_r; wire [79:0] req_2_2_0_D_f;
    wire req_2_2_1_N_v, req_2_2_1_N_r; wire [79:0] req_2_2_1_N_f;
    wire req_2_2_1_S_v, req_2_2_1_S_r; wire [79:0] req_2_2_1_S_f;
    wire req_2_2_1_W_v, req_2_2_1_W_r; wire [79:0] req_2_2_1_W_f;
    wire req_2_2_1_U_v, req_2_2_1_U_r; wire [79:0] req_2_2_1_U_f;
    wire req_2_2_1_D_v, req_2_2_1_D_r; wire [79:0] req_2_2_1_D_f;
    wire req_2_2_2_N_v, req_2_2_2_N_r; wire [79:0] req_2_2_2_N_f;
    wire req_2_2_2_S_v, req_2_2_2_S_r; wire [79:0] req_2_2_2_S_f;
    wire req_2_2_2_W_v, req_2_2_2_W_r; wire [79:0] req_2_2_2_W_f;
    wire req_2_2_2_U_v, req_2_2_2_U_r; wire [79:0] req_2_2_2_U_f;
    wire req_2_3_0_N_v, req_2_3_0_N_r; wire [79:0] req_2_3_0_N_f;
    wire req_2_3_0_W_v, req_2_3_0_W_r; wire [79:0] req_2_3_0_W_f;
    wire req_2_3_0_D_v, req_2_3_0_D_r; wire [79:0] req_2_3_0_D_f;
    wire req_2_3_1_N_v, req_2_3_1_N_r; wire [79:0] req_2_3_1_N_f;
    wire req_2_3_1_W_v, req_2_3_1_W_r; wire [79:0] req_2_3_1_W_f;
    wire req_2_3_1_U_v, req_2_3_1_U_r; wire [79:0] req_2_3_1_U_f;
    wire req_2_3_1_D_v, req_2_3_1_D_r; wire [79:0] req_2_3_1_D_f;
    wire req_2_3_2_N_v, req_2_3_2_N_r; wire [79:0] req_2_3_2_N_f;
    wire req_2_3_2_W_v, req_2_3_2_W_r; wire [79:0] req_2_3_2_W_f;
    wire req_2_3_2_U_v, req_2_3_2_U_r; wire [79:0] req_2_3_2_U_f;
    wire resp_0_0_0_S_v, resp_0_0_0_S_r; wire [37:0] resp_0_0_0_S_f;
    wire resp_0_0_0_E_v, resp_0_0_0_E_r; wire [37:0] resp_0_0_0_E_f;
    wire resp_0_0_0_D_v, resp_0_0_0_D_r; wire [37:0] resp_0_0_0_D_f;
    wire resp_0_0_1_S_v, resp_0_0_1_S_r; wire [37:0] resp_0_0_1_S_f;
    wire resp_0_0_1_E_v, resp_0_0_1_E_r; wire [37:0] resp_0_0_1_E_f;
    wire resp_0_0_1_U_v, resp_0_0_1_U_r; wire [37:0] resp_0_0_1_U_f;
    wire resp_0_0_1_D_v, resp_0_0_1_D_r; wire [37:0] resp_0_0_1_D_f;
    wire resp_0_0_2_S_v, resp_0_0_2_S_r; wire [37:0] resp_0_0_2_S_f;
    wire resp_0_0_2_E_v, resp_0_0_2_E_r; wire [37:0] resp_0_0_2_E_f;
    wire resp_0_0_2_U_v, resp_0_0_2_U_r; wire [37:0] resp_0_0_2_U_f;
    wire resp_0_1_0_N_v, resp_0_1_0_N_r; wire [37:0] resp_0_1_0_N_f;
    wire resp_0_1_0_S_v, resp_0_1_0_S_r; wire [37:0] resp_0_1_0_S_f;
    wire resp_0_1_0_E_v, resp_0_1_0_E_r; wire [37:0] resp_0_1_0_E_f;
    wire resp_0_1_0_D_v, resp_0_1_0_D_r; wire [37:0] resp_0_1_0_D_f;
    wire resp_0_1_1_N_v, resp_0_1_1_N_r; wire [37:0] resp_0_1_1_N_f;
    wire resp_0_1_1_S_v, resp_0_1_1_S_r; wire [37:0] resp_0_1_1_S_f;
    wire resp_0_1_1_E_v, resp_0_1_1_E_r; wire [37:0] resp_0_1_1_E_f;
    wire resp_0_1_1_U_v, resp_0_1_1_U_r; wire [37:0] resp_0_1_1_U_f;
    wire resp_0_1_1_D_v, resp_0_1_1_D_r; wire [37:0] resp_0_1_1_D_f;
    wire resp_0_1_2_N_v, resp_0_1_2_N_r; wire [37:0] resp_0_1_2_N_f;
    wire resp_0_1_2_S_v, resp_0_1_2_S_r; wire [37:0] resp_0_1_2_S_f;
    wire resp_0_1_2_E_v, resp_0_1_2_E_r; wire [37:0] resp_0_1_2_E_f;
    wire resp_0_1_2_U_v, resp_0_1_2_U_r; wire [37:0] resp_0_1_2_U_f;
    wire resp_0_2_0_N_v, resp_0_2_0_N_r; wire [37:0] resp_0_2_0_N_f;
    wire resp_0_2_0_S_v, resp_0_2_0_S_r; wire [37:0] resp_0_2_0_S_f;
    wire resp_0_2_0_E_v, resp_0_2_0_E_r; wire [37:0] resp_0_2_0_E_f;
    wire resp_0_2_0_D_v, resp_0_2_0_D_r; wire [37:0] resp_0_2_0_D_f;
    wire resp_0_2_1_N_v, resp_0_2_1_N_r; wire [37:0] resp_0_2_1_N_f;
    wire resp_0_2_1_S_v, resp_0_2_1_S_r; wire [37:0] resp_0_2_1_S_f;
    wire resp_0_2_1_E_v, resp_0_2_1_E_r; wire [37:0] resp_0_2_1_E_f;
    wire resp_0_2_1_U_v, resp_0_2_1_U_r; wire [37:0] resp_0_2_1_U_f;
    wire resp_0_2_1_D_v, resp_0_2_1_D_r; wire [37:0] resp_0_2_1_D_f;
    wire resp_0_2_2_N_v, resp_0_2_2_N_r; wire [37:0] resp_0_2_2_N_f;
    wire resp_0_2_2_S_v, resp_0_2_2_S_r; wire [37:0] resp_0_2_2_S_f;
    wire resp_0_2_2_E_v, resp_0_2_2_E_r; wire [37:0] resp_0_2_2_E_f;
    wire resp_0_2_2_U_v, resp_0_2_2_U_r; wire [37:0] resp_0_2_2_U_f;
    wire resp_0_3_0_N_v, resp_0_3_0_N_r; wire [37:0] resp_0_3_0_N_f;
    wire resp_0_3_0_E_v, resp_0_3_0_E_r; wire [37:0] resp_0_3_0_E_f;
    wire resp_0_3_0_D_v, resp_0_3_0_D_r; wire [37:0] resp_0_3_0_D_f;
    wire resp_0_3_1_N_v, resp_0_3_1_N_r; wire [37:0] resp_0_3_1_N_f;
    wire resp_0_3_1_E_v, resp_0_3_1_E_r; wire [37:0] resp_0_3_1_E_f;
    wire resp_0_3_1_U_v, resp_0_3_1_U_r; wire [37:0] resp_0_3_1_U_f;
    wire resp_0_3_1_D_v, resp_0_3_1_D_r; wire [37:0] resp_0_3_1_D_f;
    wire resp_0_3_2_N_v, resp_0_3_2_N_r; wire [37:0] resp_0_3_2_N_f;
    wire resp_0_3_2_E_v, resp_0_3_2_E_r; wire [37:0] resp_0_3_2_E_f;
    wire resp_0_3_2_U_v, resp_0_3_2_U_r; wire [37:0] resp_0_3_2_U_f;
    wire resp_1_0_0_S_v, resp_1_0_0_S_r; wire [37:0] resp_1_0_0_S_f;
    wire resp_1_0_0_E_v, resp_1_0_0_E_r; wire [37:0] resp_1_0_0_E_f;
    wire resp_1_0_0_W_v, resp_1_0_0_W_r; wire [37:0] resp_1_0_0_W_f;
    wire resp_1_0_0_D_v, resp_1_0_0_D_r; wire [37:0] resp_1_0_0_D_f;
    wire resp_1_0_1_S_v, resp_1_0_1_S_r; wire [37:0] resp_1_0_1_S_f;
    wire resp_1_0_1_E_v, resp_1_0_1_E_r; wire [37:0] resp_1_0_1_E_f;
    wire resp_1_0_1_W_v, resp_1_0_1_W_r; wire [37:0] resp_1_0_1_W_f;
    wire resp_1_0_1_U_v, resp_1_0_1_U_r; wire [37:0] resp_1_0_1_U_f;
    wire resp_1_0_1_D_v, resp_1_0_1_D_r; wire [37:0] resp_1_0_1_D_f;
    wire resp_1_0_2_S_v, resp_1_0_2_S_r; wire [37:0] resp_1_0_2_S_f;
    wire resp_1_0_2_E_v, resp_1_0_2_E_r; wire [37:0] resp_1_0_2_E_f;
    wire resp_1_0_2_W_v, resp_1_0_2_W_r; wire [37:0] resp_1_0_2_W_f;
    wire resp_1_0_2_U_v, resp_1_0_2_U_r; wire [37:0] resp_1_0_2_U_f;
    wire resp_1_1_0_N_v, resp_1_1_0_N_r; wire [37:0] resp_1_1_0_N_f;
    wire resp_1_1_0_S_v, resp_1_1_0_S_r; wire [37:0] resp_1_1_0_S_f;
    wire resp_1_1_0_E_v, resp_1_1_0_E_r; wire [37:0] resp_1_1_0_E_f;
    wire resp_1_1_0_W_v, resp_1_1_0_W_r; wire [37:0] resp_1_1_0_W_f;
    wire resp_1_1_0_D_v, resp_1_1_0_D_r; wire [37:0] resp_1_1_0_D_f;
    wire resp_1_1_1_N_v, resp_1_1_1_N_r; wire [37:0] resp_1_1_1_N_f;
    wire resp_1_1_1_S_v, resp_1_1_1_S_r; wire [37:0] resp_1_1_1_S_f;
    wire resp_1_1_1_E_v, resp_1_1_1_E_r; wire [37:0] resp_1_1_1_E_f;
    wire resp_1_1_1_W_v, resp_1_1_1_W_r; wire [37:0] resp_1_1_1_W_f;
    wire resp_1_1_1_U_v, resp_1_1_1_U_r; wire [37:0] resp_1_1_1_U_f;
    wire resp_1_1_1_D_v, resp_1_1_1_D_r; wire [37:0] resp_1_1_1_D_f;
    wire resp_1_1_2_N_v, resp_1_1_2_N_r; wire [37:0] resp_1_1_2_N_f;
    wire resp_1_1_2_S_v, resp_1_1_2_S_r; wire [37:0] resp_1_1_2_S_f;
    wire resp_1_1_2_E_v, resp_1_1_2_E_r; wire [37:0] resp_1_1_2_E_f;
    wire resp_1_1_2_W_v, resp_1_1_2_W_r; wire [37:0] resp_1_1_2_W_f;
    wire resp_1_1_2_U_v, resp_1_1_2_U_r; wire [37:0] resp_1_1_2_U_f;
    wire resp_1_2_0_N_v, resp_1_2_0_N_r; wire [37:0] resp_1_2_0_N_f;
    wire resp_1_2_0_S_v, resp_1_2_0_S_r; wire [37:0] resp_1_2_0_S_f;
    wire resp_1_2_0_E_v, resp_1_2_0_E_r; wire [37:0] resp_1_2_0_E_f;
    wire resp_1_2_0_W_v, resp_1_2_0_W_r; wire [37:0] resp_1_2_0_W_f;
    wire resp_1_2_0_D_v, resp_1_2_0_D_r; wire [37:0] resp_1_2_0_D_f;
    wire resp_1_2_1_N_v, resp_1_2_1_N_r; wire [37:0] resp_1_2_1_N_f;
    wire resp_1_2_1_S_v, resp_1_2_1_S_r; wire [37:0] resp_1_2_1_S_f;
    wire resp_1_2_1_E_v, resp_1_2_1_E_r; wire [37:0] resp_1_2_1_E_f;
    wire resp_1_2_1_W_v, resp_1_2_1_W_r; wire [37:0] resp_1_2_1_W_f;
    wire resp_1_2_1_U_v, resp_1_2_1_U_r; wire [37:0] resp_1_2_1_U_f;
    wire resp_1_2_1_D_v, resp_1_2_1_D_r; wire [37:0] resp_1_2_1_D_f;
    wire resp_1_2_2_N_v, resp_1_2_2_N_r; wire [37:0] resp_1_2_2_N_f;
    wire resp_1_2_2_S_v, resp_1_2_2_S_r; wire [37:0] resp_1_2_2_S_f;
    wire resp_1_2_2_E_v, resp_1_2_2_E_r; wire [37:0] resp_1_2_2_E_f;
    wire resp_1_2_2_W_v, resp_1_2_2_W_r; wire [37:0] resp_1_2_2_W_f;
    wire resp_1_2_2_U_v, resp_1_2_2_U_r; wire [37:0] resp_1_2_2_U_f;
    wire resp_1_3_0_N_v, resp_1_3_0_N_r; wire [37:0] resp_1_3_0_N_f;
    wire resp_1_3_0_E_v, resp_1_3_0_E_r; wire [37:0] resp_1_3_0_E_f;
    wire resp_1_3_0_W_v, resp_1_3_0_W_r; wire [37:0] resp_1_3_0_W_f;
    wire resp_1_3_0_D_v, resp_1_3_0_D_r; wire [37:0] resp_1_3_0_D_f;
    wire resp_1_3_1_N_v, resp_1_3_1_N_r; wire [37:0] resp_1_3_1_N_f;
    wire resp_1_3_1_E_v, resp_1_3_1_E_r; wire [37:0] resp_1_3_1_E_f;
    wire resp_1_3_1_W_v, resp_1_3_1_W_r; wire [37:0] resp_1_3_1_W_f;
    wire resp_1_3_1_U_v, resp_1_3_1_U_r; wire [37:0] resp_1_3_1_U_f;
    wire resp_1_3_1_D_v, resp_1_3_1_D_r; wire [37:0] resp_1_3_1_D_f;
    wire resp_1_3_2_N_v, resp_1_3_2_N_r; wire [37:0] resp_1_3_2_N_f;
    wire resp_1_3_2_E_v, resp_1_3_2_E_r; wire [37:0] resp_1_3_2_E_f;
    wire resp_1_3_2_W_v, resp_1_3_2_W_r; wire [37:0] resp_1_3_2_W_f;
    wire resp_1_3_2_U_v, resp_1_3_2_U_r; wire [37:0] resp_1_3_2_U_f;
    wire resp_2_0_0_S_v, resp_2_0_0_S_r; wire [37:0] resp_2_0_0_S_f;
    wire resp_2_0_0_W_v, resp_2_0_0_W_r; wire [37:0] resp_2_0_0_W_f;
    wire resp_2_0_0_D_v, resp_2_0_0_D_r; wire [37:0] resp_2_0_0_D_f;
    wire resp_2_0_1_S_v, resp_2_0_1_S_r; wire [37:0] resp_2_0_1_S_f;
    wire resp_2_0_1_W_v, resp_2_0_1_W_r; wire [37:0] resp_2_0_1_W_f;
    wire resp_2_0_1_U_v, resp_2_0_1_U_r; wire [37:0] resp_2_0_1_U_f;
    wire resp_2_0_1_D_v, resp_2_0_1_D_r; wire [37:0] resp_2_0_1_D_f;
    wire resp_2_0_2_S_v, resp_2_0_2_S_r; wire [37:0] resp_2_0_2_S_f;
    wire resp_2_0_2_W_v, resp_2_0_2_W_r; wire [37:0] resp_2_0_2_W_f;
    wire resp_2_0_2_U_v, resp_2_0_2_U_r; wire [37:0] resp_2_0_2_U_f;
    wire resp_2_1_0_N_v, resp_2_1_0_N_r; wire [37:0] resp_2_1_0_N_f;
    wire resp_2_1_0_S_v, resp_2_1_0_S_r; wire [37:0] resp_2_1_0_S_f;
    wire resp_2_1_0_W_v, resp_2_1_0_W_r; wire [37:0] resp_2_1_0_W_f;
    wire resp_2_1_0_D_v, resp_2_1_0_D_r; wire [37:0] resp_2_1_0_D_f;
    wire resp_2_1_1_N_v, resp_2_1_1_N_r; wire [37:0] resp_2_1_1_N_f;
    wire resp_2_1_1_S_v, resp_2_1_1_S_r; wire [37:0] resp_2_1_1_S_f;
    wire resp_2_1_1_W_v, resp_2_1_1_W_r; wire [37:0] resp_2_1_1_W_f;
    wire resp_2_1_1_U_v, resp_2_1_1_U_r; wire [37:0] resp_2_1_1_U_f;
    wire resp_2_1_1_D_v, resp_2_1_1_D_r; wire [37:0] resp_2_1_1_D_f;
    wire resp_2_1_2_N_v, resp_2_1_2_N_r; wire [37:0] resp_2_1_2_N_f;
    wire resp_2_1_2_S_v, resp_2_1_2_S_r; wire [37:0] resp_2_1_2_S_f;
    wire resp_2_1_2_W_v, resp_2_1_2_W_r; wire [37:0] resp_2_1_2_W_f;
    wire resp_2_1_2_U_v, resp_2_1_2_U_r; wire [37:0] resp_2_1_2_U_f;
    wire resp_2_2_0_N_v, resp_2_2_0_N_r; wire [37:0] resp_2_2_0_N_f;
    wire resp_2_2_0_S_v, resp_2_2_0_S_r; wire [37:0] resp_2_2_0_S_f;
    wire resp_2_2_0_W_v, resp_2_2_0_W_r; wire [37:0] resp_2_2_0_W_f;
    wire resp_2_2_0_D_v, resp_2_2_0_D_r; wire [37:0] resp_2_2_0_D_f;
    wire resp_2_2_1_N_v, resp_2_2_1_N_r; wire [37:0] resp_2_2_1_N_f;
    wire resp_2_2_1_S_v, resp_2_2_1_S_r; wire [37:0] resp_2_2_1_S_f;
    wire resp_2_2_1_W_v, resp_2_2_1_W_r; wire [37:0] resp_2_2_1_W_f;
    wire resp_2_2_1_U_v, resp_2_2_1_U_r; wire [37:0] resp_2_2_1_U_f;
    wire resp_2_2_1_D_v, resp_2_2_1_D_r; wire [37:0] resp_2_2_1_D_f;
    wire resp_2_2_2_N_v, resp_2_2_2_N_r; wire [37:0] resp_2_2_2_N_f;
    wire resp_2_2_2_S_v, resp_2_2_2_S_r; wire [37:0] resp_2_2_2_S_f;
    wire resp_2_2_2_W_v, resp_2_2_2_W_r; wire [37:0] resp_2_2_2_W_f;
    wire resp_2_2_2_U_v, resp_2_2_2_U_r; wire [37:0] resp_2_2_2_U_f;
    wire resp_2_3_0_N_v, resp_2_3_0_N_r; wire [37:0] resp_2_3_0_N_f;
    wire resp_2_3_0_W_v, resp_2_3_0_W_r; wire [37:0] resp_2_3_0_W_f;
    wire resp_2_3_0_D_v, resp_2_3_0_D_r; wire [37:0] resp_2_3_0_D_f;
    wire resp_2_3_1_N_v, resp_2_3_1_N_r; wire [37:0] resp_2_3_1_N_f;
    wire resp_2_3_1_W_v, resp_2_3_1_W_r; wire [37:0] resp_2_3_1_W_f;
    wire resp_2_3_1_U_v, resp_2_3_1_U_r; wire [37:0] resp_2_3_1_U_f;
    wire resp_2_3_1_D_v, resp_2_3_1_D_r; wire [37:0] resp_2_3_1_D_f;
    wire resp_2_3_2_N_v, resp_2_3_2_N_r; wire [37:0] resp_2_3_2_N_f;
    wire resp_2_3_2_W_v, resp_2_3_2_W_r; wire [37:0] resp_2_3_2_W_f;
    wire resp_2_3_2_U_v, resp_2_3_2_U_r; wire [37:0] resp_2_3_2_U_f;

    // ==================== Per-core bus + adapter wires ====================
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
    wire p12_bus_req, p12_bus_mem_write, p12_bus_mem_unsigned, p12_bus_grant;
    wire [31:0] p12_bus_addr, p12_bus_write_data, p12_bus_read_data;
    wire [1:0] p12_bus_mem_size;
    wire p12_req_out_valid, p12_req_out_ready, p12_resp_in_valid, p12_resp_in_ready;
    wire [79:0] p12_req_out_flit;
    wire [37:0] p12_resp_in_flit;
    wire p13_bus_req, p13_bus_mem_write, p13_bus_mem_unsigned, p13_bus_grant;
    wire [31:0] p13_bus_addr, p13_bus_write_data, p13_bus_read_data;
    wire [1:0] p13_bus_mem_size;
    wire p13_req_out_valid, p13_req_out_ready, p13_resp_in_valid, p13_resp_in_ready;
    wire [79:0] p13_req_out_flit;
    wire [37:0] p13_resp_in_flit;
    wire p14_bus_req, p14_bus_mem_write, p14_bus_mem_unsigned, p14_bus_grant;
    wire [31:0] p14_bus_addr, p14_bus_write_data, p14_bus_read_data;
    wire [1:0] p14_bus_mem_size;
    wire p14_req_out_valid, p14_req_out_ready, p14_resp_in_valid, p14_resp_in_ready;
    wire [79:0] p14_req_out_flit;
    wire [37:0] p14_resp_in_flit;
    wire p15_bus_req, p15_bus_mem_write, p15_bus_mem_unsigned, p15_bus_grant;
    wire [31:0] p15_bus_addr, p15_bus_write_data, p15_bus_read_data;
    wire [1:0] p15_bus_mem_size;
    wire p15_req_out_valid, p15_req_out_ready, p15_resp_in_valid, p15_resp_in_ready;
    wire [79:0] p15_req_out_flit;
    wire [37:0] p15_resp_in_flit;
    wire p16_bus_req, p16_bus_mem_write, p16_bus_mem_unsigned, p16_bus_grant;
    wire [31:0] p16_bus_addr, p16_bus_write_data, p16_bus_read_data;
    wire [1:0] p16_bus_mem_size;
    wire p16_req_out_valid, p16_req_out_ready, p16_resp_in_valid, p16_resp_in_ready;
    wire [79:0] p16_req_out_flit;
    wire [37:0] p16_resp_in_flit;
    wire p17_bus_req, p17_bus_mem_write, p17_bus_mem_unsigned, p17_bus_grant;
    wire [31:0] p17_bus_addr, p17_bus_write_data, p17_bus_read_data;
    wire [1:0] p17_bus_mem_size;
    wire p17_req_out_valid, p17_req_out_ready, p17_resp_in_valid, p17_resp_in_ready;
    wire [79:0] p17_req_out_flit;
    wire [37:0] p17_resp_in_flit;
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
    wire e12_bus_req, e12_bus_mem_write, e12_bus_mem_unsigned, e12_bus_grant;
    wire [31:0] e12_bus_addr, e12_bus_write_data, e12_bus_read_data;
    wire [1:0] e12_bus_mem_size;
    wire e12_req_out_valid, e12_req_out_ready, e12_resp_in_valid, e12_resp_in_ready;
    wire [79:0] e12_req_out_flit;
    wire [37:0] e12_resp_in_flit;
    wire e13_bus_req, e13_bus_mem_write, e13_bus_mem_unsigned, e13_bus_grant;
    wire [31:0] e13_bus_addr, e13_bus_write_data, e13_bus_read_data;
    wire [1:0] e13_bus_mem_size;
    wire e13_req_out_valid, e13_req_out_ready, e13_resp_in_valid, e13_resp_in_ready;
    wire [79:0] e13_req_out_flit;
    wire [37:0] e13_resp_in_flit;
    wire e14_bus_req, e14_bus_mem_write, e14_bus_mem_unsigned, e14_bus_grant;
    wire [31:0] e14_bus_addr, e14_bus_write_data, e14_bus_read_data;
    wire [1:0] e14_bus_mem_size;
    wire e14_req_out_valid, e14_req_out_ready, e14_resp_in_valid, e14_resp_in_ready;
    wire [79:0] e14_req_out_flit;
    wire [37:0] e14_resp_in_flit;
    wire e15_bus_req, e15_bus_mem_write, e15_bus_mem_unsigned, e15_bus_grant;
    wire [31:0] e15_bus_addr, e15_bus_write_data, e15_bus_read_data;
    wire [1:0] e15_bus_mem_size;
    wire e15_req_out_valid, e15_req_out_ready, e15_resp_in_valid, e15_resp_in_ready;
    wire [79:0] e15_req_out_flit;
    wire [37:0] e15_resp_in_flit;
    wire e16_bus_req, e16_bus_mem_write, e16_bus_mem_unsigned, e16_bus_grant;
    wire [31:0] e16_bus_addr, e16_bus_write_data, e16_bus_read_data;
    wire [1:0] e16_bus_mem_size;
    wire e16_req_out_valid, e16_req_out_ready, e16_resp_in_valid, e16_resp_in_ready;
    wire [79:0] e16_req_out_flit;
    wire [37:0] e16_resp_in_flit;
    wire mem_req_in_valid, mem_req_in_ready, mem_resp_out_valid, mem_resp_out_ready;
    wire [79:0] mem_req_in_flit;
    wire [37:0] mem_resp_out_flit;

    // ==================== Routers (2 networks x 36 grid positions) ====================
    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(0)) req_r0_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_0_N_v), .s_in_flit(req_0_1_0_N_f), .s_in_ready(req_0_1_0_N_r),
        .s_out_valid(req_0_0_0_S_v), .s_out_flit(req_0_0_0_S_f), .s_out_ready(req_0_0_0_S_r),
        .e_in_valid(req_1_0_0_W_v), .e_in_flit(req_1_0_0_W_f), .e_in_ready(req_1_0_0_W_r),
        .e_out_valid(req_0_0_0_E_v), .e_out_flit(req_0_0_0_E_f), .e_out_ready(req_0_0_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_0_1_U_v), .d_in_flit(req_0_0_1_U_f), .d_in_ready(req_0_0_1_U_r),
        .d_out_valid(req_0_0_0_D_v), .d_out_flit(req_0_0_0_D_f), .d_out_ready(req_0_0_0_D_r),
        .l_in_valid(p0_req_out_valid), .l_in_flit(p0_req_out_flit), .l_in_ready(p0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(0)) resp_r0_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_0_N_v), .s_in_flit(resp_0_1_0_N_f), .s_in_ready(resp_0_1_0_N_r),
        .s_out_valid(resp_0_0_0_S_v), .s_out_flit(resp_0_0_0_S_f), .s_out_ready(resp_0_0_0_S_r),
        .e_in_valid(resp_1_0_0_W_v), .e_in_flit(resp_1_0_0_W_f), .e_in_ready(resp_1_0_0_W_r),
        .e_out_valid(resp_0_0_0_E_v), .e_out_flit(resp_0_0_0_E_f), .e_out_ready(resp_0_0_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_0_1_U_v), .d_in_flit(resp_0_0_1_U_f), .d_in_ready(resp_0_0_1_U_r),
        .d_out_valid(resp_0_0_0_D_v), .d_out_flit(resp_0_0_0_D_f), .d_out_ready(resp_0_0_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p0_resp_in_valid), .l_out_flit(p0_resp_in_flit), .l_out_ready(p0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(1)) req_r0_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_1_N_v), .s_in_flit(req_0_1_1_N_f), .s_in_ready(req_0_1_1_N_r),
        .s_out_valid(req_0_0_1_S_v), .s_out_flit(req_0_0_1_S_f), .s_out_ready(req_0_0_1_S_r),
        .e_in_valid(req_1_0_1_W_v), .e_in_flit(req_1_0_1_W_f), .e_in_ready(req_1_0_1_W_r),
        .e_out_valid(req_0_0_1_E_v), .e_out_flit(req_0_0_1_E_f), .e_out_ready(req_0_0_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_0_D_v), .u_in_flit(req_0_0_0_D_f), .u_in_ready(req_0_0_0_D_r),
        .u_out_valid(req_0_0_1_U_v), .u_out_flit(req_0_0_1_U_f), .u_out_ready(req_0_0_1_U_r),
        .d_in_valid(req_0_0_2_U_v), .d_in_flit(req_0_0_2_U_f), .d_in_ready(req_0_0_2_U_r),
        .d_out_valid(req_0_0_1_D_v), .d_out_flit(req_0_0_1_D_f), .d_out_ready(req_0_0_1_D_r),
        .l_in_valid(p1_req_out_valid), .l_in_flit(p1_req_out_flit), .l_in_ready(p1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(1)) resp_r0_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_1_N_v), .s_in_flit(resp_0_1_1_N_f), .s_in_ready(resp_0_1_1_N_r),
        .s_out_valid(resp_0_0_1_S_v), .s_out_flit(resp_0_0_1_S_f), .s_out_ready(resp_0_0_1_S_r),
        .e_in_valid(resp_1_0_1_W_v), .e_in_flit(resp_1_0_1_W_f), .e_in_ready(resp_1_0_1_W_r),
        .e_out_valid(resp_0_0_1_E_v), .e_out_flit(resp_0_0_1_E_f), .e_out_ready(resp_0_0_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_0_D_v), .u_in_flit(resp_0_0_0_D_f), .u_in_ready(resp_0_0_0_D_r),
        .u_out_valid(resp_0_0_1_U_v), .u_out_flit(resp_0_0_1_U_f), .u_out_ready(resp_0_0_1_U_r),
        .d_in_valid(resp_0_0_2_U_v), .d_in_flit(resp_0_0_2_U_f), .d_in_ready(resp_0_0_2_U_r),
        .d_out_valid(resp_0_0_1_D_v), .d_out_flit(resp_0_0_1_D_f), .d_out_ready(resp_0_0_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p1_resp_in_valid), .l_out_flit(p1_resp_in_flit), .l_out_ready(p1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(2)) req_r0_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_2_N_v), .s_in_flit(req_0_1_2_N_f), .s_in_ready(req_0_1_2_N_r),
        .s_out_valid(req_0_0_2_S_v), .s_out_flit(req_0_0_2_S_f), .s_out_ready(req_0_0_2_S_r),
        .e_in_valid(req_1_0_2_W_v), .e_in_flit(req_1_0_2_W_f), .e_in_ready(req_1_0_2_W_r),
        .e_out_valid(req_0_0_2_E_v), .e_out_flit(req_0_0_2_E_f), .e_out_ready(req_0_0_2_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_1_D_v), .u_in_flit(req_0_0_1_D_f), .u_in_ready(req_0_0_1_D_r),
        .u_out_valid(req_0_0_2_U_v), .u_out_flit(req_0_0_2_U_f), .u_out_ready(req_0_0_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(p2_req_out_valid), .l_in_flit(p2_req_out_flit), .l_in_ready(p2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(2)) resp_r0_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_2_N_v), .s_in_flit(resp_0_1_2_N_f), .s_in_ready(resp_0_1_2_N_r),
        .s_out_valid(resp_0_0_2_S_v), .s_out_flit(resp_0_0_2_S_f), .s_out_ready(resp_0_0_2_S_r),
        .e_in_valid(resp_1_0_2_W_v), .e_in_flit(resp_1_0_2_W_f), .e_in_ready(resp_1_0_2_W_r),
        .e_out_valid(resp_0_0_2_E_v), .e_out_flit(resp_0_0_2_E_f), .e_out_ready(resp_0_0_2_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_1_D_v), .u_in_flit(resp_0_0_1_D_f), .u_in_ready(resp_0_0_1_D_r),
        .u_out_valid(resp_0_0_2_U_v), .u_out_flit(resp_0_0_2_U_f), .u_out_ready(resp_0_0_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p2_resp_in_valid), .l_out_flit(p2_resp_in_flit), .l_out_ready(p2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(0)) req_r0_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_0_S_v), .n_in_flit(req_0_0_0_S_f), .n_in_ready(req_0_0_0_S_r),
        .n_out_valid(req_0_1_0_N_v), .n_out_flit(req_0_1_0_N_f), .n_out_ready(req_0_1_0_N_r),
        .s_in_valid(req_0_2_0_N_v), .s_in_flit(req_0_2_0_N_f), .s_in_ready(req_0_2_0_N_r),
        .s_out_valid(req_0_1_0_S_v), .s_out_flit(req_0_1_0_S_f), .s_out_ready(req_0_1_0_S_r),
        .e_in_valid(req_1_1_0_W_v), .e_in_flit(req_1_1_0_W_f), .e_in_ready(req_1_1_0_W_r),
        .e_out_valid(req_0_1_0_E_v), .e_out_flit(req_0_1_0_E_f), .e_out_ready(req_0_1_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_1_1_U_v), .d_in_flit(req_0_1_1_U_f), .d_in_ready(req_0_1_1_U_r),
        .d_out_valid(req_0_1_0_D_v), .d_out_flit(req_0_1_0_D_f), .d_out_ready(req_0_1_0_D_r),
        .l_in_valid(p3_req_out_valid), .l_in_flit(p3_req_out_flit), .l_in_ready(p3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(0)) resp_r0_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_0_S_v), .n_in_flit(resp_0_0_0_S_f), .n_in_ready(resp_0_0_0_S_r),
        .n_out_valid(resp_0_1_0_N_v), .n_out_flit(resp_0_1_0_N_f), .n_out_ready(resp_0_1_0_N_r),
        .s_in_valid(resp_0_2_0_N_v), .s_in_flit(resp_0_2_0_N_f), .s_in_ready(resp_0_2_0_N_r),
        .s_out_valid(resp_0_1_0_S_v), .s_out_flit(resp_0_1_0_S_f), .s_out_ready(resp_0_1_0_S_r),
        .e_in_valid(resp_1_1_0_W_v), .e_in_flit(resp_1_1_0_W_f), .e_in_ready(resp_1_1_0_W_r),
        .e_out_valid(resp_0_1_0_E_v), .e_out_flit(resp_0_1_0_E_f), .e_out_ready(resp_0_1_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_1_1_U_v), .d_in_flit(resp_0_1_1_U_f), .d_in_ready(resp_0_1_1_U_r),
        .d_out_valid(resp_0_1_0_D_v), .d_out_flit(resp_0_1_0_D_f), .d_out_ready(resp_0_1_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p3_resp_in_valid), .l_out_flit(p3_resp_in_flit), .l_out_ready(p3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(1)) req_r0_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_1_S_v), .n_in_flit(req_0_0_1_S_f), .n_in_ready(req_0_0_1_S_r),
        .n_out_valid(req_0_1_1_N_v), .n_out_flit(req_0_1_1_N_f), .n_out_ready(req_0_1_1_N_r),
        .s_in_valid(req_0_2_1_N_v), .s_in_flit(req_0_2_1_N_f), .s_in_ready(req_0_2_1_N_r),
        .s_out_valid(req_0_1_1_S_v), .s_out_flit(req_0_1_1_S_f), .s_out_ready(req_0_1_1_S_r),
        .e_in_valid(req_1_1_1_W_v), .e_in_flit(req_1_1_1_W_f), .e_in_ready(req_1_1_1_W_r),
        .e_out_valid(req_0_1_1_E_v), .e_out_flit(req_0_1_1_E_f), .e_out_ready(req_0_1_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_0_D_v), .u_in_flit(req_0_1_0_D_f), .u_in_ready(req_0_1_0_D_r),
        .u_out_valid(req_0_1_1_U_v), .u_out_flit(req_0_1_1_U_f), .u_out_ready(req_0_1_1_U_r),
        .d_in_valid(req_0_1_2_U_v), .d_in_flit(req_0_1_2_U_f), .d_in_ready(req_0_1_2_U_r),
        .d_out_valid(req_0_1_1_D_v), .d_out_flit(req_0_1_1_D_f), .d_out_ready(req_0_1_1_D_r),
        .l_in_valid(p4_req_out_valid), .l_in_flit(p4_req_out_flit), .l_in_ready(p4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(1)) resp_r0_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_1_S_v), .n_in_flit(resp_0_0_1_S_f), .n_in_ready(resp_0_0_1_S_r),
        .n_out_valid(resp_0_1_1_N_v), .n_out_flit(resp_0_1_1_N_f), .n_out_ready(resp_0_1_1_N_r),
        .s_in_valid(resp_0_2_1_N_v), .s_in_flit(resp_0_2_1_N_f), .s_in_ready(resp_0_2_1_N_r),
        .s_out_valid(resp_0_1_1_S_v), .s_out_flit(resp_0_1_1_S_f), .s_out_ready(resp_0_1_1_S_r),
        .e_in_valid(resp_1_1_1_W_v), .e_in_flit(resp_1_1_1_W_f), .e_in_ready(resp_1_1_1_W_r),
        .e_out_valid(resp_0_1_1_E_v), .e_out_flit(resp_0_1_1_E_f), .e_out_ready(resp_0_1_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_0_D_v), .u_in_flit(resp_0_1_0_D_f), .u_in_ready(resp_0_1_0_D_r),
        .u_out_valid(resp_0_1_1_U_v), .u_out_flit(resp_0_1_1_U_f), .u_out_ready(resp_0_1_1_U_r),
        .d_in_valid(resp_0_1_2_U_v), .d_in_flit(resp_0_1_2_U_f), .d_in_ready(resp_0_1_2_U_r),
        .d_out_valid(resp_0_1_1_D_v), .d_out_flit(resp_0_1_1_D_f), .d_out_ready(resp_0_1_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p4_resp_in_valid), .l_out_flit(p4_resp_in_flit), .l_out_ready(p4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(2)) req_r0_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_2_S_v), .n_in_flit(req_0_0_2_S_f), .n_in_ready(req_0_0_2_S_r),
        .n_out_valid(req_0_1_2_N_v), .n_out_flit(req_0_1_2_N_f), .n_out_ready(req_0_1_2_N_r),
        .s_in_valid(req_0_2_2_N_v), .s_in_flit(req_0_2_2_N_f), .s_in_ready(req_0_2_2_N_r),
        .s_out_valid(req_0_1_2_S_v), .s_out_flit(req_0_1_2_S_f), .s_out_ready(req_0_1_2_S_r),
        .e_in_valid(req_1_1_2_W_v), .e_in_flit(req_1_1_2_W_f), .e_in_ready(req_1_1_2_W_r),
        .e_out_valid(req_0_1_2_E_v), .e_out_flit(req_0_1_2_E_f), .e_out_ready(req_0_1_2_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_1_D_v), .u_in_flit(req_0_1_1_D_f), .u_in_ready(req_0_1_1_D_r),
        .u_out_valid(req_0_1_2_U_v), .u_out_flit(req_0_1_2_U_f), .u_out_ready(req_0_1_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(p5_req_out_valid), .l_in_flit(p5_req_out_flit), .l_in_ready(p5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(2)) resp_r0_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_2_S_v), .n_in_flit(resp_0_0_2_S_f), .n_in_ready(resp_0_0_2_S_r),
        .n_out_valid(resp_0_1_2_N_v), .n_out_flit(resp_0_1_2_N_f), .n_out_ready(resp_0_1_2_N_r),
        .s_in_valid(resp_0_2_2_N_v), .s_in_flit(resp_0_2_2_N_f), .s_in_ready(resp_0_2_2_N_r),
        .s_out_valid(resp_0_1_2_S_v), .s_out_flit(resp_0_1_2_S_f), .s_out_ready(resp_0_1_2_S_r),
        .e_in_valid(resp_1_1_2_W_v), .e_in_flit(resp_1_1_2_W_f), .e_in_ready(resp_1_1_2_W_r),
        .e_out_valid(resp_0_1_2_E_v), .e_out_flit(resp_0_1_2_E_f), .e_out_ready(resp_0_1_2_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_1_D_v), .u_in_flit(resp_0_1_1_D_f), .u_in_ready(resp_0_1_1_D_r),
        .u_out_valid(resp_0_1_2_U_v), .u_out_flit(resp_0_1_2_U_f), .u_out_ready(resp_0_1_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p5_resp_in_valid), .l_out_flit(p5_resp_in_flit), .l_out_ready(p5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(0)) req_r0_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_0_S_v), .n_in_flit(req_0_1_0_S_f), .n_in_ready(req_0_1_0_S_r),
        .n_out_valid(req_0_2_0_N_v), .n_out_flit(req_0_2_0_N_f), .n_out_ready(req_0_2_0_N_r),
        .s_in_valid(req_0_3_0_N_v), .s_in_flit(req_0_3_0_N_f), .s_in_ready(req_0_3_0_N_r),
        .s_out_valid(req_0_2_0_S_v), .s_out_flit(req_0_2_0_S_f), .s_out_ready(req_0_2_0_S_r),
        .e_in_valid(req_1_2_0_W_v), .e_in_flit(req_1_2_0_W_f), .e_in_ready(req_1_2_0_W_r),
        .e_out_valid(req_0_2_0_E_v), .e_out_flit(req_0_2_0_E_f), .e_out_ready(req_0_2_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_2_1_U_v), .d_in_flit(req_0_2_1_U_f), .d_in_ready(req_0_2_1_U_r),
        .d_out_valid(req_0_2_0_D_v), .d_out_flit(req_0_2_0_D_f), .d_out_ready(req_0_2_0_D_r),
        .l_in_valid(p6_req_out_valid), .l_in_flit(p6_req_out_flit), .l_in_ready(p6_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(0)) resp_r0_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_0_S_v), .n_in_flit(resp_0_1_0_S_f), .n_in_ready(resp_0_1_0_S_r),
        .n_out_valid(resp_0_2_0_N_v), .n_out_flit(resp_0_2_0_N_f), .n_out_ready(resp_0_2_0_N_r),
        .s_in_valid(resp_0_3_0_N_v), .s_in_flit(resp_0_3_0_N_f), .s_in_ready(resp_0_3_0_N_r),
        .s_out_valid(resp_0_2_0_S_v), .s_out_flit(resp_0_2_0_S_f), .s_out_ready(resp_0_2_0_S_r),
        .e_in_valid(resp_1_2_0_W_v), .e_in_flit(resp_1_2_0_W_f), .e_in_ready(resp_1_2_0_W_r),
        .e_out_valid(resp_0_2_0_E_v), .e_out_flit(resp_0_2_0_E_f), .e_out_ready(resp_0_2_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_2_1_U_v), .d_in_flit(resp_0_2_1_U_f), .d_in_ready(resp_0_2_1_U_r),
        .d_out_valid(resp_0_2_0_D_v), .d_out_flit(resp_0_2_0_D_f), .d_out_ready(resp_0_2_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p6_resp_in_valid), .l_out_flit(p6_resp_in_flit), .l_out_ready(p6_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(1)) req_r0_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_1_S_v), .n_in_flit(req_0_1_1_S_f), .n_in_ready(req_0_1_1_S_r),
        .n_out_valid(req_0_2_1_N_v), .n_out_flit(req_0_2_1_N_f), .n_out_ready(req_0_2_1_N_r),
        .s_in_valid(req_0_3_1_N_v), .s_in_flit(req_0_3_1_N_f), .s_in_ready(req_0_3_1_N_r),
        .s_out_valid(req_0_2_1_S_v), .s_out_flit(req_0_2_1_S_f), .s_out_ready(req_0_2_1_S_r),
        .e_in_valid(req_1_2_1_W_v), .e_in_flit(req_1_2_1_W_f), .e_in_ready(req_1_2_1_W_r),
        .e_out_valid(req_0_2_1_E_v), .e_out_flit(req_0_2_1_E_f), .e_out_ready(req_0_2_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_0_D_v), .u_in_flit(req_0_2_0_D_f), .u_in_ready(req_0_2_0_D_r),
        .u_out_valid(req_0_2_1_U_v), .u_out_flit(req_0_2_1_U_f), .u_out_ready(req_0_2_1_U_r),
        .d_in_valid(req_0_2_2_U_v), .d_in_flit(req_0_2_2_U_f), .d_in_ready(req_0_2_2_U_r),
        .d_out_valid(req_0_2_1_D_v), .d_out_flit(req_0_2_1_D_f), .d_out_ready(req_0_2_1_D_r),
        .l_in_valid(p7_req_out_valid), .l_in_flit(p7_req_out_flit), .l_in_ready(p7_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(1)) resp_r0_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_1_S_v), .n_in_flit(resp_0_1_1_S_f), .n_in_ready(resp_0_1_1_S_r),
        .n_out_valid(resp_0_2_1_N_v), .n_out_flit(resp_0_2_1_N_f), .n_out_ready(resp_0_2_1_N_r),
        .s_in_valid(resp_0_3_1_N_v), .s_in_flit(resp_0_3_1_N_f), .s_in_ready(resp_0_3_1_N_r),
        .s_out_valid(resp_0_2_1_S_v), .s_out_flit(resp_0_2_1_S_f), .s_out_ready(resp_0_2_1_S_r),
        .e_in_valid(resp_1_2_1_W_v), .e_in_flit(resp_1_2_1_W_f), .e_in_ready(resp_1_2_1_W_r),
        .e_out_valid(resp_0_2_1_E_v), .e_out_flit(resp_0_2_1_E_f), .e_out_ready(resp_0_2_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_0_D_v), .u_in_flit(resp_0_2_0_D_f), .u_in_ready(resp_0_2_0_D_r),
        .u_out_valid(resp_0_2_1_U_v), .u_out_flit(resp_0_2_1_U_f), .u_out_ready(resp_0_2_1_U_r),
        .d_in_valid(resp_0_2_2_U_v), .d_in_flit(resp_0_2_2_U_f), .d_in_ready(resp_0_2_2_U_r),
        .d_out_valid(resp_0_2_1_D_v), .d_out_flit(resp_0_2_1_D_f), .d_out_ready(resp_0_2_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p7_resp_in_valid), .l_out_flit(p7_resp_in_flit), .l_out_ready(p7_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(2)) req_r0_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_2_S_v), .n_in_flit(req_0_1_2_S_f), .n_in_ready(req_0_1_2_S_r),
        .n_out_valid(req_0_2_2_N_v), .n_out_flit(req_0_2_2_N_f), .n_out_ready(req_0_2_2_N_r),
        .s_in_valid(req_0_3_2_N_v), .s_in_flit(req_0_3_2_N_f), .s_in_ready(req_0_3_2_N_r),
        .s_out_valid(req_0_2_2_S_v), .s_out_flit(req_0_2_2_S_f), .s_out_ready(req_0_2_2_S_r),
        .e_in_valid(req_1_2_2_W_v), .e_in_flit(req_1_2_2_W_f), .e_in_ready(req_1_2_2_W_r),
        .e_out_valid(req_0_2_2_E_v), .e_out_flit(req_0_2_2_E_f), .e_out_ready(req_0_2_2_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_1_D_v), .u_in_flit(req_0_2_1_D_f), .u_in_ready(req_0_2_1_D_r),
        .u_out_valid(req_0_2_2_U_v), .u_out_flit(req_0_2_2_U_f), .u_out_ready(req_0_2_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(p8_req_out_valid), .l_in_flit(p8_req_out_flit), .l_in_ready(p8_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(2)) resp_r0_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_2_S_v), .n_in_flit(resp_0_1_2_S_f), .n_in_ready(resp_0_1_2_S_r),
        .n_out_valid(resp_0_2_2_N_v), .n_out_flit(resp_0_2_2_N_f), .n_out_ready(resp_0_2_2_N_r),
        .s_in_valid(resp_0_3_2_N_v), .s_in_flit(resp_0_3_2_N_f), .s_in_ready(resp_0_3_2_N_r),
        .s_out_valid(resp_0_2_2_S_v), .s_out_flit(resp_0_2_2_S_f), .s_out_ready(resp_0_2_2_S_r),
        .e_in_valid(resp_1_2_2_W_v), .e_in_flit(resp_1_2_2_W_f), .e_in_ready(resp_1_2_2_W_r),
        .e_out_valid(resp_0_2_2_E_v), .e_out_flit(resp_0_2_2_E_f), .e_out_ready(resp_0_2_2_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_1_D_v), .u_in_flit(resp_0_2_1_D_f), .u_in_ready(resp_0_2_1_D_r),
        .u_out_valid(resp_0_2_2_U_v), .u_out_flit(resp_0_2_2_U_f), .u_out_ready(resp_0_2_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p8_resp_in_valid), .l_out_flit(p8_resp_in_flit), .l_out_ready(p8_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(3), .MY_Z(0)) req_r0_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_2_0_S_v), .n_in_flit(req_0_2_0_S_f), .n_in_ready(req_0_2_0_S_r),
        .n_out_valid(req_0_3_0_N_v), .n_out_flit(req_0_3_0_N_f), .n_out_ready(req_0_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_3_0_W_v), .e_in_flit(req_1_3_0_W_f), .e_in_ready(req_1_3_0_W_r),
        .e_out_valid(req_0_3_0_E_v), .e_out_flit(req_0_3_0_E_f), .e_out_ready(req_0_3_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_3_1_U_v), .d_in_flit(req_0_3_1_U_f), .d_in_ready(req_0_3_1_U_r),
        .d_out_valid(req_0_3_0_D_v), .d_out_flit(req_0_3_0_D_f), .d_out_ready(req_0_3_0_D_r),
        .l_in_valid(p9_req_out_valid), .l_in_flit(p9_req_out_flit), .l_in_ready(p9_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(3), .MY_Z(0)) resp_r0_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_2_0_S_v), .n_in_flit(resp_0_2_0_S_f), .n_in_ready(resp_0_2_0_S_r),
        .n_out_valid(resp_0_3_0_N_v), .n_out_flit(resp_0_3_0_N_f), .n_out_ready(resp_0_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_3_0_W_v), .e_in_flit(resp_1_3_0_W_f), .e_in_ready(resp_1_3_0_W_r),
        .e_out_valid(resp_0_3_0_E_v), .e_out_flit(resp_0_3_0_E_f), .e_out_ready(resp_0_3_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_3_1_U_v), .d_in_flit(resp_0_3_1_U_f), .d_in_ready(resp_0_3_1_U_r),
        .d_out_valid(resp_0_3_0_D_v), .d_out_flit(resp_0_3_0_D_f), .d_out_ready(resp_0_3_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p9_resp_in_valid), .l_out_flit(p9_resp_in_flit), .l_out_ready(p9_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(3), .MY_Z(1)) req_r0_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_2_1_S_v), .n_in_flit(req_0_2_1_S_f), .n_in_ready(req_0_2_1_S_r),
        .n_out_valid(req_0_3_1_N_v), .n_out_flit(req_0_3_1_N_f), .n_out_ready(req_0_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_3_1_W_v), .e_in_flit(req_1_3_1_W_f), .e_in_ready(req_1_3_1_W_r),
        .e_out_valid(req_0_3_1_E_v), .e_out_flit(req_0_3_1_E_f), .e_out_ready(req_0_3_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_3_0_D_v), .u_in_flit(req_0_3_0_D_f), .u_in_ready(req_0_3_0_D_r),
        .u_out_valid(req_0_3_1_U_v), .u_out_flit(req_0_3_1_U_f), .u_out_ready(req_0_3_1_U_r),
        .d_in_valid(req_0_3_2_U_v), .d_in_flit(req_0_3_2_U_f), .d_in_ready(req_0_3_2_U_r),
        .d_out_valid(req_0_3_1_D_v), .d_out_flit(req_0_3_1_D_f), .d_out_ready(req_0_3_1_D_r),
        .l_in_valid(p10_req_out_valid), .l_in_flit(p10_req_out_flit), .l_in_ready(p10_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(3), .MY_Z(1)) resp_r0_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_2_1_S_v), .n_in_flit(resp_0_2_1_S_f), .n_in_ready(resp_0_2_1_S_r),
        .n_out_valid(resp_0_3_1_N_v), .n_out_flit(resp_0_3_1_N_f), .n_out_ready(resp_0_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_3_1_W_v), .e_in_flit(resp_1_3_1_W_f), .e_in_ready(resp_1_3_1_W_r),
        .e_out_valid(resp_0_3_1_E_v), .e_out_flit(resp_0_3_1_E_f), .e_out_ready(resp_0_3_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_3_0_D_v), .u_in_flit(resp_0_3_0_D_f), .u_in_ready(resp_0_3_0_D_r),
        .u_out_valid(resp_0_3_1_U_v), .u_out_flit(resp_0_3_1_U_f), .u_out_ready(resp_0_3_1_U_r),
        .d_in_valid(resp_0_3_2_U_v), .d_in_flit(resp_0_3_2_U_f), .d_in_ready(resp_0_3_2_U_r),
        .d_out_valid(resp_0_3_1_D_v), .d_out_flit(resp_0_3_1_D_f), .d_out_ready(resp_0_3_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p10_resp_in_valid), .l_out_flit(p10_resp_in_flit), .l_out_ready(p10_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(0), .MY_Y(3), .MY_Z(2)) req_r0_3_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_2_2_S_v), .n_in_flit(req_0_2_2_S_f), .n_in_ready(req_0_2_2_S_r),
        .n_out_valid(req_0_3_2_N_v), .n_out_flit(req_0_3_2_N_f), .n_out_ready(req_0_3_2_N_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_3_2_W_v), .e_in_flit(req_1_3_2_W_f), .e_in_ready(req_1_3_2_W_r),
        .e_out_valid(req_0_3_2_E_v), .e_out_flit(req_0_3_2_E_f), .e_out_ready(req_0_3_2_E_r),
        .w_in_valid(1'b0), .w_in_flit({80{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_3_1_D_v), .u_in_flit(req_0_3_1_D_f), .u_in_ready(req_0_3_1_D_r),
        .u_out_valid(req_0_3_2_U_v), .u_out_flit(req_0_3_2_U_f), .u_out_ready(req_0_3_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(p11_req_out_valid), .l_in_flit(p11_req_out_flit), .l_in_ready(p11_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(0), .MY_Y(3), .MY_Z(2)) resp_r0_3_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_2_2_S_v), .n_in_flit(resp_0_2_2_S_f), .n_in_ready(resp_0_2_2_S_r),
        .n_out_valid(resp_0_3_2_N_v), .n_out_flit(resp_0_3_2_N_f), .n_out_ready(resp_0_3_2_N_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_3_2_W_v), .e_in_flit(resp_1_3_2_W_f), .e_in_ready(resp_1_3_2_W_r),
        .e_out_valid(resp_0_3_2_E_v), .e_out_flit(resp_0_3_2_E_f), .e_out_ready(resp_0_3_2_E_r),
        .w_in_valid(1'b0), .w_in_flit({38{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_3_1_D_v), .u_in_flit(resp_0_3_1_D_f), .u_in_ready(resp_0_3_1_D_r),
        .u_out_valid(resp_0_3_2_U_v), .u_out_flit(resp_0_3_2_U_f), .u_out_ready(resp_0_3_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p11_resp_in_valid), .l_out_flit(p11_resp_in_flit), .l_out_ready(p11_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(0)) req_r1_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_0_N_v), .s_in_flit(req_1_1_0_N_f), .s_in_ready(req_1_1_0_N_r),
        .s_out_valid(req_1_0_0_S_v), .s_out_flit(req_1_0_0_S_f), .s_out_ready(req_1_0_0_S_r),
        .e_in_valid(req_2_0_0_W_v), .e_in_flit(req_2_0_0_W_f), .e_in_ready(req_2_0_0_W_r),
        .e_out_valid(req_1_0_0_E_v), .e_out_flit(req_1_0_0_E_f), .e_out_ready(req_1_0_0_E_r),
        .w_in_valid(req_0_0_0_E_v), .w_in_flit(req_0_0_0_E_f), .w_in_ready(req_0_0_0_E_r),
        .w_out_valid(req_1_0_0_W_v), .w_out_flit(req_1_0_0_W_f), .w_out_ready(req_1_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_0_1_U_v), .d_in_flit(req_1_0_1_U_f), .d_in_ready(req_1_0_1_U_r),
        .d_out_valid(req_1_0_0_D_v), .d_out_flit(req_1_0_0_D_f), .d_out_ready(req_1_0_0_D_r),
        .l_in_valid(p12_req_out_valid), .l_in_flit(p12_req_out_flit), .l_in_ready(p12_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(0)) resp_r1_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_0_N_v), .s_in_flit(resp_1_1_0_N_f), .s_in_ready(resp_1_1_0_N_r),
        .s_out_valid(resp_1_0_0_S_v), .s_out_flit(resp_1_0_0_S_f), .s_out_ready(resp_1_0_0_S_r),
        .e_in_valid(resp_2_0_0_W_v), .e_in_flit(resp_2_0_0_W_f), .e_in_ready(resp_2_0_0_W_r),
        .e_out_valid(resp_1_0_0_E_v), .e_out_flit(resp_1_0_0_E_f), .e_out_ready(resp_1_0_0_E_r),
        .w_in_valid(resp_0_0_0_E_v), .w_in_flit(resp_0_0_0_E_f), .w_in_ready(resp_0_0_0_E_r),
        .w_out_valid(resp_1_0_0_W_v), .w_out_flit(resp_1_0_0_W_f), .w_out_ready(resp_1_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_0_1_U_v), .d_in_flit(resp_1_0_1_U_f), .d_in_ready(resp_1_0_1_U_r),
        .d_out_valid(resp_1_0_0_D_v), .d_out_flit(resp_1_0_0_D_f), .d_out_ready(resp_1_0_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p12_resp_in_valid), .l_out_flit(p12_resp_in_flit), .l_out_ready(p12_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(1)) req_r1_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_1_N_v), .s_in_flit(req_1_1_1_N_f), .s_in_ready(req_1_1_1_N_r),
        .s_out_valid(req_1_0_1_S_v), .s_out_flit(req_1_0_1_S_f), .s_out_ready(req_1_0_1_S_r),
        .e_in_valid(req_2_0_1_W_v), .e_in_flit(req_2_0_1_W_f), .e_in_ready(req_2_0_1_W_r),
        .e_out_valid(req_1_0_1_E_v), .e_out_flit(req_1_0_1_E_f), .e_out_ready(req_1_0_1_E_r),
        .w_in_valid(req_0_0_1_E_v), .w_in_flit(req_0_0_1_E_f), .w_in_ready(req_0_0_1_E_r),
        .w_out_valid(req_1_0_1_W_v), .w_out_flit(req_1_0_1_W_f), .w_out_ready(req_1_0_1_W_r),
        .u_in_valid(req_1_0_0_D_v), .u_in_flit(req_1_0_0_D_f), .u_in_ready(req_1_0_0_D_r),
        .u_out_valid(req_1_0_1_U_v), .u_out_flit(req_1_0_1_U_f), .u_out_ready(req_1_0_1_U_r),
        .d_in_valid(req_1_0_2_U_v), .d_in_flit(req_1_0_2_U_f), .d_in_ready(req_1_0_2_U_r),
        .d_out_valid(req_1_0_1_D_v), .d_out_flit(req_1_0_1_D_f), .d_out_ready(req_1_0_1_D_r),
        .l_in_valid(p13_req_out_valid), .l_in_flit(p13_req_out_flit), .l_in_ready(p13_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(1)) resp_r1_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_1_N_v), .s_in_flit(resp_1_1_1_N_f), .s_in_ready(resp_1_1_1_N_r),
        .s_out_valid(resp_1_0_1_S_v), .s_out_flit(resp_1_0_1_S_f), .s_out_ready(resp_1_0_1_S_r),
        .e_in_valid(resp_2_0_1_W_v), .e_in_flit(resp_2_0_1_W_f), .e_in_ready(resp_2_0_1_W_r),
        .e_out_valid(resp_1_0_1_E_v), .e_out_flit(resp_1_0_1_E_f), .e_out_ready(resp_1_0_1_E_r),
        .w_in_valid(resp_0_0_1_E_v), .w_in_flit(resp_0_0_1_E_f), .w_in_ready(resp_0_0_1_E_r),
        .w_out_valid(resp_1_0_1_W_v), .w_out_flit(resp_1_0_1_W_f), .w_out_ready(resp_1_0_1_W_r),
        .u_in_valid(resp_1_0_0_D_v), .u_in_flit(resp_1_0_0_D_f), .u_in_ready(resp_1_0_0_D_r),
        .u_out_valid(resp_1_0_1_U_v), .u_out_flit(resp_1_0_1_U_f), .u_out_ready(resp_1_0_1_U_r),
        .d_in_valid(resp_1_0_2_U_v), .d_in_flit(resp_1_0_2_U_f), .d_in_ready(resp_1_0_2_U_r),
        .d_out_valid(resp_1_0_1_D_v), .d_out_flit(resp_1_0_1_D_f), .d_out_ready(resp_1_0_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p13_resp_in_valid), .l_out_flit(p13_resp_in_flit), .l_out_ready(p13_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(2)) req_r1_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_2_N_v), .s_in_flit(req_1_1_2_N_f), .s_in_ready(req_1_1_2_N_r),
        .s_out_valid(req_1_0_2_S_v), .s_out_flit(req_1_0_2_S_f), .s_out_ready(req_1_0_2_S_r),
        .e_in_valid(req_2_0_2_W_v), .e_in_flit(req_2_0_2_W_f), .e_in_ready(req_2_0_2_W_r),
        .e_out_valid(req_1_0_2_E_v), .e_out_flit(req_1_0_2_E_f), .e_out_ready(req_1_0_2_E_r),
        .w_in_valid(req_0_0_2_E_v), .w_in_flit(req_0_0_2_E_f), .w_in_ready(req_0_0_2_E_r),
        .w_out_valid(req_1_0_2_W_v), .w_out_flit(req_1_0_2_W_f), .w_out_ready(req_1_0_2_W_r),
        .u_in_valid(req_1_0_1_D_v), .u_in_flit(req_1_0_1_D_f), .u_in_ready(req_1_0_1_D_r),
        .u_out_valid(req_1_0_2_U_v), .u_out_flit(req_1_0_2_U_f), .u_out_ready(req_1_0_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(p14_req_out_valid), .l_in_flit(p14_req_out_flit), .l_in_ready(p14_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(2)) resp_r1_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_2_N_v), .s_in_flit(resp_1_1_2_N_f), .s_in_ready(resp_1_1_2_N_r),
        .s_out_valid(resp_1_0_2_S_v), .s_out_flit(resp_1_0_2_S_f), .s_out_ready(resp_1_0_2_S_r),
        .e_in_valid(resp_2_0_2_W_v), .e_in_flit(resp_2_0_2_W_f), .e_in_ready(resp_2_0_2_W_r),
        .e_out_valid(resp_1_0_2_E_v), .e_out_flit(resp_1_0_2_E_f), .e_out_ready(resp_1_0_2_E_r),
        .w_in_valid(resp_0_0_2_E_v), .w_in_flit(resp_0_0_2_E_f), .w_in_ready(resp_0_0_2_E_r),
        .w_out_valid(resp_1_0_2_W_v), .w_out_flit(resp_1_0_2_W_f), .w_out_ready(resp_1_0_2_W_r),
        .u_in_valid(resp_1_0_1_D_v), .u_in_flit(resp_1_0_1_D_f), .u_in_ready(resp_1_0_1_D_r),
        .u_out_valid(resp_1_0_2_U_v), .u_out_flit(resp_1_0_2_U_f), .u_out_ready(resp_1_0_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p14_resp_in_valid), .l_out_flit(p14_resp_in_flit), .l_out_ready(p14_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(0)) req_r1_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_0_S_v), .n_in_flit(req_1_0_0_S_f), .n_in_ready(req_1_0_0_S_r),
        .n_out_valid(req_1_1_0_N_v), .n_out_flit(req_1_1_0_N_f), .n_out_ready(req_1_1_0_N_r),
        .s_in_valid(req_1_2_0_N_v), .s_in_flit(req_1_2_0_N_f), .s_in_ready(req_1_2_0_N_r),
        .s_out_valid(req_1_1_0_S_v), .s_out_flit(req_1_1_0_S_f), .s_out_ready(req_1_1_0_S_r),
        .e_in_valid(req_2_1_0_W_v), .e_in_flit(req_2_1_0_W_f), .e_in_ready(req_2_1_0_W_r),
        .e_out_valid(req_1_1_0_E_v), .e_out_flit(req_1_1_0_E_f), .e_out_ready(req_1_1_0_E_r),
        .w_in_valid(req_0_1_0_E_v), .w_in_flit(req_0_1_0_E_f), .w_in_ready(req_0_1_0_E_r),
        .w_out_valid(req_1_1_0_W_v), .w_out_flit(req_1_1_0_W_f), .w_out_ready(req_1_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_1_1_U_v), .d_in_flit(req_1_1_1_U_f), .d_in_ready(req_1_1_1_U_r),
        .d_out_valid(req_1_1_0_D_v), .d_out_flit(req_1_1_0_D_f), .d_out_ready(req_1_1_0_D_r),
        .l_in_valid(p15_req_out_valid), .l_in_flit(p15_req_out_flit), .l_in_ready(p15_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(0)) resp_r1_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_0_S_v), .n_in_flit(resp_1_0_0_S_f), .n_in_ready(resp_1_0_0_S_r),
        .n_out_valid(resp_1_1_0_N_v), .n_out_flit(resp_1_1_0_N_f), .n_out_ready(resp_1_1_0_N_r),
        .s_in_valid(resp_1_2_0_N_v), .s_in_flit(resp_1_2_0_N_f), .s_in_ready(resp_1_2_0_N_r),
        .s_out_valid(resp_1_1_0_S_v), .s_out_flit(resp_1_1_0_S_f), .s_out_ready(resp_1_1_0_S_r),
        .e_in_valid(resp_2_1_0_W_v), .e_in_flit(resp_2_1_0_W_f), .e_in_ready(resp_2_1_0_W_r),
        .e_out_valid(resp_1_1_0_E_v), .e_out_flit(resp_1_1_0_E_f), .e_out_ready(resp_1_1_0_E_r),
        .w_in_valid(resp_0_1_0_E_v), .w_in_flit(resp_0_1_0_E_f), .w_in_ready(resp_0_1_0_E_r),
        .w_out_valid(resp_1_1_0_W_v), .w_out_flit(resp_1_1_0_W_f), .w_out_ready(resp_1_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_1_1_U_v), .d_in_flit(resp_1_1_1_U_f), .d_in_ready(resp_1_1_1_U_r),
        .d_out_valid(resp_1_1_0_D_v), .d_out_flit(resp_1_1_0_D_f), .d_out_ready(resp_1_1_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p15_resp_in_valid), .l_out_flit(p15_resp_in_flit), .l_out_ready(p15_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(1)) req_r1_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_1_S_v), .n_in_flit(req_1_0_1_S_f), .n_in_ready(req_1_0_1_S_r),
        .n_out_valid(req_1_1_1_N_v), .n_out_flit(req_1_1_1_N_f), .n_out_ready(req_1_1_1_N_r),
        .s_in_valid(req_1_2_1_N_v), .s_in_flit(req_1_2_1_N_f), .s_in_ready(req_1_2_1_N_r),
        .s_out_valid(req_1_1_1_S_v), .s_out_flit(req_1_1_1_S_f), .s_out_ready(req_1_1_1_S_r),
        .e_in_valid(req_2_1_1_W_v), .e_in_flit(req_2_1_1_W_f), .e_in_ready(req_2_1_1_W_r),
        .e_out_valid(req_1_1_1_E_v), .e_out_flit(req_1_1_1_E_f), .e_out_ready(req_1_1_1_E_r),
        .w_in_valid(req_0_1_1_E_v), .w_in_flit(req_0_1_1_E_f), .w_in_ready(req_0_1_1_E_r),
        .w_out_valid(req_1_1_1_W_v), .w_out_flit(req_1_1_1_W_f), .w_out_ready(req_1_1_1_W_r),
        .u_in_valid(req_1_1_0_D_v), .u_in_flit(req_1_1_0_D_f), .u_in_ready(req_1_1_0_D_r),
        .u_out_valid(req_1_1_1_U_v), .u_out_flit(req_1_1_1_U_f), .u_out_ready(req_1_1_1_U_r),
        .d_in_valid(req_1_1_2_U_v), .d_in_flit(req_1_1_2_U_f), .d_in_ready(req_1_1_2_U_r),
        .d_out_valid(req_1_1_1_D_v), .d_out_flit(req_1_1_1_D_f), .d_out_ready(req_1_1_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({80{1'b0}}), .l_in_ready(),
        .l_out_valid(mem_req_in_valid), .l_out_flit(mem_req_in_flit), .l_out_ready(mem_req_in_ready)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(1)) resp_r1_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_1_S_v), .n_in_flit(resp_1_0_1_S_f), .n_in_ready(resp_1_0_1_S_r),
        .n_out_valid(resp_1_1_1_N_v), .n_out_flit(resp_1_1_1_N_f), .n_out_ready(resp_1_1_1_N_r),
        .s_in_valid(resp_1_2_1_N_v), .s_in_flit(resp_1_2_1_N_f), .s_in_ready(resp_1_2_1_N_r),
        .s_out_valid(resp_1_1_1_S_v), .s_out_flit(resp_1_1_1_S_f), .s_out_ready(resp_1_1_1_S_r),
        .e_in_valid(resp_2_1_1_W_v), .e_in_flit(resp_2_1_1_W_f), .e_in_ready(resp_2_1_1_W_r),
        .e_out_valid(resp_1_1_1_E_v), .e_out_flit(resp_1_1_1_E_f), .e_out_ready(resp_1_1_1_E_r),
        .w_in_valid(resp_0_1_1_E_v), .w_in_flit(resp_0_1_1_E_f), .w_in_ready(resp_0_1_1_E_r),
        .w_out_valid(resp_1_1_1_W_v), .w_out_flit(resp_1_1_1_W_f), .w_out_ready(resp_1_1_1_W_r),
        .u_in_valid(resp_1_1_0_D_v), .u_in_flit(resp_1_1_0_D_f), .u_in_ready(resp_1_1_0_D_r),
        .u_out_valid(resp_1_1_1_U_v), .u_out_flit(resp_1_1_1_U_f), .u_out_ready(resp_1_1_1_U_r),
        .d_in_valid(resp_1_1_2_U_v), .d_in_flit(resp_1_1_2_U_f), .d_in_ready(resp_1_1_2_U_r),
        .d_out_valid(resp_1_1_1_D_v), .d_out_flit(resp_1_1_1_D_f), .d_out_ready(resp_1_1_1_D_r),
        .l_in_valid(mem_resp_out_valid), .l_in_flit(mem_resp_out_flit), .l_in_ready(mem_resp_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(2)) req_r1_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_2_S_v), .n_in_flit(req_1_0_2_S_f), .n_in_ready(req_1_0_2_S_r),
        .n_out_valid(req_1_1_2_N_v), .n_out_flit(req_1_1_2_N_f), .n_out_ready(req_1_1_2_N_r),
        .s_in_valid(req_1_2_2_N_v), .s_in_flit(req_1_2_2_N_f), .s_in_ready(req_1_2_2_N_r),
        .s_out_valid(req_1_1_2_S_v), .s_out_flit(req_1_1_2_S_f), .s_out_ready(req_1_1_2_S_r),
        .e_in_valid(req_2_1_2_W_v), .e_in_flit(req_2_1_2_W_f), .e_in_ready(req_2_1_2_W_r),
        .e_out_valid(req_1_1_2_E_v), .e_out_flit(req_1_1_2_E_f), .e_out_ready(req_1_1_2_E_r),
        .w_in_valid(req_0_1_2_E_v), .w_in_flit(req_0_1_2_E_f), .w_in_ready(req_0_1_2_E_r),
        .w_out_valid(req_1_1_2_W_v), .w_out_flit(req_1_1_2_W_f), .w_out_ready(req_1_1_2_W_r),
        .u_in_valid(req_1_1_1_D_v), .u_in_flit(req_1_1_1_D_f), .u_in_ready(req_1_1_1_D_r),
        .u_out_valid(req_1_1_2_U_v), .u_out_flit(req_1_1_2_U_f), .u_out_ready(req_1_1_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(p16_req_out_valid), .l_in_flit(p16_req_out_flit), .l_in_ready(p16_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(2)) resp_r1_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_2_S_v), .n_in_flit(resp_1_0_2_S_f), .n_in_ready(resp_1_0_2_S_r),
        .n_out_valid(resp_1_1_2_N_v), .n_out_flit(resp_1_1_2_N_f), .n_out_ready(resp_1_1_2_N_r),
        .s_in_valid(resp_1_2_2_N_v), .s_in_flit(resp_1_2_2_N_f), .s_in_ready(resp_1_2_2_N_r),
        .s_out_valid(resp_1_1_2_S_v), .s_out_flit(resp_1_1_2_S_f), .s_out_ready(resp_1_1_2_S_r),
        .e_in_valid(resp_2_1_2_W_v), .e_in_flit(resp_2_1_2_W_f), .e_in_ready(resp_2_1_2_W_r),
        .e_out_valid(resp_1_1_2_E_v), .e_out_flit(resp_1_1_2_E_f), .e_out_ready(resp_1_1_2_E_r),
        .w_in_valid(resp_0_1_2_E_v), .w_in_flit(resp_0_1_2_E_f), .w_in_ready(resp_0_1_2_E_r),
        .w_out_valid(resp_1_1_2_W_v), .w_out_flit(resp_1_1_2_W_f), .w_out_ready(resp_1_1_2_W_r),
        .u_in_valid(resp_1_1_1_D_v), .u_in_flit(resp_1_1_1_D_f), .u_in_ready(resp_1_1_1_D_r),
        .u_out_valid(resp_1_1_2_U_v), .u_out_flit(resp_1_1_2_U_f), .u_out_ready(resp_1_1_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p16_resp_in_valid), .l_out_flit(p16_resp_in_flit), .l_out_ready(p16_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(0)) req_r1_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_0_S_v), .n_in_flit(req_1_1_0_S_f), .n_in_ready(req_1_1_0_S_r),
        .n_out_valid(req_1_2_0_N_v), .n_out_flit(req_1_2_0_N_f), .n_out_ready(req_1_2_0_N_r),
        .s_in_valid(req_1_3_0_N_v), .s_in_flit(req_1_3_0_N_f), .s_in_ready(req_1_3_0_N_r),
        .s_out_valid(req_1_2_0_S_v), .s_out_flit(req_1_2_0_S_f), .s_out_ready(req_1_2_0_S_r),
        .e_in_valid(req_2_2_0_W_v), .e_in_flit(req_2_2_0_W_f), .e_in_ready(req_2_2_0_W_r),
        .e_out_valid(req_1_2_0_E_v), .e_out_flit(req_1_2_0_E_f), .e_out_ready(req_1_2_0_E_r),
        .w_in_valid(req_0_2_0_E_v), .w_in_flit(req_0_2_0_E_f), .w_in_ready(req_0_2_0_E_r),
        .w_out_valid(req_1_2_0_W_v), .w_out_flit(req_1_2_0_W_f), .w_out_ready(req_1_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_2_1_U_v), .d_in_flit(req_1_2_1_U_f), .d_in_ready(req_1_2_1_U_r),
        .d_out_valid(req_1_2_0_D_v), .d_out_flit(req_1_2_0_D_f), .d_out_ready(req_1_2_0_D_r),
        .l_in_valid(p17_req_out_valid), .l_in_flit(p17_req_out_flit), .l_in_ready(p17_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(0)) resp_r1_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_0_S_v), .n_in_flit(resp_1_1_0_S_f), .n_in_ready(resp_1_1_0_S_r),
        .n_out_valid(resp_1_2_0_N_v), .n_out_flit(resp_1_2_0_N_f), .n_out_ready(resp_1_2_0_N_r),
        .s_in_valid(resp_1_3_0_N_v), .s_in_flit(resp_1_3_0_N_f), .s_in_ready(resp_1_3_0_N_r),
        .s_out_valid(resp_1_2_0_S_v), .s_out_flit(resp_1_2_0_S_f), .s_out_ready(resp_1_2_0_S_r),
        .e_in_valid(resp_2_2_0_W_v), .e_in_flit(resp_2_2_0_W_f), .e_in_ready(resp_2_2_0_W_r),
        .e_out_valid(resp_1_2_0_E_v), .e_out_flit(resp_1_2_0_E_f), .e_out_ready(resp_1_2_0_E_r),
        .w_in_valid(resp_0_2_0_E_v), .w_in_flit(resp_0_2_0_E_f), .w_in_ready(resp_0_2_0_E_r),
        .w_out_valid(resp_1_2_0_W_v), .w_out_flit(resp_1_2_0_W_f), .w_out_ready(resp_1_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_2_1_U_v), .d_in_flit(resp_1_2_1_U_f), .d_in_ready(resp_1_2_1_U_r),
        .d_out_valid(resp_1_2_0_D_v), .d_out_flit(resp_1_2_0_D_f), .d_out_ready(resp_1_2_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(p17_resp_in_valid), .l_out_flit(p17_resp_in_flit), .l_out_ready(p17_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(1)) req_r1_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_1_S_v), .n_in_flit(req_1_1_1_S_f), .n_in_ready(req_1_1_1_S_r),
        .n_out_valid(req_1_2_1_N_v), .n_out_flit(req_1_2_1_N_f), .n_out_ready(req_1_2_1_N_r),
        .s_in_valid(req_1_3_1_N_v), .s_in_flit(req_1_3_1_N_f), .s_in_ready(req_1_3_1_N_r),
        .s_out_valid(req_1_2_1_S_v), .s_out_flit(req_1_2_1_S_f), .s_out_ready(req_1_2_1_S_r),
        .e_in_valid(req_2_2_1_W_v), .e_in_flit(req_2_2_1_W_f), .e_in_ready(req_2_2_1_W_r),
        .e_out_valid(req_1_2_1_E_v), .e_out_flit(req_1_2_1_E_f), .e_out_ready(req_1_2_1_E_r),
        .w_in_valid(req_0_2_1_E_v), .w_in_flit(req_0_2_1_E_f), .w_in_ready(req_0_2_1_E_r),
        .w_out_valid(req_1_2_1_W_v), .w_out_flit(req_1_2_1_W_f), .w_out_ready(req_1_2_1_W_r),
        .u_in_valid(req_1_2_0_D_v), .u_in_flit(req_1_2_0_D_f), .u_in_ready(req_1_2_0_D_r),
        .u_out_valid(req_1_2_1_U_v), .u_out_flit(req_1_2_1_U_f), .u_out_ready(req_1_2_1_U_r),
        .d_in_valid(req_1_2_2_U_v), .d_in_flit(req_1_2_2_U_f), .d_in_ready(req_1_2_2_U_r),
        .d_out_valid(req_1_2_1_D_v), .d_out_flit(req_1_2_1_D_f), .d_out_ready(req_1_2_1_D_r),
        .l_in_valid(e0_req_out_valid), .l_in_flit(e0_req_out_flit), .l_in_ready(e0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(1)) resp_r1_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_1_S_v), .n_in_flit(resp_1_1_1_S_f), .n_in_ready(resp_1_1_1_S_r),
        .n_out_valid(resp_1_2_1_N_v), .n_out_flit(resp_1_2_1_N_f), .n_out_ready(resp_1_2_1_N_r),
        .s_in_valid(resp_1_3_1_N_v), .s_in_flit(resp_1_3_1_N_f), .s_in_ready(resp_1_3_1_N_r),
        .s_out_valid(resp_1_2_1_S_v), .s_out_flit(resp_1_2_1_S_f), .s_out_ready(resp_1_2_1_S_r),
        .e_in_valid(resp_2_2_1_W_v), .e_in_flit(resp_2_2_1_W_f), .e_in_ready(resp_2_2_1_W_r),
        .e_out_valid(resp_1_2_1_E_v), .e_out_flit(resp_1_2_1_E_f), .e_out_ready(resp_1_2_1_E_r),
        .w_in_valid(resp_0_2_1_E_v), .w_in_flit(resp_0_2_1_E_f), .w_in_ready(resp_0_2_1_E_r),
        .w_out_valid(resp_1_2_1_W_v), .w_out_flit(resp_1_2_1_W_f), .w_out_ready(resp_1_2_1_W_r),
        .u_in_valid(resp_1_2_0_D_v), .u_in_flit(resp_1_2_0_D_f), .u_in_ready(resp_1_2_0_D_r),
        .u_out_valid(resp_1_2_1_U_v), .u_out_flit(resp_1_2_1_U_f), .u_out_ready(resp_1_2_1_U_r),
        .d_in_valid(resp_1_2_2_U_v), .d_in_flit(resp_1_2_2_U_f), .d_in_ready(resp_1_2_2_U_r),
        .d_out_valid(resp_1_2_1_D_v), .d_out_flit(resp_1_2_1_D_f), .d_out_ready(resp_1_2_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e0_resp_in_valid), .l_out_flit(e0_resp_in_flit), .l_out_ready(e0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(2)) req_r1_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_2_S_v), .n_in_flit(req_1_1_2_S_f), .n_in_ready(req_1_1_2_S_r),
        .n_out_valid(req_1_2_2_N_v), .n_out_flit(req_1_2_2_N_f), .n_out_ready(req_1_2_2_N_r),
        .s_in_valid(req_1_3_2_N_v), .s_in_flit(req_1_3_2_N_f), .s_in_ready(req_1_3_2_N_r),
        .s_out_valid(req_1_2_2_S_v), .s_out_flit(req_1_2_2_S_f), .s_out_ready(req_1_2_2_S_r),
        .e_in_valid(req_2_2_2_W_v), .e_in_flit(req_2_2_2_W_f), .e_in_ready(req_2_2_2_W_r),
        .e_out_valid(req_1_2_2_E_v), .e_out_flit(req_1_2_2_E_f), .e_out_ready(req_1_2_2_E_r),
        .w_in_valid(req_0_2_2_E_v), .w_in_flit(req_0_2_2_E_f), .w_in_ready(req_0_2_2_E_r),
        .w_out_valid(req_1_2_2_W_v), .w_out_flit(req_1_2_2_W_f), .w_out_ready(req_1_2_2_W_r),
        .u_in_valid(req_1_2_1_D_v), .u_in_flit(req_1_2_1_D_f), .u_in_ready(req_1_2_1_D_r),
        .u_out_valid(req_1_2_2_U_v), .u_out_flit(req_1_2_2_U_f), .u_out_ready(req_1_2_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(e1_req_out_valid), .l_in_flit(e1_req_out_flit), .l_in_ready(e1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(2)) resp_r1_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_2_S_v), .n_in_flit(resp_1_1_2_S_f), .n_in_ready(resp_1_1_2_S_r),
        .n_out_valid(resp_1_2_2_N_v), .n_out_flit(resp_1_2_2_N_f), .n_out_ready(resp_1_2_2_N_r),
        .s_in_valid(resp_1_3_2_N_v), .s_in_flit(resp_1_3_2_N_f), .s_in_ready(resp_1_3_2_N_r),
        .s_out_valid(resp_1_2_2_S_v), .s_out_flit(resp_1_2_2_S_f), .s_out_ready(resp_1_2_2_S_r),
        .e_in_valid(resp_2_2_2_W_v), .e_in_flit(resp_2_2_2_W_f), .e_in_ready(resp_2_2_2_W_r),
        .e_out_valid(resp_1_2_2_E_v), .e_out_flit(resp_1_2_2_E_f), .e_out_ready(resp_1_2_2_E_r),
        .w_in_valid(resp_0_2_2_E_v), .w_in_flit(resp_0_2_2_E_f), .w_in_ready(resp_0_2_2_E_r),
        .w_out_valid(resp_1_2_2_W_v), .w_out_flit(resp_1_2_2_W_f), .w_out_ready(resp_1_2_2_W_r),
        .u_in_valid(resp_1_2_1_D_v), .u_in_flit(resp_1_2_1_D_f), .u_in_ready(resp_1_2_1_D_r),
        .u_out_valid(resp_1_2_2_U_v), .u_out_flit(resp_1_2_2_U_f), .u_out_ready(resp_1_2_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e1_resp_in_valid), .l_out_flit(e1_resp_in_flit), .l_out_ready(e1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(3), .MY_Z(0)) req_r1_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_2_0_S_v), .n_in_flit(req_1_2_0_S_f), .n_in_ready(req_1_2_0_S_r),
        .n_out_valid(req_1_3_0_N_v), .n_out_flit(req_1_3_0_N_f), .n_out_ready(req_1_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_2_3_0_W_v), .e_in_flit(req_2_3_0_W_f), .e_in_ready(req_2_3_0_W_r),
        .e_out_valid(req_1_3_0_E_v), .e_out_flit(req_1_3_0_E_f), .e_out_ready(req_1_3_0_E_r),
        .w_in_valid(req_0_3_0_E_v), .w_in_flit(req_0_3_0_E_f), .w_in_ready(req_0_3_0_E_r),
        .w_out_valid(req_1_3_0_W_v), .w_out_flit(req_1_3_0_W_f), .w_out_ready(req_1_3_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_3_1_U_v), .d_in_flit(req_1_3_1_U_f), .d_in_ready(req_1_3_1_U_r),
        .d_out_valid(req_1_3_0_D_v), .d_out_flit(req_1_3_0_D_f), .d_out_ready(req_1_3_0_D_r),
        .l_in_valid(e2_req_out_valid), .l_in_flit(e2_req_out_flit), .l_in_ready(e2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(3), .MY_Z(0)) resp_r1_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_2_0_S_v), .n_in_flit(resp_1_2_0_S_f), .n_in_ready(resp_1_2_0_S_r),
        .n_out_valid(resp_1_3_0_N_v), .n_out_flit(resp_1_3_0_N_f), .n_out_ready(resp_1_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_2_3_0_W_v), .e_in_flit(resp_2_3_0_W_f), .e_in_ready(resp_2_3_0_W_r),
        .e_out_valid(resp_1_3_0_E_v), .e_out_flit(resp_1_3_0_E_f), .e_out_ready(resp_1_3_0_E_r),
        .w_in_valid(resp_0_3_0_E_v), .w_in_flit(resp_0_3_0_E_f), .w_in_ready(resp_0_3_0_E_r),
        .w_out_valid(resp_1_3_0_W_v), .w_out_flit(resp_1_3_0_W_f), .w_out_ready(resp_1_3_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_3_1_U_v), .d_in_flit(resp_1_3_1_U_f), .d_in_ready(resp_1_3_1_U_r),
        .d_out_valid(resp_1_3_0_D_v), .d_out_flit(resp_1_3_0_D_f), .d_out_ready(resp_1_3_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e2_resp_in_valid), .l_out_flit(e2_resp_in_flit), .l_out_ready(e2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(3), .MY_Z(1)) req_r1_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_2_1_S_v), .n_in_flit(req_1_2_1_S_f), .n_in_ready(req_1_2_1_S_r),
        .n_out_valid(req_1_3_1_N_v), .n_out_flit(req_1_3_1_N_f), .n_out_ready(req_1_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_2_3_1_W_v), .e_in_flit(req_2_3_1_W_f), .e_in_ready(req_2_3_1_W_r),
        .e_out_valid(req_1_3_1_E_v), .e_out_flit(req_1_3_1_E_f), .e_out_ready(req_1_3_1_E_r),
        .w_in_valid(req_0_3_1_E_v), .w_in_flit(req_0_3_1_E_f), .w_in_ready(req_0_3_1_E_r),
        .w_out_valid(req_1_3_1_W_v), .w_out_flit(req_1_3_1_W_f), .w_out_ready(req_1_3_1_W_r),
        .u_in_valid(req_1_3_0_D_v), .u_in_flit(req_1_3_0_D_f), .u_in_ready(req_1_3_0_D_r),
        .u_out_valid(req_1_3_1_U_v), .u_out_flit(req_1_3_1_U_f), .u_out_ready(req_1_3_1_U_r),
        .d_in_valid(req_1_3_2_U_v), .d_in_flit(req_1_3_2_U_f), .d_in_ready(req_1_3_2_U_r),
        .d_out_valid(req_1_3_1_D_v), .d_out_flit(req_1_3_1_D_f), .d_out_ready(req_1_3_1_D_r),
        .l_in_valid(e3_req_out_valid), .l_in_flit(e3_req_out_flit), .l_in_ready(e3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(3), .MY_Z(1)) resp_r1_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_2_1_S_v), .n_in_flit(resp_1_2_1_S_f), .n_in_ready(resp_1_2_1_S_r),
        .n_out_valid(resp_1_3_1_N_v), .n_out_flit(resp_1_3_1_N_f), .n_out_ready(resp_1_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_2_3_1_W_v), .e_in_flit(resp_2_3_1_W_f), .e_in_ready(resp_2_3_1_W_r),
        .e_out_valid(resp_1_3_1_E_v), .e_out_flit(resp_1_3_1_E_f), .e_out_ready(resp_1_3_1_E_r),
        .w_in_valid(resp_0_3_1_E_v), .w_in_flit(resp_0_3_1_E_f), .w_in_ready(resp_0_3_1_E_r),
        .w_out_valid(resp_1_3_1_W_v), .w_out_flit(resp_1_3_1_W_f), .w_out_ready(resp_1_3_1_W_r),
        .u_in_valid(resp_1_3_0_D_v), .u_in_flit(resp_1_3_0_D_f), .u_in_ready(resp_1_3_0_D_r),
        .u_out_valid(resp_1_3_1_U_v), .u_out_flit(resp_1_3_1_U_f), .u_out_ready(resp_1_3_1_U_r),
        .d_in_valid(resp_1_3_2_U_v), .d_in_flit(resp_1_3_2_U_f), .d_in_ready(resp_1_3_2_U_r),
        .d_out_valid(resp_1_3_1_D_v), .d_out_flit(resp_1_3_1_D_f), .d_out_ready(resp_1_3_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e3_resp_in_valid), .l_out_flit(e3_resp_in_flit), .l_out_ready(e3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(1), .MY_Y(3), .MY_Z(2)) req_r1_3_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_2_2_S_v), .n_in_flit(req_1_2_2_S_f), .n_in_ready(req_1_2_2_S_r),
        .n_out_valid(req_1_3_2_N_v), .n_out_flit(req_1_3_2_N_f), .n_out_ready(req_1_3_2_N_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_2_3_2_W_v), .e_in_flit(req_2_3_2_W_f), .e_in_ready(req_2_3_2_W_r),
        .e_out_valid(req_1_3_2_E_v), .e_out_flit(req_1_3_2_E_f), .e_out_ready(req_1_3_2_E_r),
        .w_in_valid(req_0_3_2_E_v), .w_in_flit(req_0_3_2_E_f), .w_in_ready(req_0_3_2_E_r),
        .w_out_valid(req_1_3_2_W_v), .w_out_flit(req_1_3_2_W_f), .w_out_ready(req_1_3_2_W_r),
        .u_in_valid(req_1_3_1_D_v), .u_in_flit(req_1_3_1_D_f), .u_in_ready(req_1_3_1_D_r),
        .u_out_valid(req_1_3_2_U_v), .u_out_flit(req_1_3_2_U_f), .u_out_ready(req_1_3_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(e4_req_out_valid), .l_in_flit(e4_req_out_flit), .l_in_ready(e4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(1), .MY_Y(3), .MY_Z(2)) resp_r1_3_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_2_2_S_v), .n_in_flit(resp_1_2_2_S_f), .n_in_ready(resp_1_2_2_S_r),
        .n_out_valid(resp_1_3_2_N_v), .n_out_flit(resp_1_3_2_N_f), .n_out_ready(resp_1_3_2_N_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_2_3_2_W_v), .e_in_flit(resp_2_3_2_W_f), .e_in_ready(resp_2_3_2_W_r),
        .e_out_valid(resp_1_3_2_E_v), .e_out_flit(resp_1_3_2_E_f), .e_out_ready(resp_1_3_2_E_r),
        .w_in_valid(resp_0_3_2_E_v), .w_in_flit(resp_0_3_2_E_f), .w_in_ready(resp_0_3_2_E_r),
        .w_out_valid(resp_1_3_2_W_v), .w_out_flit(resp_1_3_2_W_f), .w_out_ready(resp_1_3_2_W_r),
        .u_in_valid(resp_1_3_1_D_v), .u_in_flit(resp_1_3_1_D_f), .u_in_ready(resp_1_3_1_D_r),
        .u_out_valid(resp_1_3_2_U_v), .u_out_flit(resp_1_3_2_U_f), .u_out_ready(resp_1_3_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e4_resp_in_valid), .l_out_flit(e4_resp_in_flit), .l_out_ready(e4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(0)) req_r2_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_2_1_0_N_v), .s_in_flit(req_2_1_0_N_f), .s_in_ready(req_2_1_0_N_r),
        .s_out_valid(req_2_0_0_S_v), .s_out_flit(req_2_0_0_S_f), .s_out_ready(req_2_0_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_0_0_E_v), .w_in_flit(req_1_0_0_E_f), .w_in_ready(req_1_0_0_E_r),
        .w_out_valid(req_2_0_0_W_v), .w_out_flit(req_2_0_0_W_f), .w_out_ready(req_2_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_2_0_1_U_v), .d_in_flit(req_2_0_1_U_f), .d_in_ready(req_2_0_1_U_r),
        .d_out_valid(req_2_0_0_D_v), .d_out_flit(req_2_0_0_D_f), .d_out_ready(req_2_0_0_D_r),
        .l_in_valid(e5_req_out_valid), .l_in_flit(e5_req_out_flit), .l_in_ready(e5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(0)) resp_r2_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_2_1_0_N_v), .s_in_flit(resp_2_1_0_N_f), .s_in_ready(resp_2_1_0_N_r),
        .s_out_valid(resp_2_0_0_S_v), .s_out_flit(resp_2_0_0_S_f), .s_out_ready(resp_2_0_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_0_0_E_v), .w_in_flit(resp_1_0_0_E_f), .w_in_ready(resp_1_0_0_E_r),
        .w_out_valid(resp_2_0_0_W_v), .w_out_flit(resp_2_0_0_W_f), .w_out_ready(resp_2_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_2_0_1_U_v), .d_in_flit(resp_2_0_1_U_f), .d_in_ready(resp_2_0_1_U_r),
        .d_out_valid(resp_2_0_0_D_v), .d_out_flit(resp_2_0_0_D_f), .d_out_ready(resp_2_0_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e5_resp_in_valid), .l_out_flit(e5_resp_in_flit), .l_out_ready(e5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(1)) req_r2_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_2_1_1_N_v), .s_in_flit(req_2_1_1_N_f), .s_in_ready(req_2_1_1_N_r),
        .s_out_valid(req_2_0_1_S_v), .s_out_flit(req_2_0_1_S_f), .s_out_ready(req_2_0_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_0_1_E_v), .w_in_flit(req_1_0_1_E_f), .w_in_ready(req_1_0_1_E_r),
        .w_out_valid(req_2_0_1_W_v), .w_out_flit(req_2_0_1_W_f), .w_out_ready(req_2_0_1_W_r),
        .u_in_valid(req_2_0_0_D_v), .u_in_flit(req_2_0_0_D_f), .u_in_ready(req_2_0_0_D_r),
        .u_out_valid(req_2_0_1_U_v), .u_out_flit(req_2_0_1_U_f), .u_out_ready(req_2_0_1_U_r),
        .d_in_valid(req_2_0_2_U_v), .d_in_flit(req_2_0_2_U_f), .d_in_ready(req_2_0_2_U_r),
        .d_out_valid(req_2_0_1_D_v), .d_out_flit(req_2_0_1_D_f), .d_out_ready(req_2_0_1_D_r),
        .l_in_valid(e6_req_out_valid), .l_in_flit(e6_req_out_flit), .l_in_ready(e6_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(1)) resp_r2_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_2_1_1_N_v), .s_in_flit(resp_2_1_1_N_f), .s_in_ready(resp_2_1_1_N_r),
        .s_out_valid(resp_2_0_1_S_v), .s_out_flit(resp_2_0_1_S_f), .s_out_ready(resp_2_0_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_0_1_E_v), .w_in_flit(resp_1_0_1_E_f), .w_in_ready(resp_1_0_1_E_r),
        .w_out_valid(resp_2_0_1_W_v), .w_out_flit(resp_2_0_1_W_f), .w_out_ready(resp_2_0_1_W_r),
        .u_in_valid(resp_2_0_0_D_v), .u_in_flit(resp_2_0_0_D_f), .u_in_ready(resp_2_0_0_D_r),
        .u_out_valid(resp_2_0_1_U_v), .u_out_flit(resp_2_0_1_U_f), .u_out_ready(resp_2_0_1_U_r),
        .d_in_valid(resp_2_0_2_U_v), .d_in_flit(resp_2_0_2_U_f), .d_in_ready(resp_2_0_2_U_r),
        .d_out_valid(resp_2_0_1_D_v), .d_out_flit(resp_2_0_1_D_f), .d_out_ready(resp_2_0_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e6_resp_in_valid), .l_out_flit(e6_resp_in_flit), .l_out_ready(e6_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(2)) req_r2_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({80{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_2_1_2_N_v), .s_in_flit(req_2_1_2_N_f), .s_in_ready(req_2_1_2_N_r),
        .s_out_valid(req_2_0_2_S_v), .s_out_flit(req_2_0_2_S_f), .s_out_ready(req_2_0_2_S_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_0_2_E_v), .w_in_flit(req_1_0_2_E_f), .w_in_ready(req_1_0_2_E_r),
        .w_out_valid(req_2_0_2_W_v), .w_out_flit(req_2_0_2_W_f), .w_out_ready(req_2_0_2_W_r),
        .u_in_valid(req_2_0_1_D_v), .u_in_flit(req_2_0_1_D_f), .u_in_ready(req_2_0_1_D_r),
        .u_out_valid(req_2_0_2_U_v), .u_out_flit(req_2_0_2_U_f), .u_out_ready(req_2_0_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(e7_req_out_valid), .l_in_flit(e7_req_out_flit), .l_in_ready(e7_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(2)) resp_r2_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({38{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_2_1_2_N_v), .s_in_flit(resp_2_1_2_N_f), .s_in_ready(resp_2_1_2_N_r),
        .s_out_valid(resp_2_0_2_S_v), .s_out_flit(resp_2_0_2_S_f), .s_out_ready(resp_2_0_2_S_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_0_2_E_v), .w_in_flit(resp_1_0_2_E_f), .w_in_ready(resp_1_0_2_E_r),
        .w_out_valid(resp_2_0_2_W_v), .w_out_flit(resp_2_0_2_W_f), .w_out_ready(resp_2_0_2_W_r),
        .u_in_valid(resp_2_0_1_D_v), .u_in_flit(resp_2_0_1_D_f), .u_in_ready(resp_2_0_1_D_r),
        .u_out_valid(resp_2_0_2_U_v), .u_out_flit(resp_2_0_2_U_f), .u_out_ready(resp_2_0_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e7_resp_in_valid), .l_out_flit(e7_resp_in_flit), .l_out_ready(e7_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(0)) req_r2_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_0_0_S_v), .n_in_flit(req_2_0_0_S_f), .n_in_ready(req_2_0_0_S_r),
        .n_out_valid(req_2_1_0_N_v), .n_out_flit(req_2_1_0_N_f), .n_out_ready(req_2_1_0_N_r),
        .s_in_valid(req_2_2_0_N_v), .s_in_flit(req_2_2_0_N_f), .s_in_ready(req_2_2_0_N_r),
        .s_out_valid(req_2_1_0_S_v), .s_out_flit(req_2_1_0_S_f), .s_out_ready(req_2_1_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_1_0_E_v), .w_in_flit(req_1_1_0_E_f), .w_in_ready(req_1_1_0_E_r),
        .w_out_valid(req_2_1_0_W_v), .w_out_flit(req_2_1_0_W_f), .w_out_ready(req_2_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_2_1_1_U_v), .d_in_flit(req_2_1_1_U_f), .d_in_ready(req_2_1_1_U_r),
        .d_out_valid(req_2_1_0_D_v), .d_out_flit(req_2_1_0_D_f), .d_out_ready(req_2_1_0_D_r),
        .l_in_valid(e8_req_out_valid), .l_in_flit(e8_req_out_flit), .l_in_ready(e8_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(0)) resp_r2_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_0_0_S_v), .n_in_flit(resp_2_0_0_S_f), .n_in_ready(resp_2_0_0_S_r),
        .n_out_valid(resp_2_1_0_N_v), .n_out_flit(resp_2_1_0_N_f), .n_out_ready(resp_2_1_0_N_r),
        .s_in_valid(resp_2_2_0_N_v), .s_in_flit(resp_2_2_0_N_f), .s_in_ready(resp_2_2_0_N_r),
        .s_out_valid(resp_2_1_0_S_v), .s_out_flit(resp_2_1_0_S_f), .s_out_ready(resp_2_1_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_1_0_E_v), .w_in_flit(resp_1_1_0_E_f), .w_in_ready(resp_1_1_0_E_r),
        .w_out_valid(resp_2_1_0_W_v), .w_out_flit(resp_2_1_0_W_f), .w_out_ready(resp_2_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_2_1_1_U_v), .d_in_flit(resp_2_1_1_U_f), .d_in_ready(resp_2_1_1_U_r),
        .d_out_valid(resp_2_1_0_D_v), .d_out_flit(resp_2_1_0_D_f), .d_out_ready(resp_2_1_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e8_resp_in_valid), .l_out_flit(e8_resp_in_flit), .l_out_ready(e8_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(1)) req_r2_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_0_1_S_v), .n_in_flit(req_2_0_1_S_f), .n_in_ready(req_2_0_1_S_r),
        .n_out_valid(req_2_1_1_N_v), .n_out_flit(req_2_1_1_N_f), .n_out_ready(req_2_1_1_N_r),
        .s_in_valid(req_2_2_1_N_v), .s_in_flit(req_2_2_1_N_f), .s_in_ready(req_2_2_1_N_r),
        .s_out_valid(req_2_1_1_S_v), .s_out_flit(req_2_1_1_S_f), .s_out_ready(req_2_1_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_1_1_E_v), .w_in_flit(req_1_1_1_E_f), .w_in_ready(req_1_1_1_E_r),
        .w_out_valid(req_2_1_1_W_v), .w_out_flit(req_2_1_1_W_f), .w_out_ready(req_2_1_1_W_r),
        .u_in_valid(req_2_1_0_D_v), .u_in_flit(req_2_1_0_D_f), .u_in_ready(req_2_1_0_D_r),
        .u_out_valid(req_2_1_1_U_v), .u_out_flit(req_2_1_1_U_f), .u_out_ready(req_2_1_1_U_r),
        .d_in_valid(req_2_1_2_U_v), .d_in_flit(req_2_1_2_U_f), .d_in_ready(req_2_1_2_U_r),
        .d_out_valid(req_2_1_1_D_v), .d_out_flit(req_2_1_1_D_f), .d_out_ready(req_2_1_1_D_r),
        .l_in_valid(e9_req_out_valid), .l_in_flit(e9_req_out_flit), .l_in_ready(e9_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(1)) resp_r2_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_0_1_S_v), .n_in_flit(resp_2_0_1_S_f), .n_in_ready(resp_2_0_1_S_r),
        .n_out_valid(resp_2_1_1_N_v), .n_out_flit(resp_2_1_1_N_f), .n_out_ready(resp_2_1_1_N_r),
        .s_in_valid(resp_2_2_1_N_v), .s_in_flit(resp_2_2_1_N_f), .s_in_ready(resp_2_2_1_N_r),
        .s_out_valid(resp_2_1_1_S_v), .s_out_flit(resp_2_1_1_S_f), .s_out_ready(resp_2_1_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_1_1_E_v), .w_in_flit(resp_1_1_1_E_f), .w_in_ready(resp_1_1_1_E_r),
        .w_out_valid(resp_2_1_1_W_v), .w_out_flit(resp_2_1_1_W_f), .w_out_ready(resp_2_1_1_W_r),
        .u_in_valid(resp_2_1_0_D_v), .u_in_flit(resp_2_1_0_D_f), .u_in_ready(resp_2_1_0_D_r),
        .u_out_valid(resp_2_1_1_U_v), .u_out_flit(resp_2_1_1_U_f), .u_out_ready(resp_2_1_1_U_r),
        .d_in_valid(resp_2_1_2_U_v), .d_in_flit(resp_2_1_2_U_f), .d_in_ready(resp_2_1_2_U_r),
        .d_out_valid(resp_2_1_1_D_v), .d_out_flit(resp_2_1_1_D_f), .d_out_ready(resp_2_1_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e9_resp_in_valid), .l_out_flit(e9_resp_in_flit), .l_out_ready(e9_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(2)) req_r2_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_0_2_S_v), .n_in_flit(req_2_0_2_S_f), .n_in_ready(req_2_0_2_S_r),
        .n_out_valid(req_2_1_2_N_v), .n_out_flit(req_2_1_2_N_f), .n_out_ready(req_2_1_2_N_r),
        .s_in_valid(req_2_2_2_N_v), .s_in_flit(req_2_2_2_N_f), .s_in_ready(req_2_2_2_N_r),
        .s_out_valid(req_2_1_2_S_v), .s_out_flit(req_2_1_2_S_f), .s_out_ready(req_2_1_2_S_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_1_2_E_v), .w_in_flit(req_1_1_2_E_f), .w_in_ready(req_1_1_2_E_r),
        .w_out_valid(req_2_1_2_W_v), .w_out_flit(req_2_1_2_W_f), .w_out_ready(req_2_1_2_W_r),
        .u_in_valid(req_2_1_1_D_v), .u_in_flit(req_2_1_1_D_f), .u_in_ready(req_2_1_1_D_r),
        .u_out_valid(req_2_1_2_U_v), .u_out_flit(req_2_1_2_U_f), .u_out_ready(req_2_1_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(e10_req_out_valid), .l_in_flit(e10_req_out_flit), .l_in_ready(e10_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(2)) resp_r2_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_0_2_S_v), .n_in_flit(resp_2_0_2_S_f), .n_in_ready(resp_2_0_2_S_r),
        .n_out_valid(resp_2_1_2_N_v), .n_out_flit(resp_2_1_2_N_f), .n_out_ready(resp_2_1_2_N_r),
        .s_in_valid(resp_2_2_2_N_v), .s_in_flit(resp_2_2_2_N_f), .s_in_ready(resp_2_2_2_N_r),
        .s_out_valid(resp_2_1_2_S_v), .s_out_flit(resp_2_1_2_S_f), .s_out_ready(resp_2_1_2_S_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_1_2_E_v), .w_in_flit(resp_1_1_2_E_f), .w_in_ready(resp_1_1_2_E_r),
        .w_out_valid(resp_2_1_2_W_v), .w_out_flit(resp_2_1_2_W_f), .w_out_ready(resp_2_1_2_W_r),
        .u_in_valid(resp_2_1_1_D_v), .u_in_flit(resp_2_1_1_D_f), .u_in_ready(resp_2_1_1_D_r),
        .u_out_valid(resp_2_1_2_U_v), .u_out_flit(resp_2_1_2_U_f), .u_out_ready(resp_2_1_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e10_resp_in_valid), .l_out_flit(e10_resp_in_flit), .l_out_ready(e10_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(0)) req_r2_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_1_0_S_v), .n_in_flit(req_2_1_0_S_f), .n_in_ready(req_2_1_0_S_r),
        .n_out_valid(req_2_2_0_N_v), .n_out_flit(req_2_2_0_N_f), .n_out_ready(req_2_2_0_N_r),
        .s_in_valid(req_2_3_0_N_v), .s_in_flit(req_2_3_0_N_f), .s_in_ready(req_2_3_0_N_r),
        .s_out_valid(req_2_2_0_S_v), .s_out_flit(req_2_2_0_S_f), .s_out_ready(req_2_2_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_2_0_E_v), .w_in_flit(req_1_2_0_E_f), .w_in_ready(req_1_2_0_E_r),
        .w_out_valid(req_2_2_0_W_v), .w_out_flit(req_2_2_0_W_f), .w_out_ready(req_2_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_2_2_1_U_v), .d_in_flit(req_2_2_1_U_f), .d_in_ready(req_2_2_1_U_r),
        .d_out_valid(req_2_2_0_D_v), .d_out_flit(req_2_2_0_D_f), .d_out_ready(req_2_2_0_D_r),
        .l_in_valid(e11_req_out_valid), .l_in_flit(e11_req_out_flit), .l_in_ready(e11_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(0)) resp_r2_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_1_0_S_v), .n_in_flit(resp_2_1_0_S_f), .n_in_ready(resp_2_1_0_S_r),
        .n_out_valid(resp_2_2_0_N_v), .n_out_flit(resp_2_2_0_N_f), .n_out_ready(resp_2_2_0_N_r),
        .s_in_valid(resp_2_3_0_N_v), .s_in_flit(resp_2_3_0_N_f), .s_in_ready(resp_2_3_0_N_r),
        .s_out_valid(resp_2_2_0_S_v), .s_out_flit(resp_2_2_0_S_f), .s_out_ready(resp_2_2_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_2_0_E_v), .w_in_flit(resp_1_2_0_E_f), .w_in_ready(resp_1_2_0_E_r),
        .w_out_valid(resp_2_2_0_W_v), .w_out_flit(resp_2_2_0_W_f), .w_out_ready(resp_2_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_2_2_1_U_v), .d_in_flit(resp_2_2_1_U_f), .d_in_ready(resp_2_2_1_U_r),
        .d_out_valid(resp_2_2_0_D_v), .d_out_flit(resp_2_2_0_D_f), .d_out_ready(resp_2_2_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e11_resp_in_valid), .l_out_flit(e11_resp_in_flit), .l_out_ready(e11_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(1)) req_r2_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_1_1_S_v), .n_in_flit(req_2_1_1_S_f), .n_in_ready(req_2_1_1_S_r),
        .n_out_valid(req_2_2_1_N_v), .n_out_flit(req_2_2_1_N_f), .n_out_ready(req_2_2_1_N_r),
        .s_in_valid(req_2_3_1_N_v), .s_in_flit(req_2_3_1_N_f), .s_in_ready(req_2_3_1_N_r),
        .s_out_valid(req_2_2_1_S_v), .s_out_flit(req_2_2_1_S_f), .s_out_ready(req_2_2_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_2_1_E_v), .w_in_flit(req_1_2_1_E_f), .w_in_ready(req_1_2_1_E_r),
        .w_out_valid(req_2_2_1_W_v), .w_out_flit(req_2_2_1_W_f), .w_out_ready(req_2_2_1_W_r),
        .u_in_valid(req_2_2_0_D_v), .u_in_flit(req_2_2_0_D_f), .u_in_ready(req_2_2_0_D_r),
        .u_out_valid(req_2_2_1_U_v), .u_out_flit(req_2_2_1_U_f), .u_out_ready(req_2_2_1_U_r),
        .d_in_valid(req_2_2_2_U_v), .d_in_flit(req_2_2_2_U_f), .d_in_ready(req_2_2_2_U_r),
        .d_out_valid(req_2_2_1_D_v), .d_out_flit(req_2_2_1_D_f), .d_out_ready(req_2_2_1_D_r),
        .l_in_valid(e12_req_out_valid), .l_in_flit(e12_req_out_flit), .l_in_ready(e12_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(1)) resp_r2_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_1_1_S_v), .n_in_flit(resp_2_1_1_S_f), .n_in_ready(resp_2_1_1_S_r),
        .n_out_valid(resp_2_2_1_N_v), .n_out_flit(resp_2_2_1_N_f), .n_out_ready(resp_2_2_1_N_r),
        .s_in_valid(resp_2_3_1_N_v), .s_in_flit(resp_2_3_1_N_f), .s_in_ready(resp_2_3_1_N_r),
        .s_out_valid(resp_2_2_1_S_v), .s_out_flit(resp_2_2_1_S_f), .s_out_ready(resp_2_2_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_2_1_E_v), .w_in_flit(resp_1_2_1_E_f), .w_in_ready(resp_1_2_1_E_r),
        .w_out_valid(resp_2_2_1_W_v), .w_out_flit(resp_2_2_1_W_f), .w_out_ready(resp_2_2_1_W_r),
        .u_in_valid(resp_2_2_0_D_v), .u_in_flit(resp_2_2_0_D_f), .u_in_ready(resp_2_2_0_D_r),
        .u_out_valid(resp_2_2_1_U_v), .u_out_flit(resp_2_2_1_U_f), .u_out_ready(resp_2_2_1_U_r),
        .d_in_valid(resp_2_2_2_U_v), .d_in_flit(resp_2_2_2_U_f), .d_in_ready(resp_2_2_2_U_r),
        .d_out_valid(resp_2_2_1_D_v), .d_out_flit(resp_2_2_1_D_f), .d_out_ready(resp_2_2_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e12_resp_in_valid), .l_out_flit(e12_resp_in_flit), .l_out_ready(e12_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(2)) req_r2_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_1_2_S_v), .n_in_flit(req_2_1_2_S_f), .n_in_ready(req_2_1_2_S_r),
        .n_out_valid(req_2_2_2_N_v), .n_out_flit(req_2_2_2_N_f), .n_out_ready(req_2_2_2_N_r),
        .s_in_valid(req_2_3_2_N_v), .s_in_flit(req_2_3_2_N_f), .s_in_ready(req_2_3_2_N_r),
        .s_out_valid(req_2_2_2_S_v), .s_out_flit(req_2_2_2_S_f), .s_out_ready(req_2_2_2_S_r),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_2_2_E_v), .w_in_flit(req_1_2_2_E_f), .w_in_ready(req_1_2_2_E_r),
        .w_out_valid(req_2_2_2_W_v), .w_out_flit(req_2_2_2_W_f), .w_out_ready(req_2_2_2_W_r),
        .u_in_valid(req_2_2_1_D_v), .u_in_flit(req_2_2_1_D_f), .u_in_ready(req_2_2_1_D_r),
        .u_out_valid(req_2_2_2_U_v), .u_out_flit(req_2_2_2_U_f), .u_out_ready(req_2_2_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(e13_req_out_valid), .l_in_flit(e13_req_out_flit), .l_in_ready(e13_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(2)) resp_r2_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_1_2_S_v), .n_in_flit(resp_2_1_2_S_f), .n_in_ready(resp_2_1_2_S_r),
        .n_out_valid(resp_2_2_2_N_v), .n_out_flit(resp_2_2_2_N_f), .n_out_ready(resp_2_2_2_N_r),
        .s_in_valid(resp_2_3_2_N_v), .s_in_flit(resp_2_3_2_N_f), .s_in_ready(resp_2_3_2_N_r),
        .s_out_valid(resp_2_2_2_S_v), .s_out_flit(resp_2_2_2_S_f), .s_out_ready(resp_2_2_2_S_r),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_2_2_E_v), .w_in_flit(resp_1_2_2_E_f), .w_in_ready(resp_1_2_2_E_r),
        .w_out_valid(resp_2_2_2_W_v), .w_out_flit(resp_2_2_2_W_f), .w_out_ready(resp_2_2_2_W_r),
        .u_in_valid(resp_2_2_1_D_v), .u_in_flit(resp_2_2_1_D_f), .u_in_ready(resp_2_2_1_D_r),
        .u_out_valid(resp_2_2_2_U_v), .u_out_flit(resp_2_2_2_U_f), .u_out_ready(resp_2_2_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e13_resp_in_valid), .l_out_flit(e13_resp_in_flit), .l_out_ready(e13_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(3), .MY_Z(0)) req_r2_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_2_0_S_v), .n_in_flit(req_2_2_0_S_f), .n_in_ready(req_2_2_0_S_r),
        .n_out_valid(req_2_3_0_N_v), .n_out_flit(req_2_3_0_N_f), .n_out_ready(req_2_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_3_0_E_v), .w_in_flit(req_1_3_0_E_f), .w_in_ready(req_1_3_0_E_r),
        .w_out_valid(req_2_3_0_W_v), .w_out_flit(req_2_3_0_W_f), .w_out_ready(req_2_3_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({80{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_2_3_1_U_v), .d_in_flit(req_2_3_1_U_f), .d_in_ready(req_2_3_1_U_r),
        .d_out_valid(req_2_3_0_D_v), .d_out_flit(req_2_3_0_D_f), .d_out_ready(req_2_3_0_D_r),
        .l_in_valid(e14_req_out_valid), .l_in_flit(e14_req_out_flit), .l_in_ready(e14_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(3), .MY_Z(0)) resp_r2_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_2_0_S_v), .n_in_flit(resp_2_2_0_S_f), .n_in_ready(resp_2_2_0_S_r),
        .n_out_valid(resp_2_3_0_N_v), .n_out_flit(resp_2_3_0_N_f), .n_out_ready(resp_2_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_3_0_E_v), .w_in_flit(resp_1_3_0_E_f), .w_in_ready(resp_1_3_0_E_r),
        .w_out_valid(resp_2_3_0_W_v), .w_out_flit(resp_2_3_0_W_f), .w_out_ready(resp_2_3_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({38{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_2_3_1_U_v), .d_in_flit(resp_2_3_1_U_f), .d_in_ready(resp_2_3_1_U_r),
        .d_out_valid(resp_2_3_0_D_v), .d_out_flit(resp_2_3_0_D_f), .d_out_ready(resp_2_3_0_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e14_resp_in_valid), .l_out_flit(e14_resp_in_flit), .l_out_ready(e14_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(3), .MY_Z(1)) req_r2_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_2_1_S_v), .n_in_flit(req_2_2_1_S_f), .n_in_ready(req_2_2_1_S_r),
        .n_out_valid(req_2_3_1_N_v), .n_out_flit(req_2_3_1_N_f), .n_out_ready(req_2_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_3_1_E_v), .w_in_flit(req_1_3_1_E_f), .w_in_ready(req_1_3_1_E_r),
        .w_out_valid(req_2_3_1_W_v), .w_out_flit(req_2_3_1_W_f), .w_out_ready(req_2_3_1_W_r),
        .u_in_valid(req_2_3_0_D_v), .u_in_flit(req_2_3_0_D_f), .u_in_ready(req_2_3_0_D_r),
        .u_out_valid(req_2_3_1_U_v), .u_out_flit(req_2_3_1_U_f), .u_out_ready(req_2_3_1_U_r),
        .d_in_valid(req_2_3_2_U_v), .d_in_flit(req_2_3_2_U_f), .d_in_ready(req_2_3_2_U_r),
        .d_out_valid(req_2_3_1_D_v), .d_out_flit(req_2_3_1_D_f), .d_out_ready(req_2_3_1_D_r),
        .l_in_valid(e15_req_out_valid), .l_in_flit(e15_req_out_flit), .l_in_ready(e15_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(3), .MY_Z(1)) resp_r2_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_2_1_S_v), .n_in_flit(resp_2_2_1_S_f), .n_in_ready(resp_2_2_1_S_r),
        .n_out_valid(resp_2_3_1_N_v), .n_out_flit(resp_2_3_1_N_f), .n_out_ready(resp_2_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_3_1_E_v), .w_in_flit(resp_1_3_1_E_f), .w_in_ready(resp_1_3_1_E_r),
        .w_out_valid(resp_2_3_1_W_v), .w_out_flit(resp_2_3_1_W_f), .w_out_ready(resp_2_3_1_W_r),
        .u_in_valid(resp_2_3_0_D_v), .u_in_flit(resp_2_3_0_D_f), .u_in_ready(resp_2_3_0_D_r),
        .u_out_valid(resp_2_3_1_U_v), .u_out_flit(resp_2_3_1_U_f), .u_out_ready(resp_2_3_1_U_r),
        .d_in_valid(resp_2_3_2_U_v), .d_in_flit(resp_2_3_2_U_f), .d_in_ready(resp_2_3_2_U_r),
        .d_out_valid(resp_2_3_1_D_v), .d_out_flit(resp_2_3_1_D_f), .d_out_ready(resp_2_3_1_D_r),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e15_resp_in_valid), .l_out_flit(e15_resp_in_flit), .l_out_ready(e15_resp_in_ready)
    );

    router #(.FLIT_WIDTH(80), .COORD_BITS(2), .MY_X(2), .MY_Y(3), .MY_Z(2)) req_r2_3_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_2_2_S_v), .n_in_flit(req_2_2_2_S_f), .n_in_ready(req_2_2_2_S_r),
        .n_out_valid(req_2_3_2_N_v), .n_out_flit(req_2_3_2_N_f), .n_out_ready(req_2_3_2_N_r),
        .s_in_valid(1'b0), .s_in_flit({80{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({80{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_1_3_2_E_v), .w_in_flit(req_1_3_2_E_f), .w_in_ready(req_1_3_2_E_r),
        .w_out_valid(req_2_3_2_W_v), .w_out_flit(req_2_3_2_W_f), .w_out_ready(req_2_3_2_W_r),
        .u_in_valid(req_2_3_1_D_v), .u_in_flit(req_2_3_1_D_f), .u_in_ready(req_2_3_1_D_r),
        .u_out_valid(req_2_3_2_U_v), .u_out_flit(req_2_3_2_U_f), .u_out_ready(req_2_3_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({80{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(e16_req_out_valid), .l_in_flit(e16_req_out_flit), .l_in_ready(e16_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(38), .COORD_BITS(2), .MY_X(2), .MY_Y(3), .MY_Z(2)) resp_r2_3_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_2_2_S_v), .n_in_flit(resp_2_2_2_S_f), .n_in_ready(resp_2_2_2_S_r),
        .n_out_valid(resp_2_3_2_N_v), .n_out_flit(resp_2_3_2_N_f), .n_out_ready(resp_2_3_2_N_r),
        .s_in_valid(1'b0), .s_in_flit({38{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({38{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_1_3_2_E_v), .w_in_flit(resp_1_3_2_E_f), .w_in_ready(resp_1_3_2_E_r),
        .w_out_valid(resp_2_3_2_W_v), .w_out_flit(resp_2_3_2_W_f), .w_out_ready(resp_2_3_2_W_r),
        .u_in_valid(resp_2_3_1_D_v), .u_in_flit(resp_2_3_1_D_f), .u_in_ready(resp_2_3_1_D_r),
        .u_out_valid(resp_2_3_2_U_v), .u_out_flit(resp_2_3_2_U_f), .u_out_ready(resp_2_3_2_U_r),
        .d_in_valid(1'b0), .d_in_flit({38{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({38{1'b0}}), .l_in_ready(),
        .l_out_valid(e16_resp_in_valid), .l_out_flit(e16_resp_in_flit), .l_out_ready(e16_resp_in_ready)
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(3), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(3), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(3), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p11_adap (
        .clk(clk), .reset(reset),
        .bus_req(p11_bus_req), .bus_addr(p11_bus_addr), .bus_write_data(p11_bus_write_data),
        .bus_mem_write(p11_bus_mem_write), .bus_mem_size(p11_bus_mem_size), .bus_mem_unsigned(p11_bus_mem_unsigned),
        .bus_grant(p11_bus_grant), .bus_read_data(p11_bus_read_data),
        .req_out_valid(p11_req_out_valid), .req_out_flit(p11_req_out_flit), .req_out_ready(p11_req_out_ready),
        .resp_in_valid(p11_resp_in_valid), .resp_in_flit(p11_resp_in_flit), .resp_in_ready(p11_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P12_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p12_core (
        .clk(clk), .reset(reset),
        .halted(p12_halted), .tohost_value(p12_tohost),
        .bus_req(p12_bus_req), .bus_addr(p12_bus_addr),
        .bus_write_data(p12_bus_write_data), .bus_mem_write(p12_bus_mem_write),
        .bus_mem_size(p12_bus_mem_size), .bus_mem_unsigned(p12_bus_mem_unsigned),
        .bus_grant(p12_bus_grant), .bus_read_data(p12_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p12_adap (
        .clk(clk), .reset(reset),
        .bus_req(p12_bus_req), .bus_addr(p12_bus_addr), .bus_write_data(p12_bus_write_data),
        .bus_mem_write(p12_bus_mem_write), .bus_mem_size(p12_bus_mem_size), .bus_mem_unsigned(p12_bus_mem_unsigned),
        .bus_grant(p12_bus_grant), .bus_read_data(p12_bus_read_data),
        .req_out_valid(p12_req_out_valid), .req_out_flit(p12_req_out_flit), .req_out_ready(p12_req_out_ready),
        .resp_in_valid(p12_resp_in_valid), .resp_in_flit(p12_resp_in_flit), .resp_in_ready(p12_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P13_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p13_core (
        .clk(clk), .reset(reset),
        .halted(p13_halted), .tohost_value(p13_tohost),
        .bus_req(p13_bus_req), .bus_addr(p13_bus_addr),
        .bus_write_data(p13_bus_write_data), .bus_mem_write(p13_bus_mem_write),
        .bus_mem_size(p13_bus_mem_size), .bus_mem_unsigned(p13_bus_mem_unsigned),
        .bus_grant(p13_bus_grant), .bus_read_data(p13_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p13_adap (
        .clk(clk), .reset(reset),
        .bus_req(p13_bus_req), .bus_addr(p13_bus_addr), .bus_write_data(p13_bus_write_data),
        .bus_mem_write(p13_bus_mem_write), .bus_mem_size(p13_bus_mem_size), .bus_mem_unsigned(p13_bus_mem_unsigned),
        .bus_grant(p13_bus_grant), .bus_read_data(p13_bus_read_data),
        .req_out_valid(p13_req_out_valid), .req_out_flit(p13_req_out_flit), .req_out_ready(p13_req_out_ready),
        .resp_in_valid(p13_resp_in_valid), .resp_in_flit(p13_resp_in_flit), .resp_in_ready(p13_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P14_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p14_core (
        .clk(clk), .reset(reset),
        .halted(p14_halted), .tohost_value(p14_tohost),
        .bus_req(p14_bus_req), .bus_addr(p14_bus_addr),
        .bus_write_data(p14_bus_write_data), .bus_mem_write(p14_bus_mem_write),
        .bus_mem_size(p14_bus_mem_size), .bus_mem_unsigned(p14_bus_mem_unsigned),
        .bus_grant(p14_bus_grant), .bus_read_data(p14_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p14_adap (
        .clk(clk), .reset(reset),
        .bus_req(p14_bus_req), .bus_addr(p14_bus_addr), .bus_write_data(p14_bus_write_data),
        .bus_mem_write(p14_bus_mem_write), .bus_mem_size(p14_bus_mem_size), .bus_mem_unsigned(p14_bus_mem_unsigned),
        .bus_grant(p14_bus_grant), .bus_read_data(p14_bus_read_data),
        .req_out_valid(p14_req_out_valid), .req_out_flit(p14_req_out_flit), .req_out_ready(p14_req_out_ready),
        .resp_in_valid(p14_resp_in_valid), .resp_in_flit(p14_resp_in_flit), .resp_in_ready(p14_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P15_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p15_core (
        .clk(clk), .reset(reset),
        .halted(p15_halted), .tohost_value(p15_tohost),
        .bus_req(p15_bus_req), .bus_addr(p15_bus_addr),
        .bus_write_data(p15_bus_write_data), .bus_mem_write(p15_bus_mem_write),
        .bus_mem_size(p15_bus_mem_size), .bus_mem_unsigned(p15_bus_mem_unsigned),
        .bus_grant(p15_bus_grant), .bus_read_data(p15_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p15_adap (
        .clk(clk), .reset(reset),
        .bus_req(p15_bus_req), .bus_addr(p15_bus_addr), .bus_write_data(p15_bus_write_data),
        .bus_mem_write(p15_bus_mem_write), .bus_mem_size(p15_bus_mem_size), .bus_mem_unsigned(p15_bus_mem_unsigned),
        .bus_grant(p15_bus_grant), .bus_read_data(p15_bus_read_data),
        .req_out_valid(p15_req_out_valid), .req_out_flit(p15_req_out_flit), .req_out_ready(p15_req_out_ready),
        .resp_in_valid(p15_resp_in_valid), .resp_in_flit(p15_resp_in_flit), .resp_in_ready(p15_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P16_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p16_core (
        .clk(clk), .reset(reset),
        .halted(p16_halted), .tohost_value(p16_tohost),
        .bus_req(p16_bus_req), .bus_addr(p16_bus_addr),
        .bus_write_data(p16_bus_write_data), .bus_mem_write(p16_bus_mem_write),
        .bus_mem_size(p16_bus_mem_size), .bus_mem_unsigned(p16_bus_mem_unsigned),
        .bus_grant(p16_bus_grant), .bus_read_data(p16_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p16_adap (
        .clk(clk), .reset(reset),
        .bus_req(p16_bus_req), .bus_addr(p16_bus_addr), .bus_write_data(p16_bus_write_data),
        .bus_mem_write(p16_bus_mem_write), .bus_mem_size(p16_bus_mem_size), .bus_mem_unsigned(p16_bus_mem_unsigned),
        .bus_grant(p16_bus_grant), .bus_read_data(p16_bus_read_data),
        .req_out_valid(p16_req_out_valid), .req_out_flit(p16_req_out_flit), .req_out_ready(p16_req_out_ready),
        .resp_in_valid(p16_resp_in_valid), .resp_in_flit(p16_resp_in_flit), .resp_in_ready(p16_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P17_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p17_core (
        .clk(clk), .reset(reset),
        .halted(p17_halted), .tohost_value(p17_tohost),
        .bus_req(p17_bus_req), .bus_addr(p17_bus_addr),
        .bus_write_data(p17_bus_write_data), .bus_mem_write(p17_bus_mem_write),
        .bus_mem_size(p17_bus_mem_size), .bus_mem_unsigned(p17_bus_mem_unsigned),
        .bus_grant(p17_bus_grant), .bus_read_data(p17_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) p17_adap (
        .clk(clk), .reset(reset),
        .bus_req(p17_bus_req), .bus_addr(p17_bus_addr), .bus_write_data(p17_bus_write_data),
        .bus_mem_write(p17_bus_mem_write), .bus_mem_size(p17_bus_mem_size), .bus_mem_unsigned(p17_bus_mem_unsigned),
        .bus_grant(p17_bus_grant), .bus_read_data(p17_bus_read_data),
        .req_out_valid(p17_req_out_valid), .req_out_flit(p17_req_out_flit), .req_out_ready(p17_req_out_ready),
        .resp_in_valid(p17_resp_in_valid), .resp_in_flit(p17_resp_in_flit), .resp_in_ready(p17_resp_in_ready)
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
        .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(1), .MY_Y(3), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(1), .MY_Y(3), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(1), .MY_Y(3), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e11_adap (
        .clk(clk), .reset(reset),
        .bus_req(e11_bus_req), .bus_addr(e11_bus_addr), .bus_write_data(e11_bus_write_data),
        .bus_mem_write(e11_bus_mem_write), .bus_mem_size(e11_bus_mem_size), .bus_mem_unsigned(e11_bus_mem_unsigned),
        .bus_grant(e11_bus_grant), .bus_read_data(e11_bus_read_data),
        .req_out_valid(e11_req_out_valid), .req_out_flit(e11_req_out_flit), .req_out_ready(e11_req_out_ready),
        .resp_in_valid(e11_resp_in_valid), .resp_in_flit(e11_resp_in_flit), .resp_in_ready(e11_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E12_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e12_core (
        .clk(clk), .reset(reset),
        .halted(e12_halted), .tohost_value(e12_tohost),
        .bus_req(e12_bus_req), .bus_addr(e12_bus_addr),
        .bus_write_data(e12_bus_write_data), .bus_mem_write(e12_bus_mem_write),
        .bus_mem_size(e12_bus_mem_size), .bus_mem_unsigned(e12_bus_mem_unsigned),
        .bus_grant(e12_bus_grant), .bus_read_data(e12_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e12_adap (
        .clk(clk), .reset(reset),
        .bus_req(e12_bus_req), .bus_addr(e12_bus_addr), .bus_write_data(e12_bus_write_data),
        .bus_mem_write(e12_bus_mem_write), .bus_mem_size(e12_bus_mem_size), .bus_mem_unsigned(e12_bus_mem_unsigned),
        .bus_grant(e12_bus_grant), .bus_read_data(e12_bus_read_data),
        .req_out_valid(e12_req_out_valid), .req_out_flit(e12_req_out_flit), .req_out_ready(e12_req_out_ready),
        .resp_in_valid(e12_resp_in_valid), .resp_in_flit(e12_resp_in_flit), .resp_in_ready(e12_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E13_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e13_core (
        .clk(clk), .reset(reset),
        .halted(e13_halted), .tohost_value(e13_tohost),
        .bus_req(e13_bus_req), .bus_addr(e13_bus_addr),
        .bus_write_data(e13_bus_write_data), .bus_mem_write(e13_bus_mem_write),
        .bus_mem_size(e13_bus_mem_size), .bus_mem_unsigned(e13_bus_mem_unsigned),
        .bus_grant(e13_bus_grant), .bus_read_data(e13_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e13_adap (
        .clk(clk), .reset(reset),
        .bus_req(e13_bus_req), .bus_addr(e13_bus_addr), .bus_write_data(e13_bus_write_data),
        .bus_mem_write(e13_bus_mem_write), .bus_mem_size(e13_bus_mem_size), .bus_mem_unsigned(e13_bus_mem_unsigned),
        .bus_grant(e13_bus_grant), .bus_read_data(e13_bus_read_data),
        .req_out_valid(e13_req_out_valid), .req_out_flit(e13_req_out_flit), .req_out_ready(e13_req_out_ready),
        .resp_in_valid(e13_resp_in_valid), .resp_in_flit(e13_resp_in_flit), .resp_in_ready(e13_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E14_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e14_core (
        .clk(clk), .reset(reset),
        .halted(e14_halted), .tohost_value(e14_tohost),
        .bus_req(e14_bus_req), .bus_addr(e14_bus_addr),
        .bus_write_data(e14_bus_write_data), .bus_mem_write(e14_bus_mem_write),
        .bus_mem_size(e14_bus_mem_size), .bus_mem_unsigned(e14_bus_mem_unsigned),
        .bus_grant(e14_bus_grant), .bus_read_data(e14_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(3), .MY_Z(0), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e14_adap (
        .clk(clk), .reset(reset),
        .bus_req(e14_bus_req), .bus_addr(e14_bus_addr), .bus_write_data(e14_bus_write_data),
        .bus_mem_write(e14_bus_mem_write), .bus_mem_size(e14_bus_mem_size), .bus_mem_unsigned(e14_bus_mem_unsigned),
        .bus_grant(e14_bus_grant), .bus_read_data(e14_bus_read_data),
        .req_out_valid(e14_req_out_valid), .req_out_flit(e14_req_out_flit), .req_out_ready(e14_req_out_ready),
        .resp_in_valid(e14_resp_in_valid), .resp_in_flit(e14_resp_in_flit), .resp_in_ready(e14_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E15_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e15_core (
        .clk(clk), .reset(reset),
        .halted(e15_halted), .tohost_value(e15_tohost),
        .bus_req(e15_bus_req), .bus_addr(e15_bus_addr),
        .bus_write_data(e15_bus_write_data), .bus_mem_write(e15_bus_mem_write),
        .bus_mem_size(e15_bus_mem_size), .bus_mem_unsigned(e15_bus_mem_unsigned),
        .bus_grant(e15_bus_grant), .bus_read_data(e15_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(3), .MY_Z(1), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e15_adap (
        .clk(clk), .reset(reset),
        .bus_req(e15_bus_req), .bus_addr(e15_bus_addr), .bus_write_data(e15_bus_write_data),
        .bus_mem_write(e15_bus_mem_write), .bus_mem_size(e15_bus_mem_size), .bus_mem_unsigned(e15_bus_mem_unsigned),
        .bus_grant(e15_bus_grant), .bus_read_data(e15_bus_read_data),
        .req_out_valid(e15_req_out_valid), .req_out_flit(e15_req_out_flit), .req_out_ready(e15_req_out_ready),
        .resp_in_valid(e15_resp_in_valid), .resp_in_flit(e15_resp_in_flit), .resp_in_ready(e15_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E16_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e16_core (
        .clk(clk), .reset(reset),
        .halted(e16_halted), .tohost_value(e16_tohost),
        .bus_req(e16_bus_req), .bus_addr(e16_bus_addr),
        .bus_write_data(e16_bus_write_data), .bus_mem_write(e16_bus_mem_write),
        .bus_mem_size(e16_bus_mem_size), .bus_mem_unsigned(e16_bus_mem_unsigned),
        .bus_grant(e16_bus_grant), .bus_read_data(e16_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(3), .MY_Z(2), .MEM_X(1), .MEM_Y(1), .MEM_Z(1),
        .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) e16_adap (
        .clk(clk), .reset(reset),
        .bus_req(e16_bus_req), .bus_addr(e16_bus_addr), .bus_write_data(e16_bus_write_data),
        .bus_mem_write(e16_bus_mem_write), .bus_mem_size(e16_bus_mem_size), .bus_mem_unsigned(e16_bus_mem_unsigned),
        .bus_grant(e16_bus_grant), .bus_read_data(e16_bus_read_data),
        .req_out_valid(e16_req_out_valid), .req_out_flit(e16_req_out_flit), .req_out_ready(e16_req_out_ready),
        .resp_in_valid(e16_resp_in_valid), .resp_in_flit(e16_resp_in_flit), .resp_in_ready(e16_resp_in_ready)
    );

    noc_mem_adapter #(
        .COORD_BITS(2), .MEM_BYTES(SHARED_MEM_BYTES), .REQ_FLIT_WIDTH(80), .RESP_FLIT_WIDTH(38)
    ) mem_adap (
        .clk(clk), .reset(reset),
        .req_in_valid(mem_req_in_valid), .req_in_flit(mem_req_in_flit), .req_in_ready(mem_req_in_ready),
        .resp_out_valid(mem_resp_out_valid), .resp_out_flit(mem_resp_out_flit), .resp_out_ready(mem_resp_out_ready)
    );

    assign all_halted = p0_halted && p1_halted && p2_halted && p3_halted && p4_halted && p5_halted && p6_halted && p7_halted && p8_halted && p9_halted && p10_halted && p11_halted && p12_halted && p13_halted && p14_halted && p15_halted && p16_halted && p17_halted && e0_halted && e1_halted && e2_halted && e3_halted && e4_halted && e5_halted && e6_halted && e7_halted && e8_halted && e9_halted && e10_halted && e11_halted && e12_halted && e13_halted && e14_halted && e15_halted && e16_halted;
endmodule
