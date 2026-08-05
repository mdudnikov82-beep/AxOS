// Network-on-Chip mini-SoC (hardware/rv32i_core) - a real 4D 2x3x6x2 mesh
// of XYZW-routed routers (router.v), each grid position connected to its
// N/E/S/W/Up/Down/Ana/Kata neighbors plus a Local port for whatever core
// or memory endpoint sits there. TWO independent router networks span
// the whole grid - REQUEST (core -> memory, FLIT_WIDTH=92) and RESPONSE
// (memory -> core, FLIT_WIDTH=44) - kept as fully separate router
// instances with zero shared state (see [[project_noc_router]]).
//
// This is a genuinely NEW dimension (W, via router.v's ana/kata ports),
// not a mechanical scale-up like the prior 3x4x3->5x6x6 case - it got a
// fresh design review before any RTL, which found a real bug: router.v's
// direction-index signals were hardcoded to 3 bits, silently safe at
// NDIRS=7 (max index 6) but NOT at NDIRS=9 (DIR_L=8 truncates to 0,
// aliasing Local delivery onto North's arbitration state) - fixed via
// DIRBITS=$clog2(NDIRS) instead of a hardcoded width. 'ana'/'kata' are
// Charles Howard Hinton's real 1880s terms for the two directions along
// a 4th spatial axis - genuine historical terminology, not invented for
// this project.
//
// Memory lives at (0,1,2,0) - exact center on the size-3 Y axis,
// the lower of two symmetric center positions on each of the size-2 X,
// size-6 Z (matching the existing 5x6x6 mesh's own choice), and size-2 W
// axes - not a corner, same 'exact center where one exists, otherwise
// the lower symmetric position' rule this project's prior meshes used.
// 71 of the 72 remaining positions host
// 36 P-cores (cpu_core_pipelined) and 35 E-cores (cpu_core); 0 are spare,
// pass-through-only routers with no local endpoint.
//
// External module interface (parameters and ports) follows the same
// shape as every prior soc_top.v (per-core INSTR_HEX parameter, per-core
// halted/tohost outputs, all_halted) - only the grid topology and
// dimensionality differ.
//
// Grid layout (x,y,z,w), MEM marked - shown as W,Z-layer slices since a
// 4D grid can't be drawn directly:
//
//   W=0, Z=0:
//     p0     p35  
//     p12    e11  
//     p23    e23  
//   W=0, Z=1:
//     p2     e1   
//     p14    e13  
//     p25    e25  
//   W=0, Z=2:
//     p4     e3   
//     MEM    e15  
//     p27    e27  
//   W=0, Z=3:
//     p6     e5   
//     p17    e17  
//     p29    e29  
//   W=0, Z=4:
//     p8     e7   
//     p19    e19  
//     p31    e31  
//   W=0, Z=5:
//     p10    e9   
//     p21    e21  
//     p33    e33  
//   W=1, Z=0:
//     p1     e0   
//     p13    e12  
//     p24    e24  
//   W=1, Z=1:
//     p3     e2   
//     p15    e14  
//     p26    e26  
//   W=1, Z=2:
//     p5     e4   
//     p16    e16  
//     p28    e28  
//   W=1, Z=3:
//     p7     e6   
//     p18    e18  
//     p30    e30  
//   W=1, Z=4:
//     p9     e8   
//     p20    e20  
//     p32    e32  
//   W=1, Z=5:
//     p11    e10  
//     p22    e22  
//     p34    e34  
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
    parameter P18_INSTR_HEX = "",
    parameter P19_INSTR_HEX = "",
    parameter P20_INSTR_HEX = "",
    parameter P21_INSTR_HEX = "",
    parameter P22_INSTR_HEX = "",
    parameter P23_INSTR_HEX = "",
    parameter P24_INSTR_HEX = "",
    parameter P25_INSTR_HEX = "",
    parameter P26_INSTR_HEX = "",
    parameter P27_INSTR_HEX = "",
    parameter P28_INSTR_HEX = "",
    parameter P29_INSTR_HEX = "",
    parameter P30_INSTR_HEX = "",
    parameter P31_INSTR_HEX = "",
    parameter P32_INSTR_HEX = "",
    parameter P33_INSTR_HEX = "",
    parameter P34_INSTR_HEX = "",
    parameter P35_INSTR_HEX = "",
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
    parameter E17_INSTR_HEX = "",
    parameter E18_INSTR_HEX = "",
    parameter E19_INSTR_HEX = "",
    parameter E20_INSTR_HEX = "",
    parameter E21_INSTR_HEX = "",
    parameter E22_INSTR_HEX = "",
    parameter E23_INSTR_HEX = "",
    parameter E24_INSTR_HEX = "",
    parameter E25_INSTR_HEX = "",
    parameter E26_INSTR_HEX = "",
    parameter E27_INSTR_HEX = "",
    parameter E28_INSTR_HEX = "",
    parameter E29_INSTR_HEX = "",
    parameter E30_INSTR_HEX = "",
    parameter E31_INSTR_HEX = "",
    parameter E32_INSTR_HEX = "",
    parameter E33_INSTR_HEX = "",
    parameter E34_INSTR_HEX = "",
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
    output wire        p18_halted,
    output wire [31:0]  p18_tohost,
    output wire        p19_halted,
    output wire [31:0]  p19_tohost,
    output wire        p20_halted,
    output wire [31:0]  p20_tohost,
    output wire        p21_halted,
    output wire [31:0]  p21_tohost,
    output wire        p22_halted,
    output wire [31:0]  p22_tohost,
    output wire        p23_halted,
    output wire [31:0]  p23_tohost,
    output wire        p24_halted,
    output wire [31:0]  p24_tohost,
    output wire        p25_halted,
    output wire [31:0]  p25_tohost,
    output wire        p26_halted,
    output wire [31:0]  p26_tohost,
    output wire        p27_halted,
    output wire [31:0]  p27_tohost,
    output wire        p28_halted,
    output wire [31:0]  p28_tohost,
    output wire        p29_halted,
    output wire [31:0]  p29_tohost,
    output wire        p30_halted,
    output wire [31:0]  p30_tohost,
    output wire        p31_halted,
    output wire [31:0]  p31_tohost,
    output wire        p32_halted,
    output wire [31:0]  p32_tohost,
    output wire        p33_halted,
    output wire [31:0]  p33_tohost,
    output wire        p34_halted,
    output wire [31:0]  p34_tohost,
    output wire        p35_halted,
    output wire [31:0]  p35_tohost,
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
    output wire        e17_halted,
    output wire [31:0]  e17_tohost,
    output wire        e18_halted,
    output wire [31:0]  e18_tohost,
    output wire        e19_halted,
    output wire [31:0]  e19_tohost,
    output wire        e20_halted,
    output wire [31:0]  e20_tohost,
    output wire        e21_halted,
    output wire [31:0]  e21_tohost,
    output wire        e22_halted,
    output wire [31:0]  e22_tohost,
    output wire        e23_halted,
    output wire [31:0]  e23_tohost,
    output wire        e24_halted,
    output wire [31:0]  e24_tohost,
    output wire        e25_halted,
    output wire [31:0]  e25_tohost,
    output wire        e26_halted,
    output wire [31:0]  e26_tohost,
    output wire        e27_halted,
    output wire [31:0]  e27_tohost,
    output wire        e28_halted,
    output wire [31:0]  e28_tohost,
    output wire        e29_halted,
    output wire [31:0]  e29_tohost,
    output wire        e30_halted,
    output wire [31:0]  e30_tohost,
    output wire        e31_halted,
    output wire [31:0]  e31_tohost,
    output wire        e32_halted,
    output wire [31:0]  e32_tohost,
    output wire        e33_halted,
    output wire [31:0]  e33_tohost,
    output wire        e34_halted,
    output wire [31:0]  e34_tohost,
    output wire        all_halted
);

    // ==================== Mesh link wires ====================
    // One {valid,flit,ready} triple per (node, direction) that has a
    // real neighbor, representing THAT node's own outgoing flow in that
    // direction - referenced directly (shared wire names, no extra
    // `assign`s needed) from both this node's *_out_* ports and the
    // neighbor's opposite-direction *_in_* ports. EVERY (node,direction)
    // pair gets its own wire - no 'owner direction' subsetting (see
    // [[project_noc_3d]]'s own history for why that shortcut is a real,
    // previously-live bug, not just a style preference).
    wire req_0_0_0_0_S_v, req_0_0_0_0_S_r; wire [91:0] req_0_0_0_0_S_f;
    wire req_0_0_0_0_E_v, req_0_0_0_0_E_r; wire [91:0] req_0_0_0_0_E_f;
    wire req_0_0_0_0_D_v, req_0_0_0_0_D_r; wire [91:0] req_0_0_0_0_D_f;
    wire req_0_0_0_0_ANA_v, req_0_0_0_0_ANA_r; wire [91:0] req_0_0_0_0_ANA_f;
    wire req_0_0_0_1_S_v, req_0_0_0_1_S_r; wire [91:0] req_0_0_0_1_S_f;
    wire req_0_0_0_1_E_v, req_0_0_0_1_E_r; wire [91:0] req_0_0_0_1_E_f;
    wire req_0_0_0_1_D_v, req_0_0_0_1_D_r; wire [91:0] req_0_0_0_1_D_f;
    wire req_0_0_0_1_KATA_v, req_0_0_0_1_KATA_r; wire [91:0] req_0_0_0_1_KATA_f;
    wire req_0_0_1_0_S_v, req_0_0_1_0_S_r; wire [91:0] req_0_0_1_0_S_f;
    wire req_0_0_1_0_E_v, req_0_0_1_0_E_r; wire [91:0] req_0_0_1_0_E_f;
    wire req_0_0_1_0_U_v, req_0_0_1_0_U_r; wire [91:0] req_0_0_1_0_U_f;
    wire req_0_0_1_0_D_v, req_0_0_1_0_D_r; wire [91:0] req_0_0_1_0_D_f;
    wire req_0_0_1_0_ANA_v, req_0_0_1_0_ANA_r; wire [91:0] req_0_0_1_0_ANA_f;
    wire req_0_0_1_1_S_v, req_0_0_1_1_S_r; wire [91:0] req_0_0_1_1_S_f;
    wire req_0_0_1_1_E_v, req_0_0_1_1_E_r; wire [91:0] req_0_0_1_1_E_f;
    wire req_0_0_1_1_U_v, req_0_0_1_1_U_r; wire [91:0] req_0_0_1_1_U_f;
    wire req_0_0_1_1_D_v, req_0_0_1_1_D_r; wire [91:0] req_0_0_1_1_D_f;
    wire req_0_0_1_1_KATA_v, req_0_0_1_1_KATA_r; wire [91:0] req_0_0_1_1_KATA_f;
    wire req_0_0_2_0_S_v, req_0_0_2_0_S_r; wire [91:0] req_0_0_2_0_S_f;
    wire req_0_0_2_0_E_v, req_0_0_2_0_E_r; wire [91:0] req_0_0_2_0_E_f;
    wire req_0_0_2_0_U_v, req_0_0_2_0_U_r; wire [91:0] req_0_0_2_0_U_f;
    wire req_0_0_2_0_D_v, req_0_0_2_0_D_r; wire [91:0] req_0_0_2_0_D_f;
    wire req_0_0_2_0_ANA_v, req_0_0_2_0_ANA_r; wire [91:0] req_0_0_2_0_ANA_f;
    wire req_0_0_2_1_S_v, req_0_0_2_1_S_r; wire [91:0] req_0_0_2_1_S_f;
    wire req_0_0_2_1_E_v, req_0_0_2_1_E_r; wire [91:0] req_0_0_2_1_E_f;
    wire req_0_0_2_1_U_v, req_0_0_2_1_U_r; wire [91:0] req_0_0_2_1_U_f;
    wire req_0_0_2_1_D_v, req_0_0_2_1_D_r; wire [91:0] req_0_0_2_1_D_f;
    wire req_0_0_2_1_KATA_v, req_0_0_2_1_KATA_r; wire [91:0] req_0_0_2_1_KATA_f;
    wire req_0_0_3_0_S_v, req_0_0_3_0_S_r; wire [91:0] req_0_0_3_0_S_f;
    wire req_0_0_3_0_E_v, req_0_0_3_0_E_r; wire [91:0] req_0_0_3_0_E_f;
    wire req_0_0_3_0_U_v, req_0_0_3_0_U_r; wire [91:0] req_0_0_3_0_U_f;
    wire req_0_0_3_0_D_v, req_0_0_3_0_D_r; wire [91:0] req_0_0_3_0_D_f;
    wire req_0_0_3_0_ANA_v, req_0_0_3_0_ANA_r; wire [91:0] req_0_0_3_0_ANA_f;
    wire req_0_0_3_1_S_v, req_0_0_3_1_S_r; wire [91:0] req_0_0_3_1_S_f;
    wire req_0_0_3_1_E_v, req_0_0_3_1_E_r; wire [91:0] req_0_0_3_1_E_f;
    wire req_0_0_3_1_U_v, req_0_0_3_1_U_r; wire [91:0] req_0_0_3_1_U_f;
    wire req_0_0_3_1_D_v, req_0_0_3_1_D_r; wire [91:0] req_0_0_3_1_D_f;
    wire req_0_0_3_1_KATA_v, req_0_0_3_1_KATA_r; wire [91:0] req_0_0_3_1_KATA_f;
    wire req_0_0_4_0_S_v, req_0_0_4_0_S_r; wire [91:0] req_0_0_4_0_S_f;
    wire req_0_0_4_0_E_v, req_0_0_4_0_E_r; wire [91:0] req_0_0_4_0_E_f;
    wire req_0_0_4_0_U_v, req_0_0_4_0_U_r; wire [91:0] req_0_0_4_0_U_f;
    wire req_0_0_4_0_D_v, req_0_0_4_0_D_r; wire [91:0] req_0_0_4_0_D_f;
    wire req_0_0_4_0_ANA_v, req_0_0_4_0_ANA_r; wire [91:0] req_0_0_4_0_ANA_f;
    wire req_0_0_4_1_S_v, req_0_0_4_1_S_r; wire [91:0] req_0_0_4_1_S_f;
    wire req_0_0_4_1_E_v, req_0_0_4_1_E_r; wire [91:0] req_0_0_4_1_E_f;
    wire req_0_0_4_1_U_v, req_0_0_4_1_U_r; wire [91:0] req_0_0_4_1_U_f;
    wire req_0_0_4_1_D_v, req_0_0_4_1_D_r; wire [91:0] req_0_0_4_1_D_f;
    wire req_0_0_4_1_KATA_v, req_0_0_4_1_KATA_r; wire [91:0] req_0_0_4_1_KATA_f;
    wire req_0_0_5_0_S_v, req_0_0_5_0_S_r; wire [91:0] req_0_0_5_0_S_f;
    wire req_0_0_5_0_E_v, req_0_0_5_0_E_r; wire [91:0] req_0_0_5_0_E_f;
    wire req_0_0_5_0_U_v, req_0_0_5_0_U_r; wire [91:0] req_0_0_5_0_U_f;
    wire req_0_0_5_0_ANA_v, req_0_0_5_0_ANA_r; wire [91:0] req_0_0_5_0_ANA_f;
    wire req_0_0_5_1_S_v, req_0_0_5_1_S_r; wire [91:0] req_0_0_5_1_S_f;
    wire req_0_0_5_1_E_v, req_0_0_5_1_E_r; wire [91:0] req_0_0_5_1_E_f;
    wire req_0_0_5_1_U_v, req_0_0_5_1_U_r; wire [91:0] req_0_0_5_1_U_f;
    wire req_0_0_5_1_KATA_v, req_0_0_5_1_KATA_r; wire [91:0] req_0_0_5_1_KATA_f;
    wire req_0_1_0_0_N_v, req_0_1_0_0_N_r; wire [91:0] req_0_1_0_0_N_f;
    wire req_0_1_0_0_S_v, req_0_1_0_0_S_r; wire [91:0] req_0_1_0_0_S_f;
    wire req_0_1_0_0_E_v, req_0_1_0_0_E_r; wire [91:0] req_0_1_0_0_E_f;
    wire req_0_1_0_0_D_v, req_0_1_0_0_D_r; wire [91:0] req_0_1_0_0_D_f;
    wire req_0_1_0_0_ANA_v, req_0_1_0_0_ANA_r; wire [91:0] req_0_1_0_0_ANA_f;
    wire req_0_1_0_1_N_v, req_0_1_0_1_N_r; wire [91:0] req_0_1_0_1_N_f;
    wire req_0_1_0_1_S_v, req_0_1_0_1_S_r; wire [91:0] req_0_1_0_1_S_f;
    wire req_0_1_0_1_E_v, req_0_1_0_1_E_r; wire [91:0] req_0_1_0_1_E_f;
    wire req_0_1_0_1_D_v, req_0_1_0_1_D_r; wire [91:0] req_0_1_0_1_D_f;
    wire req_0_1_0_1_KATA_v, req_0_1_0_1_KATA_r; wire [91:0] req_0_1_0_1_KATA_f;
    wire req_0_1_1_0_N_v, req_0_1_1_0_N_r; wire [91:0] req_0_1_1_0_N_f;
    wire req_0_1_1_0_S_v, req_0_1_1_0_S_r; wire [91:0] req_0_1_1_0_S_f;
    wire req_0_1_1_0_E_v, req_0_1_1_0_E_r; wire [91:0] req_0_1_1_0_E_f;
    wire req_0_1_1_0_U_v, req_0_1_1_0_U_r; wire [91:0] req_0_1_1_0_U_f;
    wire req_0_1_1_0_D_v, req_0_1_1_0_D_r; wire [91:0] req_0_1_1_0_D_f;
    wire req_0_1_1_0_ANA_v, req_0_1_1_0_ANA_r; wire [91:0] req_0_1_1_0_ANA_f;
    wire req_0_1_1_1_N_v, req_0_1_1_1_N_r; wire [91:0] req_0_1_1_1_N_f;
    wire req_0_1_1_1_S_v, req_0_1_1_1_S_r; wire [91:0] req_0_1_1_1_S_f;
    wire req_0_1_1_1_E_v, req_0_1_1_1_E_r; wire [91:0] req_0_1_1_1_E_f;
    wire req_0_1_1_1_U_v, req_0_1_1_1_U_r; wire [91:0] req_0_1_1_1_U_f;
    wire req_0_1_1_1_D_v, req_0_1_1_1_D_r; wire [91:0] req_0_1_1_1_D_f;
    wire req_0_1_1_1_KATA_v, req_0_1_1_1_KATA_r; wire [91:0] req_0_1_1_1_KATA_f;
    wire req_0_1_2_0_N_v, req_0_1_2_0_N_r; wire [91:0] req_0_1_2_0_N_f;
    wire req_0_1_2_0_S_v, req_0_1_2_0_S_r; wire [91:0] req_0_1_2_0_S_f;
    wire req_0_1_2_0_E_v, req_0_1_2_0_E_r; wire [91:0] req_0_1_2_0_E_f;
    wire req_0_1_2_0_U_v, req_0_1_2_0_U_r; wire [91:0] req_0_1_2_0_U_f;
    wire req_0_1_2_0_D_v, req_0_1_2_0_D_r; wire [91:0] req_0_1_2_0_D_f;
    wire req_0_1_2_0_ANA_v, req_0_1_2_0_ANA_r; wire [91:0] req_0_1_2_0_ANA_f;
    wire req_0_1_2_1_N_v, req_0_1_2_1_N_r; wire [91:0] req_0_1_2_1_N_f;
    wire req_0_1_2_1_S_v, req_0_1_2_1_S_r; wire [91:0] req_0_1_2_1_S_f;
    wire req_0_1_2_1_E_v, req_0_1_2_1_E_r; wire [91:0] req_0_1_2_1_E_f;
    wire req_0_1_2_1_U_v, req_0_1_2_1_U_r; wire [91:0] req_0_1_2_1_U_f;
    wire req_0_1_2_1_D_v, req_0_1_2_1_D_r; wire [91:0] req_0_1_2_1_D_f;
    wire req_0_1_2_1_KATA_v, req_0_1_2_1_KATA_r; wire [91:0] req_0_1_2_1_KATA_f;
    wire req_0_1_3_0_N_v, req_0_1_3_0_N_r; wire [91:0] req_0_1_3_0_N_f;
    wire req_0_1_3_0_S_v, req_0_1_3_0_S_r; wire [91:0] req_0_1_3_0_S_f;
    wire req_0_1_3_0_E_v, req_0_1_3_0_E_r; wire [91:0] req_0_1_3_0_E_f;
    wire req_0_1_3_0_U_v, req_0_1_3_0_U_r; wire [91:0] req_0_1_3_0_U_f;
    wire req_0_1_3_0_D_v, req_0_1_3_0_D_r; wire [91:0] req_0_1_3_0_D_f;
    wire req_0_1_3_0_ANA_v, req_0_1_3_0_ANA_r; wire [91:0] req_0_1_3_0_ANA_f;
    wire req_0_1_3_1_N_v, req_0_1_3_1_N_r; wire [91:0] req_0_1_3_1_N_f;
    wire req_0_1_3_1_S_v, req_0_1_3_1_S_r; wire [91:0] req_0_1_3_1_S_f;
    wire req_0_1_3_1_E_v, req_0_1_3_1_E_r; wire [91:0] req_0_1_3_1_E_f;
    wire req_0_1_3_1_U_v, req_0_1_3_1_U_r; wire [91:0] req_0_1_3_1_U_f;
    wire req_0_1_3_1_D_v, req_0_1_3_1_D_r; wire [91:0] req_0_1_3_1_D_f;
    wire req_0_1_3_1_KATA_v, req_0_1_3_1_KATA_r; wire [91:0] req_0_1_3_1_KATA_f;
    wire req_0_1_4_0_N_v, req_0_1_4_0_N_r; wire [91:0] req_0_1_4_0_N_f;
    wire req_0_1_4_0_S_v, req_0_1_4_0_S_r; wire [91:0] req_0_1_4_0_S_f;
    wire req_0_1_4_0_E_v, req_0_1_4_0_E_r; wire [91:0] req_0_1_4_0_E_f;
    wire req_0_1_4_0_U_v, req_0_1_4_0_U_r; wire [91:0] req_0_1_4_0_U_f;
    wire req_0_1_4_0_D_v, req_0_1_4_0_D_r; wire [91:0] req_0_1_4_0_D_f;
    wire req_0_1_4_0_ANA_v, req_0_1_4_0_ANA_r; wire [91:0] req_0_1_4_0_ANA_f;
    wire req_0_1_4_1_N_v, req_0_1_4_1_N_r; wire [91:0] req_0_1_4_1_N_f;
    wire req_0_1_4_1_S_v, req_0_1_4_1_S_r; wire [91:0] req_0_1_4_1_S_f;
    wire req_0_1_4_1_E_v, req_0_1_4_1_E_r; wire [91:0] req_0_1_4_1_E_f;
    wire req_0_1_4_1_U_v, req_0_1_4_1_U_r; wire [91:0] req_0_1_4_1_U_f;
    wire req_0_1_4_1_D_v, req_0_1_4_1_D_r; wire [91:0] req_0_1_4_1_D_f;
    wire req_0_1_4_1_KATA_v, req_0_1_4_1_KATA_r; wire [91:0] req_0_1_4_1_KATA_f;
    wire req_0_1_5_0_N_v, req_0_1_5_0_N_r; wire [91:0] req_0_1_5_0_N_f;
    wire req_0_1_5_0_S_v, req_0_1_5_0_S_r; wire [91:0] req_0_1_5_0_S_f;
    wire req_0_1_5_0_E_v, req_0_1_5_0_E_r; wire [91:0] req_0_1_5_0_E_f;
    wire req_0_1_5_0_U_v, req_0_1_5_0_U_r; wire [91:0] req_0_1_5_0_U_f;
    wire req_0_1_5_0_ANA_v, req_0_1_5_0_ANA_r; wire [91:0] req_0_1_5_0_ANA_f;
    wire req_0_1_5_1_N_v, req_0_1_5_1_N_r; wire [91:0] req_0_1_5_1_N_f;
    wire req_0_1_5_1_S_v, req_0_1_5_1_S_r; wire [91:0] req_0_1_5_1_S_f;
    wire req_0_1_5_1_E_v, req_0_1_5_1_E_r; wire [91:0] req_0_1_5_1_E_f;
    wire req_0_1_5_1_U_v, req_0_1_5_1_U_r; wire [91:0] req_0_1_5_1_U_f;
    wire req_0_1_5_1_KATA_v, req_0_1_5_1_KATA_r; wire [91:0] req_0_1_5_1_KATA_f;
    wire req_0_2_0_0_N_v, req_0_2_0_0_N_r; wire [91:0] req_0_2_0_0_N_f;
    wire req_0_2_0_0_E_v, req_0_2_0_0_E_r; wire [91:0] req_0_2_0_0_E_f;
    wire req_0_2_0_0_D_v, req_0_2_0_0_D_r; wire [91:0] req_0_2_0_0_D_f;
    wire req_0_2_0_0_ANA_v, req_0_2_0_0_ANA_r; wire [91:0] req_0_2_0_0_ANA_f;
    wire req_0_2_0_1_N_v, req_0_2_0_1_N_r; wire [91:0] req_0_2_0_1_N_f;
    wire req_0_2_0_1_E_v, req_0_2_0_1_E_r; wire [91:0] req_0_2_0_1_E_f;
    wire req_0_2_0_1_D_v, req_0_2_0_1_D_r; wire [91:0] req_0_2_0_1_D_f;
    wire req_0_2_0_1_KATA_v, req_0_2_0_1_KATA_r; wire [91:0] req_0_2_0_1_KATA_f;
    wire req_0_2_1_0_N_v, req_0_2_1_0_N_r; wire [91:0] req_0_2_1_0_N_f;
    wire req_0_2_1_0_E_v, req_0_2_1_0_E_r; wire [91:0] req_0_2_1_0_E_f;
    wire req_0_2_1_0_U_v, req_0_2_1_0_U_r; wire [91:0] req_0_2_1_0_U_f;
    wire req_0_2_1_0_D_v, req_0_2_1_0_D_r; wire [91:0] req_0_2_1_0_D_f;
    wire req_0_2_1_0_ANA_v, req_0_2_1_0_ANA_r; wire [91:0] req_0_2_1_0_ANA_f;
    wire req_0_2_1_1_N_v, req_0_2_1_1_N_r; wire [91:0] req_0_2_1_1_N_f;
    wire req_0_2_1_1_E_v, req_0_2_1_1_E_r; wire [91:0] req_0_2_1_1_E_f;
    wire req_0_2_1_1_U_v, req_0_2_1_1_U_r; wire [91:0] req_0_2_1_1_U_f;
    wire req_0_2_1_1_D_v, req_0_2_1_1_D_r; wire [91:0] req_0_2_1_1_D_f;
    wire req_0_2_1_1_KATA_v, req_0_2_1_1_KATA_r; wire [91:0] req_0_2_1_1_KATA_f;
    wire req_0_2_2_0_N_v, req_0_2_2_0_N_r; wire [91:0] req_0_2_2_0_N_f;
    wire req_0_2_2_0_E_v, req_0_2_2_0_E_r; wire [91:0] req_0_2_2_0_E_f;
    wire req_0_2_2_0_U_v, req_0_2_2_0_U_r; wire [91:0] req_0_2_2_0_U_f;
    wire req_0_2_2_0_D_v, req_0_2_2_0_D_r; wire [91:0] req_0_2_2_0_D_f;
    wire req_0_2_2_0_ANA_v, req_0_2_2_0_ANA_r; wire [91:0] req_0_2_2_0_ANA_f;
    wire req_0_2_2_1_N_v, req_0_2_2_1_N_r; wire [91:0] req_0_2_2_1_N_f;
    wire req_0_2_2_1_E_v, req_0_2_2_1_E_r; wire [91:0] req_0_2_2_1_E_f;
    wire req_0_2_2_1_U_v, req_0_2_2_1_U_r; wire [91:0] req_0_2_2_1_U_f;
    wire req_0_2_2_1_D_v, req_0_2_2_1_D_r; wire [91:0] req_0_2_2_1_D_f;
    wire req_0_2_2_1_KATA_v, req_0_2_2_1_KATA_r; wire [91:0] req_0_2_2_1_KATA_f;
    wire req_0_2_3_0_N_v, req_0_2_3_0_N_r; wire [91:0] req_0_2_3_0_N_f;
    wire req_0_2_3_0_E_v, req_0_2_3_0_E_r; wire [91:0] req_0_2_3_0_E_f;
    wire req_0_2_3_0_U_v, req_0_2_3_0_U_r; wire [91:0] req_0_2_3_0_U_f;
    wire req_0_2_3_0_D_v, req_0_2_3_0_D_r; wire [91:0] req_0_2_3_0_D_f;
    wire req_0_2_3_0_ANA_v, req_0_2_3_0_ANA_r; wire [91:0] req_0_2_3_0_ANA_f;
    wire req_0_2_3_1_N_v, req_0_2_3_1_N_r; wire [91:0] req_0_2_3_1_N_f;
    wire req_0_2_3_1_E_v, req_0_2_3_1_E_r; wire [91:0] req_0_2_3_1_E_f;
    wire req_0_2_3_1_U_v, req_0_2_3_1_U_r; wire [91:0] req_0_2_3_1_U_f;
    wire req_0_2_3_1_D_v, req_0_2_3_1_D_r; wire [91:0] req_0_2_3_1_D_f;
    wire req_0_2_3_1_KATA_v, req_0_2_3_1_KATA_r; wire [91:0] req_0_2_3_1_KATA_f;
    wire req_0_2_4_0_N_v, req_0_2_4_0_N_r; wire [91:0] req_0_2_4_0_N_f;
    wire req_0_2_4_0_E_v, req_0_2_4_0_E_r; wire [91:0] req_0_2_4_0_E_f;
    wire req_0_2_4_0_U_v, req_0_2_4_0_U_r; wire [91:0] req_0_2_4_0_U_f;
    wire req_0_2_4_0_D_v, req_0_2_4_0_D_r; wire [91:0] req_0_2_4_0_D_f;
    wire req_0_2_4_0_ANA_v, req_0_2_4_0_ANA_r; wire [91:0] req_0_2_4_0_ANA_f;
    wire req_0_2_4_1_N_v, req_0_2_4_1_N_r; wire [91:0] req_0_2_4_1_N_f;
    wire req_0_2_4_1_E_v, req_0_2_4_1_E_r; wire [91:0] req_0_2_4_1_E_f;
    wire req_0_2_4_1_U_v, req_0_2_4_1_U_r; wire [91:0] req_0_2_4_1_U_f;
    wire req_0_2_4_1_D_v, req_0_2_4_1_D_r; wire [91:0] req_0_2_4_1_D_f;
    wire req_0_2_4_1_KATA_v, req_0_2_4_1_KATA_r; wire [91:0] req_0_2_4_1_KATA_f;
    wire req_0_2_5_0_N_v, req_0_2_5_0_N_r; wire [91:0] req_0_2_5_0_N_f;
    wire req_0_2_5_0_E_v, req_0_2_5_0_E_r; wire [91:0] req_0_2_5_0_E_f;
    wire req_0_2_5_0_U_v, req_0_2_5_0_U_r; wire [91:0] req_0_2_5_0_U_f;
    wire req_0_2_5_0_ANA_v, req_0_2_5_0_ANA_r; wire [91:0] req_0_2_5_0_ANA_f;
    wire req_0_2_5_1_N_v, req_0_2_5_1_N_r; wire [91:0] req_0_2_5_1_N_f;
    wire req_0_2_5_1_E_v, req_0_2_5_1_E_r; wire [91:0] req_0_2_5_1_E_f;
    wire req_0_2_5_1_U_v, req_0_2_5_1_U_r; wire [91:0] req_0_2_5_1_U_f;
    wire req_0_2_5_1_KATA_v, req_0_2_5_1_KATA_r; wire [91:0] req_0_2_5_1_KATA_f;
    wire req_1_0_0_0_S_v, req_1_0_0_0_S_r; wire [91:0] req_1_0_0_0_S_f;
    wire req_1_0_0_0_W_v, req_1_0_0_0_W_r; wire [91:0] req_1_0_0_0_W_f;
    wire req_1_0_0_0_D_v, req_1_0_0_0_D_r; wire [91:0] req_1_0_0_0_D_f;
    wire req_1_0_0_0_ANA_v, req_1_0_0_0_ANA_r; wire [91:0] req_1_0_0_0_ANA_f;
    wire req_1_0_0_1_S_v, req_1_0_0_1_S_r; wire [91:0] req_1_0_0_1_S_f;
    wire req_1_0_0_1_W_v, req_1_0_0_1_W_r; wire [91:0] req_1_0_0_1_W_f;
    wire req_1_0_0_1_D_v, req_1_0_0_1_D_r; wire [91:0] req_1_0_0_1_D_f;
    wire req_1_0_0_1_KATA_v, req_1_0_0_1_KATA_r; wire [91:0] req_1_0_0_1_KATA_f;
    wire req_1_0_1_0_S_v, req_1_0_1_0_S_r; wire [91:0] req_1_0_1_0_S_f;
    wire req_1_0_1_0_W_v, req_1_0_1_0_W_r; wire [91:0] req_1_0_1_0_W_f;
    wire req_1_0_1_0_U_v, req_1_0_1_0_U_r; wire [91:0] req_1_0_1_0_U_f;
    wire req_1_0_1_0_D_v, req_1_0_1_0_D_r; wire [91:0] req_1_0_1_0_D_f;
    wire req_1_0_1_0_ANA_v, req_1_0_1_0_ANA_r; wire [91:0] req_1_0_1_0_ANA_f;
    wire req_1_0_1_1_S_v, req_1_0_1_1_S_r; wire [91:0] req_1_0_1_1_S_f;
    wire req_1_0_1_1_W_v, req_1_0_1_1_W_r; wire [91:0] req_1_0_1_1_W_f;
    wire req_1_0_1_1_U_v, req_1_0_1_1_U_r; wire [91:0] req_1_0_1_1_U_f;
    wire req_1_0_1_1_D_v, req_1_0_1_1_D_r; wire [91:0] req_1_0_1_1_D_f;
    wire req_1_0_1_1_KATA_v, req_1_0_1_1_KATA_r; wire [91:0] req_1_0_1_1_KATA_f;
    wire req_1_0_2_0_S_v, req_1_0_2_0_S_r; wire [91:0] req_1_0_2_0_S_f;
    wire req_1_0_2_0_W_v, req_1_0_2_0_W_r; wire [91:0] req_1_0_2_0_W_f;
    wire req_1_0_2_0_U_v, req_1_0_2_0_U_r; wire [91:0] req_1_0_2_0_U_f;
    wire req_1_0_2_0_D_v, req_1_0_2_0_D_r; wire [91:0] req_1_0_2_0_D_f;
    wire req_1_0_2_0_ANA_v, req_1_0_2_0_ANA_r; wire [91:0] req_1_0_2_0_ANA_f;
    wire req_1_0_2_1_S_v, req_1_0_2_1_S_r; wire [91:0] req_1_0_2_1_S_f;
    wire req_1_0_2_1_W_v, req_1_0_2_1_W_r; wire [91:0] req_1_0_2_1_W_f;
    wire req_1_0_2_1_U_v, req_1_0_2_1_U_r; wire [91:0] req_1_0_2_1_U_f;
    wire req_1_0_2_1_D_v, req_1_0_2_1_D_r; wire [91:0] req_1_0_2_1_D_f;
    wire req_1_0_2_1_KATA_v, req_1_0_2_1_KATA_r; wire [91:0] req_1_0_2_1_KATA_f;
    wire req_1_0_3_0_S_v, req_1_0_3_0_S_r; wire [91:0] req_1_0_3_0_S_f;
    wire req_1_0_3_0_W_v, req_1_0_3_0_W_r; wire [91:0] req_1_0_3_0_W_f;
    wire req_1_0_3_0_U_v, req_1_0_3_0_U_r; wire [91:0] req_1_0_3_0_U_f;
    wire req_1_0_3_0_D_v, req_1_0_3_0_D_r; wire [91:0] req_1_0_3_0_D_f;
    wire req_1_0_3_0_ANA_v, req_1_0_3_0_ANA_r; wire [91:0] req_1_0_3_0_ANA_f;
    wire req_1_0_3_1_S_v, req_1_0_3_1_S_r; wire [91:0] req_1_0_3_1_S_f;
    wire req_1_0_3_1_W_v, req_1_0_3_1_W_r; wire [91:0] req_1_0_3_1_W_f;
    wire req_1_0_3_1_U_v, req_1_0_3_1_U_r; wire [91:0] req_1_0_3_1_U_f;
    wire req_1_0_3_1_D_v, req_1_0_3_1_D_r; wire [91:0] req_1_0_3_1_D_f;
    wire req_1_0_3_1_KATA_v, req_1_0_3_1_KATA_r; wire [91:0] req_1_0_3_1_KATA_f;
    wire req_1_0_4_0_S_v, req_1_0_4_0_S_r; wire [91:0] req_1_0_4_0_S_f;
    wire req_1_0_4_0_W_v, req_1_0_4_0_W_r; wire [91:0] req_1_0_4_0_W_f;
    wire req_1_0_4_0_U_v, req_1_0_4_0_U_r; wire [91:0] req_1_0_4_0_U_f;
    wire req_1_0_4_0_D_v, req_1_0_4_0_D_r; wire [91:0] req_1_0_4_0_D_f;
    wire req_1_0_4_0_ANA_v, req_1_0_4_0_ANA_r; wire [91:0] req_1_0_4_0_ANA_f;
    wire req_1_0_4_1_S_v, req_1_0_4_1_S_r; wire [91:0] req_1_0_4_1_S_f;
    wire req_1_0_4_1_W_v, req_1_0_4_1_W_r; wire [91:0] req_1_0_4_1_W_f;
    wire req_1_0_4_1_U_v, req_1_0_4_1_U_r; wire [91:0] req_1_0_4_1_U_f;
    wire req_1_0_4_1_D_v, req_1_0_4_1_D_r; wire [91:0] req_1_0_4_1_D_f;
    wire req_1_0_4_1_KATA_v, req_1_0_4_1_KATA_r; wire [91:0] req_1_0_4_1_KATA_f;
    wire req_1_0_5_0_S_v, req_1_0_5_0_S_r; wire [91:0] req_1_0_5_0_S_f;
    wire req_1_0_5_0_W_v, req_1_0_5_0_W_r; wire [91:0] req_1_0_5_0_W_f;
    wire req_1_0_5_0_U_v, req_1_0_5_0_U_r; wire [91:0] req_1_0_5_0_U_f;
    wire req_1_0_5_0_ANA_v, req_1_0_5_0_ANA_r; wire [91:0] req_1_0_5_0_ANA_f;
    wire req_1_0_5_1_S_v, req_1_0_5_1_S_r; wire [91:0] req_1_0_5_1_S_f;
    wire req_1_0_5_1_W_v, req_1_0_5_1_W_r; wire [91:0] req_1_0_5_1_W_f;
    wire req_1_0_5_1_U_v, req_1_0_5_1_U_r; wire [91:0] req_1_0_5_1_U_f;
    wire req_1_0_5_1_KATA_v, req_1_0_5_1_KATA_r; wire [91:0] req_1_0_5_1_KATA_f;
    wire req_1_1_0_0_N_v, req_1_1_0_0_N_r; wire [91:0] req_1_1_0_0_N_f;
    wire req_1_1_0_0_S_v, req_1_1_0_0_S_r; wire [91:0] req_1_1_0_0_S_f;
    wire req_1_1_0_0_W_v, req_1_1_0_0_W_r; wire [91:0] req_1_1_0_0_W_f;
    wire req_1_1_0_0_D_v, req_1_1_0_0_D_r; wire [91:0] req_1_1_0_0_D_f;
    wire req_1_1_0_0_ANA_v, req_1_1_0_0_ANA_r; wire [91:0] req_1_1_0_0_ANA_f;
    wire req_1_1_0_1_N_v, req_1_1_0_1_N_r; wire [91:0] req_1_1_0_1_N_f;
    wire req_1_1_0_1_S_v, req_1_1_0_1_S_r; wire [91:0] req_1_1_0_1_S_f;
    wire req_1_1_0_1_W_v, req_1_1_0_1_W_r; wire [91:0] req_1_1_0_1_W_f;
    wire req_1_1_0_1_D_v, req_1_1_0_1_D_r; wire [91:0] req_1_1_0_1_D_f;
    wire req_1_1_0_1_KATA_v, req_1_1_0_1_KATA_r; wire [91:0] req_1_1_0_1_KATA_f;
    wire req_1_1_1_0_N_v, req_1_1_1_0_N_r; wire [91:0] req_1_1_1_0_N_f;
    wire req_1_1_1_0_S_v, req_1_1_1_0_S_r; wire [91:0] req_1_1_1_0_S_f;
    wire req_1_1_1_0_W_v, req_1_1_1_0_W_r; wire [91:0] req_1_1_1_0_W_f;
    wire req_1_1_1_0_U_v, req_1_1_1_0_U_r; wire [91:0] req_1_1_1_0_U_f;
    wire req_1_1_1_0_D_v, req_1_1_1_0_D_r; wire [91:0] req_1_1_1_0_D_f;
    wire req_1_1_1_0_ANA_v, req_1_1_1_0_ANA_r; wire [91:0] req_1_1_1_0_ANA_f;
    wire req_1_1_1_1_N_v, req_1_1_1_1_N_r; wire [91:0] req_1_1_1_1_N_f;
    wire req_1_1_1_1_S_v, req_1_1_1_1_S_r; wire [91:0] req_1_1_1_1_S_f;
    wire req_1_1_1_1_W_v, req_1_1_1_1_W_r; wire [91:0] req_1_1_1_1_W_f;
    wire req_1_1_1_1_U_v, req_1_1_1_1_U_r; wire [91:0] req_1_1_1_1_U_f;
    wire req_1_1_1_1_D_v, req_1_1_1_1_D_r; wire [91:0] req_1_1_1_1_D_f;
    wire req_1_1_1_1_KATA_v, req_1_1_1_1_KATA_r; wire [91:0] req_1_1_1_1_KATA_f;
    wire req_1_1_2_0_N_v, req_1_1_2_0_N_r; wire [91:0] req_1_1_2_0_N_f;
    wire req_1_1_2_0_S_v, req_1_1_2_0_S_r; wire [91:0] req_1_1_2_0_S_f;
    wire req_1_1_2_0_W_v, req_1_1_2_0_W_r; wire [91:0] req_1_1_2_0_W_f;
    wire req_1_1_2_0_U_v, req_1_1_2_0_U_r; wire [91:0] req_1_1_2_0_U_f;
    wire req_1_1_2_0_D_v, req_1_1_2_0_D_r; wire [91:0] req_1_1_2_0_D_f;
    wire req_1_1_2_0_ANA_v, req_1_1_2_0_ANA_r; wire [91:0] req_1_1_2_0_ANA_f;
    wire req_1_1_2_1_N_v, req_1_1_2_1_N_r; wire [91:0] req_1_1_2_1_N_f;
    wire req_1_1_2_1_S_v, req_1_1_2_1_S_r; wire [91:0] req_1_1_2_1_S_f;
    wire req_1_1_2_1_W_v, req_1_1_2_1_W_r; wire [91:0] req_1_1_2_1_W_f;
    wire req_1_1_2_1_U_v, req_1_1_2_1_U_r; wire [91:0] req_1_1_2_1_U_f;
    wire req_1_1_2_1_D_v, req_1_1_2_1_D_r; wire [91:0] req_1_1_2_1_D_f;
    wire req_1_1_2_1_KATA_v, req_1_1_2_1_KATA_r; wire [91:0] req_1_1_2_1_KATA_f;
    wire req_1_1_3_0_N_v, req_1_1_3_0_N_r; wire [91:0] req_1_1_3_0_N_f;
    wire req_1_1_3_0_S_v, req_1_1_3_0_S_r; wire [91:0] req_1_1_3_0_S_f;
    wire req_1_1_3_0_W_v, req_1_1_3_0_W_r; wire [91:0] req_1_1_3_0_W_f;
    wire req_1_1_3_0_U_v, req_1_1_3_0_U_r; wire [91:0] req_1_1_3_0_U_f;
    wire req_1_1_3_0_D_v, req_1_1_3_0_D_r; wire [91:0] req_1_1_3_0_D_f;
    wire req_1_1_3_0_ANA_v, req_1_1_3_0_ANA_r; wire [91:0] req_1_1_3_0_ANA_f;
    wire req_1_1_3_1_N_v, req_1_1_3_1_N_r; wire [91:0] req_1_1_3_1_N_f;
    wire req_1_1_3_1_S_v, req_1_1_3_1_S_r; wire [91:0] req_1_1_3_1_S_f;
    wire req_1_1_3_1_W_v, req_1_1_3_1_W_r; wire [91:0] req_1_1_3_1_W_f;
    wire req_1_1_3_1_U_v, req_1_1_3_1_U_r; wire [91:0] req_1_1_3_1_U_f;
    wire req_1_1_3_1_D_v, req_1_1_3_1_D_r; wire [91:0] req_1_1_3_1_D_f;
    wire req_1_1_3_1_KATA_v, req_1_1_3_1_KATA_r; wire [91:0] req_1_1_3_1_KATA_f;
    wire req_1_1_4_0_N_v, req_1_1_4_0_N_r; wire [91:0] req_1_1_4_0_N_f;
    wire req_1_1_4_0_S_v, req_1_1_4_0_S_r; wire [91:0] req_1_1_4_0_S_f;
    wire req_1_1_4_0_W_v, req_1_1_4_0_W_r; wire [91:0] req_1_1_4_0_W_f;
    wire req_1_1_4_0_U_v, req_1_1_4_0_U_r; wire [91:0] req_1_1_4_0_U_f;
    wire req_1_1_4_0_D_v, req_1_1_4_0_D_r; wire [91:0] req_1_1_4_0_D_f;
    wire req_1_1_4_0_ANA_v, req_1_1_4_0_ANA_r; wire [91:0] req_1_1_4_0_ANA_f;
    wire req_1_1_4_1_N_v, req_1_1_4_1_N_r; wire [91:0] req_1_1_4_1_N_f;
    wire req_1_1_4_1_S_v, req_1_1_4_1_S_r; wire [91:0] req_1_1_4_1_S_f;
    wire req_1_1_4_1_W_v, req_1_1_4_1_W_r; wire [91:0] req_1_1_4_1_W_f;
    wire req_1_1_4_1_U_v, req_1_1_4_1_U_r; wire [91:0] req_1_1_4_1_U_f;
    wire req_1_1_4_1_D_v, req_1_1_4_1_D_r; wire [91:0] req_1_1_4_1_D_f;
    wire req_1_1_4_1_KATA_v, req_1_1_4_1_KATA_r; wire [91:0] req_1_1_4_1_KATA_f;
    wire req_1_1_5_0_N_v, req_1_1_5_0_N_r; wire [91:0] req_1_1_5_0_N_f;
    wire req_1_1_5_0_S_v, req_1_1_5_0_S_r; wire [91:0] req_1_1_5_0_S_f;
    wire req_1_1_5_0_W_v, req_1_1_5_0_W_r; wire [91:0] req_1_1_5_0_W_f;
    wire req_1_1_5_0_U_v, req_1_1_5_0_U_r; wire [91:0] req_1_1_5_0_U_f;
    wire req_1_1_5_0_ANA_v, req_1_1_5_0_ANA_r; wire [91:0] req_1_1_5_0_ANA_f;
    wire req_1_1_5_1_N_v, req_1_1_5_1_N_r; wire [91:0] req_1_1_5_1_N_f;
    wire req_1_1_5_1_S_v, req_1_1_5_1_S_r; wire [91:0] req_1_1_5_1_S_f;
    wire req_1_1_5_1_W_v, req_1_1_5_1_W_r; wire [91:0] req_1_1_5_1_W_f;
    wire req_1_1_5_1_U_v, req_1_1_5_1_U_r; wire [91:0] req_1_1_5_1_U_f;
    wire req_1_1_5_1_KATA_v, req_1_1_5_1_KATA_r; wire [91:0] req_1_1_5_1_KATA_f;
    wire req_1_2_0_0_N_v, req_1_2_0_0_N_r; wire [91:0] req_1_2_0_0_N_f;
    wire req_1_2_0_0_W_v, req_1_2_0_0_W_r; wire [91:0] req_1_2_0_0_W_f;
    wire req_1_2_0_0_D_v, req_1_2_0_0_D_r; wire [91:0] req_1_2_0_0_D_f;
    wire req_1_2_0_0_ANA_v, req_1_2_0_0_ANA_r; wire [91:0] req_1_2_0_0_ANA_f;
    wire req_1_2_0_1_N_v, req_1_2_0_1_N_r; wire [91:0] req_1_2_0_1_N_f;
    wire req_1_2_0_1_W_v, req_1_2_0_1_W_r; wire [91:0] req_1_2_0_1_W_f;
    wire req_1_2_0_1_D_v, req_1_2_0_1_D_r; wire [91:0] req_1_2_0_1_D_f;
    wire req_1_2_0_1_KATA_v, req_1_2_0_1_KATA_r; wire [91:0] req_1_2_0_1_KATA_f;
    wire req_1_2_1_0_N_v, req_1_2_1_0_N_r; wire [91:0] req_1_2_1_0_N_f;
    wire req_1_2_1_0_W_v, req_1_2_1_0_W_r; wire [91:0] req_1_2_1_0_W_f;
    wire req_1_2_1_0_U_v, req_1_2_1_0_U_r; wire [91:0] req_1_2_1_0_U_f;
    wire req_1_2_1_0_D_v, req_1_2_1_0_D_r; wire [91:0] req_1_2_1_0_D_f;
    wire req_1_2_1_0_ANA_v, req_1_2_1_0_ANA_r; wire [91:0] req_1_2_1_0_ANA_f;
    wire req_1_2_1_1_N_v, req_1_2_1_1_N_r; wire [91:0] req_1_2_1_1_N_f;
    wire req_1_2_1_1_W_v, req_1_2_1_1_W_r; wire [91:0] req_1_2_1_1_W_f;
    wire req_1_2_1_1_U_v, req_1_2_1_1_U_r; wire [91:0] req_1_2_1_1_U_f;
    wire req_1_2_1_1_D_v, req_1_2_1_1_D_r; wire [91:0] req_1_2_1_1_D_f;
    wire req_1_2_1_1_KATA_v, req_1_2_1_1_KATA_r; wire [91:0] req_1_2_1_1_KATA_f;
    wire req_1_2_2_0_N_v, req_1_2_2_0_N_r; wire [91:0] req_1_2_2_0_N_f;
    wire req_1_2_2_0_W_v, req_1_2_2_0_W_r; wire [91:0] req_1_2_2_0_W_f;
    wire req_1_2_2_0_U_v, req_1_2_2_0_U_r; wire [91:0] req_1_2_2_0_U_f;
    wire req_1_2_2_0_D_v, req_1_2_2_0_D_r; wire [91:0] req_1_2_2_0_D_f;
    wire req_1_2_2_0_ANA_v, req_1_2_2_0_ANA_r; wire [91:0] req_1_2_2_0_ANA_f;
    wire req_1_2_2_1_N_v, req_1_2_2_1_N_r; wire [91:0] req_1_2_2_1_N_f;
    wire req_1_2_2_1_W_v, req_1_2_2_1_W_r; wire [91:0] req_1_2_2_1_W_f;
    wire req_1_2_2_1_U_v, req_1_2_2_1_U_r; wire [91:0] req_1_2_2_1_U_f;
    wire req_1_2_2_1_D_v, req_1_2_2_1_D_r; wire [91:0] req_1_2_2_1_D_f;
    wire req_1_2_2_1_KATA_v, req_1_2_2_1_KATA_r; wire [91:0] req_1_2_2_1_KATA_f;
    wire req_1_2_3_0_N_v, req_1_2_3_0_N_r; wire [91:0] req_1_2_3_0_N_f;
    wire req_1_2_3_0_W_v, req_1_2_3_0_W_r; wire [91:0] req_1_2_3_0_W_f;
    wire req_1_2_3_0_U_v, req_1_2_3_0_U_r; wire [91:0] req_1_2_3_0_U_f;
    wire req_1_2_3_0_D_v, req_1_2_3_0_D_r; wire [91:0] req_1_2_3_0_D_f;
    wire req_1_2_3_0_ANA_v, req_1_2_3_0_ANA_r; wire [91:0] req_1_2_3_0_ANA_f;
    wire req_1_2_3_1_N_v, req_1_2_3_1_N_r; wire [91:0] req_1_2_3_1_N_f;
    wire req_1_2_3_1_W_v, req_1_2_3_1_W_r; wire [91:0] req_1_2_3_1_W_f;
    wire req_1_2_3_1_U_v, req_1_2_3_1_U_r; wire [91:0] req_1_2_3_1_U_f;
    wire req_1_2_3_1_D_v, req_1_2_3_1_D_r; wire [91:0] req_1_2_3_1_D_f;
    wire req_1_2_3_1_KATA_v, req_1_2_3_1_KATA_r; wire [91:0] req_1_2_3_1_KATA_f;
    wire req_1_2_4_0_N_v, req_1_2_4_0_N_r; wire [91:0] req_1_2_4_0_N_f;
    wire req_1_2_4_0_W_v, req_1_2_4_0_W_r; wire [91:0] req_1_2_4_0_W_f;
    wire req_1_2_4_0_U_v, req_1_2_4_0_U_r; wire [91:0] req_1_2_4_0_U_f;
    wire req_1_2_4_0_D_v, req_1_2_4_0_D_r; wire [91:0] req_1_2_4_0_D_f;
    wire req_1_2_4_0_ANA_v, req_1_2_4_0_ANA_r; wire [91:0] req_1_2_4_0_ANA_f;
    wire req_1_2_4_1_N_v, req_1_2_4_1_N_r; wire [91:0] req_1_2_4_1_N_f;
    wire req_1_2_4_1_W_v, req_1_2_4_1_W_r; wire [91:0] req_1_2_4_1_W_f;
    wire req_1_2_4_1_U_v, req_1_2_4_1_U_r; wire [91:0] req_1_2_4_1_U_f;
    wire req_1_2_4_1_D_v, req_1_2_4_1_D_r; wire [91:0] req_1_2_4_1_D_f;
    wire req_1_2_4_1_KATA_v, req_1_2_4_1_KATA_r; wire [91:0] req_1_2_4_1_KATA_f;
    wire req_1_2_5_0_N_v, req_1_2_5_0_N_r; wire [91:0] req_1_2_5_0_N_f;
    wire req_1_2_5_0_W_v, req_1_2_5_0_W_r; wire [91:0] req_1_2_5_0_W_f;
    wire req_1_2_5_0_U_v, req_1_2_5_0_U_r; wire [91:0] req_1_2_5_0_U_f;
    wire req_1_2_5_0_ANA_v, req_1_2_5_0_ANA_r; wire [91:0] req_1_2_5_0_ANA_f;
    wire req_1_2_5_1_N_v, req_1_2_5_1_N_r; wire [91:0] req_1_2_5_1_N_f;
    wire req_1_2_5_1_W_v, req_1_2_5_1_W_r; wire [91:0] req_1_2_5_1_W_f;
    wire req_1_2_5_1_U_v, req_1_2_5_1_U_r; wire [91:0] req_1_2_5_1_U_f;
    wire req_1_2_5_1_KATA_v, req_1_2_5_1_KATA_r; wire [91:0] req_1_2_5_1_KATA_f;
    wire resp_0_0_0_0_S_v, resp_0_0_0_0_S_r; wire [43:0] resp_0_0_0_0_S_f;
    wire resp_0_0_0_0_E_v, resp_0_0_0_0_E_r; wire [43:0] resp_0_0_0_0_E_f;
    wire resp_0_0_0_0_D_v, resp_0_0_0_0_D_r; wire [43:0] resp_0_0_0_0_D_f;
    wire resp_0_0_0_0_ANA_v, resp_0_0_0_0_ANA_r; wire [43:0] resp_0_0_0_0_ANA_f;
    wire resp_0_0_0_1_S_v, resp_0_0_0_1_S_r; wire [43:0] resp_0_0_0_1_S_f;
    wire resp_0_0_0_1_E_v, resp_0_0_0_1_E_r; wire [43:0] resp_0_0_0_1_E_f;
    wire resp_0_0_0_1_D_v, resp_0_0_0_1_D_r; wire [43:0] resp_0_0_0_1_D_f;
    wire resp_0_0_0_1_KATA_v, resp_0_0_0_1_KATA_r; wire [43:0] resp_0_0_0_1_KATA_f;
    wire resp_0_0_1_0_S_v, resp_0_0_1_0_S_r; wire [43:0] resp_0_0_1_0_S_f;
    wire resp_0_0_1_0_E_v, resp_0_0_1_0_E_r; wire [43:0] resp_0_0_1_0_E_f;
    wire resp_0_0_1_0_U_v, resp_0_0_1_0_U_r; wire [43:0] resp_0_0_1_0_U_f;
    wire resp_0_0_1_0_D_v, resp_0_0_1_0_D_r; wire [43:0] resp_0_0_1_0_D_f;
    wire resp_0_0_1_0_ANA_v, resp_0_0_1_0_ANA_r; wire [43:0] resp_0_0_1_0_ANA_f;
    wire resp_0_0_1_1_S_v, resp_0_0_1_1_S_r; wire [43:0] resp_0_0_1_1_S_f;
    wire resp_0_0_1_1_E_v, resp_0_0_1_1_E_r; wire [43:0] resp_0_0_1_1_E_f;
    wire resp_0_0_1_1_U_v, resp_0_0_1_1_U_r; wire [43:0] resp_0_0_1_1_U_f;
    wire resp_0_0_1_1_D_v, resp_0_0_1_1_D_r; wire [43:0] resp_0_0_1_1_D_f;
    wire resp_0_0_1_1_KATA_v, resp_0_0_1_1_KATA_r; wire [43:0] resp_0_0_1_1_KATA_f;
    wire resp_0_0_2_0_S_v, resp_0_0_2_0_S_r; wire [43:0] resp_0_0_2_0_S_f;
    wire resp_0_0_2_0_E_v, resp_0_0_2_0_E_r; wire [43:0] resp_0_0_2_0_E_f;
    wire resp_0_0_2_0_U_v, resp_0_0_2_0_U_r; wire [43:0] resp_0_0_2_0_U_f;
    wire resp_0_0_2_0_D_v, resp_0_0_2_0_D_r; wire [43:0] resp_0_0_2_0_D_f;
    wire resp_0_0_2_0_ANA_v, resp_0_0_2_0_ANA_r; wire [43:0] resp_0_0_2_0_ANA_f;
    wire resp_0_0_2_1_S_v, resp_0_0_2_1_S_r; wire [43:0] resp_0_0_2_1_S_f;
    wire resp_0_0_2_1_E_v, resp_0_0_2_1_E_r; wire [43:0] resp_0_0_2_1_E_f;
    wire resp_0_0_2_1_U_v, resp_0_0_2_1_U_r; wire [43:0] resp_0_0_2_1_U_f;
    wire resp_0_0_2_1_D_v, resp_0_0_2_1_D_r; wire [43:0] resp_0_0_2_1_D_f;
    wire resp_0_0_2_1_KATA_v, resp_0_0_2_1_KATA_r; wire [43:0] resp_0_0_2_1_KATA_f;
    wire resp_0_0_3_0_S_v, resp_0_0_3_0_S_r; wire [43:0] resp_0_0_3_0_S_f;
    wire resp_0_0_3_0_E_v, resp_0_0_3_0_E_r; wire [43:0] resp_0_0_3_0_E_f;
    wire resp_0_0_3_0_U_v, resp_0_0_3_0_U_r; wire [43:0] resp_0_0_3_0_U_f;
    wire resp_0_0_3_0_D_v, resp_0_0_3_0_D_r; wire [43:0] resp_0_0_3_0_D_f;
    wire resp_0_0_3_0_ANA_v, resp_0_0_3_0_ANA_r; wire [43:0] resp_0_0_3_0_ANA_f;
    wire resp_0_0_3_1_S_v, resp_0_0_3_1_S_r; wire [43:0] resp_0_0_3_1_S_f;
    wire resp_0_0_3_1_E_v, resp_0_0_3_1_E_r; wire [43:0] resp_0_0_3_1_E_f;
    wire resp_0_0_3_1_U_v, resp_0_0_3_1_U_r; wire [43:0] resp_0_0_3_1_U_f;
    wire resp_0_0_3_1_D_v, resp_0_0_3_1_D_r; wire [43:0] resp_0_0_3_1_D_f;
    wire resp_0_0_3_1_KATA_v, resp_0_0_3_1_KATA_r; wire [43:0] resp_0_0_3_1_KATA_f;
    wire resp_0_0_4_0_S_v, resp_0_0_4_0_S_r; wire [43:0] resp_0_0_4_0_S_f;
    wire resp_0_0_4_0_E_v, resp_0_0_4_0_E_r; wire [43:0] resp_0_0_4_0_E_f;
    wire resp_0_0_4_0_U_v, resp_0_0_4_0_U_r; wire [43:0] resp_0_0_4_0_U_f;
    wire resp_0_0_4_0_D_v, resp_0_0_4_0_D_r; wire [43:0] resp_0_0_4_0_D_f;
    wire resp_0_0_4_0_ANA_v, resp_0_0_4_0_ANA_r; wire [43:0] resp_0_0_4_0_ANA_f;
    wire resp_0_0_4_1_S_v, resp_0_0_4_1_S_r; wire [43:0] resp_0_0_4_1_S_f;
    wire resp_0_0_4_1_E_v, resp_0_0_4_1_E_r; wire [43:0] resp_0_0_4_1_E_f;
    wire resp_0_0_4_1_U_v, resp_0_0_4_1_U_r; wire [43:0] resp_0_0_4_1_U_f;
    wire resp_0_0_4_1_D_v, resp_0_0_4_1_D_r; wire [43:0] resp_0_0_4_1_D_f;
    wire resp_0_0_4_1_KATA_v, resp_0_0_4_1_KATA_r; wire [43:0] resp_0_0_4_1_KATA_f;
    wire resp_0_0_5_0_S_v, resp_0_0_5_0_S_r; wire [43:0] resp_0_0_5_0_S_f;
    wire resp_0_0_5_0_E_v, resp_0_0_5_0_E_r; wire [43:0] resp_0_0_5_0_E_f;
    wire resp_0_0_5_0_U_v, resp_0_0_5_0_U_r; wire [43:0] resp_0_0_5_0_U_f;
    wire resp_0_0_5_0_ANA_v, resp_0_0_5_0_ANA_r; wire [43:0] resp_0_0_5_0_ANA_f;
    wire resp_0_0_5_1_S_v, resp_0_0_5_1_S_r; wire [43:0] resp_0_0_5_1_S_f;
    wire resp_0_0_5_1_E_v, resp_0_0_5_1_E_r; wire [43:0] resp_0_0_5_1_E_f;
    wire resp_0_0_5_1_U_v, resp_0_0_5_1_U_r; wire [43:0] resp_0_0_5_1_U_f;
    wire resp_0_0_5_1_KATA_v, resp_0_0_5_1_KATA_r; wire [43:0] resp_0_0_5_1_KATA_f;
    wire resp_0_1_0_0_N_v, resp_0_1_0_0_N_r; wire [43:0] resp_0_1_0_0_N_f;
    wire resp_0_1_0_0_S_v, resp_0_1_0_0_S_r; wire [43:0] resp_0_1_0_0_S_f;
    wire resp_0_1_0_0_E_v, resp_0_1_0_0_E_r; wire [43:0] resp_0_1_0_0_E_f;
    wire resp_0_1_0_0_D_v, resp_0_1_0_0_D_r; wire [43:0] resp_0_1_0_0_D_f;
    wire resp_0_1_0_0_ANA_v, resp_0_1_0_0_ANA_r; wire [43:0] resp_0_1_0_0_ANA_f;
    wire resp_0_1_0_1_N_v, resp_0_1_0_1_N_r; wire [43:0] resp_0_1_0_1_N_f;
    wire resp_0_1_0_1_S_v, resp_0_1_0_1_S_r; wire [43:0] resp_0_1_0_1_S_f;
    wire resp_0_1_0_1_E_v, resp_0_1_0_1_E_r; wire [43:0] resp_0_1_0_1_E_f;
    wire resp_0_1_0_1_D_v, resp_0_1_0_1_D_r; wire [43:0] resp_0_1_0_1_D_f;
    wire resp_0_1_0_1_KATA_v, resp_0_1_0_1_KATA_r; wire [43:0] resp_0_1_0_1_KATA_f;
    wire resp_0_1_1_0_N_v, resp_0_1_1_0_N_r; wire [43:0] resp_0_1_1_0_N_f;
    wire resp_0_1_1_0_S_v, resp_0_1_1_0_S_r; wire [43:0] resp_0_1_1_0_S_f;
    wire resp_0_1_1_0_E_v, resp_0_1_1_0_E_r; wire [43:0] resp_0_1_1_0_E_f;
    wire resp_0_1_1_0_U_v, resp_0_1_1_0_U_r; wire [43:0] resp_0_1_1_0_U_f;
    wire resp_0_1_1_0_D_v, resp_0_1_1_0_D_r; wire [43:0] resp_0_1_1_0_D_f;
    wire resp_0_1_1_0_ANA_v, resp_0_1_1_0_ANA_r; wire [43:0] resp_0_1_1_0_ANA_f;
    wire resp_0_1_1_1_N_v, resp_0_1_1_1_N_r; wire [43:0] resp_0_1_1_1_N_f;
    wire resp_0_1_1_1_S_v, resp_0_1_1_1_S_r; wire [43:0] resp_0_1_1_1_S_f;
    wire resp_0_1_1_1_E_v, resp_0_1_1_1_E_r; wire [43:0] resp_0_1_1_1_E_f;
    wire resp_0_1_1_1_U_v, resp_0_1_1_1_U_r; wire [43:0] resp_0_1_1_1_U_f;
    wire resp_0_1_1_1_D_v, resp_0_1_1_1_D_r; wire [43:0] resp_0_1_1_1_D_f;
    wire resp_0_1_1_1_KATA_v, resp_0_1_1_1_KATA_r; wire [43:0] resp_0_1_1_1_KATA_f;
    wire resp_0_1_2_0_N_v, resp_0_1_2_0_N_r; wire [43:0] resp_0_1_2_0_N_f;
    wire resp_0_1_2_0_S_v, resp_0_1_2_0_S_r; wire [43:0] resp_0_1_2_0_S_f;
    wire resp_0_1_2_0_E_v, resp_0_1_2_0_E_r; wire [43:0] resp_0_1_2_0_E_f;
    wire resp_0_1_2_0_U_v, resp_0_1_2_0_U_r; wire [43:0] resp_0_1_2_0_U_f;
    wire resp_0_1_2_0_D_v, resp_0_1_2_0_D_r; wire [43:0] resp_0_1_2_0_D_f;
    wire resp_0_1_2_0_ANA_v, resp_0_1_2_0_ANA_r; wire [43:0] resp_0_1_2_0_ANA_f;
    wire resp_0_1_2_1_N_v, resp_0_1_2_1_N_r; wire [43:0] resp_0_1_2_1_N_f;
    wire resp_0_1_2_1_S_v, resp_0_1_2_1_S_r; wire [43:0] resp_0_1_2_1_S_f;
    wire resp_0_1_2_1_E_v, resp_0_1_2_1_E_r; wire [43:0] resp_0_1_2_1_E_f;
    wire resp_0_1_2_1_U_v, resp_0_1_2_1_U_r; wire [43:0] resp_0_1_2_1_U_f;
    wire resp_0_1_2_1_D_v, resp_0_1_2_1_D_r; wire [43:0] resp_0_1_2_1_D_f;
    wire resp_0_1_2_1_KATA_v, resp_0_1_2_1_KATA_r; wire [43:0] resp_0_1_2_1_KATA_f;
    wire resp_0_1_3_0_N_v, resp_0_1_3_0_N_r; wire [43:0] resp_0_1_3_0_N_f;
    wire resp_0_1_3_0_S_v, resp_0_1_3_0_S_r; wire [43:0] resp_0_1_3_0_S_f;
    wire resp_0_1_3_0_E_v, resp_0_1_3_0_E_r; wire [43:0] resp_0_1_3_0_E_f;
    wire resp_0_1_3_0_U_v, resp_0_1_3_0_U_r; wire [43:0] resp_0_1_3_0_U_f;
    wire resp_0_1_3_0_D_v, resp_0_1_3_0_D_r; wire [43:0] resp_0_1_3_0_D_f;
    wire resp_0_1_3_0_ANA_v, resp_0_1_3_0_ANA_r; wire [43:0] resp_0_1_3_0_ANA_f;
    wire resp_0_1_3_1_N_v, resp_0_1_3_1_N_r; wire [43:0] resp_0_1_3_1_N_f;
    wire resp_0_1_3_1_S_v, resp_0_1_3_1_S_r; wire [43:0] resp_0_1_3_1_S_f;
    wire resp_0_1_3_1_E_v, resp_0_1_3_1_E_r; wire [43:0] resp_0_1_3_1_E_f;
    wire resp_0_1_3_1_U_v, resp_0_1_3_1_U_r; wire [43:0] resp_0_1_3_1_U_f;
    wire resp_0_1_3_1_D_v, resp_0_1_3_1_D_r; wire [43:0] resp_0_1_3_1_D_f;
    wire resp_0_1_3_1_KATA_v, resp_0_1_3_1_KATA_r; wire [43:0] resp_0_1_3_1_KATA_f;
    wire resp_0_1_4_0_N_v, resp_0_1_4_0_N_r; wire [43:0] resp_0_1_4_0_N_f;
    wire resp_0_1_4_0_S_v, resp_0_1_4_0_S_r; wire [43:0] resp_0_1_4_0_S_f;
    wire resp_0_1_4_0_E_v, resp_0_1_4_0_E_r; wire [43:0] resp_0_1_4_0_E_f;
    wire resp_0_1_4_0_U_v, resp_0_1_4_0_U_r; wire [43:0] resp_0_1_4_0_U_f;
    wire resp_0_1_4_0_D_v, resp_0_1_4_0_D_r; wire [43:0] resp_0_1_4_0_D_f;
    wire resp_0_1_4_0_ANA_v, resp_0_1_4_0_ANA_r; wire [43:0] resp_0_1_4_0_ANA_f;
    wire resp_0_1_4_1_N_v, resp_0_1_4_1_N_r; wire [43:0] resp_0_1_4_1_N_f;
    wire resp_0_1_4_1_S_v, resp_0_1_4_1_S_r; wire [43:0] resp_0_1_4_1_S_f;
    wire resp_0_1_4_1_E_v, resp_0_1_4_1_E_r; wire [43:0] resp_0_1_4_1_E_f;
    wire resp_0_1_4_1_U_v, resp_0_1_4_1_U_r; wire [43:0] resp_0_1_4_1_U_f;
    wire resp_0_1_4_1_D_v, resp_0_1_4_1_D_r; wire [43:0] resp_0_1_4_1_D_f;
    wire resp_0_1_4_1_KATA_v, resp_0_1_4_1_KATA_r; wire [43:0] resp_0_1_4_1_KATA_f;
    wire resp_0_1_5_0_N_v, resp_0_1_5_0_N_r; wire [43:0] resp_0_1_5_0_N_f;
    wire resp_0_1_5_0_S_v, resp_0_1_5_0_S_r; wire [43:0] resp_0_1_5_0_S_f;
    wire resp_0_1_5_0_E_v, resp_0_1_5_0_E_r; wire [43:0] resp_0_1_5_0_E_f;
    wire resp_0_1_5_0_U_v, resp_0_1_5_0_U_r; wire [43:0] resp_0_1_5_0_U_f;
    wire resp_0_1_5_0_ANA_v, resp_0_1_5_0_ANA_r; wire [43:0] resp_0_1_5_0_ANA_f;
    wire resp_0_1_5_1_N_v, resp_0_1_5_1_N_r; wire [43:0] resp_0_1_5_1_N_f;
    wire resp_0_1_5_1_S_v, resp_0_1_5_1_S_r; wire [43:0] resp_0_1_5_1_S_f;
    wire resp_0_1_5_1_E_v, resp_0_1_5_1_E_r; wire [43:0] resp_0_1_5_1_E_f;
    wire resp_0_1_5_1_U_v, resp_0_1_5_1_U_r; wire [43:0] resp_0_1_5_1_U_f;
    wire resp_0_1_5_1_KATA_v, resp_0_1_5_1_KATA_r; wire [43:0] resp_0_1_5_1_KATA_f;
    wire resp_0_2_0_0_N_v, resp_0_2_0_0_N_r; wire [43:0] resp_0_2_0_0_N_f;
    wire resp_0_2_0_0_E_v, resp_0_2_0_0_E_r; wire [43:0] resp_0_2_0_0_E_f;
    wire resp_0_2_0_0_D_v, resp_0_2_0_0_D_r; wire [43:0] resp_0_2_0_0_D_f;
    wire resp_0_2_0_0_ANA_v, resp_0_2_0_0_ANA_r; wire [43:0] resp_0_2_0_0_ANA_f;
    wire resp_0_2_0_1_N_v, resp_0_2_0_1_N_r; wire [43:0] resp_0_2_0_1_N_f;
    wire resp_0_2_0_1_E_v, resp_0_2_0_1_E_r; wire [43:0] resp_0_2_0_1_E_f;
    wire resp_0_2_0_1_D_v, resp_0_2_0_1_D_r; wire [43:0] resp_0_2_0_1_D_f;
    wire resp_0_2_0_1_KATA_v, resp_0_2_0_1_KATA_r; wire [43:0] resp_0_2_0_1_KATA_f;
    wire resp_0_2_1_0_N_v, resp_0_2_1_0_N_r; wire [43:0] resp_0_2_1_0_N_f;
    wire resp_0_2_1_0_E_v, resp_0_2_1_0_E_r; wire [43:0] resp_0_2_1_0_E_f;
    wire resp_0_2_1_0_U_v, resp_0_2_1_0_U_r; wire [43:0] resp_0_2_1_0_U_f;
    wire resp_0_2_1_0_D_v, resp_0_2_1_0_D_r; wire [43:0] resp_0_2_1_0_D_f;
    wire resp_0_2_1_0_ANA_v, resp_0_2_1_0_ANA_r; wire [43:0] resp_0_2_1_0_ANA_f;
    wire resp_0_2_1_1_N_v, resp_0_2_1_1_N_r; wire [43:0] resp_0_2_1_1_N_f;
    wire resp_0_2_1_1_E_v, resp_0_2_1_1_E_r; wire [43:0] resp_0_2_1_1_E_f;
    wire resp_0_2_1_1_U_v, resp_0_2_1_1_U_r; wire [43:0] resp_0_2_1_1_U_f;
    wire resp_0_2_1_1_D_v, resp_0_2_1_1_D_r; wire [43:0] resp_0_2_1_1_D_f;
    wire resp_0_2_1_1_KATA_v, resp_0_2_1_1_KATA_r; wire [43:0] resp_0_2_1_1_KATA_f;
    wire resp_0_2_2_0_N_v, resp_0_2_2_0_N_r; wire [43:0] resp_0_2_2_0_N_f;
    wire resp_0_2_2_0_E_v, resp_0_2_2_0_E_r; wire [43:0] resp_0_2_2_0_E_f;
    wire resp_0_2_2_0_U_v, resp_0_2_2_0_U_r; wire [43:0] resp_0_2_2_0_U_f;
    wire resp_0_2_2_0_D_v, resp_0_2_2_0_D_r; wire [43:0] resp_0_2_2_0_D_f;
    wire resp_0_2_2_0_ANA_v, resp_0_2_2_0_ANA_r; wire [43:0] resp_0_2_2_0_ANA_f;
    wire resp_0_2_2_1_N_v, resp_0_2_2_1_N_r; wire [43:0] resp_0_2_2_1_N_f;
    wire resp_0_2_2_1_E_v, resp_0_2_2_1_E_r; wire [43:0] resp_0_2_2_1_E_f;
    wire resp_0_2_2_1_U_v, resp_0_2_2_1_U_r; wire [43:0] resp_0_2_2_1_U_f;
    wire resp_0_2_2_1_D_v, resp_0_2_2_1_D_r; wire [43:0] resp_0_2_2_1_D_f;
    wire resp_0_2_2_1_KATA_v, resp_0_2_2_1_KATA_r; wire [43:0] resp_0_2_2_1_KATA_f;
    wire resp_0_2_3_0_N_v, resp_0_2_3_0_N_r; wire [43:0] resp_0_2_3_0_N_f;
    wire resp_0_2_3_0_E_v, resp_0_2_3_0_E_r; wire [43:0] resp_0_2_3_0_E_f;
    wire resp_0_2_3_0_U_v, resp_0_2_3_0_U_r; wire [43:0] resp_0_2_3_0_U_f;
    wire resp_0_2_3_0_D_v, resp_0_2_3_0_D_r; wire [43:0] resp_0_2_3_0_D_f;
    wire resp_0_2_3_0_ANA_v, resp_0_2_3_0_ANA_r; wire [43:0] resp_0_2_3_0_ANA_f;
    wire resp_0_2_3_1_N_v, resp_0_2_3_1_N_r; wire [43:0] resp_0_2_3_1_N_f;
    wire resp_0_2_3_1_E_v, resp_0_2_3_1_E_r; wire [43:0] resp_0_2_3_1_E_f;
    wire resp_0_2_3_1_U_v, resp_0_2_3_1_U_r; wire [43:0] resp_0_2_3_1_U_f;
    wire resp_0_2_3_1_D_v, resp_0_2_3_1_D_r; wire [43:0] resp_0_2_3_1_D_f;
    wire resp_0_2_3_1_KATA_v, resp_0_2_3_1_KATA_r; wire [43:0] resp_0_2_3_1_KATA_f;
    wire resp_0_2_4_0_N_v, resp_0_2_4_0_N_r; wire [43:0] resp_0_2_4_0_N_f;
    wire resp_0_2_4_0_E_v, resp_0_2_4_0_E_r; wire [43:0] resp_0_2_4_0_E_f;
    wire resp_0_2_4_0_U_v, resp_0_2_4_0_U_r; wire [43:0] resp_0_2_4_0_U_f;
    wire resp_0_2_4_0_D_v, resp_0_2_4_0_D_r; wire [43:0] resp_0_2_4_0_D_f;
    wire resp_0_2_4_0_ANA_v, resp_0_2_4_0_ANA_r; wire [43:0] resp_0_2_4_0_ANA_f;
    wire resp_0_2_4_1_N_v, resp_0_2_4_1_N_r; wire [43:0] resp_0_2_4_1_N_f;
    wire resp_0_2_4_1_E_v, resp_0_2_4_1_E_r; wire [43:0] resp_0_2_4_1_E_f;
    wire resp_0_2_4_1_U_v, resp_0_2_4_1_U_r; wire [43:0] resp_0_2_4_1_U_f;
    wire resp_0_2_4_1_D_v, resp_0_2_4_1_D_r; wire [43:0] resp_0_2_4_1_D_f;
    wire resp_0_2_4_1_KATA_v, resp_0_2_4_1_KATA_r; wire [43:0] resp_0_2_4_1_KATA_f;
    wire resp_0_2_5_0_N_v, resp_0_2_5_0_N_r; wire [43:0] resp_0_2_5_0_N_f;
    wire resp_0_2_5_0_E_v, resp_0_2_5_0_E_r; wire [43:0] resp_0_2_5_0_E_f;
    wire resp_0_2_5_0_U_v, resp_0_2_5_0_U_r; wire [43:0] resp_0_2_5_0_U_f;
    wire resp_0_2_5_0_ANA_v, resp_0_2_5_0_ANA_r; wire [43:0] resp_0_2_5_0_ANA_f;
    wire resp_0_2_5_1_N_v, resp_0_2_5_1_N_r; wire [43:0] resp_0_2_5_1_N_f;
    wire resp_0_2_5_1_E_v, resp_0_2_5_1_E_r; wire [43:0] resp_0_2_5_1_E_f;
    wire resp_0_2_5_1_U_v, resp_0_2_5_1_U_r; wire [43:0] resp_0_2_5_1_U_f;
    wire resp_0_2_5_1_KATA_v, resp_0_2_5_1_KATA_r; wire [43:0] resp_0_2_5_1_KATA_f;
    wire resp_1_0_0_0_S_v, resp_1_0_0_0_S_r; wire [43:0] resp_1_0_0_0_S_f;
    wire resp_1_0_0_0_W_v, resp_1_0_0_0_W_r; wire [43:0] resp_1_0_0_0_W_f;
    wire resp_1_0_0_0_D_v, resp_1_0_0_0_D_r; wire [43:0] resp_1_0_0_0_D_f;
    wire resp_1_0_0_0_ANA_v, resp_1_0_0_0_ANA_r; wire [43:0] resp_1_0_0_0_ANA_f;
    wire resp_1_0_0_1_S_v, resp_1_0_0_1_S_r; wire [43:0] resp_1_0_0_1_S_f;
    wire resp_1_0_0_1_W_v, resp_1_0_0_1_W_r; wire [43:0] resp_1_0_0_1_W_f;
    wire resp_1_0_0_1_D_v, resp_1_0_0_1_D_r; wire [43:0] resp_1_0_0_1_D_f;
    wire resp_1_0_0_1_KATA_v, resp_1_0_0_1_KATA_r; wire [43:0] resp_1_0_0_1_KATA_f;
    wire resp_1_0_1_0_S_v, resp_1_0_1_0_S_r; wire [43:0] resp_1_0_1_0_S_f;
    wire resp_1_0_1_0_W_v, resp_1_0_1_0_W_r; wire [43:0] resp_1_0_1_0_W_f;
    wire resp_1_0_1_0_U_v, resp_1_0_1_0_U_r; wire [43:0] resp_1_0_1_0_U_f;
    wire resp_1_0_1_0_D_v, resp_1_0_1_0_D_r; wire [43:0] resp_1_0_1_0_D_f;
    wire resp_1_0_1_0_ANA_v, resp_1_0_1_0_ANA_r; wire [43:0] resp_1_0_1_0_ANA_f;
    wire resp_1_0_1_1_S_v, resp_1_0_1_1_S_r; wire [43:0] resp_1_0_1_1_S_f;
    wire resp_1_0_1_1_W_v, resp_1_0_1_1_W_r; wire [43:0] resp_1_0_1_1_W_f;
    wire resp_1_0_1_1_U_v, resp_1_0_1_1_U_r; wire [43:0] resp_1_0_1_1_U_f;
    wire resp_1_0_1_1_D_v, resp_1_0_1_1_D_r; wire [43:0] resp_1_0_1_1_D_f;
    wire resp_1_0_1_1_KATA_v, resp_1_0_1_1_KATA_r; wire [43:0] resp_1_0_1_1_KATA_f;
    wire resp_1_0_2_0_S_v, resp_1_0_2_0_S_r; wire [43:0] resp_1_0_2_0_S_f;
    wire resp_1_0_2_0_W_v, resp_1_0_2_0_W_r; wire [43:0] resp_1_0_2_0_W_f;
    wire resp_1_0_2_0_U_v, resp_1_0_2_0_U_r; wire [43:0] resp_1_0_2_0_U_f;
    wire resp_1_0_2_0_D_v, resp_1_0_2_0_D_r; wire [43:0] resp_1_0_2_0_D_f;
    wire resp_1_0_2_0_ANA_v, resp_1_0_2_0_ANA_r; wire [43:0] resp_1_0_2_0_ANA_f;
    wire resp_1_0_2_1_S_v, resp_1_0_2_1_S_r; wire [43:0] resp_1_0_2_1_S_f;
    wire resp_1_0_2_1_W_v, resp_1_0_2_1_W_r; wire [43:0] resp_1_0_2_1_W_f;
    wire resp_1_0_2_1_U_v, resp_1_0_2_1_U_r; wire [43:0] resp_1_0_2_1_U_f;
    wire resp_1_0_2_1_D_v, resp_1_0_2_1_D_r; wire [43:0] resp_1_0_2_1_D_f;
    wire resp_1_0_2_1_KATA_v, resp_1_0_2_1_KATA_r; wire [43:0] resp_1_0_2_1_KATA_f;
    wire resp_1_0_3_0_S_v, resp_1_0_3_0_S_r; wire [43:0] resp_1_0_3_0_S_f;
    wire resp_1_0_3_0_W_v, resp_1_0_3_0_W_r; wire [43:0] resp_1_0_3_0_W_f;
    wire resp_1_0_3_0_U_v, resp_1_0_3_0_U_r; wire [43:0] resp_1_0_3_0_U_f;
    wire resp_1_0_3_0_D_v, resp_1_0_3_0_D_r; wire [43:0] resp_1_0_3_0_D_f;
    wire resp_1_0_3_0_ANA_v, resp_1_0_3_0_ANA_r; wire [43:0] resp_1_0_3_0_ANA_f;
    wire resp_1_0_3_1_S_v, resp_1_0_3_1_S_r; wire [43:0] resp_1_0_3_1_S_f;
    wire resp_1_0_3_1_W_v, resp_1_0_3_1_W_r; wire [43:0] resp_1_0_3_1_W_f;
    wire resp_1_0_3_1_U_v, resp_1_0_3_1_U_r; wire [43:0] resp_1_0_3_1_U_f;
    wire resp_1_0_3_1_D_v, resp_1_0_3_1_D_r; wire [43:0] resp_1_0_3_1_D_f;
    wire resp_1_0_3_1_KATA_v, resp_1_0_3_1_KATA_r; wire [43:0] resp_1_0_3_1_KATA_f;
    wire resp_1_0_4_0_S_v, resp_1_0_4_0_S_r; wire [43:0] resp_1_0_4_0_S_f;
    wire resp_1_0_4_0_W_v, resp_1_0_4_0_W_r; wire [43:0] resp_1_0_4_0_W_f;
    wire resp_1_0_4_0_U_v, resp_1_0_4_0_U_r; wire [43:0] resp_1_0_4_0_U_f;
    wire resp_1_0_4_0_D_v, resp_1_0_4_0_D_r; wire [43:0] resp_1_0_4_0_D_f;
    wire resp_1_0_4_0_ANA_v, resp_1_0_4_0_ANA_r; wire [43:0] resp_1_0_4_0_ANA_f;
    wire resp_1_0_4_1_S_v, resp_1_0_4_1_S_r; wire [43:0] resp_1_0_4_1_S_f;
    wire resp_1_0_4_1_W_v, resp_1_0_4_1_W_r; wire [43:0] resp_1_0_4_1_W_f;
    wire resp_1_0_4_1_U_v, resp_1_0_4_1_U_r; wire [43:0] resp_1_0_4_1_U_f;
    wire resp_1_0_4_1_D_v, resp_1_0_4_1_D_r; wire [43:0] resp_1_0_4_1_D_f;
    wire resp_1_0_4_1_KATA_v, resp_1_0_4_1_KATA_r; wire [43:0] resp_1_0_4_1_KATA_f;
    wire resp_1_0_5_0_S_v, resp_1_0_5_0_S_r; wire [43:0] resp_1_0_5_0_S_f;
    wire resp_1_0_5_0_W_v, resp_1_0_5_0_W_r; wire [43:0] resp_1_0_5_0_W_f;
    wire resp_1_0_5_0_U_v, resp_1_0_5_0_U_r; wire [43:0] resp_1_0_5_0_U_f;
    wire resp_1_0_5_0_ANA_v, resp_1_0_5_0_ANA_r; wire [43:0] resp_1_0_5_0_ANA_f;
    wire resp_1_0_5_1_S_v, resp_1_0_5_1_S_r; wire [43:0] resp_1_0_5_1_S_f;
    wire resp_1_0_5_1_W_v, resp_1_0_5_1_W_r; wire [43:0] resp_1_0_5_1_W_f;
    wire resp_1_0_5_1_U_v, resp_1_0_5_1_U_r; wire [43:0] resp_1_0_5_1_U_f;
    wire resp_1_0_5_1_KATA_v, resp_1_0_5_1_KATA_r; wire [43:0] resp_1_0_5_1_KATA_f;
    wire resp_1_1_0_0_N_v, resp_1_1_0_0_N_r; wire [43:0] resp_1_1_0_0_N_f;
    wire resp_1_1_0_0_S_v, resp_1_1_0_0_S_r; wire [43:0] resp_1_1_0_0_S_f;
    wire resp_1_1_0_0_W_v, resp_1_1_0_0_W_r; wire [43:0] resp_1_1_0_0_W_f;
    wire resp_1_1_0_0_D_v, resp_1_1_0_0_D_r; wire [43:0] resp_1_1_0_0_D_f;
    wire resp_1_1_0_0_ANA_v, resp_1_1_0_0_ANA_r; wire [43:0] resp_1_1_0_0_ANA_f;
    wire resp_1_1_0_1_N_v, resp_1_1_0_1_N_r; wire [43:0] resp_1_1_0_1_N_f;
    wire resp_1_1_0_1_S_v, resp_1_1_0_1_S_r; wire [43:0] resp_1_1_0_1_S_f;
    wire resp_1_1_0_1_W_v, resp_1_1_0_1_W_r; wire [43:0] resp_1_1_0_1_W_f;
    wire resp_1_1_0_1_D_v, resp_1_1_0_1_D_r; wire [43:0] resp_1_1_0_1_D_f;
    wire resp_1_1_0_1_KATA_v, resp_1_1_0_1_KATA_r; wire [43:0] resp_1_1_0_1_KATA_f;
    wire resp_1_1_1_0_N_v, resp_1_1_1_0_N_r; wire [43:0] resp_1_1_1_0_N_f;
    wire resp_1_1_1_0_S_v, resp_1_1_1_0_S_r; wire [43:0] resp_1_1_1_0_S_f;
    wire resp_1_1_1_0_W_v, resp_1_1_1_0_W_r; wire [43:0] resp_1_1_1_0_W_f;
    wire resp_1_1_1_0_U_v, resp_1_1_1_0_U_r; wire [43:0] resp_1_1_1_0_U_f;
    wire resp_1_1_1_0_D_v, resp_1_1_1_0_D_r; wire [43:0] resp_1_1_1_0_D_f;
    wire resp_1_1_1_0_ANA_v, resp_1_1_1_0_ANA_r; wire [43:0] resp_1_1_1_0_ANA_f;
    wire resp_1_1_1_1_N_v, resp_1_1_1_1_N_r; wire [43:0] resp_1_1_1_1_N_f;
    wire resp_1_1_1_1_S_v, resp_1_1_1_1_S_r; wire [43:0] resp_1_1_1_1_S_f;
    wire resp_1_1_1_1_W_v, resp_1_1_1_1_W_r; wire [43:0] resp_1_1_1_1_W_f;
    wire resp_1_1_1_1_U_v, resp_1_1_1_1_U_r; wire [43:0] resp_1_1_1_1_U_f;
    wire resp_1_1_1_1_D_v, resp_1_1_1_1_D_r; wire [43:0] resp_1_1_1_1_D_f;
    wire resp_1_1_1_1_KATA_v, resp_1_1_1_1_KATA_r; wire [43:0] resp_1_1_1_1_KATA_f;
    wire resp_1_1_2_0_N_v, resp_1_1_2_0_N_r; wire [43:0] resp_1_1_2_0_N_f;
    wire resp_1_1_2_0_S_v, resp_1_1_2_0_S_r; wire [43:0] resp_1_1_2_0_S_f;
    wire resp_1_1_2_0_W_v, resp_1_1_2_0_W_r; wire [43:0] resp_1_1_2_0_W_f;
    wire resp_1_1_2_0_U_v, resp_1_1_2_0_U_r; wire [43:0] resp_1_1_2_0_U_f;
    wire resp_1_1_2_0_D_v, resp_1_1_2_0_D_r; wire [43:0] resp_1_1_2_0_D_f;
    wire resp_1_1_2_0_ANA_v, resp_1_1_2_0_ANA_r; wire [43:0] resp_1_1_2_0_ANA_f;
    wire resp_1_1_2_1_N_v, resp_1_1_2_1_N_r; wire [43:0] resp_1_1_2_1_N_f;
    wire resp_1_1_2_1_S_v, resp_1_1_2_1_S_r; wire [43:0] resp_1_1_2_1_S_f;
    wire resp_1_1_2_1_W_v, resp_1_1_2_1_W_r; wire [43:0] resp_1_1_2_1_W_f;
    wire resp_1_1_2_1_U_v, resp_1_1_2_1_U_r; wire [43:0] resp_1_1_2_1_U_f;
    wire resp_1_1_2_1_D_v, resp_1_1_2_1_D_r; wire [43:0] resp_1_1_2_1_D_f;
    wire resp_1_1_2_1_KATA_v, resp_1_1_2_1_KATA_r; wire [43:0] resp_1_1_2_1_KATA_f;
    wire resp_1_1_3_0_N_v, resp_1_1_3_0_N_r; wire [43:0] resp_1_1_3_0_N_f;
    wire resp_1_1_3_0_S_v, resp_1_1_3_0_S_r; wire [43:0] resp_1_1_3_0_S_f;
    wire resp_1_1_3_0_W_v, resp_1_1_3_0_W_r; wire [43:0] resp_1_1_3_0_W_f;
    wire resp_1_1_3_0_U_v, resp_1_1_3_0_U_r; wire [43:0] resp_1_1_3_0_U_f;
    wire resp_1_1_3_0_D_v, resp_1_1_3_0_D_r; wire [43:0] resp_1_1_3_0_D_f;
    wire resp_1_1_3_0_ANA_v, resp_1_1_3_0_ANA_r; wire [43:0] resp_1_1_3_0_ANA_f;
    wire resp_1_1_3_1_N_v, resp_1_1_3_1_N_r; wire [43:0] resp_1_1_3_1_N_f;
    wire resp_1_1_3_1_S_v, resp_1_1_3_1_S_r; wire [43:0] resp_1_1_3_1_S_f;
    wire resp_1_1_3_1_W_v, resp_1_1_3_1_W_r; wire [43:0] resp_1_1_3_1_W_f;
    wire resp_1_1_3_1_U_v, resp_1_1_3_1_U_r; wire [43:0] resp_1_1_3_1_U_f;
    wire resp_1_1_3_1_D_v, resp_1_1_3_1_D_r; wire [43:0] resp_1_1_3_1_D_f;
    wire resp_1_1_3_1_KATA_v, resp_1_1_3_1_KATA_r; wire [43:0] resp_1_1_3_1_KATA_f;
    wire resp_1_1_4_0_N_v, resp_1_1_4_0_N_r; wire [43:0] resp_1_1_4_0_N_f;
    wire resp_1_1_4_0_S_v, resp_1_1_4_0_S_r; wire [43:0] resp_1_1_4_0_S_f;
    wire resp_1_1_4_0_W_v, resp_1_1_4_0_W_r; wire [43:0] resp_1_1_4_0_W_f;
    wire resp_1_1_4_0_U_v, resp_1_1_4_0_U_r; wire [43:0] resp_1_1_4_0_U_f;
    wire resp_1_1_4_0_D_v, resp_1_1_4_0_D_r; wire [43:0] resp_1_1_4_0_D_f;
    wire resp_1_1_4_0_ANA_v, resp_1_1_4_0_ANA_r; wire [43:0] resp_1_1_4_0_ANA_f;
    wire resp_1_1_4_1_N_v, resp_1_1_4_1_N_r; wire [43:0] resp_1_1_4_1_N_f;
    wire resp_1_1_4_1_S_v, resp_1_1_4_1_S_r; wire [43:0] resp_1_1_4_1_S_f;
    wire resp_1_1_4_1_W_v, resp_1_1_4_1_W_r; wire [43:0] resp_1_1_4_1_W_f;
    wire resp_1_1_4_1_U_v, resp_1_1_4_1_U_r; wire [43:0] resp_1_1_4_1_U_f;
    wire resp_1_1_4_1_D_v, resp_1_1_4_1_D_r; wire [43:0] resp_1_1_4_1_D_f;
    wire resp_1_1_4_1_KATA_v, resp_1_1_4_1_KATA_r; wire [43:0] resp_1_1_4_1_KATA_f;
    wire resp_1_1_5_0_N_v, resp_1_1_5_0_N_r; wire [43:0] resp_1_1_5_0_N_f;
    wire resp_1_1_5_0_S_v, resp_1_1_5_0_S_r; wire [43:0] resp_1_1_5_0_S_f;
    wire resp_1_1_5_0_W_v, resp_1_1_5_0_W_r; wire [43:0] resp_1_1_5_0_W_f;
    wire resp_1_1_5_0_U_v, resp_1_1_5_0_U_r; wire [43:0] resp_1_1_5_0_U_f;
    wire resp_1_1_5_0_ANA_v, resp_1_1_5_0_ANA_r; wire [43:0] resp_1_1_5_0_ANA_f;
    wire resp_1_1_5_1_N_v, resp_1_1_5_1_N_r; wire [43:0] resp_1_1_5_1_N_f;
    wire resp_1_1_5_1_S_v, resp_1_1_5_1_S_r; wire [43:0] resp_1_1_5_1_S_f;
    wire resp_1_1_5_1_W_v, resp_1_1_5_1_W_r; wire [43:0] resp_1_1_5_1_W_f;
    wire resp_1_1_5_1_U_v, resp_1_1_5_1_U_r; wire [43:0] resp_1_1_5_1_U_f;
    wire resp_1_1_5_1_KATA_v, resp_1_1_5_1_KATA_r; wire [43:0] resp_1_1_5_1_KATA_f;
    wire resp_1_2_0_0_N_v, resp_1_2_0_0_N_r; wire [43:0] resp_1_2_0_0_N_f;
    wire resp_1_2_0_0_W_v, resp_1_2_0_0_W_r; wire [43:0] resp_1_2_0_0_W_f;
    wire resp_1_2_0_0_D_v, resp_1_2_0_0_D_r; wire [43:0] resp_1_2_0_0_D_f;
    wire resp_1_2_0_0_ANA_v, resp_1_2_0_0_ANA_r; wire [43:0] resp_1_2_0_0_ANA_f;
    wire resp_1_2_0_1_N_v, resp_1_2_0_1_N_r; wire [43:0] resp_1_2_0_1_N_f;
    wire resp_1_2_0_1_W_v, resp_1_2_0_1_W_r; wire [43:0] resp_1_2_0_1_W_f;
    wire resp_1_2_0_1_D_v, resp_1_2_0_1_D_r; wire [43:0] resp_1_2_0_1_D_f;
    wire resp_1_2_0_1_KATA_v, resp_1_2_0_1_KATA_r; wire [43:0] resp_1_2_0_1_KATA_f;
    wire resp_1_2_1_0_N_v, resp_1_2_1_0_N_r; wire [43:0] resp_1_2_1_0_N_f;
    wire resp_1_2_1_0_W_v, resp_1_2_1_0_W_r; wire [43:0] resp_1_2_1_0_W_f;
    wire resp_1_2_1_0_U_v, resp_1_2_1_0_U_r; wire [43:0] resp_1_2_1_0_U_f;
    wire resp_1_2_1_0_D_v, resp_1_2_1_0_D_r; wire [43:0] resp_1_2_1_0_D_f;
    wire resp_1_2_1_0_ANA_v, resp_1_2_1_0_ANA_r; wire [43:0] resp_1_2_1_0_ANA_f;
    wire resp_1_2_1_1_N_v, resp_1_2_1_1_N_r; wire [43:0] resp_1_2_1_1_N_f;
    wire resp_1_2_1_1_W_v, resp_1_2_1_1_W_r; wire [43:0] resp_1_2_1_1_W_f;
    wire resp_1_2_1_1_U_v, resp_1_2_1_1_U_r; wire [43:0] resp_1_2_1_1_U_f;
    wire resp_1_2_1_1_D_v, resp_1_2_1_1_D_r; wire [43:0] resp_1_2_1_1_D_f;
    wire resp_1_2_1_1_KATA_v, resp_1_2_1_1_KATA_r; wire [43:0] resp_1_2_1_1_KATA_f;
    wire resp_1_2_2_0_N_v, resp_1_2_2_0_N_r; wire [43:0] resp_1_2_2_0_N_f;
    wire resp_1_2_2_0_W_v, resp_1_2_2_0_W_r; wire [43:0] resp_1_2_2_0_W_f;
    wire resp_1_2_2_0_U_v, resp_1_2_2_0_U_r; wire [43:0] resp_1_2_2_0_U_f;
    wire resp_1_2_2_0_D_v, resp_1_2_2_0_D_r; wire [43:0] resp_1_2_2_0_D_f;
    wire resp_1_2_2_0_ANA_v, resp_1_2_2_0_ANA_r; wire [43:0] resp_1_2_2_0_ANA_f;
    wire resp_1_2_2_1_N_v, resp_1_2_2_1_N_r; wire [43:0] resp_1_2_2_1_N_f;
    wire resp_1_2_2_1_W_v, resp_1_2_2_1_W_r; wire [43:0] resp_1_2_2_1_W_f;
    wire resp_1_2_2_1_U_v, resp_1_2_2_1_U_r; wire [43:0] resp_1_2_2_1_U_f;
    wire resp_1_2_2_1_D_v, resp_1_2_2_1_D_r; wire [43:0] resp_1_2_2_1_D_f;
    wire resp_1_2_2_1_KATA_v, resp_1_2_2_1_KATA_r; wire [43:0] resp_1_2_2_1_KATA_f;
    wire resp_1_2_3_0_N_v, resp_1_2_3_0_N_r; wire [43:0] resp_1_2_3_0_N_f;
    wire resp_1_2_3_0_W_v, resp_1_2_3_0_W_r; wire [43:0] resp_1_2_3_0_W_f;
    wire resp_1_2_3_0_U_v, resp_1_2_3_0_U_r; wire [43:0] resp_1_2_3_0_U_f;
    wire resp_1_2_3_0_D_v, resp_1_2_3_0_D_r; wire [43:0] resp_1_2_3_0_D_f;
    wire resp_1_2_3_0_ANA_v, resp_1_2_3_0_ANA_r; wire [43:0] resp_1_2_3_0_ANA_f;
    wire resp_1_2_3_1_N_v, resp_1_2_3_1_N_r; wire [43:0] resp_1_2_3_1_N_f;
    wire resp_1_2_3_1_W_v, resp_1_2_3_1_W_r; wire [43:0] resp_1_2_3_1_W_f;
    wire resp_1_2_3_1_U_v, resp_1_2_3_1_U_r; wire [43:0] resp_1_2_3_1_U_f;
    wire resp_1_2_3_1_D_v, resp_1_2_3_1_D_r; wire [43:0] resp_1_2_3_1_D_f;
    wire resp_1_2_3_1_KATA_v, resp_1_2_3_1_KATA_r; wire [43:0] resp_1_2_3_1_KATA_f;
    wire resp_1_2_4_0_N_v, resp_1_2_4_0_N_r; wire [43:0] resp_1_2_4_0_N_f;
    wire resp_1_2_4_0_W_v, resp_1_2_4_0_W_r; wire [43:0] resp_1_2_4_0_W_f;
    wire resp_1_2_4_0_U_v, resp_1_2_4_0_U_r; wire [43:0] resp_1_2_4_0_U_f;
    wire resp_1_2_4_0_D_v, resp_1_2_4_0_D_r; wire [43:0] resp_1_2_4_0_D_f;
    wire resp_1_2_4_0_ANA_v, resp_1_2_4_0_ANA_r; wire [43:0] resp_1_2_4_0_ANA_f;
    wire resp_1_2_4_1_N_v, resp_1_2_4_1_N_r; wire [43:0] resp_1_2_4_1_N_f;
    wire resp_1_2_4_1_W_v, resp_1_2_4_1_W_r; wire [43:0] resp_1_2_4_1_W_f;
    wire resp_1_2_4_1_U_v, resp_1_2_4_1_U_r; wire [43:0] resp_1_2_4_1_U_f;
    wire resp_1_2_4_1_D_v, resp_1_2_4_1_D_r; wire [43:0] resp_1_2_4_1_D_f;
    wire resp_1_2_4_1_KATA_v, resp_1_2_4_1_KATA_r; wire [43:0] resp_1_2_4_1_KATA_f;
    wire resp_1_2_5_0_N_v, resp_1_2_5_0_N_r; wire [43:0] resp_1_2_5_0_N_f;
    wire resp_1_2_5_0_W_v, resp_1_2_5_0_W_r; wire [43:0] resp_1_2_5_0_W_f;
    wire resp_1_2_5_0_U_v, resp_1_2_5_0_U_r; wire [43:0] resp_1_2_5_0_U_f;
    wire resp_1_2_5_0_ANA_v, resp_1_2_5_0_ANA_r; wire [43:0] resp_1_2_5_0_ANA_f;
    wire resp_1_2_5_1_N_v, resp_1_2_5_1_N_r; wire [43:0] resp_1_2_5_1_N_f;
    wire resp_1_2_5_1_W_v, resp_1_2_5_1_W_r; wire [43:0] resp_1_2_5_1_W_f;
    wire resp_1_2_5_1_U_v, resp_1_2_5_1_U_r; wire [43:0] resp_1_2_5_1_U_f;
    wire resp_1_2_5_1_KATA_v, resp_1_2_5_1_KATA_r; wire [43:0] resp_1_2_5_1_KATA_f;

    // ==================== Per-core bus + adapter wires ====================
    wire p0_bus_req, p0_bus_mem_write, p0_bus_mem_unsigned, p0_bus_grant;
    wire [31:0] p0_bus_addr, p0_bus_write_data, p0_bus_read_data;
    wire [1:0] p0_bus_mem_size;
    wire p0_req_out_valid, p0_req_out_ready, p0_resp_in_valid, p0_resp_in_ready;
    wire [91:0] p0_req_out_flit;
    wire [43:0] p0_resp_in_flit;
    wire p1_bus_req, p1_bus_mem_write, p1_bus_mem_unsigned, p1_bus_grant;
    wire [31:0] p1_bus_addr, p1_bus_write_data, p1_bus_read_data;
    wire [1:0] p1_bus_mem_size;
    wire p1_req_out_valid, p1_req_out_ready, p1_resp_in_valid, p1_resp_in_ready;
    wire [91:0] p1_req_out_flit;
    wire [43:0] p1_resp_in_flit;
    wire p2_bus_req, p2_bus_mem_write, p2_bus_mem_unsigned, p2_bus_grant;
    wire [31:0] p2_bus_addr, p2_bus_write_data, p2_bus_read_data;
    wire [1:0] p2_bus_mem_size;
    wire p2_req_out_valid, p2_req_out_ready, p2_resp_in_valid, p2_resp_in_ready;
    wire [91:0] p2_req_out_flit;
    wire [43:0] p2_resp_in_flit;
    wire p3_bus_req, p3_bus_mem_write, p3_bus_mem_unsigned, p3_bus_grant;
    wire [31:0] p3_bus_addr, p3_bus_write_data, p3_bus_read_data;
    wire [1:0] p3_bus_mem_size;
    wire p3_req_out_valid, p3_req_out_ready, p3_resp_in_valid, p3_resp_in_ready;
    wire [91:0] p3_req_out_flit;
    wire [43:0] p3_resp_in_flit;
    wire p4_bus_req, p4_bus_mem_write, p4_bus_mem_unsigned, p4_bus_grant;
    wire [31:0] p4_bus_addr, p4_bus_write_data, p4_bus_read_data;
    wire [1:0] p4_bus_mem_size;
    wire p4_req_out_valid, p4_req_out_ready, p4_resp_in_valid, p4_resp_in_ready;
    wire [91:0] p4_req_out_flit;
    wire [43:0] p4_resp_in_flit;
    wire p5_bus_req, p5_bus_mem_write, p5_bus_mem_unsigned, p5_bus_grant;
    wire [31:0] p5_bus_addr, p5_bus_write_data, p5_bus_read_data;
    wire [1:0] p5_bus_mem_size;
    wire p5_req_out_valid, p5_req_out_ready, p5_resp_in_valid, p5_resp_in_ready;
    wire [91:0] p5_req_out_flit;
    wire [43:0] p5_resp_in_flit;
    wire p6_bus_req, p6_bus_mem_write, p6_bus_mem_unsigned, p6_bus_grant;
    wire [31:0] p6_bus_addr, p6_bus_write_data, p6_bus_read_data;
    wire [1:0] p6_bus_mem_size;
    wire p6_req_out_valid, p6_req_out_ready, p6_resp_in_valid, p6_resp_in_ready;
    wire [91:0] p6_req_out_flit;
    wire [43:0] p6_resp_in_flit;
    wire p7_bus_req, p7_bus_mem_write, p7_bus_mem_unsigned, p7_bus_grant;
    wire [31:0] p7_bus_addr, p7_bus_write_data, p7_bus_read_data;
    wire [1:0] p7_bus_mem_size;
    wire p7_req_out_valid, p7_req_out_ready, p7_resp_in_valid, p7_resp_in_ready;
    wire [91:0] p7_req_out_flit;
    wire [43:0] p7_resp_in_flit;
    wire p8_bus_req, p8_bus_mem_write, p8_bus_mem_unsigned, p8_bus_grant;
    wire [31:0] p8_bus_addr, p8_bus_write_data, p8_bus_read_data;
    wire [1:0] p8_bus_mem_size;
    wire p8_req_out_valid, p8_req_out_ready, p8_resp_in_valid, p8_resp_in_ready;
    wire [91:0] p8_req_out_flit;
    wire [43:0] p8_resp_in_flit;
    wire p9_bus_req, p9_bus_mem_write, p9_bus_mem_unsigned, p9_bus_grant;
    wire [31:0] p9_bus_addr, p9_bus_write_data, p9_bus_read_data;
    wire [1:0] p9_bus_mem_size;
    wire p9_req_out_valid, p9_req_out_ready, p9_resp_in_valid, p9_resp_in_ready;
    wire [91:0] p9_req_out_flit;
    wire [43:0] p9_resp_in_flit;
    wire p10_bus_req, p10_bus_mem_write, p10_bus_mem_unsigned, p10_bus_grant;
    wire [31:0] p10_bus_addr, p10_bus_write_data, p10_bus_read_data;
    wire [1:0] p10_bus_mem_size;
    wire p10_req_out_valid, p10_req_out_ready, p10_resp_in_valid, p10_resp_in_ready;
    wire [91:0] p10_req_out_flit;
    wire [43:0] p10_resp_in_flit;
    wire p11_bus_req, p11_bus_mem_write, p11_bus_mem_unsigned, p11_bus_grant;
    wire [31:0] p11_bus_addr, p11_bus_write_data, p11_bus_read_data;
    wire [1:0] p11_bus_mem_size;
    wire p11_req_out_valid, p11_req_out_ready, p11_resp_in_valid, p11_resp_in_ready;
    wire [91:0] p11_req_out_flit;
    wire [43:0] p11_resp_in_flit;
    wire p12_bus_req, p12_bus_mem_write, p12_bus_mem_unsigned, p12_bus_grant;
    wire [31:0] p12_bus_addr, p12_bus_write_data, p12_bus_read_data;
    wire [1:0] p12_bus_mem_size;
    wire p12_req_out_valid, p12_req_out_ready, p12_resp_in_valid, p12_resp_in_ready;
    wire [91:0] p12_req_out_flit;
    wire [43:0] p12_resp_in_flit;
    wire p13_bus_req, p13_bus_mem_write, p13_bus_mem_unsigned, p13_bus_grant;
    wire [31:0] p13_bus_addr, p13_bus_write_data, p13_bus_read_data;
    wire [1:0] p13_bus_mem_size;
    wire p13_req_out_valid, p13_req_out_ready, p13_resp_in_valid, p13_resp_in_ready;
    wire [91:0] p13_req_out_flit;
    wire [43:0] p13_resp_in_flit;
    wire p14_bus_req, p14_bus_mem_write, p14_bus_mem_unsigned, p14_bus_grant;
    wire [31:0] p14_bus_addr, p14_bus_write_data, p14_bus_read_data;
    wire [1:0] p14_bus_mem_size;
    wire p14_req_out_valid, p14_req_out_ready, p14_resp_in_valid, p14_resp_in_ready;
    wire [91:0] p14_req_out_flit;
    wire [43:0] p14_resp_in_flit;
    wire p15_bus_req, p15_bus_mem_write, p15_bus_mem_unsigned, p15_bus_grant;
    wire [31:0] p15_bus_addr, p15_bus_write_data, p15_bus_read_data;
    wire [1:0] p15_bus_mem_size;
    wire p15_req_out_valid, p15_req_out_ready, p15_resp_in_valid, p15_resp_in_ready;
    wire [91:0] p15_req_out_flit;
    wire [43:0] p15_resp_in_flit;
    wire p16_bus_req, p16_bus_mem_write, p16_bus_mem_unsigned, p16_bus_grant;
    wire [31:0] p16_bus_addr, p16_bus_write_data, p16_bus_read_data;
    wire [1:0] p16_bus_mem_size;
    wire p16_req_out_valid, p16_req_out_ready, p16_resp_in_valid, p16_resp_in_ready;
    wire [91:0] p16_req_out_flit;
    wire [43:0] p16_resp_in_flit;
    wire p17_bus_req, p17_bus_mem_write, p17_bus_mem_unsigned, p17_bus_grant;
    wire [31:0] p17_bus_addr, p17_bus_write_data, p17_bus_read_data;
    wire [1:0] p17_bus_mem_size;
    wire p17_req_out_valid, p17_req_out_ready, p17_resp_in_valid, p17_resp_in_ready;
    wire [91:0] p17_req_out_flit;
    wire [43:0] p17_resp_in_flit;
    wire p18_bus_req, p18_bus_mem_write, p18_bus_mem_unsigned, p18_bus_grant;
    wire [31:0] p18_bus_addr, p18_bus_write_data, p18_bus_read_data;
    wire [1:0] p18_bus_mem_size;
    wire p18_req_out_valid, p18_req_out_ready, p18_resp_in_valid, p18_resp_in_ready;
    wire [91:0] p18_req_out_flit;
    wire [43:0] p18_resp_in_flit;
    wire p19_bus_req, p19_bus_mem_write, p19_bus_mem_unsigned, p19_bus_grant;
    wire [31:0] p19_bus_addr, p19_bus_write_data, p19_bus_read_data;
    wire [1:0] p19_bus_mem_size;
    wire p19_req_out_valid, p19_req_out_ready, p19_resp_in_valid, p19_resp_in_ready;
    wire [91:0] p19_req_out_flit;
    wire [43:0] p19_resp_in_flit;
    wire p20_bus_req, p20_bus_mem_write, p20_bus_mem_unsigned, p20_bus_grant;
    wire [31:0] p20_bus_addr, p20_bus_write_data, p20_bus_read_data;
    wire [1:0] p20_bus_mem_size;
    wire p20_req_out_valid, p20_req_out_ready, p20_resp_in_valid, p20_resp_in_ready;
    wire [91:0] p20_req_out_flit;
    wire [43:0] p20_resp_in_flit;
    wire p21_bus_req, p21_bus_mem_write, p21_bus_mem_unsigned, p21_bus_grant;
    wire [31:0] p21_bus_addr, p21_bus_write_data, p21_bus_read_data;
    wire [1:0] p21_bus_mem_size;
    wire p21_req_out_valid, p21_req_out_ready, p21_resp_in_valid, p21_resp_in_ready;
    wire [91:0] p21_req_out_flit;
    wire [43:0] p21_resp_in_flit;
    wire p22_bus_req, p22_bus_mem_write, p22_bus_mem_unsigned, p22_bus_grant;
    wire [31:0] p22_bus_addr, p22_bus_write_data, p22_bus_read_data;
    wire [1:0] p22_bus_mem_size;
    wire p22_req_out_valid, p22_req_out_ready, p22_resp_in_valid, p22_resp_in_ready;
    wire [91:0] p22_req_out_flit;
    wire [43:0] p22_resp_in_flit;
    wire p23_bus_req, p23_bus_mem_write, p23_bus_mem_unsigned, p23_bus_grant;
    wire [31:0] p23_bus_addr, p23_bus_write_data, p23_bus_read_data;
    wire [1:0] p23_bus_mem_size;
    wire p23_req_out_valid, p23_req_out_ready, p23_resp_in_valid, p23_resp_in_ready;
    wire [91:0] p23_req_out_flit;
    wire [43:0] p23_resp_in_flit;
    wire p24_bus_req, p24_bus_mem_write, p24_bus_mem_unsigned, p24_bus_grant;
    wire [31:0] p24_bus_addr, p24_bus_write_data, p24_bus_read_data;
    wire [1:0] p24_bus_mem_size;
    wire p24_req_out_valid, p24_req_out_ready, p24_resp_in_valid, p24_resp_in_ready;
    wire [91:0] p24_req_out_flit;
    wire [43:0] p24_resp_in_flit;
    wire p25_bus_req, p25_bus_mem_write, p25_bus_mem_unsigned, p25_bus_grant;
    wire [31:0] p25_bus_addr, p25_bus_write_data, p25_bus_read_data;
    wire [1:0] p25_bus_mem_size;
    wire p25_req_out_valid, p25_req_out_ready, p25_resp_in_valid, p25_resp_in_ready;
    wire [91:0] p25_req_out_flit;
    wire [43:0] p25_resp_in_flit;
    wire p26_bus_req, p26_bus_mem_write, p26_bus_mem_unsigned, p26_bus_grant;
    wire [31:0] p26_bus_addr, p26_bus_write_data, p26_bus_read_data;
    wire [1:0] p26_bus_mem_size;
    wire p26_req_out_valid, p26_req_out_ready, p26_resp_in_valid, p26_resp_in_ready;
    wire [91:0] p26_req_out_flit;
    wire [43:0] p26_resp_in_flit;
    wire p27_bus_req, p27_bus_mem_write, p27_bus_mem_unsigned, p27_bus_grant;
    wire [31:0] p27_bus_addr, p27_bus_write_data, p27_bus_read_data;
    wire [1:0] p27_bus_mem_size;
    wire p27_req_out_valid, p27_req_out_ready, p27_resp_in_valid, p27_resp_in_ready;
    wire [91:0] p27_req_out_flit;
    wire [43:0] p27_resp_in_flit;
    wire p28_bus_req, p28_bus_mem_write, p28_bus_mem_unsigned, p28_bus_grant;
    wire [31:0] p28_bus_addr, p28_bus_write_data, p28_bus_read_data;
    wire [1:0] p28_bus_mem_size;
    wire p28_req_out_valid, p28_req_out_ready, p28_resp_in_valid, p28_resp_in_ready;
    wire [91:0] p28_req_out_flit;
    wire [43:0] p28_resp_in_flit;
    wire p29_bus_req, p29_bus_mem_write, p29_bus_mem_unsigned, p29_bus_grant;
    wire [31:0] p29_bus_addr, p29_bus_write_data, p29_bus_read_data;
    wire [1:0] p29_bus_mem_size;
    wire p29_req_out_valid, p29_req_out_ready, p29_resp_in_valid, p29_resp_in_ready;
    wire [91:0] p29_req_out_flit;
    wire [43:0] p29_resp_in_flit;
    wire p30_bus_req, p30_bus_mem_write, p30_bus_mem_unsigned, p30_bus_grant;
    wire [31:0] p30_bus_addr, p30_bus_write_data, p30_bus_read_data;
    wire [1:0] p30_bus_mem_size;
    wire p30_req_out_valid, p30_req_out_ready, p30_resp_in_valid, p30_resp_in_ready;
    wire [91:0] p30_req_out_flit;
    wire [43:0] p30_resp_in_flit;
    wire p31_bus_req, p31_bus_mem_write, p31_bus_mem_unsigned, p31_bus_grant;
    wire [31:0] p31_bus_addr, p31_bus_write_data, p31_bus_read_data;
    wire [1:0] p31_bus_mem_size;
    wire p31_req_out_valid, p31_req_out_ready, p31_resp_in_valid, p31_resp_in_ready;
    wire [91:0] p31_req_out_flit;
    wire [43:0] p31_resp_in_flit;
    wire p32_bus_req, p32_bus_mem_write, p32_bus_mem_unsigned, p32_bus_grant;
    wire [31:0] p32_bus_addr, p32_bus_write_data, p32_bus_read_data;
    wire [1:0] p32_bus_mem_size;
    wire p32_req_out_valid, p32_req_out_ready, p32_resp_in_valid, p32_resp_in_ready;
    wire [91:0] p32_req_out_flit;
    wire [43:0] p32_resp_in_flit;
    wire p33_bus_req, p33_bus_mem_write, p33_bus_mem_unsigned, p33_bus_grant;
    wire [31:0] p33_bus_addr, p33_bus_write_data, p33_bus_read_data;
    wire [1:0] p33_bus_mem_size;
    wire p33_req_out_valid, p33_req_out_ready, p33_resp_in_valid, p33_resp_in_ready;
    wire [91:0] p33_req_out_flit;
    wire [43:0] p33_resp_in_flit;
    wire p34_bus_req, p34_bus_mem_write, p34_bus_mem_unsigned, p34_bus_grant;
    wire [31:0] p34_bus_addr, p34_bus_write_data, p34_bus_read_data;
    wire [1:0] p34_bus_mem_size;
    wire p34_req_out_valid, p34_req_out_ready, p34_resp_in_valid, p34_resp_in_ready;
    wire [91:0] p34_req_out_flit;
    wire [43:0] p34_resp_in_flit;
    wire p35_bus_req, p35_bus_mem_write, p35_bus_mem_unsigned, p35_bus_grant;
    wire [31:0] p35_bus_addr, p35_bus_write_data, p35_bus_read_data;
    wire [1:0] p35_bus_mem_size;
    wire p35_req_out_valid, p35_req_out_ready, p35_resp_in_valid, p35_resp_in_ready;
    wire [91:0] p35_req_out_flit;
    wire [43:0] p35_resp_in_flit;
    wire e0_bus_req, e0_bus_mem_write, e0_bus_mem_unsigned, e0_bus_grant;
    wire [31:0] e0_bus_addr, e0_bus_write_data, e0_bus_read_data;
    wire [1:0] e0_bus_mem_size;
    wire e0_req_out_valid, e0_req_out_ready, e0_resp_in_valid, e0_resp_in_ready;
    wire [91:0] e0_req_out_flit;
    wire [43:0] e0_resp_in_flit;
    wire e1_bus_req, e1_bus_mem_write, e1_bus_mem_unsigned, e1_bus_grant;
    wire [31:0] e1_bus_addr, e1_bus_write_data, e1_bus_read_data;
    wire [1:0] e1_bus_mem_size;
    wire e1_req_out_valid, e1_req_out_ready, e1_resp_in_valid, e1_resp_in_ready;
    wire [91:0] e1_req_out_flit;
    wire [43:0] e1_resp_in_flit;
    wire e2_bus_req, e2_bus_mem_write, e2_bus_mem_unsigned, e2_bus_grant;
    wire [31:0] e2_bus_addr, e2_bus_write_data, e2_bus_read_data;
    wire [1:0] e2_bus_mem_size;
    wire e2_req_out_valid, e2_req_out_ready, e2_resp_in_valid, e2_resp_in_ready;
    wire [91:0] e2_req_out_flit;
    wire [43:0] e2_resp_in_flit;
    wire e3_bus_req, e3_bus_mem_write, e3_bus_mem_unsigned, e3_bus_grant;
    wire [31:0] e3_bus_addr, e3_bus_write_data, e3_bus_read_data;
    wire [1:0] e3_bus_mem_size;
    wire e3_req_out_valid, e3_req_out_ready, e3_resp_in_valid, e3_resp_in_ready;
    wire [91:0] e3_req_out_flit;
    wire [43:0] e3_resp_in_flit;
    wire e4_bus_req, e4_bus_mem_write, e4_bus_mem_unsigned, e4_bus_grant;
    wire [31:0] e4_bus_addr, e4_bus_write_data, e4_bus_read_data;
    wire [1:0] e4_bus_mem_size;
    wire e4_req_out_valid, e4_req_out_ready, e4_resp_in_valid, e4_resp_in_ready;
    wire [91:0] e4_req_out_flit;
    wire [43:0] e4_resp_in_flit;
    wire e5_bus_req, e5_bus_mem_write, e5_bus_mem_unsigned, e5_bus_grant;
    wire [31:0] e5_bus_addr, e5_bus_write_data, e5_bus_read_data;
    wire [1:0] e5_bus_mem_size;
    wire e5_req_out_valid, e5_req_out_ready, e5_resp_in_valid, e5_resp_in_ready;
    wire [91:0] e5_req_out_flit;
    wire [43:0] e5_resp_in_flit;
    wire e6_bus_req, e6_bus_mem_write, e6_bus_mem_unsigned, e6_bus_grant;
    wire [31:0] e6_bus_addr, e6_bus_write_data, e6_bus_read_data;
    wire [1:0] e6_bus_mem_size;
    wire e6_req_out_valid, e6_req_out_ready, e6_resp_in_valid, e6_resp_in_ready;
    wire [91:0] e6_req_out_flit;
    wire [43:0] e6_resp_in_flit;
    wire e7_bus_req, e7_bus_mem_write, e7_bus_mem_unsigned, e7_bus_grant;
    wire [31:0] e7_bus_addr, e7_bus_write_data, e7_bus_read_data;
    wire [1:0] e7_bus_mem_size;
    wire e7_req_out_valid, e7_req_out_ready, e7_resp_in_valid, e7_resp_in_ready;
    wire [91:0] e7_req_out_flit;
    wire [43:0] e7_resp_in_flit;
    wire e8_bus_req, e8_bus_mem_write, e8_bus_mem_unsigned, e8_bus_grant;
    wire [31:0] e8_bus_addr, e8_bus_write_data, e8_bus_read_data;
    wire [1:0] e8_bus_mem_size;
    wire e8_req_out_valid, e8_req_out_ready, e8_resp_in_valid, e8_resp_in_ready;
    wire [91:0] e8_req_out_flit;
    wire [43:0] e8_resp_in_flit;
    wire e9_bus_req, e9_bus_mem_write, e9_bus_mem_unsigned, e9_bus_grant;
    wire [31:0] e9_bus_addr, e9_bus_write_data, e9_bus_read_data;
    wire [1:0] e9_bus_mem_size;
    wire e9_req_out_valid, e9_req_out_ready, e9_resp_in_valid, e9_resp_in_ready;
    wire [91:0] e9_req_out_flit;
    wire [43:0] e9_resp_in_flit;
    wire e10_bus_req, e10_bus_mem_write, e10_bus_mem_unsigned, e10_bus_grant;
    wire [31:0] e10_bus_addr, e10_bus_write_data, e10_bus_read_data;
    wire [1:0] e10_bus_mem_size;
    wire e10_req_out_valid, e10_req_out_ready, e10_resp_in_valid, e10_resp_in_ready;
    wire [91:0] e10_req_out_flit;
    wire [43:0] e10_resp_in_flit;
    wire e11_bus_req, e11_bus_mem_write, e11_bus_mem_unsigned, e11_bus_grant;
    wire [31:0] e11_bus_addr, e11_bus_write_data, e11_bus_read_data;
    wire [1:0] e11_bus_mem_size;
    wire e11_req_out_valid, e11_req_out_ready, e11_resp_in_valid, e11_resp_in_ready;
    wire [91:0] e11_req_out_flit;
    wire [43:0] e11_resp_in_flit;
    wire e12_bus_req, e12_bus_mem_write, e12_bus_mem_unsigned, e12_bus_grant;
    wire [31:0] e12_bus_addr, e12_bus_write_data, e12_bus_read_data;
    wire [1:0] e12_bus_mem_size;
    wire e12_req_out_valid, e12_req_out_ready, e12_resp_in_valid, e12_resp_in_ready;
    wire [91:0] e12_req_out_flit;
    wire [43:0] e12_resp_in_flit;
    wire e13_bus_req, e13_bus_mem_write, e13_bus_mem_unsigned, e13_bus_grant;
    wire [31:0] e13_bus_addr, e13_bus_write_data, e13_bus_read_data;
    wire [1:0] e13_bus_mem_size;
    wire e13_req_out_valid, e13_req_out_ready, e13_resp_in_valid, e13_resp_in_ready;
    wire [91:0] e13_req_out_flit;
    wire [43:0] e13_resp_in_flit;
    wire e14_bus_req, e14_bus_mem_write, e14_bus_mem_unsigned, e14_bus_grant;
    wire [31:0] e14_bus_addr, e14_bus_write_data, e14_bus_read_data;
    wire [1:0] e14_bus_mem_size;
    wire e14_req_out_valid, e14_req_out_ready, e14_resp_in_valid, e14_resp_in_ready;
    wire [91:0] e14_req_out_flit;
    wire [43:0] e14_resp_in_flit;
    wire e15_bus_req, e15_bus_mem_write, e15_bus_mem_unsigned, e15_bus_grant;
    wire [31:0] e15_bus_addr, e15_bus_write_data, e15_bus_read_data;
    wire [1:0] e15_bus_mem_size;
    wire e15_req_out_valid, e15_req_out_ready, e15_resp_in_valid, e15_resp_in_ready;
    wire [91:0] e15_req_out_flit;
    wire [43:0] e15_resp_in_flit;
    wire e16_bus_req, e16_bus_mem_write, e16_bus_mem_unsigned, e16_bus_grant;
    wire [31:0] e16_bus_addr, e16_bus_write_data, e16_bus_read_data;
    wire [1:0] e16_bus_mem_size;
    wire e16_req_out_valid, e16_req_out_ready, e16_resp_in_valid, e16_resp_in_ready;
    wire [91:0] e16_req_out_flit;
    wire [43:0] e16_resp_in_flit;
    wire e17_bus_req, e17_bus_mem_write, e17_bus_mem_unsigned, e17_bus_grant;
    wire [31:0] e17_bus_addr, e17_bus_write_data, e17_bus_read_data;
    wire [1:0] e17_bus_mem_size;
    wire e17_req_out_valid, e17_req_out_ready, e17_resp_in_valid, e17_resp_in_ready;
    wire [91:0] e17_req_out_flit;
    wire [43:0] e17_resp_in_flit;
    wire e18_bus_req, e18_bus_mem_write, e18_bus_mem_unsigned, e18_bus_grant;
    wire [31:0] e18_bus_addr, e18_bus_write_data, e18_bus_read_data;
    wire [1:0] e18_bus_mem_size;
    wire e18_req_out_valid, e18_req_out_ready, e18_resp_in_valid, e18_resp_in_ready;
    wire [91:0] e18_req_out_flit;
    wire [43:0] e18_resp_in_flit;
    wire e19_bus_req, e19_bus_mem_write, e19_bus_mem_unsigned, e19_bus_grant;
    wire [31:0] e19_bus_addr, e19_bus_write_data, e19_bus_read_data;
    wire [1:0] e19_bus_mem_size;
    wire e19_req_out_valid, e19_req_out_ready, e19_resp_in_valid, e19_resp_in_ready;
    wire [91:0] e19_req_out_flit;
    wire [43:0] e19_resp_in_flit;
    wire e20_bus_req, e20_bus_mem_write, e20_bus_mem_unsigned, e20_bus_grant;
    wire [31:0] e20_bus_addr, e20_bus_write_data, e20_bus_read_data;
    wire [1:0] e20_bus_mem_size;
    wire e20_req_out_valid, e20_req_out_ready, e20_resp_in_valid, e20_resp_in_ready;
    wire [91:0] e20_req_out_flit;
    wire [43:0] e20_resp_in_flit;
    wire e21_bus_req, e21_bus_mem_write, e21_bus_mem_unsigned, e21_bus_grant;
    wire [31:0] e21_bus_addr, e21_bus_write_data, e21_bus_read_data;
    wire [1:0] e21_bus_mem_size;
    wire e21_req_out_valid, e21_req_out_ready, e21_resp_in_valid, e21_resp_in_ready;
    wire [91:0] e21_req_out_flit;
    wire [43:0] e21_resp_in_flit;
    wire e22_bus_req, e22_bus_mem_write, e22_bus_mem_unsigned, e22_bus_grant;
    wire [31:0] e22_bus_addr, e22_bus_write_data, e22_bus_read_data;
    wire [1:0] e22_bus_mem_size;
    wire e22_req_out_valid, e22_req_out_ready, e22_resp_in_valid, e22_resp_in_ready;
    wire [91:0] e22_req_out_flit;
    wire [43:0] e22_resp_in_flit;
    wire e23_bus_req, e23_bus_mem_write, e23_bus_mem_unsigned, e23_bus_grant;
    wire [31:0] e23_bus_addr, e23_bus_write_data, e23_bus_read_data;
    wire [1:0] e23_bus_mem_size;
    wire e23_req_out_valid, e23_req_out_ready, e23_resp_in_valid, e23_resp_in_ready;
    wire [91:0] e23_req_out_flit;
    wire [43:0] e23_resp_in_flit;
    wire e24_bus_req, e24_bus_mem_write, e24_bus_mem_unsigned, e24_bus_grant;
    wire [31:0] e24_bus_addr, e24_bus_write_data, e24_bus_read_data;
    wire [1:0] e24_bus_mem_size;
    wire e24_req_out_valid, e24_req_out_ready, e24_resp_in_valid, e24_resp_in_ready;
    wire [91:0] e24_req_out_flit;
    wire [43:0] e24_resp_in_flit;
    wire e25_bus_req, e25_bus_mem_write, e25_bus_mem_unsigned, e25_bus_grant;
    wire [31:0] e25_bus_addr, e25_bus_write_data, e25_bus_read_data;
    wire [1:0] e25_bus_mem_size;
    wire e25_req_out_valid, e25_req_out_ready, e25_resp_in_valid, e25_resp_in_ready;
    wire [91:0] e25_req_out_flit;
    wire [43:0] e25_resp_in_flit;
    wire e26_bus_req, e26_bus_mem_write, e26_bus_mem_unsigned, e26_bus_grant;
    wire [31:0] e26_bus_addr, e26_bus_write_data, e26_bus_read_data;
    wire [1:0] e26_bus_mem_size;
    wire e26_req_out_valid, e26_req_out_ready, e26_resp_in_valid, e26_resp_in_ready;
    wire [91:0] e26_req_out_flit;
    wire [43:0] e26_resp_in_flit;
    wire e27_bus_req, e27_bus_mem_write, e27_bus_mem_unsigned, e27_bus_grant;
    wire [31:0] e27_bus_addr, e27_bus_write_data, e27_bus_read_data;
    wire [1:0] e27_bus_mem_size;
    wire e27_req_out_valid, e27_req_out_ready, e27_resp_in_valid, e27_resp_in_ready;
    wire [91:0] e27_req_out_flit;
    wire [43:0] e27_resp_in_flit;
    wire e28_bus_req, e28_bus_mem_write, e28_bus_mem_unsigned, e28_bus_grant;
    wire [31:0] e28_bus_addr, e28_bus_write_data, e28_bus_read_data;
    wire [1:0] e28_bus_mem_size;
    wire e28_req_out_valid, e28_req_out_ready, e28_resp_in_valid, e28_resp_in_ready;
    wire [91:0] e28_req_out_flit;
    wire [43:0] e28_resp_in_flit;
    wire e29_bus_req, e29_bus_mem_write, e29_bus_mem_unsigned, e29_bus_grant;
    wire [31:0] e29_bus_addr, e29_bus_write_data, e29_bus_read_data;
    wire [1:0] e29_bus_mem_size;
    wire e29_req_out_valid, e29_req_out_ready, e29_resp_in_valid, e29_resp_in_ready;
    wire [91:0] e29_req_out_flit;
    wire [43:0] e29_resp_in_flit;
    wire e30_bus_req, e30_bus_mem_write, e30_bus_mem_unsigned, e30_bus_grant;
    wire [31:0] e30_bus_addr, e30_bus_write_data, e30_bus_read_data;
    wire [1:0] e30_bus_mem_size;
    wire e30_req_out_valid, e30_req_out_ready, e30_resp_in_valid, e30_resp_in_ready;
    wire [91:0] e30_req_out_flit;
    wire [43:0] e30_resp_in_flit;
    wire e31_bus_req, e31_bus_mem_write, e31_bus_mem_unsigned, e31_bus_grant;
    wire [31:0] e31_bus_addr, e31_bus_write_data, e31_bus_read_data;
    wire [1:0] e31_bus_mem_size;
    wire e31_req_out_valid, e31_req_out_ready, e31_resp_in_valid, e31_resp_in_ready;
    wire [91:0] e31_req_out_flit;
    wire [43:0] e31_resp_in_flit;
    wire e32_bus_req, e32_bus_mem_write, e32_bus_mem_unsigned, e32_bus_grant;
    wire [31:0] e32_bus_addr, e32_bus_write_data, e32_bus_read_data;
    wire [1:0] e32_bus_mem_size;
    wire e32_req_out_valid, e32_req_out_ready, e32_resp_in_valid, e32_resp_in_ready;
    wire [91:0] e32_req_out_flit;
    wire [43:0] e32_resp_in_flit;
    wire e33_bus_req, e33_bus_mem_write, e33_bus_mem_unsigned, e33_bus_grant;
    wire [31:0] e33_bus_addr, e33_bus_write_data, e33_bus_read_data;
    wire [1:0] e33_bus_mem_size;
    wire e33_req_out_valid, e33_req_out_ready, e33_resp_in_valid, e33_resp_in_ready;
    wire [91:0] e33_req_out_flit;
    wire [43:0] e33_resp_in_flit;
    wire e34_bus_req, e34_bus_mem_write, e34_bus_mem_unsigned, e34_bus_grant;
    wire [31:0] e34_bus_addr, e34_bus_write_data, e34_bus_read_data;
    wire [1:0] e34_bus_mem_size;
    wire e34_req_out_valid, e34_req_out_ready, e34_resp_in_valid, e34_resp_in_ready;
    wire [91:0] e34_req_out_flit;
    wire [43:0] e34_resp_in_flit;
    wire mem_req_in_valid, mem_req_in_ready, mem_resp_out_valid, mem_resp_out_ready;
    wire [91:0] mem_req_in_flit;
    wire [43:0] mem_resp_out_flit;

    // ==================== Routers (2 networks x 72 grid positions) ====================
    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r0_0_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_0_0_N_v), .s_in_flit(req_0_1_0_0_N_f), .s_in_ready(req_0_1_0_0_N_r),
        .s_out_valid(req_0_0_0_0_S_v), .s_out_flit(req_0_0_0_0_S_f), .s_out_ready(req_0_0_0_0_S_r),
        .e_in_valid(req_1_0_0_0_W_v), .e_in_flit(req_1_0_0_0_W_f), .e_in_ready(req_1_0_0_0_W_r),
        .e_out_valid(req_0_0_0_0_E_v), .e_out_flit(req_0_0_0_0_E_f), .e_out_ready(req_0_0_0_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_0_1_0_U_v), .d_in_flit(req_0_0_1_0_U_f), .d_in_ready(req_0_0_1_0_U_r),
        .d_out_valid(req_0_0_0_0_D_v), .d_out_flit(req_0_0_0_0_D_f), .d_out_ready(req_0_0_0_0_D_r),
        .ana_in_valid(req_0_0_0_1_KATA_v), .ana_in_flit(req_0_0_0_1_KATA_f), .ana_in_ready(req_0_0_0_1_KATA_r),
        .ana_out_valid(req_0_0_0_0_ANA_v), .ana_out_flit(req_0_0_0_0_ANA_f), .ana_out_ready(req_0_0_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p0_req_out_valid), .l_in_flit(p0_req_out_flit), .l_in_ready(p0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r0_0_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_0_0_N_v), .s_in_flit(resp_0_1_0_0_N_f), .s_in_ready(resp_0_1_0_0_N_r),
        .s_out_valid(resp_0_0_0_0_S_v), .s_out_flit(resp_0_0_0_0_S_f), .s_out_ready(resp_0_0_0_0_S_r),
        .e_in_valid(resp_1_0_0_0_W_v), .e_in_flit(resp_1_0_0_0_W_f), .e_in_ready(resp_1_0_0_0_W_r),
        .e_out_valid(resp_0_0_0_0_E_v), .e_out_flit(resp_0_0_0_0_E_f), .e_out_ready(resp_0_0_0_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_0_1_0_U_v), .d_in_flit(resp_0_0_1_0_U_f), .d_in_ready(resp_0_0_1_0_U_r),
        .d_out_valid(resp_0_0_0_0_D_v), .d_out_flit(resp_0_0_0_0_D_f), .d_out_ready(resp_0_0_0_0_D_r),
        .ana_in_valid(resp_0_0_0_1_KATA_v), .ana_in_flit(resp_0_0_0_1_KATA_f), .ana_in_ready(resp_0_0_0_1_KATA_r),
        .ana_out_valid(resp_0_0_0_0_ANA_v), .ana_out_flit(resp_0_0_0_0_ANA_f), .ana_out_ready(resp_0_0_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p0_resp_in_valid), .l_out_flit(p0_resp_in_flit), .l_out_ready(p0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(1)) req_r0_0_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_0_1_N_v), .s_in_flit(req_0_1_0_1_N_f), .s_in_ready(req_0_1_0_1_N_r),
        .s_out_valid(req_0_0_0_1_S_v), .s_out_flit(req_0_0_0_1_S_f), .s_out_ready(req_0_0_0_1_S_r),
        .e_in_valid(req_1_0_0_1_W_v), .e_in_flit(req_1_0_0_1_W_f), .e_in_ready(req_1_0_0_1_W_r),
        .e_out_valid(req_0_0_0_1_E_v), .e_out_flit(req_0_0_0_1_E_f), .e_out_ready(req_0_0_0_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_0_1_1_U_v), .d_in_flit(req_0_0_1_1_U_f), .d_in_ready(req_0_0_1_1_U_r),
        .d_out_valid(req_0_0_0_1_D_v), .d_out_flit(req_0_0_0_1_D_f), .d_out_ready(req_0_0_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_0_0_0_ANA_v), .kata_in_flit(req_0_0_0_0_ANA_f), .kata_in_ready(req_0_0_0_0_ANA_r),
        .kata_out_valid(req_0_0_0_1_KATA_v), .kata_out_flit(req_0_0_0_1_KATA_f), .kata_out_ready(req_0_0_0_1_KATA_r),
        .l_in_valid(p1_req_out_valid), .l_in_flit(p1_req_out_flit), .l_in_ready(p1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(1)) resp_r0_0_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_0_1_N_v), .s_in_flit(resp_0_1_0_1_N_f), .s_in_ready(resp_0_1_0_1_N_r),
        .s_out_valid(resp_0_0_0_1_S_v), .s_out_flit(resp_0_0_0_1_S_f), .s_out_ready(resp_0_0_0_1_S_r),
        .e_in_valid(resp_1_0_0_1_W_v), .e_in_flit(resp_1_0_0_1_W_f), .e_in_ready(resp_1_0_0_1_W_r),
        .e_out_valid(resp_0_0_0_1_E_v), .e_out_flit(resp_0_0_0_1_E_f), .e_out_ready(resp_0_0_0_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_0_1_1_U_v), .d_in_flit(resp_0_0_1_1_U_f), .d_in_ready(resp_0_0_1_1_U_r),
        .d_out_valid(resp_0_0_0_1_D_v), .d_out_flit(resp_0_0_0_1_D_f), .d_out_ready(resp_0_0_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_0_0_0_ANA_v), .kata_in_flit(resp_0_0_0_0_ANA_f), .kata_in_ready(resp_0_0_0_0_ANA_r),
        .kata_out_valid(resp_0_0_0_1_KATA_v), .kata_out_flit(resp_0_0_0_1_KATA_f), .kata_out_ready(resp_0_0_0_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p1_resp_in_valid), .l_out_flit(p1_resp_in_flit), .l_out_ready(p1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(1), .MY_W(0)) req_r0_0_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_1_0_N_v), .s_in_flit(req_0_1_1_0_N_f), .s_in_ready(req_0_1_1_0_N_r),
        .s_out_valid(req_0_0_1_0_S_v), .s_out_flit(req_0_0_1_0_S_f), .s_out_ready(req_0_0_1_0_S_r),
        .e_in_valid(req_1_0_1_0_W_v), .e_in_flit(req_1_0_1_0_W_f), .e_in_ready(req_1_0_1_0_W_r),
        .e_out_valid(req_0_0_1_0_E_v), .e_out_flit(req_0_0_1_0_E_f), .e_out_ready(req_0_0_1_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_0_0_D_v), .u_in_flit(req_0_0_0_0_D_f), .u_in_ready(req_0_0_0_0_D_r),
        .u_out_valid(req_0_0_1_0_U_v), .u_out_flit(req_0_0_1_0_U_f), .u_out_ready(req_0_0_1_0_U_r),
        .d_in_valid(req_0_0_2_0_U_v), .d_in_flit(req_0_0_2_0_U_f), .d_in_ready(req_0_0_2_0_U_r),
        .d_out_valid(req_0_0_1_0_D_v), .d_out_flit(req_0_0_1_0_D_f), .d_out_ready(req_0_0_1_0_D_r),
        .ana_in_valid(req_0_0_1_1_KATA_v), .ana_in_flit(req_0_0_1_1_KATA_f), .ana_in_ready(req_0_0_1_1_KATA_r),
        .ana_out_valid(req_0_0_1_0_ANA_v), .ana_out_flit(req_0_0_1_0_ANA_f), .ana_out_ready(req_0_0_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p2_req_out_valid), .l_in_flit(p2_req_out_flit), .l_in_ready(p2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(1), .MY_W(0)) resp_r0_0_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_1_0_N_v), .s_in_flit(resp_0_1_1_0_N_f), .s_in_ready(resp_0_1_1_0_N_r),
        .s_out_valid(resp_0_0_1_0_S_v), .s_out_flit(resp_0_0_1_0_S_f), .s_out_ready(resp_0_0_1_0_S_r),
        .e_in_valid(resp_1_0_1_0_W_v), .e_in_flit(resp_1_0_1_0_W_f), .e_in_ready(resp_1_0_1_0_W_r),
        .e_out_valid(resp_0_0_1_0_E_v), .e_out_flit(resp_0_0_1_0_E_f), .e_out_ready(resp_0_0_1_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_0_0_D_v), .u_in_flit(resp_0_0_0_0_D_f), .u_in_ready(resp_0_0_0_0_D_r),
        .u_out_valid(resp_0_0_1_0_U_v), .u_out_flit(resp_0_0_1_0_U_f), .u_out_ready(resp_0_0_1_0_U_r),
        .d_in_valid(resp_0_0_2_0_U_v), .d_in_flit(resp_0_0_2_0_U_f), .d_in_ready(resp_0_0_2_0_U_r),
        .d_out_valid(resp_0_0_1_0_D_v), .d_out_flit(resp_0_0_1_0_D_f), .d_out_ready(resp_0_0_1_0_D_r),
        .ana_in_valid(resp_0_0_1_1_KATA_v), .ana_in_flit(resp_0_0_1_1_KATA_f), .ana_in_ready(resp_0_0_1_1_KATA_r),
        .ana_out_valid(resp_0_0_1_0_ANA_v), .ana_out_flit(resp_0_0_1_0_ANA_f), .ana_out_ready(resp_0_0_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p2_resp_in_valid), .l_out_flit(p2_resp_in_flit), .l_out_ready(p2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(1), .MY_W(1)) req_r0_0_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_1_1_N_v), .s_in_flit(req_0_1_1_1_N_f), .s_in_ready(req_0_1_1_1_N_r),
        .s_out_valid(req_0_0_1_1_S_v), .s_out_flit(req_0_0_1_1_S_f), .s_out_ready(req_0_0_1_1_S_r),
        .e_in_valid(req_1_0_1_1_W_v), .e_in_flit(req_1_0_1_1_W_f), .e_in_ready(req_1_0_1_1_W_r),
        .e_out_valid(req_0_0_1_1_E_v), .e_out_flit(req_0_0_1_1_E_f), .e_out_ready(req_0_0_1_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_0_1_D_v), .u_in_flit(req_0_0_0_1_D_f), .u_in_ready(req_0_0_0_1_D_r),
        .u_out_valid(req_0_0_1_1_U_v), .u_out_flit(req_0_0_1_1_U_f), .u_out_ready(req_0_0_1_1_U_r),
        .d_in_valid(req_0_0_2_1_U_v), .d_in_flit(req_0_0_2_1_U_f), .d_in_ready(req_0_0_2_1_U_r),
        .d_out_valid(req_0_0_1_1_D_v), .d_out_flit(req_0_0_1_1_D_f), .d_out_ready(req_0_0_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_0_1_0_ANA_v), .kata_in_flit(req_0_0_1_0_ANA_f), .kata_in_ready(req_0_0_1_0_ANA_r),
        .kata_out_valid(req_0_0_1_1_KATA_v), .kata_out_flit(req_0_0_1_1_KATA_f), .kata_out_ready(req_0_0_1_1_KATA_r),
        .l_in_valid(p3_req_out_valid), .l_in_flit(p3_req_out_flit), .l_in_ready(p3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(1), .MY_W(1)) resp_r0_0_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_1_1_N_v), .s_in_flit(resp_0_1_1_1_N_f), .s_in_ready(resp_0_1_1_1_N_r),
        .s_out_valid(resp_0_0_1_1_S_v), .s_out_flit(resp_0_0_1_1_S_f), .s_out_ready(resp_0_0_1_1_S_r),
        .e_in_valid(resp_1_0_1_1_W_v), .e_in_flit(resp_1_0_1_1_W_f), .e_in_ready(resp_1_0_1_1_W_r),
        .e_out_valid(resp_0_0_1_1_E_v), .e_out_flit(resp_0_0_1_1_E_f), .e_out_ready(resp_0_0_1_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_0_1_D_v), .u_in_flit(resp_0_0_0_1_D_f), .u_in_ready(resp_0_0_0_1_D_r),
        .u_out_valid(resp_0_0_1_1_U_v), .u_out_flit(resp_0_0_1_1_U_f), .u_out_ready(resp_0_0_1_1_U_r),
        .d_in_valid(resp_0_0_2_1_U_v), .d_in_flit(resp_0_0_2_1_U_f), .d_in_ready(resp_0_0_2_1_U_r),
        .d_out_valid(resp_0_0_1_1_D_v), .d_out_flit(resp_0_0_1_1_D_f), .d_out_ready(resp_0_0_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_0_1_0_ANA_v), .kata_in_flit(resp_0_0_1_0_ANA_f), .kata_in_ready(resp_0_0_1_0_ANA_r),
        .kata_out_valid(resp_0_0_1_1_KATA_v), .kata_out_flit(resp_0_0_1_1_KATA_f), .kata_out_ready(resp_0_0_1_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p3_resp_in_valid), .l_out_flit(p3_resp_in_flit), .l_out_ready(p3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(2), .MY_W(0)) req_r0_0_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_2_0_N_v), .s_in_flit(req_0_1_2_0_N_f), .s_in_ready(req_0_1_2_0_N_r),
        .s_out_valid(req_0_0_2_0_S_v), .s_out_flit(req_0_0_2_0_S_f), .s_out_ready(req_0_0_2_0_S_r),
        .e_in_valid(req_1_0_2_0_W_v), .e_in_flit(req_1_0_2_0_W_f), .e_in_ready(req_1_0_2_0_W_r),
        .e_out_valid(req_0_0_2_0_E_v), .e_out_flit(req_0_0_2_0_E_f), .e_out_ready(req_0_0_2_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_1_0_D_v), .u_in_flit(req_0_0_1_0_D_f), .u_in_ready(req_0_0_1_0_D_r),
        .u_out_valid(req_0_0_2_0_U_v), .u_out_flit(req_0_0_2_0_U_f), .u_out_ready(req_0_0_2_0_U_r),
        .d_in_valid(req_0_0_3_0_U_v), .d_in_flit(req_0_0_3_0_U_f), .d_in_ready(req_0_0_3_0_U_r),
        .d_out_valid(req_0_0_2_0_D_v), .d_out_flit(req_0_0_2_0_D_f), .d_out_ready(req_0_0_2_0_D_r),
        .ana_in_valid(req_0_0_2_1_KATA_v), .ana_in_flit(req_0_0_2_1_KATA_f), .ana_in_ready(req_0_0_2_1_KATA_r),
        .ana_out_valid(req_0_0_2_0_ANA_v), .ana_out_flit(req_0_0_2_0_ANA_f), .ana_out_ready(req_0_0_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p4_req_out_valid), .l_in_flit(p4_req_out_flit), .l_in_ready(p4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(2), .MY_W(0)) resp_r0_0_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_2_0_N_v), .s_in_flit(resp_0_1_2_0_N_f), .s_in_ready(resp_0_1_2_0_N_r),
        .s_out_valid(resp_0_0_2_0_S_v), .s_out_flit(resp_0_0_2_0_S_f), .s_out_ready(resp_0_0_2_0_S_r),
        .e_in_valid(resp_1_0_2_0_W_v), .e_in_flit(resp_1_0_2_0_W_f), .e_in_ready(resp_1_0_2_0_W_r),
        .e_out_valid(resp_0_0_2_0_E_v), .e_out_flit(resp_0_0_2_0_E_f), .e_out_ready(resp_0_0_2_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_1_0_D_v), .u_in_flit(resp_0_0_1_0_D_f), .u_in_ready(resp_0_0_1_0_D_r),
        .u_out_valid(resp_0_0_2_0_U_v), .u_out_flit(resp_0_0_2_0_U_f), .u_out_ready(resp_0_0_2_0_U_r),
        .d_in_valid(resp_0_0_3_0_U_v), .d_in_flit(resp_0_0_3_0_U_f), .d_in_ready(resp_0_0_3_0_U_r),
        .d_out_valid(resp_0_0_2_0_D_v), .d_out_flit(resp_0_0_2_0_D_f), .d_out_ready(resp_0_0_2_0_D_r),
        .ana_in_valid(resp_0_0_2_1_KATA_v), .ana_in_flit(resp_0_0_2_1_KATA_f), .ana_in_ready(resp_0_0_2_1_KATA_r),
        .ana_out_valid(resp_0_0_2_0_ANA_v), .ana_out_flit(resp_0_0_2_0_ANA_f), .ana_out_ready(resp_0_0_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p4_resp_in_valid), .l_out_flit(p4_resp_in_flit), .l_out_ready(p4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(2), .MY_W(1)) req_r0_0_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_2_1_N_v), .s_in_flit(req_0_1_2_1_N_f), .s_in_ready(req_0_1_2_1_N_r),
        .s_out_valid(req_0_0_2_1_S_v), .s_out_flit(req_0_0_2_1_S_f), .s_out_ready(req_0_0_2_1_S_r),
        .e_in_valid(req_1_0_2_1_W_v), .e_in_flit(req_1_0_2_1_W_f), .e_in_ready(req_1_0_2_1_W_r),
        .e_out_valid(req_0_0_2_1_E_v), .e_out_flit(req_0_0_2_1_E_f), .e_out_ready(req_0_0_2_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_1_1_D_v), .u_in_flit(req_0_0_1_1_D_f), .u_in_ready(req_0_0_1_1_D_r),
        .u_out_valid(req_0_0_2_1_U_v), .u_out_flit(req_0_0_2_1_U_f), .u_out_ready(req_0_0_2_1_U_r),
        .d_in_valid(req_0_0_3_1_U_v), .d_in_flit(req_0_0_3_1_U_f), .d_in_ready(req_0_0_3_1_U_r),
        .d_out_valid(req_0_0_2_1_D_v), .d_out_flit(req_0_0_2_1_D_f), .d_out_ready(req_0_0_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_0_2_0_ANA_v), .kata_in_flit(req_0_0_2_0_ANA_f), .kata_in_ready(req_0_0_2_0_ANA_r),
        .kata_out_valid(req_0_0_2_1_KATA_v), .kata_out_flit(req_0_0_2_1_KATA_f), .kata_out_ready(req_0_0_2_1_KATA_r),
        .l_in_valid(p5_req_out_valid), .l_in_flit(p5_req_out_flit), .l_in_ready(p5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(2), .MY_W(1)) resp_r0_0_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_2_1_N_v), .s_in_flit(resp_0_1_2_1_N_f), .s_in_ready(resp_0_1_2_1_N_r),
        .s_out_valid(resp_0_0_2_1_S_v), .s_out_flit(resp_0_0_2_1_S_f), .s_out_ready(resp_0_0_2_1_S_r),
        .e_in_valid(resp_1_0_2_1_W_v), .e_in_flit(resp_1_0_2_1_W_f), .e_in_ready(resp_1_0_2_1_W_r),
        .e_out_valid(resp_0_0_2_1_E_v), .e_out_flit(resp_0_0_2_1_E_f), .e_out_ready(resp_0_0_2_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_1_1_D_v), .u_in_flit(resp_0_0_1_1_D_f), .u_in_ready(resp_0_0_1_1_D_r),
        .u_out_valid(resp_0_0_2_1_U_v), .u_out_flit(resp_0_0_2_1_U_f), .u_out_ready(resp_0_0_2_1_U_r),
        .d_in_valid(resp_0_0_3_1_U_v), .d_in_flit(resp_0_0_3_1_U_f), .d_in_ready(resp_0_0_3_1_U_r),
        .d_out_valid(resp_0_0_2_1_D_v), .d_out_flit(resp_0_0_2_1_D_f), .d_out_ready(resp_0_0_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_0_2_0_ANA_v), .kata_in_flit(resp_0_0_2_0_ANA_f), .kata_in_ready(resp_0_0_2_0_ANA_r),
        .kata_out_valid(resp_0_0_2_1_KATA_v), .kata_out_flit(resp_0_0_2_1_KATA_f), .kata_out_ready(resp_0_0_2_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p5_resp_in_valid), .l_out_flit(p5_resp_in_flit), .l_out_ready(p5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(3), .MY_W(0)) req_r0_0_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_3_0_N_v), .s_in_flit(req_0_1_3_0_N_f), .s_in_ready(req_0_1_3_0_N_r),
        .s_out_valid(req_0_0_3_0_S_v), .s_out_flit(req_0_0_3_0_S_f), .s_out_ready(req_0_0_3_0_S_r),
        .e_in_valid(req_1_0_3_0_W_v), .e_in_flit(req_1_0_3_0_W_f), .e_in_ready(req_1_0_3_0_W_r),
        .e_out_valid(req_0_0_3_0_E_v), .e_out_flit(req_0_0_3_0_E_f), .e_out_ready(req_0_0_3_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_2_0_D_v), .u_in_flit(req_0_0_2_0_D_f), .u_in_ready(req_0_0_2_0_D_r),
        .u_out_valid(req_0_0_3_0_U_v), .u_out_flit(req_0_0_3_0_U_f), .u_out_ready(req_0_0_3_0_U_r),
        .d_in_valid(req_0_0_4_0_U_v), .d_in_flit(req_0_0_4_0_U_f), .d_in_ready(req_0_0_4_0_U_r),
        .d_out_valid(req_0_0_3_0_D_v), .d_out_flit(req_0_0_3_0_D_f), .d_out_ready(req_0_0_3_0_D_r),
        .ana_in_valid(req_0_0_3_1_KATA_v), .ana_in_flit(req_0_0_3_1_KATA_f), .ana_in_ready(req_0_0_3_1_KATA_r),
        .ana_out_valid(req_0_0_3_0_ANA_v), .ana_out_flit(req_0_0_3_0_ANA_f), .ana_out_ready(req_0_0_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p6_req_out_valid), .l_in_flit(p6_req_out_flit), .l_in_ready(p6_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(3), .MY_W(0)) resp_r0_0_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_3_0_N_v), .s_in_flit(resp_0_1_3_0_N_f), .s_in_ready(resp_0_1_3_0_N_r),
        .s_out_valid(resp_0_0_3_0_S_v), .s_out_flit(resp_0_0_3_0_S_f), .s_out_ready(resp_0_0_3_0_S_r),
        .e_in_valid(resp_1_0_3_0_W_v), .e_in_flit(resp_1_0_3_0_W_f), .e_in_ready(resp_1_0_3_0_W_r),
        .e_out_valid(resp_0_0_3_0_E_v), .e_out_flit(resp_0_0_3_0_E_f), .e_out_ready(resp_0_0_3_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_2_0_D_v), .u_in_flit(resp_0_0_2_0_D_f), .u_in_ready(resp_0_0_2_0_D_r),
        .u_out_valid(resp_0_0_3_0_U_v), .u_out_flit(resp_0_0_3_0_U_f), .u_out_ready(resp_0_0_3_0_U_r),
        .d_in_valid(resp_0_0_4_0_U_v), .d_in_flit(resp_0_0_4_0_U_f), .d_in_ready(resp_0_0_4_0_U_r),
        .d_out_valid(resp_0_0_3_0_D_v), .d_out_flit(resp_0_0_3_0_D_f), .d_out_ready(resp_0_0_3_0_D_r),
        .ana_in_valid(resp_0_0_3_1_KATA_v), .ana_in_flit(resp_0_0_3_1_KATA_f), .ana_in_ready(resp_0_0_3_1_KATA_r),
        .ana_out_valid(resp_0_0_3_0_ANA_v), .ana_out_flit(resp_0_0_3_0_ANA_f), .ana_out_ready(resp_0_0_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p6_resp_in_valid), .l_out_flit(p6_resp_in_flit), .l_out_ready(p6_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(3), .MY_W(1)) req_r0_0_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_3_1_N_v), .s_in_flit(req_0_1_3_1_N_f), .s_in_ready(req_0_1_3_1_N_r),
        .s_out_valid(req_0_0_3_1_S_v), .s_out_flit(req_0_0_3_1_S_f), .s_out_ready(req_0_0_3_1_S_r),
        .e_in_valid(req_1_0_3_1_W_v), .e_in_flit(req_1_0_3_1_W_f), .e_in_ready(req_1_0_3_1_W_r),
        .e_out_valid(req_0_0_3_1_E_v), .e_out_flit(req_0_0_3_1_E_f), .e_out_ready(req_0_0_3_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_2_1_D_v), .u_in_flit(req_0_0_2_1_D_f), .u_in_ready(req_0_0_2_1_D_r),
        .u_out_valid(req_0_0_3_1_U_v), .u_out_flit(req_0_0_3_1_U_f), .u_out_ready(req_0_0_3_1_U_r),
        .d_in_valid(req_0_0_4_1_U_v), .d_in_flit(req_0_0_4_1_U_f), .d_in_ready(req_0_0_4_1_U_r),
        .d_out_valid(req_0_0_3_1_D_v), .d_out_flit(req_0_0_3_1_D_f), .d_out_ready(req_0_0_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_0_3_0_ANA_v), .kata_in_flit(req_0_0_3_0_ANA_f), .kata_in_ready(req_0_0_3_0_ANA_r),
        .kata_out_valid(req_0_0_3_1_KATA_v), .kata_out_flit(req_0_0_3_1_KATA_f), .kata_out_ready(req_0_0_3_1_KATA_r),
        .l_in_valid(p7_req_out_valid), .l_in_flit(p7_req_out_flit), .l_in_ready(p7_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(3), .MY_W(1)) resp_r0_0_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_3_1_N_v), .s_in_flit(resp_0_1_3_1_N_f), .s_in_ready(resp_0_1_3_1_N_r),
        .s_out_valid(resp_0_0_3_1_S_v), .s_out_flit(resp_0_0_3_1_S_f), .s_out_ready(resp_0_0_3_1_S_r),
        .e_in_valid(resp_1_0_3_1_W_v), .e_in_flit(resp_1_0_3_1_W_f), .e_in_ready(resp_1_0_3_1_W_r),
        .e_out_valid(resp_0_0_3_1_E_v), .e_out_flit(resp_0_0_3_1_E_f), .e_out_ready(resp_0_0_3_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_2_1_D_v), .u_in_flit(resp_0_0_2_1_D_f), .u_in_ready(resp_0_0_2_1_D_r),
        .u_out_valid(resp_0_0_3_1_U_v), .u_out_flit(resp_0_0_3_1_U_f), .u_out_ready(resp_0_0_3_1_U_r),
        .d_in_valid(resp_0_0_4_1_U_v), .d_in_flit(resp_0_0_4_1_U_f), .d_in_ready(resp_0_0_4_1_U_r),
        .d_out_valid(resp_0_0_3_1_D_v), .d_out_flit(resp_0_0_3_1_D_f), .d_out_ready(resp_0_0_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_0_3_0_ANA_v), .kata_in_flit(resp_0_0_3_0_ANA_f), .kata_in_ready(resp_0_0_3_0_ANA_r),
        .kata_out_valid(resp_0_0_3_1_KATA_v), .kata_out_flit(resp_0_0_3_1_KATA_f), .kata_out_ready(resp_0_0_3_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p7_resp_in_valid), .l_out_flit(p7_resp_in_flit), .l_out_ready(p7_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(4), .MY_W(0)) req_r0_0_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_4_0_N_v), .s_in_flit(req_0_1_4_0_N_f), .s_in_ready(req_0_1_4_0_N_r),
        .s_out_valid(req_0_0_4_0_S_v), .s_out_flit(req_0_0_4_0_S_f), .s_out_ready(req_0_0_4_0_S_r),
        .e_in_valid(req_1_0_4_0_W_v), .e_in_flit(req_1_0_4_0_W_f), .e_in_ready(req_1_0_4_0_W_r),
        .e_out_valid(req_0_0_4_0_E_v), .e_out_flit(req_0_0_4_0_E_f), .e_out_ready(req_0_0_4_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_3_0_D_v), .u_in_flit(req_0_0_3_0_D_f), .u_in_ready(req_0_0_3_0_D_r),
        .u_out_valid(req_0_0_4_0_U_v), .u_out_flit(req_0_0_4_0_U_f), .u_out_ready(req_0_0_4_0_U_r),
        .d_in_valid(req_0_0_5_0_U_v), .d_in_flit(req_0_0_5_0_U_f), .d_in_ready(req_0_0_5_0_U_r),
        .d_out_valid(req_0_0_4_0_D_v), .d_out_flit(req_0_0_4_0_D_f), .d_out_ready(req_0_0_4_0_D_r),
        .ana_in_valid(req_0_0_4_1_KATA_v), .ana_in_flit(req_0_0_4_1_KATA_f), .ana_in_ready(req_0_0_4_1_KATA_r),
        .ana_out_valid(req_0_0_4_0_ANA_v), .ana_out_flit(req_0_0_4_0_ANA_f), .ana_out_ready(req_0_0_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p8_req_out_valid), .l_in_flit(p8_req_out_flit), .l_in_ready(p8_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(4), .MY_W(0)) resp_r0_0_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_4_0_N_v), .s_in_flit(resp_0_1_4_0_N_f), .s_in_ready(resp_0_1_4_0_N_r),
        .s_out_valid(resp_0_0_4_0_S_v), .s_out_flit(resp_0_0_4_0_S_f), .s_out_ready(resp_0_0_4_0_S_r),
        .e_in_valid(resp_1_0_4_0_W_v), .e_in_flit(resp_1_0_4_0_W_f), .e_in_ready(resp_1_0_4_0_W_r),
        .e_out_valid(resp_0_0_4_0_E_v), .e_out_flit(resp_0_0_4_0_E_f), .e_out_ready(resp_0_0_4_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_3_0_D_v), .u_in_flit(resp_0_0_3_0_D_f), .u_in_ready(resp_0_0_3_0_D_r),
        .u_out_valid(resp_0_0_4_0_U_v), .u_out_flit(resp_0_0_4_0_U_f), .u_out_ready(resp_0_0_4_0_U_r),
        .d_in_valid(resp_0_0_5_0_U_v), .d_in_flit(resp_0_0_5_0_U_f), .d_in_ready(resp_0_0_5_0_U_r),
        .d_out_valid(resp_0_0_4_0_D_v), .d_out_flit(resp_0_0_4_0_D_f), .d_out_ready(resp_0_0_4_0_D_r),
        .ana_in_valid(resp_0_0_4_1_KATA_v), .ana_in_flit(resp_0_0_4_1_KATA_f), .ana_in_ready(resp_0_0_4_1_KATA_r),
        .ana_out_valid(resp_0_0_4_0_ANA_v), .ana_out_flit(resp_0_0_4_0_ANA_f), .ana_out_ready(resp_0_0_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p8_resp_in_valid), .l_out_flit(p8_resp_in_flit), .l_out_ready(p8_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(4), .MY_W(1)) req_r0_0_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_4_1_N_v), .s_in_flit(req_0_1_4_1_N_f), .s_in_ready(req_0_1_4_1_N_r),
        .s_out_valid(req_0_0_4_1_S_v), .s_out_flit(req_0_0_4_1_S_f), .s_out_ready(req_0_0_4_1_S_r),
        .e_in_valid(req_1_0_4_1_W_v), .e_in_flit(req_1_0_4_1_W_f), .e_in_ready(req_1_0_4_1_W_r),
        .e_out_valid(req_0_0_4_1_E_v), .e_out_flit(req_0_0_4_1_E_f), .e_out_ready(req_0_0_4_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_3_1_D_v), .u_in_flit(req_0_0_3_1_D_f), .u_in_ready(req_0_0_3_1_D_r),
        .u_out_valid(req_0_0_4_1_U_v), .u_out_flit(req_0_0_4_1_U_f), .u_out_ready(req_0_0_4_1_U_r),
        .d_in_valid(req_0_0_5_1_U_v), .d_in_flit(req_0_0_5_1_U_f), .d_in_ready(req_0_0_5_1_U_r),
        .d_out_valid(req_0_0_4_1_D_v), .d_out_flit(req_0_0_4_1_D_f), .d_out_ready(req_0_0_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_0_4_0_ANA_v), .kata_in_flit(req_0_0_4_0_ANA_f), .kata_in_ready(req_0_0_4_0_ANA_r),
        .kata_out_valid(req_0_0_4_1_KATA_v), .kata_out_flit(req_0_0_4_1_KATA_f), .kata_out_ready(req_0_0_4_1_KATA_r),
        .l_in_valid(p9_req_out_valid), .l_in_flit(p9_req_out_flit), .l_in_ready(p9_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(4), .MY_W(1)) resp_r0_0_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_4_1_N_v), .s_in_flit(resp_0_1_4_1_N_f), .s_in_ready(resp_0_1_4_1_N_r),
        .s_out_valid(resp_0_0_4_1_S_v), .s_out_flit(resp_0_0_4_1_S_f), .s_out_ready(resp_0_0_4_1_S_r),
        .e_in_valid(resp_1_0_4_1_W_v), .e_in_flit(resp_1_0_4_1_W_f), .e_in_ready(resp_1_0_4_1_W_r),
        .e_out_valid(resp_0_0_4_1_E_v), .e_out_flit(resp_0_0_4_1_E_f), .e_out_ready(resp_0_0_4_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_3_1_D_v), .u_in_flit(resp_0_0_3_1_D_f), .u_in_ready(resp_0_0_3_1_D_r),
        .u_out_valid(resp_0_0_4_1_U_v), .u_out_flit(resp_0_0_4_1_U_f), .u_out_ready(resp_0_0_4_1_U_r),
        .d_in_valid(resp_0_0_5_1_U_v), .d_in_flit(resp_0_0_5_1_U_f), .d_in_ready(resp_0_0_5_1_U_r),
        .d_out_valid(resp_0_0_4_1_D_v), .d_out_flit(resp_0_0_4_1_D_f), .d_out_ready(resp_0_0_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_0_4_0_ANA_v), .kata_in_flit(resp_0_0_4_0_ANA_f), .kata_in_ready(resp_0_0_4_0_ANA_r),
        .kata_out_valid(resp_0_0_4_1_KATA_v), .kata_out_flit(resp_0_0_4_1_KATA_f), .kata_out_ready(resp_0_0_4_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p9_resp_in_valid), .l_out_flit(p9_resp_in_flit), .l_out_ready(p9_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(5), .MY_W(0)) req_r0_0_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_5_0_N_v), .s_in_flit(req_0_1_5_0_N_f), .s_in_ready(req_0_1_5_0_N_r),
        .s_out_valid(req_0_0_5_0_S_v), .s_out_flit(req_0_0_5_0_S_f), .s_out_ready(req_0_0_5_0_S_r),
        .e_in_valid(req_1_0_5_0_W_v), .e_in_flit(req_1_0_5_0_W_f), .e_in_ready(req_1_0_5_0_W_r),
        .e_out_valid(req_0_0_5_0_E_v), .e_out_flit(req_0_0_5_0_E_f), .e_out_ready(req_0_0_5_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_4_0_D_v), .u_in_flit(req_0_0_4_0_D_f), .u_in_ready(req_0_0_4_0_D_r),
        .u_out_valid(req_0_0_5_0_U_v), .u_out_flit(req_0_0_5_0_U_f), .u_out_ready(req_0_0_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(req_0_0_5_1_KATA_v), .ana_in_flit(req_0_0_5_1_KATA_f), .ana_in_ready(req_0_0_5_1_KATA_r),
        .ana_out_valid(req_0_0_5_0_ANA_v), .ana_out_flit(req_0_0_5_0_ANA_f), .ana_out_ready(req_0_0_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p10_req_out_valid), .l_in_flit(p10_req_out_flit), .l_in_ready(p10_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(5), .MY_W(0)) resp_r0_0_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_5_0_N_v), .s_in_flit(resp_0_1_5_0_N_f), .s_in_ready(resp_0_1_5_0_N_r),
        .s_out_valid(resp_0_0_5_0_S_v), .s_out_flit(resp_0_0_5_0_S_f), .s_out_ready(resp_0_0_5_0_S_r),
        .e_in_valid(resp_1_0_5_0_W_v), .e_in_flit(resp_1_0_5_0_W_f), .e_in_ready(resp_1_0_5_0_W_r),
        .e_out_valid(resp_0_0_5_0_E_v), .e_out_flit(resp_0_0_5_0_E_f), .e_out_ready(resp_0_0_5_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_4_0_D_v), .u_in_flit(resp_0_0_4_0_D_f), .u_in_ready(resp_0_0_4_0_D_r),
        .u_out_valid(resp_0_0_5_0_U_v), .u_out_flit(resp_0_0_5_0_U_f), .u_out_ready(resp_0_0_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(resp_0_0_5_1_KATA_v), .ana_in_flit(resp_0_0_5_1_KATA_f), .ana_in_ready(resp_0_0_5_1_KATA_r),
        .ana_out_valid(resp_0_0_5_0_ANA_v), .ana_out_flit(resp_0_0_5_0_ANA_f), .ana_out_ready(resp_0_0_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p10_resp_in_valid), .l_out_flit(p10_resp_in_flit), .l_out_ready(p10_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(5), .MY_W(1)) req_r0_0_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_0_1_5_1_N_v), .s_in_flit(req_0_1_5_1_N_f), .s_in_ready(req_0_1_5_1_N_r),
        .s_out_valid(req_0_0_5_1_S_v), .s_out_flit(req_0_0_5_1_S_f), .s_out_ready(req_0_0_5_1_S_r),
        .e_in_valid(req_1_0_5_1_W_v), .e_in_flit(req_1_0_5_1_W_f), .e_in_ready(req_1_0_5_1_W_r),
        .e_out_valid(req_0_0_5_1_E_v), .e_out_flit(req_0_0_5_1_E_f), .e_out_ready(req_0_0_5_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_4_1_D_v), .u_in_flit(req_0_0_4_1_D_f), .u_in_ready(req_0_0_4_1_D_r),
        .u_out_valid(req_0_0_5_1_U_v), .u_out_flit(req_0_0_5_1_U_f), .u_out_ready(req_0_0_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_0_5_0_ANA_v), .kata_in_flit(req_0_0_5_0_ANA_f), .kata_in_ready(req_0_0_5_0_ANA_r),
        .kata_out_valid(req_0_0_5_1_KATA_v), .kata_out_flit(req_0_0_5_1_KATA_f), .kata_out_ready(req_0_0_5_1_KATA_r),
        .l_in_valid(p11_req_out_valid), .l_in_flit(p11_req_out_flit), .l_in_ready(p11_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(5), .MY_W(1)) resp_r0_0_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_0_1_5_1_N_v), .s_in_flit(resp_0_1_5_1_N_f), .s_in_ready(resp_0_1_5_1_N_r),
        .s_out_valid(resp_0_0_5_1_S_v), .s_out_flit(resp_0_0_5_1_S_f), .s_out_ready(resp_0_0_5_1_S_r),
        .e_in_valid(resp_1_0_5_1_W_v), .e_in_flit(resp_1_0_5_1_W_f), .e_in_ready(resp_1_0_5_1_W_r),
        .e_out_valid(resp_0_0_5_1_E_v), .e_out_flit(resp_0_0_5_1_E_f), .e_out_ready(resp_0_0_5_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_4_1_D_v), .u_in_flit(resp_0_0_4_1_D_f), .u_in_ready(resp_0_0_4_1_D_r),
        .u_out_valid(resp_0_0_5_1_U_v), .u_out_flit(resp_0_0_5_1_U_f), .u_out_ready(resp_0_0_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_0_5_0_ANA_v), .kata_in_flit(resp_0_0_5_0_ANA_f), .kata_in_ready(resp_0_0_5_0_ANA_r),
        .kata_out_valid(resp_0_0_5_1_KATA_v), .kata_out_flit(resp_0_0_5_1_KATA_f), .kata_out_ready(resp_0_0_5_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p11_resp_in_valid), .l_out_flit(p11_resp_in_flit), .l_out_ready(p11_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(0)) req_r0_1_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_0_0_S_v), .n_in_flit(req_0_0_0_0_S_f), .n_in_ready(req_0_0_0_0_S_r),
        .n_out_valid(req_0_1_0_0_N_v), .n_out_flit(req_0_1_0_0_N_f), .n_out_ready(req_0_1_0_0_N_r),
        .s_in_valid(req_0_2_0_0_N_v), .s_in_flit(req_0_2_0_0_N_f), .s_in_ready(req_0_2_0_0_N_r),
        .s_out_valid(req_0_1_0_0_S_v), .s_out_flit(req_0_1_0_0_S_f), .s_out_ready(req_0_1_0_0_S_r),
        .e_in_valid(req_1_1_0_0_W_v), .e_in_flit(req_1_1_0_0_W_f), .e_in_ready(req_1_1_0_0_W_r),
        .e_out_valid(req_0_1_0_0_E_v), .e_out_flit(req_0_1_0_0_E_f), .e_out_ready(req_0_1_0_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_1_1_0_U_v), .d_in_flit(req_0_1_1_0_U_f), .d_in_ready(req_0_1_1_0_U_r),
        .d_out_valid(req_0_1_0_0_D_v), .d_out_flit(req_0_1_0_0_D_f), .d_out_ready(req_0_1_0_0_D_r),
        .ana_in_valid(req_0_1_0_1_KATA_v), .ana_in_flit(req_0_1_0_1_KATA_f), .ana_in_ready(req_0_1_0_1_KATA_r),
        .ana_out_valid(req_0_1_0_0_ANA_v), .ana_out_flit(req_0_1_0_0_ANA_f), .ana_out_ready(req_0_1_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p12_req_out_valid), .l_in_flit(p12_req_out_flit), .l_in_ready(p12_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(0)) resp_r0_1_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_0_0_S_v), .n_in_flit(resp_0_0_0_0_S_f), .n_in_ready(resp_0_0_0_0_S_r),
        .n_out_valid(resp_0_1_0_0_N_v), .n_out_flit(resp_0_1_0_0_N_f), .n_out_ready(resp_0_1_0_0_N_r),
        .s_in_valid(resp_0_2_0_0_N_v), .s_in_flit(resp_0_2_0_0_N_f), .s_in_ready(resp_0_2_0_0_N_r),
        .s_out_valid(resp_0_1_0_0_S_v), .s_out_flit(resp_0_1_0_0_S_f), .s_out_ready(resp_0_1_0_0_S_r),
        .e_in_valid(resp_1_1_0_0_W_v), .e_in_flit(resp_1_1_0_0_W_f), .e_in_ready(resp_1_1_0_0_W_r),
        .e_out_valid(resp_0_1_0_0_E_v), .e_out_flit(resp_0_1_0_0_E_f), .e_out_ready(resp_0_1_0_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_1_1_0_U_v), .d_in_flit(resp_0_1_1_0_U_f), .d_in_ready(resp_0_1_1_0_U_r),
        .d_out_valid(resp_0_1_0_0_D_v), .d_out_flit(resp_0_1_0_0_D_f), .d_out_ready(resp_0_1_0_0_D_r),
        .ana_in_valid(resp_0_1_0_1_KATA_v), .ana_in_flit(resp_0_1_0_1_KATA_f), .ana_in_ready(resp_0_1_0_1_KATA_r),
        .ana_out_valid(resp_0_1_0_0_ANA_v), .ana_out_flit(resp_0_1_0_0_ANA_f), .ana_out_ready(resp_0_1_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p12_resp_in_valid), .l_out_flit(p12_resp_in_flit), .l_out_ready(p12_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(1)) req_r0_1_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_0_1_S_v), .n_in_flit(req_0_0_0_1_S_f), .n_in_ready(req_0_0_0_1_S_r),
        .n_out_valid(req_0_1_0_1_N_v), .n_out_flit(req_0_1_0_1_N_f), .n_out_ready(req_0_1_0_1_N_r),
        .s_in_valid(req_0_2_0_1_N_v), .s_in_flit(req_0_2_0_1_N_f), .s_in_ready(req_0_2_0_1_N_r),
        .s_out_valid(req_0_1_0_1_S_v), .s_out_flit(req_0_1_0_1_S_f), .s_out_ready(req_0_1_0_1_S_r),
        .e_in_valid(req_1_1_0_1_W_v), .e_in_flit(req_1_1_0_1_W_f), .e_in_ready(req_1_1_0_1_W_r),
        .e_out_valid(req_0_1_0_1_E_v), .e_out_flit(req_0_1_0_1_E_f), .e_out_ready(req_0_1_0_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_1_1_1_U_v), .d_in_flit(req_0_1_1_1_U_f), .d_in_ready(req_0_1_1_1_U_r),
        .d_out_valid(req_0_1_0_1_D_v), .d_out_flit(req_0_1_0_1_D_f), .d_out_ready(req_0_1_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_1_0_0_ANA_v), .kata_in_flit(req_0_1_0_0_ANA_f), .kata_in_ready(req_0_1_0_0_ANA_r),
        .kata_out_valid(req_0_1_0_1_KATA_v), .kata_out_flit(req_0_1_0_1_KATA_f), .kata_out_ready(req_0_1_0_1_KATA_r),
        .l_in_valid(p13_req_out_valid), .l_in_flit(p13_req_out_flit), .l_in_ready(p13_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(1)) resp_r0_1_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_0_1_S_v), .n_in_flit(resp_0_0_0_1_S_f), .n_in_ready(resp_0_0_0_1_S_r),
        .n_out_valid(resp_0_1_0_1_N_v), .n_out_flit(resp_0_1_0_1_N_f), .n_out_ready(resp_0_1_0_1_N_r),
        .s_in_valid(resp_0_2_0_1_N_v), .s_in_flit(resp_0_2_0_1_N_f), .s_in_ready(resp_0_2_0_1_N_r),
        .s_out_valid(resp_0_1_0_1_S_v), .s_out_flit(resp_0_1_0_1_S_f), .s_out_ready(resp_0_1_0_1_S_r),
        .e_in_valid(resp_1_1_0_1_W_v), .e_in_flit(resp_1_1_0_1_W_f), .e_in_ready(resp_1_1_0_1_W_r),
        .e_out_valid(resp_0_1_0_1_E_v), .e_out_flit(resp_0_1_0_1_E_f), .e_out_ready(resp_0_1_0_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_1_1_1_U_v), .d_in_flit(resp_0_1_1_1_U_f), .d_in_ready(resp_0_1_1_1_U_r),
        .d_out_valid(resp_0_1_0_1_D_v), .d_out_flit(resp_0_1_0_1_D_f), .d_out_ready(resp_0_1_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_1_0_0_ANA_v), .kata_in_flit(resp_0_1_0_0_ANA_f), .kata_in_ready(resp_0_1_0_0_ANA_r),
        .kata_out_valid(resp_0_1_0_1_KATA_v), .kata_out_flit(resp_0_1_0_1_KATA_f), .kata_out_ready(resp_0_1_0_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p13_resp_in_valid), .l_out_flit(p13_resp_in_flit), .l_out_ready(p13_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(1), .MY_W(0)) req_r0_1_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_1_0_S_v), .n_in_flit(req_0_0_1_0_S_f), .n_in_ready(req_0_0_1_0_S_r),
        .n_out_valid(req_0_1_1_0_N_v), .n_out_flit(req_0_1_1_0_N_f), .n_out_ready(req_0_1_1_0_N_r),
        .s_in_valid(req_0_2_1_0_N_v), .s_in_flit(req_0_2_1_0_N_f), .s_in_ready(req_0_2_1_0_N_r),
        .s_out_valid(req_0_1_1_0_S_v), .s_out_flit(req_0_1_1_0_S_f), .s_out_ready(req_0_1_1_0_S_r),
        .e_in_valid(req_1_1_1_0_W_v), .e_in_flit(req_1_1_1_0_W_f), .e_in_ready(req_1_1_1_0_W_r),
        .e_out_valid(req_0_1_1_0_E_v), .e_out_flit(req_0_1_1_0_E_f), .e_out_ready(req_0_1_1_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_0_0_D_v), .u_in_flit(req_0_1_0_0_D_f), .u_in_ready(req_0_1_0_0_D_r),
        .u_out_valid(req_0_1_1_0_U_v), .u_out_flit(req_0_1_1_0_U_f), .u_out_ready(req_0_1_1_0_U_r),
        .d_in_valid(req_0_1_2_0_U_v), .d_in_flit(req_0_1_2_0_U_f), .d_in_ready(req_0_1_2_0_U_r),
        .d_out_valid(req_0_1_1_0_D_v), .d_out_flit(req_0_1_1_0_D_f), .d_out_ready(req_0_1_1_0_D_r),
        .ana_in_valid(req_0_1_1_1_KATA_v), .ana_in_flit(req_0_1_1_1_KATA_f), .ana_in_ready(req_0_1_1_1_KATA_r),
        .ana_out_valid(req_0_1_1_0_ANA_v), .ana_out_flit(req_0_1_1_0_ANA_f), .ana_out_ready(req_0_1_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p14_req_out_valid), .l_in_flit(p14_req_out_flit), .l_in_ready(p14_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(1), .MY_W(0)) resp_r0_1_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_1_0_S_v), .n_in_flit(resp_0_0_1_0_S_f), .n_in_ready(resp_0_0_1_0_S_r),
        .n_out_valid(resp_0_1_1_0_N_v), .n_out_flit(resp_0_1_1_0_N_f), .n_out_ready(resp_0_1_1_0_N_r),
        .s_in_valid(resp_0_2_1_0_N_v), .s_in_flit(resp_0_2_1_0_N_f), .s_in_ready(resp_0_2_1_0_N_r),
        .s_out_valid(resp_0_1_1_0_S_v), .s_out_flit(resp_0_1_1_0_S_f), .s_out_ready(resp_0_1_1_0_S_r),
        .e_in_valid(resp_1_1_1_0_W_v), .e_in_flit(resp_1_1_1_0_W_f), .e_in_ready(resp_1_1_1_0_W_r),
        .e_out_valid(resp_0_1_1_0_E_v), .e_out_flit(resp_0_1_1_0_E_f), .e_out_ready(resp_0_1_1_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_0_0_D_v), .u_in_flit(resp_0_1_0_0_D_f), .u_in_ready(resp_0_1_0_0_D_r),
        .u_out_valid(resp_0_1_1_0_U_v), .u_out_flit(resp_0_1_1_0_U_f), .u_out_ready(resp_0_1_1_0_U_r),
        .d_in_valid(resp_0_1_2_0_U_v), .d_in_flit(resp_0_1_2_0_U_f), .d_in_ready(resp_0_1_2_0_U_r),
        .d_out_valid(resp_0_1_1_0_D_v), .d_out_flit(resp_0_1_1_0_D_f), .d_out_ready(resp_0_1_1_0_D_r),
        .ana_in_valid(resp_0_1_1_1_KATA_v), .ana_in_flit(resp_0_1_1_1_KATA_f), .ana_in_ready(resp_0_1_1_1_KATA_r),
        .ana_out_valid(resp_0_1_1_0_ANA_v), .ana_out_flit(resp_0_1_1_0_ANA_f), .ana_out_ready(resp_0_1_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p14_resp_in_valid), .l_out_flit(p14_resp_in_flit), .l_out_ready(p14_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(1), .MY_W(1)) req_r0_1_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_1_1_S_v), .n_in_flit(req_0_0_1_1_S_f), .n_in_ready(req_0_0_1_1_S_r),
        .n_out_valid(req_0_1_1_1_N_v), .n_out_flit(req_0_1_1_1_N_f), .n_out_ready(req_0_1_1_1_N_r),
        .s_in_valid(req_0_2_1_1_N_v), .s_in_flit(req_0_2_1_1_N_f), .s_in_ready(req_0_2_1_1_N_r),
        .s_out_valid(req_0_1_1_1_S_v), .s_out_flit(req_0_1_1_1_S_f), .s_out_ready(req_0_1_1_1_S_r),
        .e_in_valid(req_1_1_1_1_W_v), .e_in_flit(req_1_1_1_1_W_f), .e_in_ready(req_1_1_1_1_W_r),
        .e_out_valid(req_0_1_1_1_E_v), .e_out_flit(req_0_1_1_1_E_f), .e_out_ready(req_0_1_1_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_0_1_D_v), .u_in_flit(req_0_1_0_1_D_f), .u_in_ready(req_0_1_0_1_D_r),
        .u_out_valid(req_0_1_1_1_U_v), .u_out_flit(req_0_1_1_1_U_f), .u_out_ready(req_0_1_1_1_U_r),
        .d_in_valid(req_0_1_2_1_U_v), .d_in_flit(req_0_1_2_1_U_f), .d_in_ready(req_0_1_2_1_U_r),
        .d_out_valid(req_0_1_1_1_D_v), .d_out_flit(req_0_1_1_1_D_f), .d_out_ready(req_0_1_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_1_1_0_ANA_v), .kata_in_flit(req_0_1_1_0_ANA_f), .kata_in_ready(req_0_1_1_0_ANA_r),
        .kata_out_valid(req_0_1_1_1_KATA_v), .kata_out_flit(req_0_1_1_1_KATA_f), .kata_out_ready(req_0_1_1_1_KATA_r),
        .l_in_valid(p15_req_out_valid), .l_in_flit(p15_req_out_flit), .l_in_ready(p15_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(1), .MY_W(1)) resp_r0_1_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_1_1_S_v), .n_in_flit(resp_0_0_1_1_S_f), .n_in_ready(resp_0_0_1_1_S_r),
        .n_out_valid(resp_0_1_1_1_N_v), .n_out_flit(resp_0_1_1_1_N_f), .n_out_ready(resp_0_1_1_1_N_r),
        .s_in_valid(resp_0_2_1_1_N_v), .s_in_flit(resp_0_2_1_1_N_f), .s_in_ready(resp_0_2_1_1_N_r),
        .s_out_valid(resp_0_1_1_1_S_v), .s_out_flit(resp_0_1_1_1_S_f), .s_out_ready(resp_0_1_1_1_S_r),
        .e_in_valid(resp_1_1_1_1_W_v), .e_in_flit(resp_1_1_1_1_W_f), .e_in_ready(resp_1_1_1_1_W_r),
        .e_out_valid(resp_0_1_1_1_E_v), .e_out_flit(resp_0_1_1_1_E_f), .e_out_ready(resp_0_1_1_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_0_1_D_v), .u_in_flit(resp_0_1_0_1_D_f), .u_in_ready(resp_0_1_0_1_D_r),
        .u_out_valid(resp_0_1_1_1_U_v), .u_out_flit(resp_0_1_1_1_U_f), .u_out_ready(resp_0_1_1_1_U_r),
        .d_in_valid(resp_0_1_2_1_U_v), .d_in_flit(resp_0_1_2_1_U_f), .d_in_ready(resp_0_1_2_1_U_r),
        .d_out_valid(resp_0_1_1_1_D_v), .d_out_flit(resp_0_1_1_1_D_f), .d_out_ready(resp_0_1_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_1_1_0_ANA_v), .kata_in_flit(resp_0_1_1_0_ANA_f), .kata_in_ready(resp_0_1_1_0_ANA_r),
        .kata_out_valid(resp_0_1_1_1_KATA_v), .kata_out_flit(resp_0_1_1_1_KATA_f), .kata_out_ready(resp_0_1_1_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p15_resp_in_valid), .l_out_flit(p15_resp_in_flit), .l_out_ready(p15_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(2), .MY_W(0)) req_r0_1_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_2_0_S_v), .n_in_flit(req_0_0_2_0_S_f), .n_in_ready(req_0_0_2_0_S_r),
        .n_out_valid(req_0_1_2_0_N_v), .n_out_flit(req_0_1_2_0_N_f), .n_out_ready(req_0_1_2_0_N_r),
        .s_in_valid(req_0_2_2_0_N_v), .s_in_flit(req_0_2_2_0_N_f), .s_in_ready(req_0_2_2_0_N_r),
        .s_out_valid(req_0_1_2_0_S_v), .s_out_flit(req_0_1_2_0_S_f), .s_out_ready(req_0_1_2_0_S_r),
        .e_in_valid(req_1_1_2_0_W_v), .e_in_flit(req_1_1_2_0_W_f), .e_in_ready(req_1_1_2_0_W_r),
        .e_out_valid(req_0_1_2_0_E_v), .e_out_flit(req_0_1_2_0_E_f), .e_out_ready(req_0_1_2_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_1_0_D_v), .u_in_flit(req_0_1_1_0_D_f), .u_in_ready(req_0_1_1_0_D_r),
        .u_out_valid(req_0_1_2_0_U_v), .u_out_flit(req_0_1_2_0_U_f), .u_out_ready(req_0_1_2_0_U_r),
        .d_in_valid(req_0_1_3_0_U_v), .d_in_flit(req_0_1_3_0_U_f), .d_in_ready(req_0_1_3_0_U_r),
        .d_out_valid(req_0_1_2_0_D_v), .d_out_flit(req_0_1_2_0_D_f), .d_out_ready(req_0_1_2_0_D_r),
        .ana_in_valid(req_0_1_2_1_KATA_v), .ana_in_flit(req_0_1_2_1_KATA_f), .ana_in_ready(req_0_1_2_1_KATA_r),
        .ana_out_valid(req_0_1_2_0_ANA_v), .ana_out_flit(req_0_1_2_0_ANA_f), .ana_out_ready(req_0_1_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({92{1'b0}}), .l_in_ready(),
        .l_out_valid(mem_req_in_valid), .l_out_flit(mem_req_in_flit), .l_out_ready(mem_req_in_ready)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(2), .MY_W(0)) resp_r0_1_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_2_0_S_v), .n_in_flit(resp_0_0_2_0_S_f), .n_in_ready(resp_0_0_2_0_S_r),
        .n_out_valid(resp_0_1_2_0_N_v), .n_out_flit(resp_0_1_2_0_N_f), .n_out_ready(resp_0_1_2_0_N_r),
        .s_in_valid(resp_0_2_2_0_N_v), .s_in_flit(resp_0_2_2_0_N_f), .s_in_ready(resp_0_2_2_0_N_r),
        .s_out_valid(resp_0_1_2_0_S_v), .s_out_flit(resp_0_1_2_0_S_f), .s_out_ready(resp_0_1_2_0_S_r),
        .e_in_valid(resp_1_1_2_0_W_v), .e_in_flit(resp_1_1_2_0_W_f), .e_in_ready(resp_1_1_2_0_W_r),
        .e_out_valid(resp_0_1_2_0_E_v), .e_out_flit(resp_0_1_2_0_E_f), .e_out_ready(resp_0_1_2_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_1_0_D_v), .u_in_flit(resp_0_1_1_0_D_f), .u_in_ready(resp_0_1_1_0_D_r),
        .u_out_valid(resp_0_1_2_0_U_v), .u_out_flit(resp_0_1_2_0_U_f), .u_out_ready(resp_0_1_2_0_U_r),
        .d_in_valid(resp_0_1_3_0_U_v), .d_in_flit(resp_0_1_3_0_U_f), .d_in_ready(resp_0_1_3_0_U_r),
        .d_out_valid(resp_0_1_2_0_D_v), .d_out_flit(resp_0_1_2_0_D_f), .d_out_ready(resp_0_1_2_0_D_r),
        .ana_in_valid(resp_0_1_2_1_KATA_v), .ana_in_flit(resp_0_1_2_1_KATA_f), .ana_in_ready(resp_0_1_2_1_KATA_r),
        .ana_out_valid(resp_0_1_2_0_ANA_v), .ana_out_flit(resp_0_1_2_0_ANA_f), .ana_out_ready(resp_0_1_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(mem_resp_out_valid), .l_in_flit(mem_resp_out_flit), .l_in_ready(mem_resp_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(2), .MY_W(1)) req_r0_1_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_2_1_S_v), .n_in_flit(req_0_0_2_1_S_f), .n_in_ready(req_0_0_2_1_S_r),
        .n_out_valid(req_0_1_2_1_N_v), .n_out_flit(req_0_1_2_1_N_f), .n_out_ready(req_0_1_2_1_N_r),
        .s_in_valid(req_0_2_2_1_N_v), .s_in_flit(req_0_2_2_1_N_f), .s_in_ready(req_0_2_2_1_N_r),
        .s_out_valid(req_0_1_2_1_S_v), .s_out_flit(req_0_1_2_1_S_f), .s_out_ready(req_0_1_2_1_S_r),
        .e_in_valid(req_1_1_2_1_W_v), .e_in_flit(req_1_1_2_1_W_f), .e_in_ready(req_1_1_2_1_W_r),
        .e_out_valid(req_0_1_2_1_E_v), .e_out_flit(req_0_1_2_1_E_f), .e_out_ready(req_0_1_2_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_1_1_D_v), .u_in_flit(req_0_1_1_1_D_f), .u_in_ready(req_0_1_1_1_D_r),
        .u_out_valid(req_0_1_2_1_U_v), .u_out_flit(req_0_1_2_1_U_f), .u_out_ready(req_0_1_2_1_U_r),
        .d_in_valid(req_0_1_3_1_U_v), .d_in_flit(req_0_1_3_1_U_f), .d_in_ready(req_0_1_3_1_U_r),
        .d_out_valid(req_0_1_2_1_D_v), .d_out_flit(req_0_1_2_1_D_f), .d_out_ready(req_0_1_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_1_2_0_ANA_v), .kata_in_flit(req_0_1_2_0_ANA_f), .kata_in_ready(req_0_1_2_0_ANA_r),
        .kata_out_valid(req_0_1_2_1_KATA_v), .kata_out_flit(req_0_1_2_1_KATA_f), .kata_out_ready(req_0_1_2_1_KATA_r),
        .l_in_valid(p16_req_out_valid), .l_in_flit(p16_req_out_flit), .l_in_ready(p16_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(2), .MY_W(1)) resp_r0_1_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_2_1_S_v), .n_in_flit(resp_0_0_2_1_S_f), .n_in_ready(resp_0_0_2_1_S_r),
        .n_out_valid(resp_0_1_2_1_N_v), .n_out_flit(resp_0_1_2_1_N_f), .n_out_ready(resp_0_1_2_1_N_r),
        .s_in_valid(resp_0_2_2_1_N_v), .s_in_flit(resp_0_2_2_1_N_f), .s_in_ready(resp_0_2_2_1_N_r),
        .s_out_valid(resp_0_1_2_1_S_v), .s_out_flit(resp_0_1_2_1_S_f), .s_out_ready(resp_0_1_2_1_S_r),
        .e_in_valid(resp_1_1_2_1_W_v), .e_in_flit(resp_1_1_2_1_W_f), .e_in_ready(resp_1_1_2_1_W_r),
        .e_out_valid(resp_0_1_2_1_E_v), .e_out_flit(resp_0_1_2_1_E_f), .e_out_ready(resp_0_1_2_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_1_1_D_v), .u_in_flit(resp_0_1_1_1_D_f), .u_in_ready(resp_0_1_1_1_D_r),
        .u_out_valid(resp_0_1_2_1_U_v), .u_out_flit(resp_0_1_2_1_U_f), .u_out_ready(resp_0_1_2_1_U_r),
        .d_in_valid(resp_0_1_3_1_U_v), .d_in_flit(resp_0_1_3_1_U_f), .d_in_ready(resp_0_1_3_1_U_r),
        .d_out_valid(resp_0_1_2_1_D_v), .d_out_flit(resp_0_1_2_1_D_f), .d_out_ready(resp_0_1_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_1_2_0_ANA_v), .kata_in_flit(resp_0_1_2_0_ANA_f), .kata_in_ready(resp_0_1_2_0_ANA_r),
        .kata_out_valid(resp_0_1_2_1_KATA_v), .kata_out_flit(resp_0_1_2_1_KATA_f), .kata_out_ready(resp_0_1_2_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p16_resp_in_valid), .l_out_flit(p16_resp_in_flit), .l_out_ready(p16_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(3), .MY_W(0)) req_r0_1_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_3_0_S_v), .n_in_flit(req_0_0_3_0_S_f), .n_in_ready(req_0_0_3_0_S_r),
        .n_out_valid(req_0_1_3_0_N_v), .n_out_flit(req_0_1_3_0_N_f), .n_out_ready(req_0_1_3_0_N_r),
        .s_in_valid(req_0_2_3_0_N_v), .s_in_flit(req_0_2_3_0_N_f), .s_in_ready(req_0_2_3_0_N_r),
        .s_out_valid(req_0_1_3_0_S_v), .s_out_flit(req_0_1_3_0_S_f), .s_out_ready(req_0_1_3_0_S_r),
        .e_in_valid(req_1_1_3_0_W_v), .e_in_flit(req_1_1_3_0_W_f), .e_in_ready(req_1_1_3_0_W_r),
        .e_out_valid(req_0_1_3_0_E_v), .e_out_flit(req_0_1_3_0_E_f), .e_out_ready(req_0_1_3_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_2_0_D_v), .u_in_flit(req_0_1_2_0_D_f), .u_in_ready(req_0_1_2_0_D_r),
        .u_out_valid(req_0_1_3_0_U_v), .u_out_flit(req_0_1_3_0_U_f), .u_out_ready(req_0_1_3_0_U_r),
        .d_in_valid(req_0_1_4_0_U_v), .d_in_flit(req_0_1_4_0_U_f), .d_in_ready(req_0_1_4_0_U_r),
        .d_out_valid(req_0_1_3_0_D_v), .d_out_flit(req_0_1_3_0_D_f), .d_out_ready(req_0_1_3_0_D_r),
        .ana_in_valid(req_0_1_3_1_KATA_v), .ana_in_flit(req_0_1_3_1_KATA_f), .ana_in_ready(req_0_1_3_1_KATA_r),
        .ana_out_valid(req_0_1_3_0_ANA_v), .ana_out_flit(req_0_1_3_0_ANA_f), .ana_out_ready(req_0_1_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p17_req_out_valid), .l_in_flit(p17_req_out_flit), .l_in_ready(p17_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(3), .MY_W(0)) resp_r0_1_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_3_0_S_v), .n_in_flit(resp_0_0_3_0_S_f), .n_in_ready(resp_0_0_3_0_S_r),
        .n_out_valid(resp_0_1_3_0_N_v), .n_out_flit(resp_0_1_3_0_N_f), .n_out_ready(resp_0_1_3_0_N_r),
        .s_in_valid(resp_0_2_3_0_N_v), .s_in_flit(resp_0_2_3_0_N_f), .s_in_ready(resp_0_2_3_0_N_r),
        .s_out_valid(resp_0_1_3_0_S_v), .s_out_flit(resp_0_1_3_0_S_f), .s_out_ready(resp_0_1_3_0_S_r),
        .e_in_valid(resp_1_1_3_0_W_v), .e_in_flit(resp_1_1_3_0_W_f), .e_in_ready(resp_1_1_3_0_W_r),
        .e_out_valid(resp_0_1_3_0_E_v), .e_out_flit(resp_0_1_3_0_E_f), .e_out_ready(resp_0_1_3_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_2_0_D_v), .u_in_flit(resp_0_1_2_0_D_f), .u_in_ready(resp_0_1_2_0_D_r),
        .u_out_valid(resp_0_1_3_0_U_v), .u_out_flit(resp_0_1_3_0_U_f), .u_out_ready(resp_0_1_3_0_U_r),
        .d_in_valid(resp_0_1_4_0_U_v), .d_in_flit(resp_0_1_4_0_U_f), .d_in_ready(resp_0_1_4_0_U_r),
        .d_out_valid(resp_0_1_3_0_D_v), .d_out_flit(resp_0_1_3_0_D_f), .d_out_ready(resp_0_1_3_0_D_r),
        .ana_in_valid(resp_0_1_3_1_KATA_v), .ana_in_flit(resp_0_1_3_1_KATA_f), .ana_in_ready(resp_0_1_3_1_KATA_r),
        .ana_out_valid(resp_0_1_3_0_ANA_v), .ana_out_flit(resp_0_1_3_0_ANA_f), .ana_out_ready(resp_0_1_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p17_resp_in_valid), .l_out_flit(p17_resp_in_flit), .l_out_ready(p17_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(3), .MY_W(1)) req_r0_1_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_3_1_S_v), .n_in_flit(req_0_0_3_1_S_f), .n_in_ready(req_0_0_3_1_S_r),
        .n_out_valid(req_0_1_3_1_N_v), .n_out_flit(req_0_1_3_1_N_f), .n_out_ready(req_0_1_3_1_N_r),
        .s_in_valid(req_0_2_3_1_N_v), .s_in_flit(req_0_2_3_1_N_f), .s_in_ready(req_0_2_3_1_N_r),
        .s_out_valid(req_0_1_3_1_S_v), .s_out_flit(req_0_1_3_1_S_f), .s_out_ready(req_0_1_3_1_S_r),
        .e_in_valid(req_1_1_3_1_W_v), .e_in_flit(req_1_1_3_1_W_f), .e_in_ready(req_1_1_3_1_W_r),
        .e_out_valid(req_0_1_3_1_E_v), .e_out_flit(req_0_1_3_1_E_f), .e_out_ready(req_0_1_3_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_2_1_D_v), .u_in_flit(req_0_1_2_1_D_f), .u_in_ready(req_0_1_2_1_D_r),
        .u_out_valid(req_0_1_3_1_U_v), .u_out_flit(req_0_1_3_1_U_f), .u_out_ready(req_0_1_3_1_U_r),
        .d_in_valid(req_0_1_4_1_U_v), .d_in_flit(req_0_1_4_1_U_f), .d_in_ready(req_0_1_4_1_U_r),
        .d_out_valid(req_0_1_3_1_D_v), .d_out_flit(req_0_1_3_1_D_f), .d_out_ready(req_0_1_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_1_3_0_ANA_v), .kata_in_flit(req_0_1_3_0_ANA_f), .kata_in_ready(req_0_1_3_0_ANA_r),
        .kata_out_valid(req_0_1_3_1_KATA_v), .kata_out_flit(req_0_1_3_1_KATA_f), .kata_out_ready(req_0_1_3_1_KATA_r),
        .l_in_valid(p18_req_out_valid), .l_in_flit(p18_req_out_flit), .l_in_ready(p18_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(3), .MY_W(1)) resp_r0_1_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_3_1_S_v), .n_in_flit(resp_0_0_3_1_S_f), .n_in_ready(resp_0_0_3_1_S_r),
        .n_out_valid(resp_0_1_3_1_N_v), .n_out_flit(resp_0_1_3_1_N_f), .n_out_ready(resp_0_1_3_1_N_r),
        .s_in_valid(resp_0_2_3_1_N_v), .s_in_flit(resp_0_2_3_1_N_f), .s_in_ready(resp_0_2_3_1_N_r),
        .s_out_valid(resp_0_1_3_1_S_v), .s_out_flit(resp_0_1_3_1_S_f), .s_out_ready(resp_0_1_3_1_S_r),
        .e_in_valid(resp_1_1_3_1_W_v), .e_in_flit(resp_1_1_3_1_W_f), .e_in_ready(resp_1_1_3_1_W_r),
        .e_out_valid(resp_0_1_3_1_E_v), .e_out_flit(resp_0_1_3_1_E_f), .e_out_ready(resp_0_1_3_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_2_1_D_v), .u_in_flit(resp_0_1_2_1_D_f), .u_in_ready(resp_0_1_2_1_D_r),
        .u_out_valid(resp_0_1_3_1_U_v), .u_out_flit(resp_0_1_3_1_U_f), .u_out_ready(resp_0_1_3_1_U_r),
        .d_in_valid(resp_0_1_4_1_U_v), .d_in_flit(resp_0_1_4_1_U_f), .d_in_ready(resp_0_1_4_1_U_r),
        .d_out_valid(resp_0_1_3_1_D_v), .d_out_flit(resp_0_1_3_1_D_f), .d_out_ready(resp_0_1_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_1_3_0_ANA_v), .kata_in_flit(resp_0_1_3_0_ANA_f), .kata_in_ready(resp_0_1_3_0_ANA_r),
        .kata_out_valid(resp_0_1_3_1_KATA_v), .kata_out_flit(resp_0_1_3_1_KATA_f), .kata_out_ready(resp_0_1_3_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p18_resp_in_valid), .l_out_flit(p18_resp_in_flit), .l_out_ready(p18_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(4), .MY_W(0)) req_r0_1_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_4_0_S_v), .n_in_flit(req_0_0_4_0_S_f), .n_in_ready(req_0_0_4_0_S_r),
        .n_out_valid(req_0_1_4_0_N_v), .n_out_flit(req_0_1_4_0_N_f), .n_out_ready(req_0_1_4_0_N_r),
        .s_in_valid(req_0_2_4_0_N_v), .s_in_flit(req_0_2_4_0_N_f), .s_in_ready(req_0_2_4_0_N_r),
        .s_out_valid(req_0_1_4_0_S_v), .s_out_flit(req_0_1_4_0_S_f), .s_out_ready(req_0_1_4_0_S_r),
        .e_in_valid(req_1_1_4_0_W_v), .e_in_flit(req_1_1_4_0_W_f), .e_in_ready(req_1_1_4_0_W_r),
        .e_out_valid(req_0_1_4_0_E_v), .e_out_flit(req_0_1_4_0_E_f), .e_out_ready(req_0_1_4_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_3_0_D_v), .u_in_flit(req_0_1_3_0_D_f), .u_in_ready(req_0_1_3_0_D_r),
        .u_out_valid(req_0_1_4_0_U_v), .u_out_flit(req_0_1_4_0_U_f), .u_out_ready(req_0_1_4_0_U_r),
        .d_in_valid(req_0_1_5_0_U_v), .d_in_flit(req_0_1_5_0_U_f), .d_in_ready(req_0_1_5_0_U_r),
        .d_out_valid(req_0_1_4_0_D_v), .d_out_flit(req_0_1_4_0_D_f), .d_out_ready(req_0_1_4_0_D_r),
        .ana_in_valid(req_0_1_4_1_KATA_v), .ana_in_flit(req_0_1_4_1_KATA_f), .ana_in_ready(req_0_1_4_1_KATA_r),
        .ana_out_valid(req_0_1_4_0_ANA_v), .ana_out_flit(req_0_1_4_0_ANA_f), .ana_out_ready(req_0_1_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p19_req_out_valid), .l_in_flit(p19_req_out_flit), .l_in_ready(p19_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(4), .MY_W(0)) resp_r0_1_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_4_0_S_v), .n_in_flit(resp_0_0_4_0_S_f), .n_in_ready(resp_0_0_4_0_S_r),
        .n_out_valid(resp_0_1_4_0_N_v), .n_out_flit(resp_0_1_4_0_N_f), .n_out_ready(resp_0_1_4_0_N_r),
        .s_in_valid(resp_0_2_4_0_N_v), .s_in_flit(resp_0_2_4_0_N_f), .s_in_ready(resp_0_2_4_0_N_r),
        .s_out_valid(resp_0_1_4_0_S_v), .s_out_flit(resp_0_1_4_0_S_f), .s_out_ready(resp_0_1_4_0_S_r),
        .e_in_valid(resp_1_1_4_0_W_v), .e_in_flit(resp_1_1_4_0_W_f), .e_in_ready(resp_1_1_4_0_W_r),
        .e_out_valid(resp_0_1_4_0_E_v), .e_out_flit(resp_0_1_4_0_E_f), .e_out_ready(resp_0_1_4_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_3_0_D_v), .u_in_flit(resp_0_1_3_0_D_f), .u_in_ready(resp_0_1_3_0_D_r),
        .u_out_valid(resp_0_1_4_0_U_v), .u_out_flit(resp_0_1_4_0_U_f), .u_out_ready(resp_0_1_4_0_U_r),
        .d_in_valid(resp_0_1_5_0_U_v), .d_in_flit(resp_0_1_5_0_U_f), .d_in_ready(resp_0_1_5_0_U_r),
        .d_out_valid(resp_0_1_4_0_D_v), .d_out_flit(resp_0_1_4_0_D_f), .d_out_ready(resp_0_1_4_0_D_r),
        .ana_in_valid(resp_0_1_4_1_KATA_v), .ana_in_flit(resp_0_1_4_1_KATA_f), .ana_in_ready(resp_0_1_4_1_KATA_r),
        .ana_out_valid(resp_0_1_4_0_ANA_v), .ana_out_flit(resp_0_1_4_0_ANA_f), .ana_out_ready(resp_0_1_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p19_resp_in_valid), .l_out_flit(p19_resp_in_flit), .l_out_ready(p19_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(4), .MY_W(1)) req_r0_1_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_4_1_S_v), .n_in_flit(req_0_0_4_1_S_f), .n_in_ready(req_0_0_4_1_S_r),
        .n_out_valid(req_0_1_4_1_N_v), .n_out_flit(req_0_1_4_1_N_f), .n_out_ready(req_0_1_4_1_N_r),
        .s_in_valid(req_0_2_4_1_N_v), .s_in_flit(req_0_2_4_1_N_f), .s_in_ready(req_0_2_4_1_N_r),
        .s_out_valid(req_0_1_4_1_S_v), .s_out_flit(req_0_1_4_1_S_f), .s_out_ready(req_0_1_4_1_S_r),
        .e_in_valid(req_1_1_4_1_W_v), .e_in_flit(req_1_1_4_1_W_f), .e_in_ready(req_1_1_4_1_W_r),
        .e_out_valid(req_0_1_4_1_E_v), .e_out_flit(req_0_1_4_1_E_f), .e_out_ready(req_0_1_4_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_3_1_D_v), .u_in_flit(req_0_1_3_1_D_f), .u_in_ready(req_0_1_3_1_D_r),
        .u_out_valid(req_0_1_4_1_U_v), .u_out_flit(req_0_1_4_1_U_f), .u_out_ready(req_0_1_4_1_U_r),
        .d_in_valid(req_0_1_5_1_U_v), .d_in_flit(req_0_1_5_1_U_f), .d_in_ready(req_0_1_5_1_U_r),
        .d_out_valid(req_0_1_4_1_D_v), .d_out_flit(req_0_1_4_1_D_f), .d_out_ready(req_0_1_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_1_4_0_ANA_v), .kata_in_flit(req_0_1_4_0_ANA_f), .kata_in_ready(req_0_1_4_0_ANA_r),
        .kata_out_valid(req_0_1_4_1_KATA_v), .kata_out_flit(req_0_1_4_1_KATA_f), .kata_out_ready(req_0_1_4_1_KATA_r),
        .l_in_valid(p20_req_out_valid), .l_in_flit(p20_req_out_flit), .l_in_ready(p20_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(4), .MY_W(1)) resp_r0_1_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_4_1_S_v), .n_in_flit(resp_0_0_4_1_S_f), .n_in_ready(resp_0_0_4_1_S_r),
        .n_out_valid(resp_0_1_4_1_N_v), .n_out_flit(resp_0_1_4_1_N_f), .n_out_ready(resp_0_1_4_1_N_r),
        .s_in_valid(resp_0_2_4_1_N_v), .s_in_flit(resp_0_2_4_1_N_f), .s_in_ready(resp_0_2_4_1_N_r),
        .s_out_valid(resp_0_1_4_1_S_v), .s_out_flit(resp_0_1_4_1_S_f), .s_out_ready(resp_0_1_4_1_S_r),
        .e_in_valid(resp_1_1_4_1_W_v), .e_in_flit(resp_1_1_4_1_W_f), .e_in_ready(resp_1_1_4_1_W_r),
        .e_out_valid(resp_0_1_4_1_E_v), .e_out_flit(resp_0_1_4_1_E_f), .e_out_ready(resp_0_1_4_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_3_1_D_v), .u_in_flit(resp_0_1_3_1_D_f), .u_in_ready(resp_0_1_3_1_D_r),
        .u_out_valid(resp_0_1_4_1_U_v), .u_out_flit(resp_0_1_4_1_U_f), .u_out_ready(resp_0_1_4_1_U_r),
        .d_in_valid(resp_0_1_5_1_U_v), .d_in_flit(resp_0_1_5_1_U_f), .d_in_ready(resp_0_1_5_1_U_r),
        .d_out_valid(resp_0_1_4_1_D_v), .d_out_flit(resp_0_1_4_1_D_f), .d_out_ready(resp_0_1_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_1_4_0_ANA_v), .kata_in_flit(resp_0_1_4_0_ANA_f), .kata_in_ready(resp_0_1_4_0_ANA_r),
        .kata_out_valid(resp_0_1_4_1_KATA_v), .kata_out_flit(resp_0_1_4_1_KATA_f), .kata_out_ready(resp_0_1_4_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p20_resp_in_valid), .l_out_flit(p20_resp_in_flit), .l_out_ready(p20_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(5), .MY_W(0)) req_r0_1_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_5_0_S_v), .n_in_flit(req_0_0_5_0_S_f), .n_in_ready(req_0_0_5_0_S_r),
        .n_out_valid(req_0_1_5_0_N_v), .n_out_flit(req_0_1_5_0_N_f), .n_out_ready(req_0_1_5_0_N_r),
        .s_in_valid(req_0_2_5_0_N_v), .s_in_flit(req_0_2_5_0_N_f), .s_in_ready(req_0_2_5_0_N_r),
        .s_out_valid(req_0_1_5_0_S_v), .s_out_flit(req_0_1_5_0_S_f), .s_out_ready(req_0_1_5_0_S_r),
        .e_in_valid(req_1_1_5_0_W_v), .e_in_flit(req_1_1_5_0_W_f), .e_in_ready(req_1_1_5_0_W_r),
        .e_out_valid(req_0_1_5_0_E_v), .e_out_flit(req_0_1_5_0_E_f), .e_out_ready(req_0_1_5_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_4_0_D_v), .u_in_flit(req_0_1_4_0_D_f), .u_in_ready(req_0_1_4_0_D_r),
        .u_out_valid(req_0_1_5_0_U_v), .u_out_flit(req_0_1_5_0_U_f), .u_out_ready(req_0_1_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(req_0_1_5_1_KATA_v), .ana_in_flit(req_0_1_5_1_KATA_f), .ana_in_ready(req_0_1_5_1_KATA_r),
        .ana_out_valid(req_0_1_5_0_ANA_v), .ana_out_flit(req_0_1_5_0_ANA_f), .ana_out_ready(req_0_1_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p21_req_out_valid), .l_in_flit(p21_req_out_flit), .l_in_ready(p21_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(5), .MY_W(0)) resp_r0_1_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_5_0_S_v), .n_in_flit(resp_0_0_5_0_S_f), .n_in_ready(resp_0_0_5_0_S_r),
        .n_out_valid(resp_0_1_5_0_N_v), .n_out_flit(resp_0_1_5_0_N_f), .n_out_ready(resp_0_1_5_0_N_r),
        .s_in_valid(resp_0_2_5_0_N_v), .s_in_flit(resp_0_2_5_0_N_f), .s_in_ready(resp_0_2_5_0_N_r),
        .s_out_valid(resp_0_1_5_0_S_v), .s_out_flit(resp_0_1_5_0_S_f), .s_out_ready(resp_0_1_5_0_S_r),
        .e_in_valid(resp_1_1_5_0_W_v), .e_in_flit(resp_1_1_5_0_W_f), .e_in_ready(resp_1_1_5_0_W_r),
        .e_out_valid(resp_0_1_5_0_E_v), .e_out_flit(resp_0_1_5_0_E_f), .e_out_ready(resp_0_1_5_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_4_0_D_v), .u_in_flit(resp_0_1_4_0_D_f), .u_in_ready(resp_0_1_4_0_D_r),
        .u_out_valid(resp_0_1_5_0_U_v), .u_out_flit(resp_0_1_5_0_U_f), .u_out_ready(resp_0_1_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(resp_0_1_5_1_KATA_v), .ana_in_flit(resp_0_1_5_1_KATA_f), .ana_in_ready(resp_0_1_5_1_KATA_r),
        .ana_out_valid(resp_0_1_5_0_ANA_v), .ana_out_flit(resp_0_1_5_0_ANA_f), .ana_out_ready(resp_0_1_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p21_resp_in_valid), .l_out_flit(p21_resp_in_flit), .l_out_ready(p21_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(5), .MY_W(1)) req_r0_1_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_5_1_S_v), .n_in_flit(req_0_0_5_1_S_f), .n_in_ready(req_0_0_5_1_S_r),
        .n_out_valid(req_0_1_5_1_N_v), .n_out_flit(req_0_1_5_1_N_f), .n_out_ready(req_0_1_5_1_N_r),
        .s_in_valid(req_0_2_5_1_N_v), .s_in_flit(req_0_2_5_1_N_f), .s_in_ready(req_0_2_5_1_N_r),
        .s_out_valid(req_0_1_5_1_S_v), .s_out_flit(req_0_1_5_1_S_f), .s_out_ready(req_0_1_5_1_S_r),
        .e_in_valid(req_1_1_5_1_W_v), .e_in_flit(req_1_1_5_1_W_f), .e_in_ready(req_1_1_5_1_W_r),
        .e_out_valid(req_0_1_5_1_E_v), .e_out_flit(req_0_1_5_1_E_f), .e_out_ready(req_0_1_5_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_4_1_D_v), .u_in_flit(req_0_1_4_1_D_f), .u_in_ready(req_0_1_4_1_D_r),
        .u_out_valid(req_0_1_5_1_U_v), .u_out_flit(req_0_1_5_1_U_f), .u_out_ready(req_0_1_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_1_5_0_ANA_v), .kata_in_flit(req_0_1_5_0_ANA_f), .kata_in_ready(req_0_1_5_0_ANA_r),
        .kata_out_valid(req_0_1_5_1_KATA_v), .kata_out_flit(req_0_1_5_1_KATA_f), .kata_out_ready(req_0_1_5_1_KATA_r),
        .l_in_valid(p22_req_out_valid), .l_in_flit(p22_req_out_flit), .l_in_ready(p22_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(5), .MY_W(1)) resp_r0_1_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_5_1_S_v), .n_in_flit(resp_0_0_5_1_S_f), .n_in_ready(resp_0_0_5_1_S_r),
        .n_out_valid(resp_0_1_5_1_N_v), .n_out_flit(resp_0_1_5_1_N_f), .n_out_ready(resp_0_1_5_1_N_r),
        .s_in_valid(resp_0_2_5_1_N_v), .s_in_flit(resp_0_2_5_1_N_f), .s_in_ready(resp_0_2_5_1_N_r),
        .s_out_valid(resp_0_1_5_1_S_v), .s_out_flit(resp_0_1_5_1_S_f), .s_out_ready(resp_0_1_5_1_S_r),
        .e_in_valid(resp_1_1_5_1_W_v), .e_in_flit(resp_1_1_5_1_W_f), .e_in_ready(resp_1_1_5_1_W_r),
        .e_out_valid(resp_0_1_5_1_E_v), .e_out_flit(resp_0_1_5_1_E_f), .e_out_ready(resp_0_1_5_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_4_1_D_v), .u_in_flit(resp_0_1_4_1_D_f), .u_in_ready(resp_0_1_4_1_D_r),
        .u_out_valid(resp_0_1_5_1_U_v), .u_out_flit(resp_0_1_5_1_U_f), .u_out_ready(resp_0_1_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_1_5_0_ANA_v), .kata_in_flit(resp_0_1_5_0_ANA_f), .kata_in_ready(resp_0_1_5_0_ANA_r),
        .kata_out_valid(resp_0_1_5_1_KATA_v), .kata_out_flit(resp_0_1_5_1_KATA_f), .kata_out_ready(resp_0_1_5_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p22_resp_in_valid), .l_out_flit(p22_resp_in_flit), .l_out_ready(p22_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(0)) req_r0_2_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_0_0_S_v), .n_in_flit(req_0_1_0_0_S_f), .n_in_ready(req_0_1_0_0_S_r),
        .n_out_valid(req_0_2_0_0_N_v), .n_out_flit(req_0_2_0_0_N_f), .n_out_ready(req_0_2_0_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_0_0_W_v), .e_in_flit(req_1_2_0_0_W_f), .e_in_ready(req_1_2_0_0_W_r),
        .e_out_valid(req_0_2_0_0_E_v), .e_out_flit(req_0_2_0_0_E_f), .e_out_ready(req_0_2_0_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_2_1_0_U_v), .d_in_flit(req_0_2_1_0_U_f), .d_in_ready(req_0_2_1_0_U_r),
        .d_out_valid(req_0_2_0_0_D_v), .d_out_flit(req_0_2_0_0_D_f), .d_out_ready(req_0_2_0_0_D_r),
        .ana_in_valid(req_0_2_0_1_KATA_v), .ana_in_flit(req_0_2_0_1_KATA_f), .ana_in_ready(req_0_2_0_1_KATA_r),
        .ana_out_valid(req_0_2_0_0_ANA_v), .ana_out_flit(req_0_2_0_0_ANA_f), .ana_out_ready(req_0_2_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p23_req_out_valid), .l_in_flit(p23_req_out_flit), .l_in_ready(p23_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(0)) resp_r0_2_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_0_0_S_v), .n_in_flit(resp_0_1_0_0_S_f), .n_in_ready(resp_0_1_0_0_S_r),
        .n_out_valid(resp_0_2_0_0_N_v), .n_out_flit(resp_0_2_0_0_N_f), .n_out_ready(resp_0_2_0_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_0_0_W_v), .e_in_flit(resp_1_2_0_0_W_f), .e_in_ready(resp_1_2_0_0_W_r),
        .e_out_valid(resp_0_2_0_0_E_v), .e_out_flit(resp_0_2_0_0_E_f), .e_out_ready(resp_0_2_0_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_2_1_0_U_v), .d_in_flit(resp_0_2_1_0_U_f), .d_in_ready(resp_0_2_1_0_U_r),
        .d_out_valid(resp_0_2_0_0_D_v), .d_out_flit(resp_0_2_0_0_D_f), .d_out_ready(resp_0_2_0_0_D_r),
        .ana_in_valid(resp_0_2_0_1_KATA_v), .ana_in_flit(resp_0_2_0_1_KATA_f), .ana_in_ready(resp_0_2_0_1_KATA_r),
        .ana_out_valid(resp_0_2_0_0_ANA_v), .ana_out_flit(resp_0_2_0_0_ANA_f), .ana_out_ready(resp_0_2_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p23_resp_in_valid), .l_out_flit(p23_resp_in_flit), .l_out_ready(p23_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(1)) req_r0_2_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_0_1_S_v), .n_in_flit(req_0_1_0_1_S_f), .n_in_ready(req_0_1_0_1_S_r),
        .n_out_valid(req_0_2_0_1_N_v), .n_out_flit(req_0_2_0_1_N_f), .n_out_ready(req_0_2_0_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_0_1_W_v), .e_in_flit(req_1_2_0_1_W_f), .e_in_ready(req_1_2_0_1_W_r),
        .e_out_valid(req_0_2_0_1_E_v), .e_out_flit(req_0_2_0_1_E_f), .e_out_ready(req_0_2_0_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_2_1_1_U_v), .d_in_flit(req_0_2_1_1_U_f), .d_in_ready(req_0_2_1_1_U_r),
        .d_out_valid(req_0_2_0_1_D_v), .d_out_flit(req_0_2_0_1_D_f), .d_out_ready(req_0_2_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_2_0_0_ANA_v), .kata_in_flit(req_0_2_0_0_ANA_f), .kata_in_ready(req_0_2_0_0_ANA_r),
        .kata_out_valid(req_0_2_0_1_KATA_v), .kata_out_flit(req_0_2_0_1_KATA_f), .kata_out_ready(req_0_2_0_1_KATA_r),
        .l_in_valid(p24_req_out_valid), .l_in_flit(p24_req_out_flit), .l_in_ready(p24_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(1)) resp_r0_2_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_0_1_S_v), .n_in_flit(resp_0_1_0_1_S_f), .n_in_ready(resp_0_1_0_1_S_r),
        .n_out_valid(resp_0_2_0_1_N_v), .n_out_flit(resp_0_2_0_1_N_f), .n_out_ready(resp_0_2_0_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_0_1_W_v), .e_in_flit(resp_1_2_0_1_W_f), .e_in_ready(resp_1_2_0_1_W_r),
        .e_out_valid(resp_0_2_0_1_E_v), .e_out_flit(resp_0_2_0_1_E_f), .e_out_ready(resp_0_2_0_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_2_1_1_U_v), .d_in_flit(resp_0_2_1_1_U_f), .d_in_ready(resp_0_2_1_1_U_r),
        .d_out_valid(resp_0_2_0_1_D_v), .d_out_flit(resp_0_2_0_1_D_f), .d_out_ready(resp_0_2_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_2_0_0_ANA_v), .kata_in_flit(resp_0_2_0_0_ANA_f), .kata_in_ready(resp_0_2_0_0_ANA_r),
        .kata_out_valid(resp_0_2_0_1_KATA_v), .kata_out_flit(resp_0_2_0_1_KATA_f), .kata_out_ready(resp_0_2_0_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p24_resp_in_valid), .l_out_flit(p24_resp_in_flit), .l_out_ready(p24_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(1), .MY_W(0)) req_r0_2_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_1_0_S_v), .n_in_flit(req_0_1_1_0_S_f), .n_in_ready(req_0_1_1_0_S_r),
        .n_out_valid(req_0_2_1_0_N_v), .n_out_flit(req_0_2_1_0_N_f), .n_out_ready(req_0_2_1_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_1_0_W_v), .e_in_flit(req_1_2_1_0_W_f), .e_in_ready(req_1_2_1_0_W_r),
        .e_out_valid(req_0_2_1_0_E_v), .e_out_flit(req_0_2_1_0_E_f), .e_out_ready(req_0_2_1_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_0_0_D_v), .u_in_flit(req_0_2_0_0_D_f), .u_in_ready(req_0_2_0_0_D_r),
        .u_out_valid(req_0_2_1_0_U_v), .u_out_flit(req_0_2_1_0_U_f), .u_out_ready(req_0_2_1_0_U_r),
        .d_in_valid(req_0_2_2_0_U_v), .d_in_flit(req_0_2_2_0_U_f), .d_in_ready(req_0_2_2_0_U_r),
        .d_out_valid(req_0_2_1_0_D_v), .d_out_flit(req_0_2_1_0_D_f), .d_out_ready(req_0_2_1_0_D_r),
        .ana_in_valid(req_0_2_1_1_KATA_v), .ana_in_flit(req_0_2_1_1_KATA_f), .ana_in_ready(req_0_2_1_1_KATA_r),
        .ana_out_valid(req_0_2_1_0_ANA_v), .ana_out_flit(req_0_2_1_0_ANA_f), .ana_out_ready(req_0_2_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p25_req_out_valid), .l_in_flit(p25_req_out_flit), .l_in_ready(p25_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(1), .MY_W(0)) resp_r0_2_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_1_0_S_v), .n_in_flit(resp_0_1_1_0_S_f), .n_in_ready(resp_0_1_1_0_S_r),
        .n_out_valid(resp_0_2_1_0_N_v), .n_out_flit(resp_0_2_1_0_N_f), .n_out_ready(resp_0_2_1_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_1_0_W_v), .e_in_flit(resp_1_2_1_0_W_f), .e_in_ready(resp_1_2_1_0_W_r),
        .e_out_valid(resp_0_2_1_0_E_v), .e_out_flit(resp_0_2_1_0_E_f), .e_out_ready(resp_0_2_1_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_0_0_D_v), .u_in_flit(resp_0_2_0_0_D_f), .u_in_ready(resp_0_2_0_0_D_r),
        .u_out_valid(resp_0_2_1_0_U_v), .u_out_flit(resp_0_2_1_0_U_f), .u_out_ready(resp_0_2_1_0_U_r),
        .d_in_valid(resp_0_2_2_0_U_v), .d_in_flit(resp_0_2_2_0_U_f), .d_in_ready(resp_0_2_2_0_U_r),
        .d_out_valid(resp_0_2_1_0_D_v), .d_out_flit(resp_0_2_1_0_D_f), .d_out_ready(resp_0_2_1_0_D_r),
        .ana_in_valid(resp_0_2_1_1_KATA_v), .ana_in_flit(resp_0_2_1_1_KATA_f), .ana_in_ready(resp_0_2_1_1_KATA_r),
        .ana_out_valid(resp_0_2_1_0_ANA_v), .ana_out_flit(resp_0_2_1_0_ANA_f), .ana_out_ready(resp_0_2_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p25_resp_in_valid), .l_out_flit(p25_resp_in_flit), .l_out_ready(p25_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(1), .MY_W(1)) req_r0_2_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_1_1_S_v), .n_in_flit(req_0_1_1_1_S_f), .n_in_ready(req_0_1_1_1_S_r),
        .n_out_valid(req_0_2_1_1_N_v), .n_out_flit(req_0_2_1_1_N_f), .n_out_ready(req_0_2_1_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_1_1_W_v), .e_in_flit(req_1_2_1_1_W_f), .e_in_ready(req_1_2_1_1_W_r),
        .e_out_valid(req_0_2_1_1_E_v), .e_out_flit(req_0_2_1_1_E_f), .e_out_ready(req_0_2_1_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_0_1_D_v), .u_in_flit(req_0_2_0_1_D_f), .u_in_ready(req_0_2_0_1_D_r),
        .u_out_valid(req_0_2_1_1_U_v), .u_out_flit(req_0_2_1_1_U_f), .u_out_ready(req_0_2_1_1_U_r),
        .d_in_valid(req_0_2_2_1_U_v), .d_in_flit(req_0_2_2_1_U_f), .d_in_ready(req_0_2_2_1_U_r),
        .d_out_valid(req_0_2_1_1_D_v), .d_out_flit(req_0_2_1_1_D_f), .d_out_ready(req_0_2_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_2_1_0_ANA_v), .kata_in_flit(req_0_2_1_0_ANA_f), .kata_in_ready(req_0_2_1_0_ANA_r),
        .kata_out_valid(req_0_2_1_1_KATA_v), .kata_out_flit(req_0_2_1_1_KATA_f), .kata_out_ready(req_0_2_1_1_KATA_r),
        .l_in_valid(p26_req_out_valid), .l_in_flit(p26_req_out_flit), .l_in_ready(p26_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(1), .MY_W(1)) resp_r0_2_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_1_1_S_v), .n_in_flit(resp_0_1_1_1_S_f), .n_in_ready(resp_0_1_1_1_S_r),
        .n_out_valid(resp_0_2_1_1_N_v), .n_out_flit(resp_0_2_1_1_N_f), .n_out_ready(resp_0_2_1_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_1_1_W_v), .e_in_flit(resp_1_2_1_1_W_f), .e_in_ready(resp_1_2_1_1_W_r),
        .e_out_valid(resp_0_2_1_1_E_v), .e_out_flit(resp_0_2_1_1_E_f), .e_out_ready(resp_0_2_1_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_0_1_D_v), .u_in_flit(resp_0_2_0_1_D_f), .u_in_ready(resp_0_2_0_1_D_r),
        .u_out_valid(resp_0_2_1_1_U_v), .u_out_flit(resp_0_2_1_1_U_f), .u_out_ready(resp_0_2_1_1_U_r),
        .d_in_valid(resp_0_2_2_1_U_v), .d_in_flit(resp_0_2_2_1_U_f), .d_in_ready(resp_0_2_2_1_U_r),
        .d_out_valid(resp_0_2_1_1_D_v), .d_out_flit(resp_0_2_1_1_D_f), .d_out_ready(resp_0_2_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_2_1_0_ANA_v), .kata_in_flit(resp_0_2_1_0_ANA_f), .kata_in_ready(resp_0_2_1_0_ANA_r),
        .kata_out_valid(resp_0_2_1_1_KATA_v), .kata_out_flit(resp_0_2_1_1_KATA_f), .kata_out_ready(resp_0_2_1_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p26_resp_in_valid), .l_out_flit(p26_resp_in_flit), .l_out_ready(p26_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(2), .MY_W(0)) req_r0_2_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_2_0_S_v), .n_in_flit(req_0_1_2_0_S_f), .n_in_ready(req_0_1_2_0_S_r),
        .n_out_valid(req_0_2_2_0_N_v), .n_out_flit(req_0_2_2_0_N_f), .n_out_ready(req_0_2_2_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_2_0_W_v), .e_in_flit(req_1_2_2_0_W_f), .e_in_ready(req_1_2_2_0_W_r),
        .e_out_valid(req_0_2_2_0_E_v), .e_out_flit(req_0_2_2_0_E_f), .e_out_ready(req_0_2_2_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_1_0_D_v), .u_in_flit(req_0_2_1_0_D_f), .u_in_ready(req_0_2_1_0_D_r),
        .u_out_valid(req_0_2_2_0_U_v), .u_out_flit(req_0_2_2_0_U_f), .u_out_ready(req_0_2_2_0_U_r),
        .d_in_valid(req_0_2_3_0_U_v), .d_in_flit(req_0_2_3_0_U_f), .d_in_ready(req_0_2_3_0_U_r),
        .d_out_valid(req_0_2_2_0_D_v), .d_out_flit(req_0_2_2_0_D_f), .d_out_ready(req_0_2_2_0_D_r),
        .ana_in_valid(req_0_2_2_1_KATA_v), .ana_in_flit(req_0_2_2_1_KATA_f), .ana_in_ready(req_0_2_2_1_KATA_r),
        .ana_out_valid(req_0_2_2_0_ANA_v), .ana_out_flit(req_0_2_2_0_ANA_f), .ana_out_ready(req_0_2_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p27_req_out_valid), .l_in_flit(p27_req_out_flit), .l_in_ready(p27_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(2), .MY_W(0)) resp_r0_2_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_2_0_S_v), .n_in_flit(resp_0_1_2_0_S_f), .n_in_ready(resp_0_1_2_0_S_r),
        .n_out_valid(resp_0_2_2_0_N_v), .n_out_flit(resp_0_2_2_0_N_f), .n_out_ready(resp_0_2_2_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_2_0_W_v), .e_in_flit(resp_1_2_2_0_W_f), .e_in_ready(resp_1_2_2_0_W_r),
        .e_out_valid(resp_0_2_2_0_E_v), .e_out_flit(resp_0_2_2_0_E_f), .e_out_ready(resp_0_2_2_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_1_0_D_v), .u_in_flit(resp_0_2_1_0_D_f), .u_in_ready(resp_0_2_1_0_D_r),
        .u_out_valid(resp_0_2_2_0_U_v), .u_out_flit(resp_0_2_2_0_U_f), .u_out_ready(resp_0_2_2_0_U_r),
        .d_in_valid(resp_0_2_3_0_U_v), .d_in_flit(resp_0_2_3_0_U_f), .d_in_ready(resp_0_2_3_0_U_r),
        .d_out_valid(resp_0_2_2_0_D_v), .d_out_flit(resp_0_2_2_0_D_f), .d_out_ready(resp_0_2_2_0_D_r),
        .ana_in_valid(resp_0_2_2_1_KATA_v), .ana_in_flit(resp_0_2_2_1_KATA_f), .ana_in_ready(resp_0_2_2_1_KATA_r),
        .ana_out_valid(resp_0_2_2_0_ANA_v), .ana_out_flit(resp_0_2_2_0_ANA_f), .ana_out_ready(resp_0_2_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p27_resp_in_valid), .l_out_flit(p27_resp_in_flit), .l_out_ready(p27_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(2), .MY_W(1)) req_r0_2_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_2_1_S_v), .n_in_flit(req_0_1_2_1_S_f), .n_in_ready(req_0_1_2_1_S_r),
        .n_out_valid(req_0_2_2_1_N_v), .n_out_flit(req_0_2_2_1_N_f), .n_out_ready(req_0_2_2_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_2_1_W_v), .e_in_flit(req_1_2_2_1_W_f), .e_in_ready(req_1_2_2_1_W_r),
        .e_out_valid(req_0_2_2_1_E_v), .e_out_flit(req_0_2_2_1_E_f), .e_out_ready(req_0_2_2_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_1_1_D_v), .u_in_flit(req_0_2_1_1_D_f), .u_in_ready(req_0_2_1_1_D_r),
        .u_out_valid(req_0_2_2_1_U_v), .u_out_flit(req_0_2_2_1_U_f), .u_out_ready(req_0_2_2_1_U_r),
        .d_in_valid(req_0_2_3_1_U_v), .d_in_flit(req_0_2_3_1_U_f), .d_in_ready(req_0_2_3_1_U_r),
        .d_out_valid(req_0_2_2_1_D_v), .d_out_flit(req_0_2_2_1_D_f), .d_out_ready(req_0_2_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_2_2_0_ANA_v), .kata_in_flit(req_0_2_2_0_ANA_f), .kata_in_ready(req_0_2_2_0_ANA_r),
        .kata_out_valid(req_0_2_2_1_KATA_v), .kata_out_flit(req_0_2_2_1_KATA_f), .kata_out_ready(req_0_2_2_1_KATA_r),
        .l_in_valid(p28_req_out_valid), .l_in_flit(p28_req_out_flit), .l_in_ready(p28_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(2), .MY_W(1)) resp_r0_2_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_2_1_S_v), .n_in_flit(resp_0_1_2_1_S_f), .n_in_ready(resp_0_1_2_1_S_r),
        .n_out_valid(resp_0_2_2_1_N_v), .n_out_flit(resp_0_2_2_1_N_f), .n_out_ready(resp_0_2_2_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_2_1_W_v), .e_in_flit(resp_1_2_2_1_W_f), .e_in_ready(resp_1_2_2_1_W_r),
        .e_out_valid(resp_0_2_2_1_E_v), .e_out_flit(resp_0_2_2_1_E_f), .e_out_ready(resp_0_2_2_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_1_1_D_v), .u_in_flit(resp_0_2_1_1_D_f), .u_in_ready(resp_0_2_1_1_D_r),
        .u_out_valid(resp_0_2_2_1_U_v), .u_out_flit(resp_0_2_2_1_U_f), .u_out_ready(resp_0_2_2_1_U_r),
        .d_in_valid(resp_0_2_3_1_U_v), .d_in_flit(resp_0_2_3_1_U_f), .d_in_ready(resp_0_2_3_1_U_r),
        .d_out_valid(resp_0_2_2_1_D_v), .d_out_flit(resp_0_2_2_1_D_f), .d_out_ready(resp_0_2_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_2_2_0_ANA_v), .kata_in_flit(resp_0_2_2_0_ANA_f), .kata_in_ready(resp_0_2_2_0_ANA_r),
        .kata_out_valid(resp_0_2_2_1_KATA_v), .kata_out_flit(resp_0_2_2_1_KATA_f), .kata_out_ready(resp_0_2_2_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p28_resp_in_valid), .l_out_flit(p28_resp_in_flit), .l_out_ready(p28_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(3), .MY_W(0)) req_r0_2_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_3_0_S_v), .n_in_flit(req_0_1_3_0_S_f), .n_in_ready(req_0_1_3_0_S_r),
        .n_out_valid(req_0_2_3_0_N_v), .n_out_flit(req_0_2_3_0_N_f), .n_out_ready(req_0_2_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_3_0_W_v), .e_in_flit(req_1_2_3_0_W_f), .e_in_ready(req_1_2_3_0_W_r),
        .e_out_valid(req_0_2_3_0_E_v), .e_out_flit(req_0_2_3_0_E_f), .e_out_ready(req_0_2_3_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_2_0_D_v), .u_in_flit(req_0_2_2_0_D_f), .u_in_ready(req_0_2_2_0_D_r),
        .u_out_valid(req_0_2_3_0_U_v), .u_out_flit(req_0_2_3_0_U_f), .u_out_ready(req_0_2_3_0_U_r),
        .d_in_valid(req_0_2_4_0_U_v), .d_in_flit(req_0_2_4_0_U_f), .d_in_ready(req_0_2_4_0_U_r),
        .d_out_valid(req_0_2_3_0_D_v), .d_out_flit(req_0_2_3_0_D_f), .d_out_ready(req_0_2_3_0_D_r),
        .ana_in_valid(req_0_2_3_1_KATA_v), .ana_in_flit(req_0_2_3_1_KATA_f), .ana_in_ready(req_0_2_3_1_KATA_r),
        .ana_out_valid(req_0_2_3_0_ANA_v), .ana_out_flit(req_0_2_3_0_ANA_f), .ana_out_ready(req_0_2_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p29_req_out_valid), .l_in_flit(p29_req_out_flit), .l_in_ready(p29_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(3), .MY_W(0)) resp_r0_2_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_3_0_S_v), .n_in_flit(resp_0_1_3_0_S_f), .n_in_ready(resp_0_1_3_0_S_r),
        .n_out_valid(resp_0_2_3_0_N_v), .n_out_flit(resp_0_2_3_0_N_f), .n_out_ready(resp_0_2_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_3_0_W_v), .e_in_flit(resp_1_2_3_0_W_f), .e_in_ready(resp_1_2_3_0_W_r),
        .e_out_valid(resp_0_2_3_0_E_v), .e_out_flit(resp_0_2_3_0_E_f), .e_out_ready(resp_0_2_3_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_2_0_D_v), .u_in_flit(resp_0_2_2_0_D_f), .u_in_ready(resp_0_2_2_0_D_r),
        .u_out_valid(resp_0_2_3_0_U_v), .u_out_flit(resp_0_2_3_0_U_f), .u_out_ready(resp_0_2_3_0_U_r),
        .d_in_valid(resp_0_2_4_0_U_v), .d_in_flit(resp_0_2_4_0_U_f), .d_in_ready(resp_0_2_4_0_U_r),
        .d_out_valid(resp_0_2_3_0_D_v), .d_out_flit(resp_0_2_3_0_D_f), .d_out_ready(resp_0_2_3_0_D_r),
        .ana_in_valid(resp_0_2_3_1_KATA_v), .ana_in_flit(resp_0_2_3_1_KATA_f), .ana_in_ready(resp_0_2_3_1_KATA_r),
        .ana_out_valid(resp_0_2_3_0_ANA_v), .ana_out_flit(resp_0_2_3_0_ANA_f), .ana_out_ready(resp_0_2_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p29_resp_in_valid), .l_out_flit(p29_resp_in_flit), .l_out_ready(p29_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(3), .MY_W(1)) req_r0_2_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_3_1_S_v), .n_in_flit(req_0_1_3_1_S_f), .n_in_ready(req_0_1_3_1_S_r),
        .n_out_valid(req_0_2_3_1_N_v), .n_out_flit(req_0_2_3_1_N_f), .n_out_ready(req_0_2_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_3_1_W_v), .e_in_flit(req_1_2_3_1_W_f), .e_in_ready(req_1_2_3_1_W_r),
        .e_out_valid(req_0_2_3_1_E_v), .e_out_flit(req_0_2_3_1_E_f), .e_out_ready(req_0_2_3_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_2_1_D_v), .u_in_flit(req_0_2_2_1_D_f), .u_in_ready(req_0_2_2_1_D_r),
        .u_out_valid(req_0_2_3_1_U_v), .u_out_flit(req_0_2_3_1_U_f), .u_out_ready(req_0_2_3_1_U_r),
        .d_in_valid(req_0_2_4_1_U_v), .d_in_flit(req_0_2_4_1_U_f), .d_in_ready(req_0_2_4_1_U_r),
        .d_out_valid(req_0_2_3_1_D_v), .d_out_flit(req_0_2_3_1_D_f), .d_out_ready(req_0_2_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_2_3_0_ANA_v), .kata_in_flit(req_0_2_3_0_ANA_f), .kata_in_ready(req_0_2_3_0_ANA_r),
        .kata_out_valid(req_0_2_3_1_KATA_v), .kata_out_flit(req_0_2_3_1_KATA_f), .kata_out_ready(req_0_2_3_1_KATA_r),
        .l_in_valid(p30_req_out_valid), .l_in_flit(p30_req_out_flit), .l_in_ready(p30_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(3), .MY_W(1)) resp_r0_2_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_3_1_S_v), .n_in_flit(resp_0_1_3_1_S_f), .n_in_ready(resp_0_1_3_1_S_r),
        .n_out_valid(resp_0_2_3_1_N_v), .n_out_flit(resp_0_2_3_1_N_f), .n_out_ready(resp_0_2_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_3_1_W_v), .e_in_flit(resp_1_2_3_1_W_f), .e_in_ready(resp_1_2_3_1_W_r),
        .e_out_valid(resp_0_2_3_1_E_v), .e_out_flit(resp_0_2_3_1_E_f), .e_out_ready(resp_0_2_3_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_2_1_D_v), .u_in_flit(resp_0_2_2_1_D_f), .u_in_ready(resp_0_2_2_1_D_r),
        .u_out_valid(resp_0_2_3_1_U_v), .u_out_flit(resp_0_2_3_1_U_f), .u_out_ready(resp_0_2_3_1_U_r),
        .d_in_valid(resp_0_2_4_1_U_v), .d_in_flit(resp_0_2_4_1_U_f), .d_in_ready(resp_0_2_4_1_U_r),
        .d_out_valid(resp_0_2_3_1_D_v), .d_out_flit(resp_0_2_3_1_D_f), .d_out_ready(resp_0_2_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_2_3_0_ANA_v), .kata_in_flit(resp_0_2_3_0_ANA_f), .kata_in_ready(resp_0_2_3_0_ANA_r),
        .kata_out_valid(resp_0_2_3_1_KATA_v), .kata_out_flit(resp_0_2_3_1_KATA_f), .kata_out_ready(resp_0_2_3_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p30_resp_in_valid), .l_out_flit(p30_resp_in_flit), .l_out_ready(p30_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(4), .MY_W(0)) req_r0_2_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_4_0_S_v), .n_in_flit(req_0_1_4_0_S_f), .n_in_ready(req_0_1_4_0_S_r),
        .n_out_valid(req_0_2_4_0_N_v), .n_out_flit(req_0_2_4_0_N_f), .n_out_ready(req_0_2_4_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_4_0_W_v), .e_in_flit(req_1_2_4_0_W_f), .e_in_ready(req_1_2_4_0_W_r),
        .e_out_valid(req_0_2_4_0_E_v), .e_out_flit(req_0_2_4_0_E_f), .e_out_ready(req_0_2_4_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_3_0_D_v), .u_in_flit(req_0_2_3_0_D_f), .u_in_ready(req_0_2_3_0_D_r),
        .u_out_valid(req_0_2_4_0_U_v), .u_out_flit(req_0_2_4_0_U_f), .u_out_ready(req_0_2_4_0_U_r),
        .d_in_valid(req_0_2_5_0_U_v), .d_in_flit(req_0_2_5_0_U_f), .d_in_ready(req_0_2_5_0_U_r),
        .d_out_valid(req_0_2_4_0_D_v), .d_out_flit(req_0_2_4_0_D_f), .d_out_ready(req_0_2_4_0_D_r),
        .ana_in_valid(req_0_2_4_1_KATA_v), .ana_in_flit(req_0_2_4_1_KATA_f), .ana_in_ready(req_0_2_4_1_KATA_r),
        .ana_out_valid(req_0_2_4_0_ANA_v), .ana_out_flit(req_0_2_4_0_ANA_f), .ana_out_ready(req_0_2_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p31_req_out_valid), .l_in_flit(p31_req_out_flit), .l_in_ready(p31_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(4), .MY_W(0)) resp_r0_2_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_4_0_S_v), .n_in_flit(resp_0_1_4_0_S_f), .n_in_ready(resp_0_1_4_0_S_r),
        .n_out_valid(resp_0_2_4_0_N_v), .n_out_flit(resp_0_2_4_0_N_f), .n_out_ready(resp_0_2_4_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_4_0_W_v), .e_in_flit(resp_1_2_4_0_W_f), .e_in_ready(resp_1_2_4_0_W_r),
        .e_out_valid(resp_0_2_4_0_E_v), .e_out_flit(resp_0_2_4_0_E_f), .e_out_ready(resp_0_2_4_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_3_0_D_v), .u_in_flit(resp_0_2_3_0_D_f), .u_in_ready(resp_0_2_3_0_D_r),
        .u_out_valid(resp_0_2_4_0_U_v), .u_out_flit(resp_0_2_4_0_U_f), .u_out_ready(resp_0_2_4_0_U_r),
        .d_in_valid(resp_0_2_5_0_U_v), .d_in_flit(resp_0_2_5_0_U_f), .d_in_ready(resp_0_2_5_0_U_r),
        .d_out_valid(resp_0_2_4_0_D_v), .d_out_flit(resp_0_2_4_0_D_f), .d_out_ready(resp_0_2_4_0_D_r),
        .ana_in_valid(resp_0_2_4_1_KATA_v), .ana_in_flit(resp_0_2_4_1_KATA_f), .ana_in_ready(resp_0_2_4_1_KATA_r),
        .ana_out_valid(resp_0_2_4_0_ANA_v), .ana_out_flit(resp_0_2_4_0_ANA_f), .ana_out_ready(resp_0_2_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p31_resp_in_valid), .l_out_flit(p31_resp_in_flit), .l_out_ready(p31_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(4), .MY_W(1)) req_r0_2_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_4_1_S_v), .n_in_flit(req_0_1_4_1_S_f), .n_in_ready(req_0_1_4_1_S_r),
        .n_out_valid(req_0_2_4_1_N_v), .n_out_flit(req_0_2_4_1_N_f), .n_out_ready(req_0_2_4_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_4_1_W_v), .e_in_flit(req_1_2_4_1_W_f), .e_in_ready(req_1_2_4_1_W_r),
        .e_out_valid(req_0_2_4_1_E_v), .e_out_flit(req_0_2_4_1_E_f), .e_out_ready(req_0_2_4_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_3_1_D_v), .u_in_flit(req_0_2_3_1_D_f), .u_in_ready(req_0_2_3_1_D_r),
        .u_out_valid(req_0_2_4_1_U_v), .u_out_flit(req_0_2_4_1_U_f), .u_out_ready(req_0_2_4_1_U_r),
        .d_in_valid(req_0_2_5_1_U_v), .d_in_flit(req_0_2_5_1_U_f), .d_in_ready(req_0_2_5_1_U_r),
        .d_out_valid(req_0_2_4_1_D_v), .d_out_flit(req_0_2_4_1_D_f), .d_out_ready(req_0_2_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_2_4_0_ANA_v), .kata_in_flit(req_0_2_4_0_ANA_f), .kata_in_ready(req_0_2_4_0_ANA_r),
        .kata_out_valid(req_0_2_4_1_KATA_v), .kata_out_flit(req_0_2_4_1_KATA_f), .kata_out_ready(req_0_2_4_1_KATA_r),
        .l_in_valid(p32_req_out_valid), .l_in_flit(p32_req_out_flit), .l_in_ready(p32_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(4), .MY_W(1)) resp_r0_2_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_4_1_S_v), .n_in_flit(resp_0_1_4_1_S_f), .n_in_ready(resp_0_1_4_1_S_r),
        .n_out_valid(resp_0_2_4_1_N_v), .n_out_flit(resp_0_2_4_1_N_f), .n_out_ready(resp_0_2_4_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_4_1_W_v), .e_in_flit(resp_1_2_4_1_W_f), .e_in_ready(resp_1_2_4_1_W_r),
        .e_out_valid(resp_0_2_4_1_E_v), .e_out_flit(resp_0_2_4_1_E_f), .e_out_ready(resp_0_2_4_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_3_1_D_v), .u_in_flit(resp_0_2_3_1_D_f), .u_in_ready(resp_0_2_3_1_D_r),
        .u_out_valid(resp_0_2_4_1_U_v), .u_out_flit(resp_0_2_4_1_U_f), .u_out_ready(resp_0_2_4_1_U_r),
        .d_in_valid(resp_0_2_5_1_U_v), .d_in_flit(resp_0_2_5_1_U_f), .d_in_ready(resp_0_2_5_1_U_r),
        .d_out_valid(resp_0_2_4_1_D_v), .d_out_flit(resp_0_2_4_1_D_f), .d_out_ready(resp_0_2_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_2_4_0_ANA_v), .kata_in_flit(resp_0_2_4_0_ANA_f), .kata_in_ready(resp_0_2_4_0_ANA_r),
        .kata_out_valid(resp_0_2_4_1_KATA_v), .kata_out_flit(resp_0_2_4_1_KATA_f), .kata_out_ready(resp_0_2_4_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p32_resp_in_valid), .l_out_flit(p32_resp_in_flit), .l_out_ready(p32_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(5), .MY_W(0)) req_r0_2_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_5_0_S_v), .n_in_flit(req_0_1_5_0_S_f), .n_in_ready(req_0_1_5_0_S_r),
        .n_out_valid(req_0_2_5_0_N_v), .n_out_flit(req_0_2_5_0_N_f), .n_out_ready(req_0_2_5_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_5_0_W_v), .e_in_flit(req_1_2_5_0_W_f), .e_in_ready(req_1_2_5_0_W_r),
        .e_out_valid(req_0_2_5_0_E_v), .e_out_flit(req_0_2_5_0_E_f), .e_out_ready(req_0_2_5_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_4_0_D_v), .u_in_flit(req_0_2_4_0_D_f), .u_in_ready(req_0_2_4_0_D_r),
        .u_out_valid(req_0_2_5_0_U_v), .u_out_flit(req_0_2_5_0_U_f), .u_out_ready(req_0_2_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(req_0_2_5_1_KATA_v), .ana_in_flit(req_0_2_5_1_KATA_f), .ana_in_ready(req_0_2_5_1_KATA_r),
        .ana_out_valid(req_0_2_5_0_ANA_v), .ana_out_flit(req_0_2_5_0_ANA_f), .ana_out_ready(req_0_2_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p33_req_out_valid), .l_in_flit(p33_req_out_flit), .l_in_ready(p33_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(5), .MY_W(0)) resp_r0_2_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_5_0_S_v), .n_in_flit(resp_0_1_5_0_S_f), .n_in_ready(resp_0_1_5_0_S_r),
        .n_out_valid(resp_0_2_5_0_N_v), .n_out_flit(resp_0_2_5_0_N_f), .n_out_ready(resp_0_2_5_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_5_0_W_v), .e_in_flit(resp_1_2_5_0_W_f), .e_in_ready(resp_1_2_5_0_W_r),
        .e_out_valid(resp_0_2_5_0_E_v), .e_out_flit(resp_0_2_5_0_E_f), .e_out_ready(resp_0_2_5_0_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_4_0_D_v), .u_in_flit(resp_0_2_4_0_D_f), .u_in_ready(resp_0_2_4_0_D_r),
        .u_out_valid(resp_0_2_5_0_U_v), .u_out_flit(resp_0_2_5_0_U_f), .u_out_ready(resp_0_2_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(resp_0_2_5_1_KATA_v), .ana_in_flit(resp_0_2_5_1_KATA_f), .ana_in_ready(resp_0_2_5_1_KATA_r),
        .ana_out_valid(resp_0_2_5_0_ANA_v), .ana_out_flit(resp_0_2_5_0_ANA_f), .ana_out_ready(resp_0_2_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p33_resp_in_valid), .l_out_flit(p33_resp_in_flit), .l_out_ready(p33_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(5), .MY_W(1)) req_r0_2_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_5_1_S_v), .n_in_flit(req_0_1_5_1_S_f), .n_in_ready(req_0_1_5_1_S_r),
        .n_out_valid(req_0_2_5_1_N_v), .n_out_flit(req_0_2_5_1_N_f), .n_out_ready(req_0_2_5_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(req_1_2_5_1_W_v), .e_in_flit(req_1_2_5_1_W_f), .e_in_ready(req_1_2_5_1_W_r),
        .e_out_valid(req_0_2_5_1_E_v), .e_out_flit(req_0_2_5_1_E_f), .e_out_ready(req_0_2_5_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({92{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_4_1_D_v), .u_in_flit(req_0_2_4_1_D_f), .u_in_ready(req_0_2_4_1_D_r),
        .u_out_valid(req_0_2_5_1_U_v), .u_out_flit(req_0_2_5_1_U_f), .u_out_ready(req_0_2_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_0_2_5_0_ANA_v), .kata_in_flit(req_0_2_5_0_ANA_f), .kata_in_ready(req_0_2_5_0_ANA_r),
        .kata_out_valid(req_0_2_5_1_KATA_v), .kata_out_flit(req_0_2_5_1_KATA_f), .kata_out_ready(req_0_2_5_1_KATA_r),
        .l_in_valid(p34_req_out_valid), .l_in_flit(p34_req_out_flit), .l_in_ready(p34_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(5), .MY_W(1)) resp_r0_2_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_5_1_S_v), .n_in_flit(resp_0_1_5_1_S_f), .n_in_ready(resp_0_1_5_1_S_r),
        .n_out_valid(resp_0_2_5_1_N_v), .n_out_flit(resp_0_2_5_1_N_f), .n_out_ready(resp_0_2_5_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(resp_1_2_5_1_W_v), .e_in_flit(resp_1_2_5_1_W_f), .e_in_ready(resp_1_2_5_1_W_r),
        .e_out_valid(resp_0_2_5_1_E_v), .e_out_flit(resp_0_2_5_1_E_f), .e_out_ready(resp_0_2_5_1_E_r),
        .w_in_valid(1'b0), .w_in_flit({44{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_4_1_D_v), .u_in_flit(resp_0_2_4_1_D_f), .u_in_ready(resp_0_2_4_1_D_r),
        .u_out_valid(resp_0_2_5_1_U_v), .u_out_flit(resp_0_2_5_1_U_f), .u_out_ready(resp_0_2_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_0_2_5_0_ANA_v), .kata_in_flit(resp_0_2_5_0_ANA_f), .kata_in_ready(resp_0_2_5_0_ANA_r),
        .kata_out_valid(resp_0_2_5_1_KATA_v), .kata_out_flit(resp_0_2_5_1_KATA_f), .kata_out_ready(resp_0_2_5_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p34_resp_in_valid), .l_out_flit(p34_resp_in_flit), .l_out_ready(p34_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r1_0_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_0_0_N_v), .s_in_flit(req_1_1_0_0_N_f), .s_in_ready(req_1_1_0_0_N_r),
        .s_out_valid(req_1_0_0_0_S_v), .s_out_flit(req_1_0_0_0_S_f), .s_out_ready(req_1_0_0_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_0_0_E_v), .w_in_flit(req_0_0_0_0_E_f), .w_in_ready(req_0_0_0_0_E_r),
        .w_out_valid(req_1_0_0_0_W_v), .w_out_flit(req_1_0_0_0_W_f), .w_out_ready(req_1_0_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_0_1_0_U_v), .d_in_flit(req_1_0_1_0_U_f), .d_in_ready(req_1_0_1_0_U_r),
        .d_out_valid(req_1_0_0_0_D_v), .d_out_flit(req_1_0_0_0_D_f), .d_out_ready(req_1_0_0_0_D_r),
        .ana_in_valid(req_1_0_0_1_KATA_v), .ana_in_flit(req_1_0_0_1_KATA_f), .ana_in_ready(req_1_0_0_1_KATA_r),
        .ana_out_valid(req_1_0_0_0_ANA_v), .ana_out_flit(req_1_0_0_0_ANA_f), .ana_out_ready(req_1_0_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(p35_req_out_valid), .l_in_flit(p35_req_out_flit), .l_in_ready(p35_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r1_0_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_0_0_N_v), .s_in_flit(resp_1_1_0_0_N_f), .s_in_ready(resp_1_1_0_0_N_r),
        .s_out_valid(resp_1_0_0_0_S_v), .s_out_flit(resp_1_0_0_0_S_f), .s_out_ready(resp_1_0_0_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_0_0_E_v), .w_in_flit(resp_0_0_0_0_E_f), .w_in_ready(resp_0_0_0_0_E_r),
        .w_out_valid(resp_1_0_0_0_W_v), .w_out_flit(resp_1_0_0_0_W_f), .w_out_ready(resp_1_0_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_0_1_0_U_v), .d_in_flit(resp_1_0_1_0_U_f), .d_in_ready(resp_1_0_1_0_U_r),
        .d_out_valid(resp_1_0_0_0_D_v), .d_out_flit(resp_1_0_0_0_D_f), .d_out_ready(resp_1_0_0_0_D_r),
        .ana_in_valid(resp_1_0_0_1_KATA_v), .ana_in_flit(resp_1_0_0_1_KATA_f), .ana_in_ready(resp_1_0_0_1_KATA_r),
        .ana_out_valid(resp_1_0_0_0_ANA_v), .ana_out_flit(resp_1_0_0_0_ANA_f), .ana_out_ready(resp_1_0_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(p35_resp_in_valid), .l_out_flit(p35_resp_in_flit), .l_out_ready(p35_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(1)) req_r1_0_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_0_1_N_v), .s_in_flit(req_1_1_0_1_N_f), .s_in_ready(req_1_1_0_1_N_r),
        .s_out_valid(req_1_0_0_1_S_v), .s_out_flit(req_1_0_0_1_S_f), .s_out_ready(req_1_0_0_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_0_1_E_v), .w_in_flit(req_0_0_0_1_E_f), .w_in_ready(req_0_0_0_1_E_r),
        .w_out_valid(req_1_0_0_1_W_v), .w_out_flit(req_1_0_0_1_W_f), .w_out_ready(req_1_0_0_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_0_1_1_U_v), .d_in_flit(req_1_0_1_1_U_f), .d_in_ready(req_1_0_1_1_U_r),
        .d_out_valid(req_1_0_0_1_D_v), .d_out_flit(req_1_0_0_1_D_f), .d_out_ready(req_1_0_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_0_0_0_ANA_v), .kata_in_flit(req_1_0_0_0_ANA_f), .kata_in_ready(req_1_0_0_0_ANA_r),
        .kata_out_valid(req_1_0_0_1_KATA_v), .kata_out_flit(req_1_0_0_1_KATA_f), .kata_out_ready(req_1_0_0_1_KATA_r),
        .l_in_valid(e0_req_out_valid), .l_in_flit(e0_req_out_flit), .l_in_ready(e0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(1)) resp_r1_0_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_0_1_N_v), .s_in_flit(resp_1_1_0_1_N_f), .s_in_ready(resp_1_1_0_1_N_r),
        .s_out_valid(resp_1_0_0_1_S_v), .s_out_flit(resp_1_0_0_1_S_f), .s_out_ready(resp_1_0_0_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_0_1_E_v), .w_in_flit(resp_0_0_0_1_E_f), .w_in_ready(resp_0_0_0_1_E_r),
        .w_out_valid(resp_1_0_0_1_W_v), .w_out_flit(resp_1_0_0_1_W_f), .w_out_ready(resp_1_0_0_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_0_1_1_U_v), .d_in_flit(resp_1_0_1_1_U_f), .d_in_ready(resp_1_0_1_1_U_r),
        .d_out_valid(resp_1_0_0_1_D_v), .d_out_flit(resp_1_0_0_1_D_f), .d_out_ready(resp_1_0_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_0_0_0_ANA_v), .kata_in_flit(resp_1_0_0_0_ANA_f), .kata_in_ready(resp_1_0_0_0_ANA_r),
        .kata_out_valid(resp_1_0_0_1_KATA_v), .kata_out_flit(resp_1_0_0_1_KATA_f), .kata_out_ready(resp_1_0_0_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e0_resp_in_valid), .l_out_flit(e0_resp_in_flit), .l_out_ready(e0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(1), .MY_W(0)) req_r1_0_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_1_0_N_v), .s_in_flit(req_1_1_1_0_N_f), .s_in_ready(req_1_1_1_0_N_r),
        .s_out_valid(req_1_0_1_0_S_v), .s_out_flit(req_1_0_1_0_S_f), .s_out_ready(req_1_0_1_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_1_0_E_v), .w_in_flit(req_0_0_1_0_E_f), .w_in_ready(req_0_0_1_0_E_r),
        .w_out_valid(req_1_0_1_0_W_v), .w_out_flit(req_1_0_1_0_W_f), .w_out_ready(req_1_0_1_0_W_r),
        .u_in_valid(req_1_0_0_0_D_v), .u_in_flit(req_1_0_0_0_D_f), .u_in_ready(req_1_0_0_0_D_r),
        .u_out_valid(req_1_0_1_0_U_v), .u_out_flit(req_1_0_1_0_U_f), .u_out_ready(req_1_0_1_0_U_r),
        .d_in_valid(req_1_0_2_0_U_v), .d_in_flit(req_1_0_2_0_U_f), .d_in_ready(req_1_0_2_0_U_r),
        .d_out_valid(req_1_0_1_0_D_v), .d_out_flit(req_1_0_1_0_D_f), .d_out_ready(req_1_0_1_0_D_r),
        .ana_in_valid(req_1_0_1_1_KATA_v), .ana_in_flit(req_1_0_1_1_KATA_f), .ana_in_ready(req_1_0_1_1_KATA_r),
        .ana_out_valid(req_1_0_1_0_ANA_v), .ana_out_flit(req_1_0_1_0_ANA_f), .ana_out_ready(req_1_0_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e1_req_out_valid), .l_in_flit(e1_req_out_flit), .l_in_ready(e1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(1), .MY_W(0)) resp_r1_0_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_1_0_N_v), .s_in_flit(resp_1_1_1_0_N_f), .s_in_ready(resp_1_1_1_0_N_r),
        .s_out_valid(resp_1_0_1_0_S_v), .s_out_flit(resp_1_0_1_0_S_f), .s_out_ready(resp_1_0_1_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_1_0_E_v), .w_in_flit(resp_0_0_1_0_E_f), .w_in_ready(resp_0_0_1_0_E_r),
        .w_out_valid(resp_1_0_1_0_W_v), .w_out_flit(resp_1_0_1_0_W_f), .w_out_ready(resp_1_0_1_0_W_r),
        .u_in_valid(resp_1_0_0_0_D_v), .u_in_flit(resp_1_0_0_0_D_f), .u_in_ready(resp_1_0_0_0_D_r),
        .u_out_valid(resp_1_0_1_0_U_v), .u_out_flit(resp_1_0_1_0_U_f), .u_out_ready(resp_1_0_1_0_U_r),
        .d_in_valid(resp_1_0_2_0_U_v), .d_in_flit(resp_1_0_2_0_U_f), .d_in_ready(resp_1_0_2_0_U_r),
        .d_out_valid(resp_1_0_1_0_D_v), .d_out_flit(resp_1_0_1_0_D_f), .d_out_ready(resp_1_0_1_0_D_r),
        .ana_in_valid(resp_1_0_1_1_KATA_v), .ana_in_flit(resp_1_0_1_1_KATA_f), .ana_in_ready(resp_1_0_1_1_KATA_r),
        .ana_out_valid(resp_1_0_1_0_ANA_v), .ana_out_flit(resp_1_0_1_0_ANA_f), .ana_out_ready(resp_1_0_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e1_resp_in_valid), .l_out_flit(e1_resp_in_flit), .l_out_ready(e1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(1), .MY_W(1)) req_r1_0_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_1_1_N_v), .s_in_flit(req_1_1_1_1_N_f), .s_in_ready(req_1_1_1_1_N_r),
        .s_out_valid(req_1_0_1_1_S_v), .s_out_flit(req_1_0_1_1_S_f), .s_out_ready(req_1_0_1_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_1_1_E_v), .w_in_flit(req_0_0_1_1_E_f), .w_in_ready(req_0_0_1_1_E_r),
        .w_out_valid(req_1_0_1_1_W_v), .w_out_flit(req_1_0_1_1_W_f), .w_out_ready(req_1_0_1_1_W_r),
        .u_in_valid(req_1_0_0_1_D_v), .u_in_flit(req_1_0_0_1_D_f), .u_in_ready(req_1_0_0_1_D_r),
        .u_out_valid(req_1_0_1_1_U_v), .u_out_flit(req_1_0_1_1_U_f), .u_out_ready(req_1_0_1_1_U_r),
        .d_in_valid(req_1_0_2_1_U_v), .d_in_flit(req_1_0_2_1_U_f), .d_in_ready(req_1_0_2_1_U_r),
        .d_out_valid(req_1_0_1_1_D_v), .d_out_flit(req_1_0_1_1_D_f), .d_out_ready(req_1_0_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_0_1_0_ANA_v), .kata_in_flit(req_1_0_1_0_ANA_f), .kata_in_ready(req_1_0_1_0_ANA_r),
        .kata_out_valid(req_1_0_1_1_KATA_v), .kata_out_flit(req_1_0_1_1_KATA_f), .kata_out_ready(req_1_0_1_1_KATA_r),
        .l_in_valid(e2_req_out_valid), .l_in_flit(e2_req_out_flit), .l_in_ready(e2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(1), .MY_W(1)) resp_r1_0_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_1_1_N_v), .s_in_flit(resp_1_1_1_1_N_f), .s_in_ready(resp_1_1_1_1_N_r),
        .s_out_valid(resp_1_0_1_1_S_v), .s_out_flit(resp_1_0_1_1_S_f), .s_out_ready(resp_1_0_1_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_1_1_E_v), .w_in_flit(resp_0_0_1_1_E_f), .w_in_ready(resp_0_0_1_1_E_r),
        .w_out_valid(resp_1_0_1_1_W_v), .w_out_flit(resp_1_0_1_1_W_f), .w_out_ready(resp_1_0_1_1_W_r),
        .u_in_valid(resp_1_0_0_1_D_v), .u_in_flit(resp_1_0_0_1_D_f), .u_in_ready(resp_1_0_0_1_D_r),
        .u_out_valid(resp_1_0_1_1_U_v), .u_out_flit(resp_1_0_1_1_U_f), .u_out_ready(resp_1_0_1_1_U_r),
        .d_in_valid(resp_1_0_2_1_U_v), .d_in_flit(resp_1_0_2_1_U_f), .d_in_ready(resp_1_0_2_1_U_r),
        .d_out_valid(resp_1_0_1_1_D_v), .d_out_flit(resp_1_0_1_1_D_f), .d_out_ready(resp_1_0_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_0_1_0_ANA_v), .kata_in_flit(resp_1_0_1_0_ANA_f), .kata_in_ready(resp_1_0_1_0_ANA_r),
        .kata_out_valid(resp_1_0_1_1_KATA_v), .kata_out_flit(resp_1_0_1_1_KATA_f), .kata_out_ready(resp_1_0_1_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e2_resp_in_valid), .l_out_flit(e2_resp_in_flit), .l_out_ready(e2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(2), .MY_W(0)) req_r1_0_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_2_0_N_v), .s_in_flit(req_1_1_2_0_N_f), .s_in_ready(req_1_1_2_0_N_r),
        .s_out_valid(req_1_0_2_0_S_v), .s_out_flit(req_1_0_2_0_S_f), .s_out_ready(req_1_0_2_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_2_0_E_v), .w_in_flit(req_0_0_2_0_E_f), .w_in_ready(req_0_0_2_0_E_r),
        .w_out_valid(req_1_0_2_0_W_v), .w_out_flit(req_1_0_2_0_W_f), .w_out_ready(req_1_0_2_0_W_r),
        .u_in_valid(req_1_0_1_0_D_v), .u_in_flit(req_1_0_1_0_D_f), .u_in_ready(req_1_0_1_0_D_r),
        .u_out_valid(req_1_0_2_0_U_v), .u_out_flit(req_1_0_2_0_U_f), .u_out_ready(req_1_0_2_0_U_r),
        .d_in_valid(req_1_0_3_0_U_v), .d_in_flit(req_1_0_3_0_U_f), .d_in_ready(req_1_0_3_0_U_r),
        .d_out_valid(req_1_0_2_0_D_v), .d_out_flit(req_1_0_2_0_D_f), .d_out_ready(req_1_0_2_0_D_r),
        .ana_in_valid(req_1_0_2_1_KATA_v), .ana_in_flit(req_1_0_2_1_KATA_f), .ana_in_ready(req_1_0_2_1_KATA_r),
        .ana_out_valid(req_1_0_2_0_ANA_v), .ana_out_flit(req_1_0_2_0_ANA_f), .ana_out_ready(req_1_0_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e3_req_out_valid), .l_in_flit(e3_req_out_flit), .l_in_ready(e3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(2), .MY_W(0)) resp_r1_0_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_2_0_N_v), .s_in_flit(resp_1_1_2_0_N_f), .s_in_ready(resp_1_1_2_0_N_r),
        .s_out_valid(resp_1_0_2_0_S_v), .s_out_flit(resp_1_0_2_0_S_f), .s_out_ready(resp_1_0_2_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_2_0_E_v), .w_in_flit(resp_0_0_2_0_E_f), .w_in_ready(resp_0_0_2_0_E_r),
        .w_out_valid(resp_1_0_2_0_W_v), .w_out_flit(resp_1_0_2_0_W_f), .w_out_ready(resp_1_0_2_0_W_r),
        .u_in_valid(resp_1_0_1_0_D_v), .u_in_flit(resp_1_0_1_0_D_f), .u_in_ready(resp_1_0_1_0_D_r),
        .u_out_valid(resp_1_0_2_0_U_v), .u_out_flit(resp_1_0_2_0_U_f), .u_out_ready(resp_1_0_2_0_U_r),
        .d_in_valid(resp_1_0_3_0_U_v), .d_in_flit(resp_1_0_3_0_U_f), .d_in_ready(resp_1_0_3_0_U_r),
        .d_out_valid(resp_1_0_2_0_D_v), .d_out_flit(resp_1_0_2_0_D_f), .d_out_ready(resp_1_0_2_0_D_r),
        .ana_in_valid(resp_1_0_2_1_KATA_v), .ana_in_flit(resp_1_0_2_1_KATA_f), .ana_in_ready(resp_1_0_2_1_KATA_r),
        .ana_out_valid(resp_1_0_2_0_ANA_v), .ana_out_flit(resp_1_0_2_0_ANA_f), .ana_out_ready(resp_1_0_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e3_resp_in_valid), .l_out_flit(e3_resp_in_flit), .l_out_ready(e3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(2), .MY_W(1)) req_r1_0_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_2_1_N_v), .s_in_flit(req_1_1_2_1_N_f), .s_in_ready(req_1_1_2_1_N_r),
        .s_out_valid(req_1_0_2_1_S_v), .s_out_flit(req_1_0_2_1_S_f), .s_out_ready(req_1_0_2_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_2_1_E_v), .w_in_flit(req_0_0_2_1_E_f), .w_in_ready(req_0_0_2_1_E_r),
        .w_out_valid(req_1_0_2_1_W_v), .w_out_flit(req_1_0_2_1_W_f), .w_out_ready(req_1_0_2_1_W_r),
        .u_in_valid(req_1_0_1_1_D_v), .u_in_flit(req_1_0_1_1_D_f), .u_in_ready(req_1_0_1_1_D_r),
        .u_out_valid(req_1_0_2_1_U_v), .u_out_flit(req_1_0_2_1_U_f), .u_out_ready(req_1_0_2_1_U_r),
        .d_in_valid(req_1_0_3_1_U_v), .d_in_flit(req_1_0_3_1_U_f), .d_in_ready(req_1_0_3_1_U_r),
        .d_out_valid(req_1_0_2_1_D_v), .d_out_flit(req_1_0_2_1_D_f), .d_out_ready(req_1_0_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_0_2_0_ANA_v), .kata_in_flit(req_1_0_2_0_ANA_f), .kata_in_ready(req_1_0_2_0_ANA_r),
        .kata_out_valid(req_1_0_2_1_KATA_v), .kata_out_flit(req_1_0_2_1_KATA_f), .kata_out_ready(req_1_0_2_1_KATA_r),
        .l_in_valid(e4_req_out_valid), .l_in_flit(e4_req_out_flit), .l_in_ready(e4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(2), .MY_W(1)) resp_r1_0_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_2_1_N_v), .s_in_flit(resp_1_1_2_1_N_f), .s_in_ready(resp_1_1_2_1_N_r),
        .s_out_valid(resp_1_0_2_1_S_v), .s_out_flit(resp_1_0_2_1_S_f), .s_out_ready(resp_1_0_2_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_2_1_E_v), .w_in_flit(resp_0_0_2_1_E_f), .w_in_ready(resp_0_0_2_1_E_r),
        .w_out_valid(resp_1_0_2_1_W_v), .w_out_flit(resp_1_0_2_1_W_f), .w_out_ready(resp_1_0_2_1_W_r),
        .u_in_valid(resp_1_0_1_1_D_v), .u_in_flit(resp_1_0_1_1_D_f), .u_in_ready(resp_1_0_1_1_D_r),
        .u_out_valid(resp_1_0_2_1_U_v), .u_out_flit(resp_1_0_2_1_U_f), .u_out_ready(resp_1_0_2_1_U_r),
        .d_in_valid(resp_1_0_3_1_U_v), .d_in_flit(resp_1_0_3_1_U_f), .d_in_ready(resp_1_0_3_1_U_r),
        .d_out_valid(resp_1_0_2_1_D_v), .d_out_flit(resp_1_0_2_1_D_f), .d_out_ready(resp_1_0_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_0_2_0_ANA_v), .kata_in_flit(resp_1_0_2_0_ANA_f), .kata_in_ready(resp_1_0_2_0_ANA_r),
        .kata_out_valid(resp_1_0_2_1_KATA_v), .kata_out_flit(resp_1_0_2_1_KATA_f), .kata_out_ready(resp_1_0_2_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e4_resp_in_valid), .l_out_flit(e4_resp_in_flit), .l_out_ready(e4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(3), .MY_W(0)) req_r1_0_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_3_0_N_v), .s_in_flit(req_1_1_3_0_N_f), .s_in_ready(req_1_1_3_0_N_r),
        .s_out_valid(req_1_0_3_0_S_v), .s_out_flit(req_1_0_3_0_S_f), .s_out_ready(req_1_0_3_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_3_0_E_v), .w_in_flit(req_0_0_3_0_E_f), .w_in_ready(req_0_0_3_0_E_r),
        .w_out_valid(req_1_0_3_0_W_v), .w_out_flit(req_1_0_3_0_W_f), .w_out_ready(req_1_0_3_0_W_r),
        .u_in_valid(req_1_0_2_0_D_v), .u_in_flit(req_1_0_2_0_D_f), .u_in_ready(req_1_0_2_0_D_r),
        .u_out_valid(req_1_0_3_0_U_v), .u_out_flit(req_1_0_3_0_U_f), .u_out_ready(req_1_0_3_0_U_r),
        .d_in_valid(req_1_0_4_0_U_v), .d_in_flit(req_1_0_4_0_U_f), .d_in_ready(req_1_0_4_0_U_r),
        .d_out_valid(req_1_0_3_0_D_v), .d_out_flit(req_1_0_3_0_D_f), .d_out_ready(req_1_0_3_0_D_r),
        .ana_in_valid(req_1_0_3_1_KATA_v), .ana_in_flit(req_1_0_3_1_KATA_f), .ana_in_ready(req_1_0_3_1_KATA_r),
        .ana_out_valid(req_1_0_3_0_ANA_v), .ana_out_flit(req_1_0_3_0_ANA_f), .ana_out_ready(req_1_0_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e5_req_out_valid), .l_in_flit(e5_req_out_flit), .l_in_ready(e5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(3), .MY_W(0)) resp_r1_0_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_3_0_N_v), .s_in_flit(resp_1_1_3_0_N_f), .s_in_ready(resp_1_1_3_0_N_r),
        .s_out_valid(resp_1_0_3_0_S_v), .s_out_flit(resp_1_0_3_0_S_f), .s_out_ready(resp_1_0_3_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_3_0_E_v), .w_in_flit(resp_0_0_3_0_E_f), .w_in_ready(resp_0_0_3_0_E_r),
        .w_out_valid(resp_1_0_3_0_W_v), .w_out_flit(resp_1_0_3_0_W_f), .w_out_ready(resp_1_0_3_0_W_r),
        .u_in_valid(resp_1_0_2_0_D_v), .u_in_flit(resp_1_0_2_0_D_f), .u_in_ready(resp_1_0_2_0_D_r),
        .u_out_valid(resp_1_0_3_0_U_v), .u_out_flit(resp_1_0_3_0_U_f), .u_out_ready(resp_1_0_3_0_U_r),
        .d_in_valid(resp_1_0_4_0_U_v), .d_in_flit(resp_1_0_4_0_U_f), .d_in_ready(resp_1_0_4_0_U_r),
        .d_out_valid(resp_1_0_3_0_D_v), .d_out_flit(resp_1_0_3_0_D_f), .d_out_ready(resp_1_0_3_0_D_r),
        .ana_in_valid(resp_1_0_3_1_KATA_v), .ana_in_flit(resp_1_0_3_1_KATA_f), .ana_in_ready(resp_1_0_3_1_KATA_r),
        .ana_out_valid(resp_1_0_3_0_ANA_v), .ana_out_flit(resp_1_0_3_0_ANA_f), .ana_out_ready(resp_1_0_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e5_resp_in_valid), .l_out_flit(e5_resp_in_flit), .l_out_ready(e5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(3), .MY_W(1)) req_r1_0_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_3_1_N_v), .s_in_flit(req_1_1_3_1_N_f), .s_in_ready(req_1_1_3_1_N_r),
        .s_out_valid(req_1_0_3_1_S_v), .s_out_flit(req_1_0_3_1_S_f), .s_out_ready(req_1_0_3_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_3_1_E_v), .w_in_flit(req_0_0_3_1_E_f), .w_in_ready(req_0_0_3_1_E_r),
        .w_out_valid(req_1_0_3_1_W_v), .w_out_flit(req_1_0_3_1_W_f), .w_out_ready(req_1_0_3_1_W_r),
        .u_in_valid(req_1_0_2_1_D_v), .u_in_flit(req_1_0_2_1_D_f), .u_in_ready(req_1_0_2_1_D_r),
        .u_out_valid(req_1_0_3_1_U_v), .u_out_flit(req_1_0_3_1_U_f), .u_out_ready(req_1_0_3_1_U_r),
        .d_in_valid(req_1_0_4_1_U_v), .d_in_flit(req_1_0_4_1_U_f), .d_in_ready(req_1_0_4_1_U_r),
        .d_out_valid(req_1_0_3_1_D_v), .d_out_flit(req_1_0_3_1_D_f), .d_out_ready(req_1_0_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_0_3_0_ANA_v), .kata_in_flit(req_1_0_3_0_ANA_f), .kata_in_ready(req_1_0_3_0_ANA_r),
        .kata_out_valid(req_1_0_3_1_KATA_v), .kata_out_flit(req_1_0_3_1_KATA_f), .kata_out_ready(req_1_0_3_1_KATA_r),
        .l_in_valid(e6_req_out_valid), .l_in_flit(e6_req_out_flit), .l_in_ready(e6_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(3), .MY_W(1)) resp_r1_0_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_3_1_N_v), .s_in_flit(resp_1_1_3_1_N_f), .s_in_ready(resp_1_1_3_1_N_r),
        .s_out_valid(resp_1_0_3_1_S_v), .s_out_flit(resp_1_0_3_1_S_f), .s_out_ready(resp_1_0_3_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_3_1_E_v), .w_in_flit(resp_0_0_3_1_E_f), .w_in_ready(resp_0_0_3_1_E_r),
        .w_out_valid(resp_1_0_3_1_W_v), .w_out_flit(resp_1_0_3_1_W_f), .w_out_ready(resp_1_0_3_1_W_r),
        .u_in_valid(resp_1_0_2_1_D_v), .u_in_flit(resp_1_0_2_1_D_f), .u_in_ready(resp_1_0_2_1_D_r),
        .u_out_valid(resp_1_0_3_1_U_v), .u_out_flit(resp_1_0_3_1_U_f), .u_out_ready(resp_1_0_3_1_U_r),
        .d_in_valid(resp_1_0_4_1_U_v), .d_in_flit(resp_1_0_4_1_U_f), .d_in_ready(resp_1_0_4_1_U_r),
        .d_out_valid(resp_1_0_3_1_D_v), .d_out_flit(resp_1_0_3_1_D_f), .d_out_ready(resp_1_0_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_0_3_0_ANA_v), .kata_in_flit(resp_1_0_3_0_ANA_f), .kata_in_ready(resp_1_0_3_0_ANA_r),
        .kata_out_valid(resp_1_0_3_1_KATA_v), .kata_out_flit(resp_1_0_3_1_KATA_f), .kata_out_ready(resp_1_0_3_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e6_resp_in_valid), .l_out_flit(e6_resp_in_flit), .l_out_ready(e6_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(4), .MY_W(0)) req_r1_0_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_4_0_N_v), .s_in_flit(req_1_1_4_0_N_f), .s_in_ready(req_1_1_4_0_N_r),
        .s_out_valid(req_1_0_4_0_S_v), .s_out_flit(req_1_0_4_0_S_f), .s_out_ready(req_1_0_4_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_4_0_E_v), .w_in_flit(req_0_0_4_0_E_f), .w_in_ready(req_0_0_4_0_E_r),
        .w_out_valid(req_1_0_4_0_W_v), .w_out_flit(req_1_0_4_0_W_f), .w_out_ready(req_1_0_4_0_W_r),
        .u_in_valid(req_1_0_3_0_D_v), .u_in_flit(req_1_0_3_0_D_f), .u_in_ready(req_1_0_3_0_D_r),
        .u_out_valid(req_1_0_4_0_U_v), .u_out_flit(req_1_0_4_0_U_f), .u_out_ready(req_1_0_4_0_U_r),
        .d_in_valid(req_1_0_5_0_U_v), .d_in_flit(req_1_0_5_0_U_f), .d_in_ready(req_1_0_5_0_U_r),
        .d_out_valid(req_1_0_4_0_D_v), .d_out_flit(req_1_0_4_0_D_f), .d_out_ready(req_1_0_4_0_D_r),
        .ana_in_valid(req_1_0_4_1_KATA_v), .ana_in_flit(req_1_0_4_1_KATA_f), .ana_in_ready(req_1_0_4_1_KATA_r),
        .ana_out_valid(req_1_0_4_0_ANA_v), .ana_out_flit(req_1_0_4_0_ANA_f), .ana_out_ready(req_1_0_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e7_req_out_valid), .l_in_flit(e7_req_out_flit), .l_in_ready(e7_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(4), .MY_W(0)) resp_r1_0_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_4_0_N_v), .s_in_flit(resp_1_1_4_0_N_f), .s_in_ready(resp_1_1_4_0_N_r),
        .s_out_valid(resp_1_0_4_0_S_v), .s_out_flit(resp_1_0_4_0_S_f), .s_out_ready(resp_1_0_4_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_4_0_E_v), .w_in_flit(resp_0_0_4_0_E_f), .w_in_ready(resp_0_0_4_0_E_r),
        .w_out_valid(resp_1_0_4_0_W_v), .w_out_flit(resp_1_0_4_0_W_f), .w_out_ready(resp_1_0_4_0_W_r),
        .u_in_valid(resp_1_0_3_0_D_v), .u_in_flit(resp_1_0_3_0_D_f), .u_in_ready(resp_1_0_3_0_D_r),
        .u_out_valid(resp_1_0_4_0_U_v), .u_out_flit(resp_1_0_4_0_U_f), .u_out_ready(resp_1_0_4_0_U_r),
        .d_in_valid(resp_1_0_5_0_U_v), .d_in_flit(resp_1_0_5_0_U_f), .d_in_ready(resp_1_0_5_0_U_r),
        .d_out_valid(resp_1_0_4_0_D_v), .d_out_flit(resp_1_0_4_0_D_f), .d_out_ready(resp_1_0_4_0_D_r),
        .ana_in_valid(resp_1_0_4_1_KATA_v), .ana_in_flit(resp_1_0_4_1_KATA_f), .ana_in_ready(resp_1_0_4_1_KATA_r),
        .ana_out_valid(resp_1_0_4_0_ANA_v), .ana_out_flit(resp_1_0_4_0_ANA_f), .ana_out_ready(resp_1_0_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e7_resp_in_valid), .l_out_flit(e7_resp_in_flit), .l_out_ready(e7_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(4), .MY_W(1)) req_r1_0_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_4_1_N_v), .s_in_flit(req_1_1_4_1_N_f), .s_in_ready(req_1_1_4_1_N_r),
        .s_out_valid(req_1_0_4_1_S_v), .s_out_flit(req_1_0_4_1_S_f), .s_out_ready(req_1_0_4_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_4_1_E_v), .w_in_flit(req_0_0_4_1_E_f), .w_in_ready(req_0_0_4_1_E_r),
        .w_out_valid(req_1_0_4_1_W_v), .w_out_flit(req_1_0_4_1_W_f), .w_out_ready(req_1_0_4_1_W_r),
        .u_in_valid(req_1_0_3_1_D_v), .u_in_flit(req_1_0_3_1_D_f), .u_in_ready(req_1_0_3_1_D_r),
        .u_out_valid(req_1_0_4_1_U_v), .u_out_flit(req_1_0_4_1_U_f), .u_out_ready(req_1_0_4_1_U_r),
        .d_in_valid(req_1_0_5_1_U_v), .d_in_flit(req_1_0_5_1_U_f), .d_in_ready(req_1_0_5_1_U_r),
        .d_out_valid(req_1_0_4_1_D_v), .d_out_flit(req_1_0_4_1_D_f), .d_out_ready(req_1_0_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_0_4_0_ANA_v), .kata_in_flit(req_1_0_4_0_ANA_f), .kata_in_ready(req_1_0_4_0_ANA_r),
        .kata_out_valid(req_1_0_4_1_KATA_v), .kata_out_flit(req_1_0_4_1_KATA_f), .kata_out_ready(req_1_0_4_1_KATA_r),
        .l_in_valid(e8_req_out_valid), .l_in_flit(e8_req_out_flit), .l_in_ready(e8_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(4), .MY_W(1)) resp_r1_0_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_4_1_N_v), .s_in_flit(resp_1_1_4_1_N_f), .s_in_ready(resp_1_1_4_1_N_r),
        .s_out_valid(resp_1_0_4_1_S_v), .s_out_flit(resp_1_0_4_1_S_f), .s_out_ready(resp_1_0_4_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_4_1_E_v), .w_in_flit(resp_0_0_4_1_E_f), .w_in_ready(resp_0_0_4_1_E_r),
        .w_out_valid(resp_1_0_4_1_W_v), .w_out_flit(resp_1_0_4_1_W_f), .w_out_ready(resp_1_0_4_1_W_r),
        .u_in_valid(resp_1_0_3_1_D_v), .u_in_flit(resp_1_0_3_1_D_f), .u_in_ready(resp_1_0_3_1_D_r),
        .u_out_valid(resp_1_0_4_1_U_v), .u_out_flit(resp_1_0_4_1_U_f), .u_out_ready(resp_1_0_4_1_U_r),
        .d_in_valid(resp_1_0_5_1_U_v), .d_in_flit(resp_1_0_5_1_U_f), .d_in_ready(resp_1_0_5_1_U_r),
        .d_out_valid(resp_1_0_4_1_D_v), .d_out_flit(resp_1_0_4_1_D_f), .d_out_ready(resp_1_0_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_0_4_0_ANA_v), .kata_in_flit(resp_1_0_4_0_ANA_f), .kata_in_ready(resp_1_0_4_0_ANA_r),
        .kata_out_valid(resp_1_0_4_1_KATA_v), .kata_out_flit(resp_1_0_4_1_KATA_f), .kata_out_ready(resp_1_0_4_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e8_resp_in_valid), .l_out_flit(e8_resp_in_flit), .l_out_ready(e8_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(5), .MY_W(0)) req_r1_0_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_5_0_N_v), .s_in_flit(req_1_1_5_0_N_f), .s_in_ready(req_1_1_5_0_N_r),
        .s_out_valid(req_1_0_5_0_S_v), .s_out_flit(req_1_0_5_0_S_f), .s_out_ready(req_1_0_5_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_5_0_E_v), .w_in_flit(req_0_0_5_0_E_f), .w_in_ready(req_0_0_5_0_E_r),
        .w_out_valid(req_1_0_5_0_W_v), .w_out_flit(req_1_0_5_0_W_f), .w_out_ready(req_1_0_5_0_W_r),
        .u_in_valid(req_1_0_4_0_D_v), .u_in_flit(req_1_0_4_0_D_f), .u_in_ready(req_1_0_4_0_D_r),
        .u_out_valid(req_1_0_5_0_U_v), .u_out_flit(req_1_0_5_0_U_f), .u_out_ready(req_1_0_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(req_1_0_5_1_KATA_v), .ana_in_flit(req_1_0_5_1_KATA_f), .ana_in_ready(req_1_0_5_1_KATA_r),
        .ana_out_valid(req_1_0_5_0_ANA_v), .ana_out_flit(req_1_0_5_0_ANA_f), .ana_out_ready(req_1_0_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e9_req_out_valid), .l_in_flit(e9_req_out_flit), .l_in_ready(e9_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(5), .MY_W(0)) resp_r1_0_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_5_0_N_v), .s_in_flit(resp_1_1_5_0_N_f), .s_in_ready(resp_1_1_5_0_N_r),
        .s_out_valid(resp_1_0_5_0_S_v), .s_out_flit(resp_1_0_5_0_S_f), .s_out_ready(resp_1_0_5_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_5_0_E_v), .w_in_flit(resp_0_0_5_0_E_f), .w_in_ready(resp_0_0_5_0_E_r),
        .w_out_valid(resp_1_0_5_0_W_v), .w_out_flit(resp_1_0_5_0_W_f), .w_out_ready(resp_1_0_5_0_W_r),
        .u_in_valid(resp_1_0_4_0_D_v), .u_in_flit(resp_1_0_4_0_D_f), .u_in_ready(resp_1_0_4_0_D_r),
        .u_out_valid(resp_1_0_5_0_U_v), .u_out_flit(resp_1_0_5_0_U_f), .u_out_ready(resp_1_0_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(resp_1_0_5_1_KATA_v), .ana_in_flit(resp_1_0_5_1_KATA_f), .ana_in_ready(resp_1_0_5_1_KATA_r),
        .ana_out_valid(resp_1_0_5_0_ANA_v), .ana_out_flit(resp_1_0_5_0_ANA_f), .ana_out_ready(resp_1_0_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e9_resp_in_valid), .l_out_flit(e9_resp_in_flit), .l_out_ready(e9_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(5), .MY_W(1)) req_r1_0_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({92{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(req_1_1_5_1_N_v), .s_in_flit(req_1_1_5_1_N_f), .s_in_ready(req_1_1_5_1_N_r),
        .s_out_valid(req_1_0_5_1_S_v), .s_out_flit(req_1_0_5_1_S_f), .s_out_ready(req_1_0_5_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_0_5_1_E_v), .w_in_flit(req_0_0_5_1_E_f), .w_in_ready(req_0_0_5_1_E_r),
        .w_out_valid(req_1_0_5_1_W_v), .w_out_flit(req_1_0_5_1_W_f), .w_out_ready(req_1_0_5_1_W_r),
        .u_in_valid(req_1_0_4_1_D_v), .u_in_flit(req_1_0_4_1_D_f), .u_in_ready(req_1_0_4_1_D_r),
        .u_out_valid(req_1_0_5_1_U_v), .u_out_flit(req_1_0_5_1_U_f), .u_out_ready(req_1_0_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_0_5_0_ANA_v), .kata_in_flit(req_1_0_5_0_ANA_f), .kata_in_ready(req_1_0_5_0_ANA_r),
        .kata_out_valid(req_1_0_5_1_KATA_v), .kata_out_flit(req_1_0_5_1_KATA_f), .kata_out_ready(req_1_0_5_1_KATA_r),
        .l_in_valid(e10_req_out_valid), .l_in_flit(e10_req_out_flit), .l_in_ready(e10_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(5), .MY_W(1)) resp_r1_0_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({44{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .s_in_valid(resp_1_1_5_1_N_v), .s_in_flit(resp_1_1_5_1_N_f), .s_in_ready(resp_1_1_5_1_N_r),
        .s_out_valid(resp_1_0_5_1_S_v), .s_out_flit(resp_1_0_5_1_S_f), .s_out_ready(resp_1_0_5_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_0_5_1_E_v), .w_in_flit(resp_0_0_5_1_E_f), .w_in_ready(resp_0_0_5_1_E_r),
        .w_out_valid(resp_1_0_5_1_W_v), .w_out_flit(resp_1_0_5_1_W_f), .w_out_ready(resp_1_0_5_1_W_r),
        .u_in_valid(resp_1_0_4_1_D_v), .u_in_flit(resp_1_0_4_1_D_f), .u_in_ready(resp_1_0_4_1_D_r),
        .u_out_valid(resp_1_0_5_1_U_v), .u_out_flit(resp_1_0_5_1_U_f), .u_out_ready(resp_1_0_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_0_5_0_ANA_v), .kata_in_flit(resp_1_0_5_0_ANA_f), .kata_in_ready(resp_1_0_5_0_ANA_r),
        .kata_out_valid(resp_1_0_5_1_KATA_v), .kata_out_flit(resp_1_0_5_1_KATA_f), .kata_out_ready(resp_1_0_5_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e10_resp_in_valid), .l_out_flit(e10_resp_in_flit), .l_out_ready(e10_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(0)) req_r1_1_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_0_0_S_v), .n_in_flit(req_1_0_0_0_S_f), .n_in_ready(req_1_0_0_0_S_r),
        .n_out_valid(req_1_1_0_0_N_v), .n_out_flit(req_1_1_0_0_N_f), .n_out_ready(req_1_1_0_0_N_r),
        .s_in_valid(req_1_2_0_0_N_v), .s_in_flit(req_1_2_0_0_N_f), .s_in_ready(req_1_2_0_0_N_r),
        .s_out_valid(req_1_1_0_0_S_v), .s_out_flit(req_1_1_0_0_S_f), .s_out_ready(req_1_1_0_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_0_0_E_v), .w_in_flit(req_0_1_0_0_E_f), .w_in_ready(req_0_1_0_0_E_r),
        .w_out_valid(req_1_1_0_0_W_v), .w_out_flit(req_1_1_0_0_W_f), .w_out_ready(req_1_1_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_1_1_0_U_v), .d_in_flit(req_1_1_1_0_U_f), .d_in_ready(req_1_1_1_0_U_r),
        .d_out_valid(req_1_1_0_0_D_v), .d_out_flit(req_1_1_0_0_D_f), .d_out_ready(req_1_1_0_0_D_r),
        .ana_in_valid(req_1_1_0_1_KATA_v), .ana_in_flit(req_1_1_0_1_KATA_f), .ana_in_ready(req_1_1_0_1_KATA_r),
        .ana_out_valid(req_1_1_0_0_ANA_v), .ana_out_flit(req_1_1_0_0_ANA_f), .ana_out_ready(req_1_1_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e11_req_out_valid), .l_in_flit(e11_req_out_flit), .l_in_ready(e11_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(0)) resp_r1_1_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_0_0_S_v), .n_in_flit(resp_1_0_0_0_S_f), .n_in_ready(resp_1_0_0_0_S_r),
        .n_out_valid(resp_1_1_0_0_N_v), .n_out_flit(resp_1_1_0_0_N_f), .n_out_ready(resp_1_1_0_0_N_r),
        .s_in_valid(resp_1_2_0_0_N_v), .s_in_flit(resp_1_2_0_0_N_f), .s_in_ready(resp_1_2_0_0_N_r),
        .s_out_valid(resp_1_1_0_0_S_v), .s_out_flit(resp_1_1_0_0_S_f), .s_out_ready(resp_1_1_0_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_0_0_E_v), .w_in_flit(resp_0_1_0_0_E_f), .w_in_ready(resp_0_1_0_0_E_r),
        .w_out_valid(resp_1_1_0_0_W_v), .w_out_flit(resp_1_1_0_0_W_f), .w_out_ready(resp_1_1_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_1_1_0_U_v), .d_in_flit(resp_1_1_1_0_U_f), .d_in_ready(resp_1_1_1_0_U_r),
        .d_out_valid(resp_1_1_0_0_D_v), .d_out_flit(resp_1_1_0_0_D_f), .d_out_ready(resp_1_1_0_0_D_r),
        .ana_in_valid(resp_1_1_0_1_KATA_v), .ana_in_flit(resp_1_1_0_1_KATA_f), .ana_in_ready(resp_1_1_0_1_KATA_r),
        .ana_out_valid(resp_1_1_0_0_ANA_v), .ana_out_flit(resp_1_1_0_0_ANA_f), .ana_out_ready(resp_1_1_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e11_resp_in_valid), .l_out_flit(e11_resp_in_flit), .l_out_ready(e11_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(1)) req_r1_1_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_0_1_S_v), .n_in_flit(req_1_0_0_1_S_f), .n_in_ready(req_1_0_0_1_S_r),
        .n_out_valid(req_1_1_0_1_N_v), .n_out_flit(req_1_1_0_1_N_f), .n_out_ready(req_1_1_0_1_N_r),
        .s_in_valid(req_1_2_0_1_N_v), .s_in_flit(req_1_2_0_1_N_f), .s_in_ready(req_1_2_0_1_N_r),
        .s_out_valid(req_1_1_0_1_S_v), .s_out_flit(req_1_1_0_1_S_f), .s_out_ready(req_1_1_0_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_0_1_E_v), .w_in_flit(req_0_1_0_1_E_f), .w_in_ready(req_0_1_0_1_E_r),
        .w_out_valid(req_1_1_0_1_W_v), .w_out_flit(req_1_1_0_1_W_f), .w_out_ready(req_1_1_0_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_1_1_1_U_v), .d_in_flit(req_1_1_1_1_U_f), .d_in_ready(req_1_1_1_1_U_r),
        .d_out_valid(req_1_1_0_1_D_v), .d_out_flit(req_1_1_0_1_D_f), .d_out_ready(req_1_1_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_1_0_0_ANA_v), .kata_in_flit(req_1_1_0_0_ANA_f), .kata_in_ready(req_1_1_0_0_ANA_r),
        .kata_out_valid(req_1_1_0_1_KATA_v), .kata_out_flit(req_1_1_0_1_KATA_f), .kata_out_ready(req_1_1_0_1_KATA_r),
        .l_in_valid(e12_req_out_valid), .l_in_flit(e12_req_out_flit), .l_in_ready(e12_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(1)) resp_r1_1_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_0_1_S_v), .n_in_flit(resp_1_0_0_1_S_f), .n_in_ready(resp_1_0_0_1_S_r),
        .n_out_valid(resp_1_1_0_1_N_v), .n_out_flit(resp_1_1_0_1_N_f), .n_out_ready(resp_1_1_0_1_N_r),
        .s_in_valid(resp_1_2_0_1_N_v), .s_in_flit(resp_1_2_0_1_N_f), .s_in_ready(resp_1_2_0_1_N_r),
        .s_out_valid(resp_1_1_0_1_S_v), .s_out_flit(resp_1_1_0_1_S_f), .s_out_ready(resp_1_1_0_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_0_1_E_v), .w_in_flit(resp_0_1_0_1_E_f), .w_in_ready(resp_0_1_0_1_E_r),
        .w_out_valid(resp_1_1_0_1_W_v), .w_out_flit(resp_1_1_0_1_W_f), .w_out_ready(resp_1_1_0_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_1_1_1_U_v), .d_in_flit(resp_1_1_1_1_U_f), .d_in_ready(resp_1_1_1_1_U_r),
        .d_out_valid(resp_1_1_0_1_D_v), .d_out_flit(resp_1_1_0_1_D_f), .d_out_ready(resp_1_1_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_1_0_0_ANA_v), .kata_in_flit(resp_1_1_0_0_ANA_f), .kata_in_ready(resp_1_1_0_0_ANA_r),
        .kata_out_valid(resp_1_1_0_1_KATA_v), .kata_out_flit(resp_1_1_0_1_KATA_f), .kata_out_ready(resp_1_1_0_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e12_resp_in_valid), .l_out_flit(e12_resp_in_flit), .l_out_ready(e12_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(1), .MY_W(0)) req_r1_1_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_1_0_S_v), .n_in_flit(req_1_0_1_0_S_f), .n_in_ready(req_1_0_1_0_S_r),
        .n_out_valid(req_1_1_1_0_N_v), .n_out_flit(req_1_1_1_0_N_f), .n_out_ready(req_1_1_1_0_N_r),
        .s_in_valid(req_1_2_1_0_N_v), .s_in_flit(req_1_2_1_0_N_f), .s_in_ready(req_1_2_1_0_N_r),
        .s_out_valid(req_1_1_1_0_S_v), .s_out_flit(req_1_1_1_0_S_f), .s_out_ready(req_1_1_1_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_1_0_E_v), .w_in_flit(req_0_1_1_0_E_f), .w_in_ready(req_0_1_1_0_E_r),
        .w_out_valid(req_1_1_1_0_W_v), .w_out_flit(req_1_1_1_0_W_f), .w_out_ready(req_1_1_1_0_W_r),
        .u_in_valid(req_1_1_0_0_D_v), .u_in_flit(req_1_1_0_0_D_f), .u_in_ready(req_1_1_0_0_D_r),
        .u_out_valid(req_1_1_1_0_U_v), .u_out_flit(req_1_1_1_0_U_f), .u_out_ready(req_1_1_1_0_U_r),
        .d_in_valid(req_1_1_2_0_U_v), .d_in_flit(req_1_1_2_0_U_f), .d_in_ready(req_1_1_2_0_U_r),
        .d_out_valid(req_1_1_1_0_D_v), .d_out_flit(req_1_1_1_0_D_f), .d_out_ready(req_1_1_1_0_D_r),
        .ana_in_valid(req_1_1_1_1_KATA_v), .ana_in_flit(req_1_1_1_1_KATA_f), .ana_in_ready(req_1_1_1_1_KATA_r),
        .ana_out_valid(req_1_1_1_0_ANA_v), .ana_out_flit(req_1_1_1_0_ANA_f), .ana_out_ready(req_1_1_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e13_req_out_valid), .l_in_flit(e13_req_out_flit), .l_in_ready(e13_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(1), .MY_W(0)) resp_r1_1_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_1_0_S_v), .n_in_flit(resp_1_0_1_0_S_f), .n_in_ready(resp_1_0_1_0_S_r),
        .n_out_valid(resp_1_1_1_0_N_v), .n_out_flit(resp_1_1_1_0_N_f), .n_out_ready(resp_1_1_1_0_N_r),
        .s_in_valid(resp_1_2_1_0_N_v), .s_in_flit(resp_1_2_1_0_N_f), .s_in_ready(resp_1_2_1_0_N_r),
        .s_out_valid(resp_1_1_1_0_S_v), .s_out_flit(resp_1_1_1_0_S_f), .s_out_ready(resp_1_1_1_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_1_0_E_v), .w_in_flit(resp_0_1_1_0_E_f), .w_in_ready(resp_0_1_1_0_E_r),
        .w_out_valid(resp_1_1_1_0_W_v), .w_out_flit(resp_1_1_1_0_W_f), .w_out_ready(resp_1_1_1_0_W_r),
        .u_in_valid(resp_1_1_0_0_D_v), .u_in_flit(resp_1_1_0_0_D_f), .u_in_ready(resp_1_1_0_0_D_r),
        .u_out_valid(resp_1_1_1_0_U_v), .u_out_flit(resp_1_1_1_0_U_f), .u_out_ready(resp_1_1_1_0_U_r),
        .d_in_valid(resp_1_1_2_0_U_v), .d_in_flit(resp_1_1_2_0_U_f), .d_in_ready(resp_1_1_2_0_U_r),
        .d_out_valid(resp_1_1_1_0_D_v), .d_out_flit(resp_1_1_1_0_D_f), .d_out_ready(resp_1_1_1_0_D_r),
        .ana_in_valid(resp_1_1_1_1_KATA_v), .ana_in_flit(resp_1_1_1_1_KATA_f), .ana_in_ready(resp_1_1_1_1_KATA_r),
        .ana_out_valid(resp_1_1_1_0_ANA_v), .ana_out_flit(resp_1_1_1_0_ANA_f), .ana_out_ready(resp_1_1_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e13_resp_in_valid), .l_out_flit(e13_resp_in_flit), .l_out_ready(e13_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(1), .MY_W(1)) req_r1_1_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_1_1_S_v), .n_in_flit(req_1_0_1_1_S_f), .n_in_ready(req_1_0_1_1_S_r),
        .n_out_valid(req_1_1_1_1_N_v), .n_out_flit(req_1_1_1_1_N_f), .n_out_ready(req_1_1_1_1_N_r),
        .s_in_valid(req_1_2_1_1_N_v), .s_in_flit(req_1_2_1_1_N_f), .s_in_ready(req_1_2_1_1_N_r),
        .s_out_valid(req_1_1_1_1_S_v), .s_out_flit(req_1_1_1_1_S_f), .s_out_ready(req_1_1_1_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_1_1_E_v), .w_in_flit(req_0_1_1_1_E_f), .w_in_ready(req_0_1_1_1_E_r),
        .w_out_valid(req_1_1_1_1_W_v), .w_out_flit(req_1_1_1_1_W_f), .w_out_ready(req_1_1_1_1_W_r),
        .u_in_valid(req_1_1_0_1_D_v), .u_in_flit(req_1_1_0_1_D_f), .u_in_ready(req_1_1_0_1_D_r),
        .u_out_valid(req_1_1_1_1_U_v), .u_out_flit(req_1_1_1_1_U_f), .u_out_ready(req_1_1_1_1_U_r),
        .d_in_valid(req_1_1_2_1_U_v), .d_in_flit(req_1_1_2_1_U_f), .d_in_ready(req_1_1_2_1_U_r),
        .d_out_valid(req_1_1_1_1_D_v), .d_out_flit(req_1_1_1_1_D_f), .d_out_ready(req_1_1_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_1_1_0_ANA_v), .kata_in_flit(req_1_1_1_0_ANA_f), .kata_in_ready(req_1_1_1_0_ANA_r),
        .kata_out_valid(req_1_1_1_1_KATA_v), .kata_out_flit(req_1_1_1_1_KATA_f), .kata_out_ready(req_1_1_1_1_KATA_r),
        .l_in_valid(e14_req_out_valid), .l_in_flit(e14_req_out_flit), .l_in_ready(e14_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(1), .MY_W(1)) resp_r1_1_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_1_1_S_v), .n_in_flit(resp_1_0_1_1_S_f), .n_in_ready(resp_1_0_1_1_S_r),
        .n_out_valid(resp_1_1_1_1_N_v), .n_out_flit(resp_1_1_1_1_N_f), .n_out_ready(resp_1_1_1_1_N_r),
        .s_in_valid(resp_1_2_1_1_N_v), .s_in_flit(resp_1_2_1_1_N_f), .s_in_ready(resp_1_2_1_1_N_r),
        .s_out_valid(resp_1_1_1_1_S_v), .s_out_flit(resp_1_1_1_1_S_f), .s_out_ready(resp_1_1_1_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_1_1_E_v), .w_in_flit(resp_0_1_1_1_E_f), .w_in_ready(resp_0_1_1_1_E_r),
        .w_out_valid(resp_1_1_1_1_W_v), .w_out_flit(resp_1_1_1_1_W_f), .w_out_ready(resp_1_1_1_1_W_r),
        .u_in_valid(resp_1_1_0_1_D_v), .u_in_flit(resp_1_1_0_1_D_f), .u_in_ready(resp_1_1_0_1_D_r),
        .u_out_valid(resp_1_1_1_1_U_v), .u_out_flit(resp_1_1_1_1_U_f), .u_out_ready(resp_1_1_1_1_U_r),
        .d_in_valid(resp_1_1_2_1_U_v), .d_in_flit(resp_1_1_2_1_U_f), .d_in_ready(resp_1_1_2_1_U_r),
        .d_out_valid(resp_1_1_1_1_D_v), .d_out_flit(resp_1_1_1_1_D_f), .d_out_ready(resp_1_1_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_1_1_0_ANA_v), .kata_in_flit(resp_1_1_1_0_ANA_f), .kata_in_ready(resp_1_1_1_0_ANA_r),
        .kata_out_valid(resp_1_1_1_1_KATA_v), .kata_out_flit(resp_1_1_1_1_KATA_f), .kata_out_ready(resp_1_1_1_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e14_resp_in_valid), .l_out_flit(e14_resp_in_flit), .l_out_ready(e14_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(2), .MY_W(0)) req_r1_1_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_2_0_S_v), .n_in_flit(req_1_0_2_0_S_f), .n_in_ready(req_1_0_2_0_S_r),
        .n_out_valid(req_1_1_2_0_N_v), .n_out_flit(req_1_1_2_0_N_f), .n_out_ready(req_1_1_2_0_N_r),
        .s_in_valid(req_1_2_2_0_N_v), .s_in_flit(req_1_2_2_0_N_f), .s_in_ready(req_1_2_2_0_N_r),
        .s_out_valid(req_1_1_2_0_S_v), .s_out_flit(req_1_1_2_0_S_f), .s_out_ready(req_1_1_2_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_2_0_E_v), .w_in_flit(req_0_1_2_0_E_f), .w_in_ready(req_0_1_2_0_E_r),
        .w_out_valid(req_1_1_2_0_W_v), .w_out_flit(req_1_1_2_0_W_f), .w_out_ready(req_1_1_2_0_W_r),
        .u_in_valid(req_1_1_1_0_D_v), .u_in_flit(req_1_1_1_0_D_f), .u_in_ready(req_1_1_1_0_D_r),
        .u_out_valid(req_1_1_2_0_U_v), .u_out_flit(req_1_1_2_0_U_f), .u_out_ready(req_1_1_2_0_U_r),
        .d_in_valid(req_1_1_3_0_U_v), .d_in_flit(req_1_1_3_0_U_f), .d_in_ready(req_1_1_3_0_U_r),
        .d_out_valid(req_1_1_2_0_D_v), .d_out_flit(req_1_1_2_0_D_f), .d_out_ready(req_1_1_2_0_D_r),
        .ana_in_valid(req_1_1_2_1_KATA_v), .ana_in_flit(req_1_1_2_1_KATA_f), .ana_in_ready(req_1_1_2_1_KATA_r),
        .ana_out_valid(req_1_1_2_0_ANA_v), .ana_out_flit(req_1_1_2_0_ANA_f), .ana_out_ready(req_1_1_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e15_req_out_valid), .l_in_flit(e15_req_out_flit), .l_in_ready(e15_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(2), .MY_W(0)) resp_r1_1_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_2_0_S_v), .n_in_flit(resp_1_0_2_0_S_f), .n_in_ready(resp_1_0_2_0_S_r),
        .n_out_valid(resp_1_1_2_0_N_v), .n_out_flit(resp_1_1_2_0_N_f), .n_out_ready(resp_1_1_2_0_N_r),
        .s_in_valid(resp_1_2_2_0_N_v), .s_in_flit(resp_1_2_2_0_N_f), .s_in_ready(resp_1_2_2_0_N_r),
        .s_out_valid(resp_1_1_2_0_S_v), .s_out_flit(resp_1_1_2_0_S_f), .s_out_ready(resp_1_1_2_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_2_0_E_v), .w_in_flit(resp_0_1_2_0_E_f), .w_in_ready(resp_0_1_2_0_E_r),
        .w_out_valid(resp_1_1_2_0_W_v), .w_out_flit(resp_1_1_2_0_W_f), .w_out_ready(resp_1_1_2_0_W_r),
        .u_in_valid(resp_1_1_1_0_D_v), .u_in_flit(resp_1_1_1_0_D_f), .u_in_ready(resp_1_1_1_0_D_r),
        .u_out_valid(resp_1_1_2_0_U_v), .u_out_flit(resp_1_1_2_0_U_f), .u_out_ready(resp_1_1_2_0_U_r),
        .d_in_valid(resp_1_1_3_0_U_v), .d_in_flit(resp_1_1_3_0_U_f), .d_in_ready(resp_1_1_3_0_U_r),
        .d_out_valid(resp_1_1_2_0_D_v), .d_out_flit(resp_1_1_2_0_D_f), .d_out_ready(resp_1_1_2_0_D_r),
        .ana_in_valid(resp_1_1_2_1_KATA_v), .ana_in_flit(resp_1_1_2_1_KATA_f), .ana_in_ready(resp_1_1_2_1_KATA_r),
        .ana_out_valid(resp_1_1_2_0_ANA_v), .ana_out_flit(resp_1_1_2_0_ANA_f), .ana_out_ready(resp_1_1_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e15_resp_in_valid), .l_out_flit(e15_resp_in_flit), .l_out_ready(e15_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(2), .MY_W(1)) req_r1_1_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_2_1_S_v), .n_in_flit(req_1_0_2_1_S_f), .n_in_ready(req_1_0_2_1_S_r),
        .n_out_valid(req_1_1_2_1_N_v), .n_out_flit(req_1_1_2_1_N_f), .n_out_ready(req_1_1_2_1_N_r),
        .s_in_valid(req_1_2_2_1_N_v), .s_in_flit(req_1_2_2_1_N_f), .s_in_ready(req_1_2_2_1_N_r),
        .s_out_valid(req_1_1_2_1_S_v), .s_out_flit(req_1_1_2_1_S_f), .s_out_ready(req_1_1_2_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_2_1_E_v), .w_in_flit(req_0_1_2_1_E_f), .w_in_ready(req_0_1_2_1_E_r),
        .w_out_valid(req_1_1_2_1_W_v), .w_out_flit(req_1_1_2_1_W_f), .w_out_ready(req_1_1_2_1_W_r),
        .u_in_valid(req_1_1_1_1_D_v), .u_in_flit(req_1_1_1_1_D_f), .u_in_ready(req_1_1_1_1_D_r),
        .u_out_valid(req_1_1_2_1_U_v), .u_out_flit(req_1_1_2_1_U_f), .u_out_ready(req_1_1_2_1_U_r),
        .d_in_valid(req_1_1_3_1_U_v), .d_in_flit(req_1_1_3_1_U_f), .d_in_ready(req_1_1_3_1_U_r),
        .d_out_valid(req_1_1_2_1_D_v), .d_out_flit(req_1_1_2_1_D_f), .d_out_ready(req_1_1_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_1_2_0_ANA_v), .kata_in_flit(req_1_1_2_0_ANA_f), .kata_in_ready(req_1_1_2_0_ANA_r),
        .kata_out_valid(req_1_1_2_1_KATA_v), .kata_out_flit(req_1_1_2_1_KATA_f), .kata_out_ready(req_1_1_2_1_KATA_r),
        .l_in_valid(e16_req_out_valid), .l_in_flit(e16_req_out_flit), .l_in_ready(e16_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(2), .MY_W(1)) resp_r1_1_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_2_1_S_v), .n_in_flit(resp_1_0_2_1_S_f), .n_in_ready(resp_1_0_2_1_S_r),
        .n_out_valid(resp_1_1_2_1_N_v), .n_out_flit(resp_1_1_2_1_N_f), .n_out_ready(resp_1_1_2_1_N_r),
        .s_in_valid(resp_1_2_2_1_N_v), .s_in_flit(resp_1_2_2_1_N_f), .s_in_ready(resp_1_2_2_1_N_r),
        .s_out_valid(resp_1_1_2_1_S_v), .s_out_flit(resp_1_1_2_1_S_f), .s_out_ready(resp_1_1_2_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_2_1_E_v), .w_in_flit(resp_0_1_2_1_E_f), .w_in_ready(resp_0_1_2_1_E_r),
        .w_out_valid(resp_1_1_2_1_W_v), .w_out_flit(resp_1_1_2_1_W_f), .w_out_ready(resp_1_1_2_1_W_r),
        .u_in_valid(resp_1_1_1_1_D_v), .u_in_flit(resp_1_1_1_1_D_f), .u_in_ready(resp_1_1_1_1_D_r),
        .u_out_valid(resp_1_1_2_1_U_v), .u_out_flit(resp_1_1_2_1_U_f), .u_out_ready(resp_1_1_2_1_U_r),
        .d_in_valid(resp_1_1_3_1_U_v), .d_in_flit(resp_1_1_3_1_U_f), .d_in_ready(resp_1_1_3_1_U_r),
        .d_out_valid(resp_1_1_2_1_D_v), .d_out_flit(resp_1_1_2_1_D_f), .d_out_ready(resp_1_1_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_1_2_0_ANA_v), .kata_in_flit(resp_1_1_2_0_ANA_f), .kata_in_ready(resp_1_1_2_0_ANA_r),
        .kata_out_valid(resp_1_1_2_1_KATA_v), .kata_out_flit(resp_1_1_2_1_KATA_f), .kata_out_ready(resp_1_1_2_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e16_resp_in_valid), .l_out_flit(e16_resp_in_flit), .l_out_ready(e16_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(3), .MY_W(0)) req_r1_1_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_3_0_S_v), .n_in_flit(req_1_0_3_0_S_f), .n_in_ready(req_1_0_3_0_S_r),
        .n_out_valid(req_1_1_3_0_N_v), .n_out_flit(req_1_1_3_0_N_f), .n_out_ready(req_1_1_3_0_N_r),
        .s_in_valid(req_1_2_3_0_N_v), .s_in_flit(req_1_2_3_0_N_f), .s_in_ready(req_1_2_3_0_N_r),
        .s_out_valid(req_1_1_3_0_S_v), .s_out_flit(req_1_1_3_0_S_f), .s_out_ready(req_1_1_3_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_3_0_E_v), .w_in_flit(req_0_1_3_0_E_f), .w_in_ready(req_0_1_3_0_E_r),
        .w_out_valid(req_1_1_3_0_W_v), .w_out_flit(req_1_1_3_0_W_f), .w_out_ready(req_1_1_3_0_W_r),
        .u_in_valid(req_1_1_2_0_D_v), .u_in_flit(req_1_1_2_0_D_f), .u_in_ready(req_1_1_2_0_D_r),
        .u_out_valid(req_1_1_3_0_U_v), .u_out_flit(req_1_1_3_0_U_f), .u_out_ready(req_1_1_3_0_U_r),
        .d_in_valid(req_1_1_4_0_U_v), .d_in_flit(req_1_1_4_0_U_f), .d_in_ready(req_1_1_4_0_U_r),
        .d_out_valid(req_1_1_3_0_D_v), .d_out_flit(req_1_1_3_0_D_f), .d_out_ready(req_1_1_3_0_D_r),
        .ana_in_valid(req_1_1_3_1_KATA_v), .ana_in_flit(req_1_1_3_1_KATA_f), .ana_in_ready(req_1_1_3_1_KATA_r),
        .ana_out_valid(req_1_1_3_0_ANA_v), .ana_out_flit(req_1_1_3_0_ANA_f), .ana_out_ready(req_1_1_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e17_req_out_valid), .l_in_flit(e17_req_out_flit), .l_in_ready(e17_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(3), .MY_W(0)) resp_r1_1_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_3_0_S_v), .n_in_flit(resp_1_0_3_0_S_f), .n_in_ready(resp_1_0_3_0_S_r),
        .n_out_valid(resp_1_1_3_0_N_v), .n_out_flit(resp_1_1_3_0_N_f), .n_out_ready(resp_1_1_3_0_N_r),
        .s_in_valid(resp_1_2_3_0_N_v), .s_in_flit(resp_1_2_3_0_N_f), .s_in_ready(resp_1_2_3_0_N_r),
        .s_out_valid(resp_1_1_3_0_S_v), .s_out_flit(resp_1_1_3_0_S_f), .s_out_ready(resp_1_1_3_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_3_0_E_v), .w_in_flit(resp_0_1_3_0_E_f), .w_in_ready(resp_0_1_3_0_E_r),
        .w_out_valid(resp_1_1_3_0_W_v), .w_out_flit(resp_1_1_3_0_W_f), .w_out_ready(resp_1_1_3_0_W_r),
        .u_in_valid(resp_1_1_2_0_D_v), .u_in_flit(resp_1_1_2_0_D_f), .u_in_ready(resp_1_1_2_0_D_r),
        .u_out_valid(resp_1_1_3_0_U_v), .u_out_flit(resp_1_1_3_0_U_f), .u_out_ready(resp_1_1_3_0_U_r),
        .d_in_valid(resp_1_1_4_0_U_v), .d_in_flit(resp_1_1_4_0_U_f), .d_in_ready(resp_1_1_4_0_U_r),
        .d_out_valid(resp_1_1_3_0_D_v), .d_out_flit(resp_1_1_3_0_D_f), .d_out_ready(resp_1_1_3_0_D_r),
        .ana_in_valid(resp_1_1_3_1_KATA_v), .ana_in_flit(resp_1_1_3_1_KATA_f), .ana_in_ready(resp_1_1_3_1_KATA_r),
        .ana_out_valid(resp_1_1_3_0_ANA_v), .ana_out_flit(resp_1_1_3_0_ANA_f), .ana_out_ready(resp_1_1_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e17_resp_in_valid), .l_out_flit(e17_resp_in_flit), .l_out_ready(e17_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(3), .MY_W(1)) req_r1_1_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_3_1_S_v), .n_in_flit(req_1_0_3_1_S_f), .n_in_ready(req_1_0_3_1_S_r),
        .n_out_valid(req_1_1_3_1_N_v), .n_out_flit(req_1_1_3_1_N_f), .n_out_ready(req_1_1_3_1_N_r),
        .s_in_valid(req_1_2_3_1_N_v), .s_in_flit(req_1_2_3_1_N_f), .s_in_ready(req_1_2_3_1_N_r),
        .s_out_valid(req_1_1_3_1_S_v), .s_out_flit(req_1_1_3_1_S_f), .s_out_ready(req_1_1_3_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_3_1_E_v), .w_in_flit(req_0_1_3_1_E_f), .w_in_ready(req_0_1_3_1_E_r),
        .w_out_valid(req_1_1_3_1_W_v), .w_out_flit(req_1_1_3_1_W_f), .w_out_ready(req_1_1_3_1_W_r),
        .u_in_valid(req_1_1_2_1_D_v), .u_in_flit(req_1_1_2_1_D_f), .u_in_ready(req_1_1_2_1_D_r),
        .u_out_valid(req_1_1_3_1_U_v), .u_out_flit(req_1_1_3_1_U_f), .u_out_ready(req_1_1_3_1_U_r),
        .d_in_valid(req_1_1_4_1_U_v), .d_in_flit(req_1_1_4_1_U_f), .d_in_ready(req_1_1_4_1_U_r),
        .d_out_valid(req_1_1_3_1_D_v), .d_out_flit(req_1_1_3_1_D_f), .d_out_ready(req_1_1_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_1_3_0_ANA_v), .kata_in_flit(req_1_1_3_0_ANA_f), .kata_in_ready(req_1_1_3_0_ANA_r),
        .kata_out_valid(req_1_1_3_1_KATA_v), .kata_out_flit(req_1_1_3_1_KATA_f), .kata_out_ready(req_1_1_3_1_KATA_r),
        .l_in_valid(e18_req_out_valid), .l_in_flit(e18_req_out_flit), .l_in_ready(e18_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(3), .MY_W(1)) resp_r1_1_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_3_1_S_v), .n_in_flit(resp_1_0_3_1_S_f), .n_in_ready(resp_1_0_3_1_S_r),
        .n_out_valid(resp_1_1_3_1_N_v), .n_out_flit(resp_1_1_3_1_N_f), .n_out_ready(resp_1_1_3_1_N_r),
        .s_in_valid(resp_1_2_3_1_N_v), .s_in_flit(resp_1_2_3_1_N_f), .s_in_ready(resp_1_2_3_1_N_r),
        .s_out_valid(resp_1_1_3_1_S_v), .s_out_flit(resp_1_1_3_1_S_f), .s_out_ready(resp_1_1_3_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_3_1_E_v), .w_in_flit(resp_0_1_3_1_E_f), .w_in_ready(resp_0_1_3_1_E_r),
        .w_out_valid(resp_1_1_3_1_W_v), .w_out_flit(resp_1_1_3_1_W_f), .w_out_ready(resp_1_1_3_1_W_r),
        .u_in_valid(resp_1_1_2_1_D_v), .u_in_flit(resp_1_1_2_1_D_f), .u_in_ready(resp_1_1_2_1_D_r),
        .u_out_valid(resp_1_1_3_1_U_v), .u_out_flit(resp_1_1_3_1_U_f), .u_out_ready(resp_1_1_3_1_U_r),
        .d_in_valid(resp_1_1_4_1_U_v), .d_in_flit(resp_1_1_4_1_U_f), .d_in_ready(resp_1_1_4_1_U_r),
        .d_out_valid(resp_1_1_3_1_D_v), .d_out_flit(resp_1_1_3_1_D_f), .d_out_ready(resp_1_1_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_1_3_0_ANA_v), .kata_in_flit(resp_1_1_3_0_ANA_f), .kata_in_ready(resp_1_1_3_0_ANA_r),
        .kata_out_valid(resp_1_1_3_1_KATA_v), .kata_out_flit(resp_1_1_3_1_KATA_f), .kata_out_ready(resp_1_1_3_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e18_resp_in_valid), .l_out_flit(e18_resp_in_flit), .l_out_ready(e18_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(4), .MY_W(0)) req_r1_1_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_4_0_S_v), .n_in_flit(req_1_0_4_0_S_f), .n_in_ready(req_1_0_4_0_S_r),
        .n_out_valid(req_1_1_4_0_N_v), .n_out_flit(req_1_1_4_0_N_f), .n_out_ready(req_1_1_4_0_N_r),
        .s_in_valid(req_1_2_4_0_N_v), .s_in_flit(req_1_2_4_0_N_f), .s_in_ready(req_1_2_4_0_N_r),
        .s_out_valid(req_1_1_4_0_S_v), .s_out_flit(req_1_1_4_0_S_f), .s_out_ready(req_1_1_4_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_4_0_E_v), .w_in_flit(req_0_1_4_0_E_f), .w_in_ready(req_0_1_4_0_E_r),
        .w_out_valid(req_1_1_4_0_W_v), .w_out_flit(req_1_1_4_0_W_f), .w_out_ready(req_1_1_4_0_W_r),
        .u_in_valid(req_1_1_3_0_D_v), .u_in_flit(req_1_1_3_0_D_f), .u_in_ready(req_1_1_3_0_D_r),
        .u_out_valid(req_1_1_4_0_U_v), .u_out_flit(req_1_1_4_0_U_f), .u_out_ready(req_1_1_4_0_U_r),
        .d_in_valid(req_1_1_5_0_U_v), .d_in_flit(req_1_1_5_0_U_f), .d_in_ready(req_1_1_5_0_U_r),
        .d_out_valid(req_1_1_4_0_D_v), .d_out_flit(req_1_1_4_0_D_f), .d_out_ready(req_1_1_4_0_D_r),
        .ana_in_valid(req_1_1_4_1_KATA_v), .ana_in_flit(req_1_1_4_1_KATA_f), .ana_in_ready(req_1_1_4_1_KATA_r),
        .ana_out_valid(req_1_1_4_0_ANA_v), .ana_out_flit(req_1_1_4_0_ANA_f), .ana_out_ready(req_1_1_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e19_req_out_valid), .l_in_flit(e19_req_out_flit), .l_in_ready(e19_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(4), .MY_W(0)) resp_r1_1_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_4_0_S_v), .n_in_flit(resp_1_0_4_0_S_f), .n_in_ready(resp_1_0_4_0_S_r),
        .n_out_valid(resp_1_1_4_0_N_v), .n_out_flit(resp_1_1_4_0_N_f), .n_out_ready(resp_1_1_4_0_N_r),
        .s_in_valid(resp_1_2_4_0_N_v), .s_in_flit(resp_1_2_4_0_N_f), .s_in_ready(resp_1_2_4_0_N_r),
        .s_out_valid(resp_1_1_4_0_S_v), .s_out_flit(resp_1_1_4_0_S_f), .s_out_ready(resp_1_1_4_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_4_0_E_v), .w_in_flit(resp_0_1_4_0_E_f), .w_in_ready(resp_0_1_4_0_E_r),
        .w_out_valid(resp_1_1_4_0_W_v), .w_out_flit(resp_1_1_4_0_W_f), .w_out_ready(resp_1_1_4_0_W_r),
        .u_in_valid(resp_1_1_3_0_D_v), .u_in_flit(resp_1_1_3_0_D_f), .u_in_ready(resp_1_1_3_0_D_r),
        .u_out_valid(resp_1_1_4_0_U_v), .u_out_flit(resp_1_1_4_0_U_f), .u_out_ready(resp_1_1_4_0_U_r),
        .d_in_valid(resp_1_1_5_0_U_v), .d_in_flit(resp_1_1_5_0_U_f), .d_in_ready(resp_1_1_5_0_U_r),
        .d_out_valid(resp_1_1_4_0_D_v), .d_out_flit(resp_1_1_4_0_D_f), .d_out_ready(resp_1_1_4_0_D_r),
        .ana_in_valid(resp_1_1_4_1_KATA_v), .ana_in_flit(resp_1_1_4_1_KATA_f), .ana_in_ready(resp_1_1_4_1_KATA_r),
        .ana_out_valid(resp_1_1_4_0_ANA_v), .ana_out_flit(resp_1_1_4_0_ANA_f), .ana_out_ready(resp_1_1_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e19_resp_in_valid), .l_out_flit(e19_resp_in_flit), .l_out_ready(e19_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(4), .MY_W(1)) req_r1_1_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_4_1_S_v), .n_in_flit(req_1_0_4_1_S_f), .n_in_ready(req_1_0_4_1_S_r),
        .n_out_valid(req_1_1_4_1_N_v), .n_out_flit(req_1_1_4_1_N_f), .n_out_ready(req_1_1_4_1_N_r),
        .s_in_valid(req_1_2_4_1_N_v), .s_in_flit(req_1_2_4_1_N_f), .s_in_ready(req_1_2_4_1_N_r),
        .s_out_valid(req_1_1_4_1_S_v), .s_out_flit(req_1_1_4_1_S_f), .s_out_ready(req_1_1_4_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_4_1_E_v), .w_in_flit(req_0_1_4_1_E_f), .w_in_ready(req_0_1_4_1_E_r),
        .w_out_valid(req_1_1_4_1_W_v), .w_out_flit(req_1_1_4_1_W_f), .w_out_ready(req_1_1_4_1_W_r),
        .u_in_valid(req_1_1_3_1_D_v), .u_in_flit(req_1_1_3_1_D_f), .u_in_ready(req_1_1_3_1_D_r),
        .u_out_valid(req_1_1_4_1_U_v), .u_out_flit(req_1_1_4_1_U_f), .u_out_ready(req_1_1_4_1_U_r),
        .d_in_valid(req_1_1_5_1_U_v), .d_in_flit(req_1_1_5_1_U_f), .d_in_ready(req_1_1_5_1_U_r),
        .d_out_valid(req_1_1_4_1_D_v), .d_out_flit(req_1_1_4_1_D_f), .d_out_ready(req_1_1_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_1_4_0_ANA_v), .kata_in_flit(req_1_1_4_0_ANA_f), .kata_in_ready(req_1_1_4_0_ANA_r),
        .kata_out_valid(req_1_1_4_1_KATA_v), .kata_out_flit(req_1_1_4_1_KATA_f), .kata_out_ready(req_1_1_4_1_KATA_r),
        .l_in_valid(e20_req_out_valid), .l_in_flit(e20_req_out_flit), .l_in_ready(e20_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(4), .MY_W(1)) resp_r1_1_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_4_1_S_v), .n_in_flit(resp_1_0_4_1_S_f), .n_in_ready(resp_1_0_4_1_S_r),
        .n_out_valid(resp_1_1_4_1_N_v), .n_out_flit(resp_1_1_4_1_N_f), .n_out_ready(resp_1_1_4_1_N_r),
        .s_in_valid(resp_1_2_4_1_N_v), .s_in_flit(resp_1_2_4_1_N_f), .s_in_ready(resp_1_2_4_1_N_r),
        .s_out_valid(resp_1_1_4_1_S_v), .s_out_flit(resp_1_1_4_1_S_f), .s_out_ready(resp_1_1_4_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_4_1_E_v), .w_in_flit(resp_0_1_4_1_E_f), .w_in_ready(resp_0_1_4_1_E_r),
        .w_out_valid(resp_1_1_4_1_W_v), .w_out_flit(resp_1_1_4_1_W_f), .w_out_ready(resp_1_1_4_1_W_r),
        .u_in_valid(resp_1_1_3_1_D_v), .u_in_flit(resp_1_1_3_1_D_f), .u_in_ready(resp_1_1_3_1_D_r),
        .u_out_valid(resp_1_1_4_1_U_v), .u_out_flit(resp_1_1_4_1_U_f), .u_out_ready(resp_1_1_4_1_U_r),
        .d_in_valid(resp_1_1_5_1_U_v), .d_in_flit(resp_1_1_5_1_U_f), .d_in_ready(resp_1_1_5_1_U_r),
        .d_out_valid(resp_1_1_4_1_D_v), .d_out_flit(resp_1_1_4_1_D_f), .d_out_ready(resp_1_1_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_1_4_0_ANA_v), .kata_in_flit(resp_1_1_4_0_ANA_f), .kata_in_ready(resp_1_1_4_0_ANA_r),
        .kata_out_valid(resp_1_1_4_1_KATA_v), .kata_out_flit(resp_1_1_4_1_KATA_f), .kata_out_ready(resp_1_1_4_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e20_resp_in_valid), .l_out_flit(e20_resp_in_flit), .l_out_ready(e20_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(5), .MY_W(0)) req_r1_1_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_5_0_S_v), .n_in_flit(req_1_0_5_0_S_f), .n_in_ready(req_1_0_5_0_S_r),
        .n_out_valid(req_1_1_5_0_N_v), .n_out_flit(req_1_1_5_0_N_f), .n_out_ready(req_1_1_5_0_N_r),
        .s_in_valid(req_1_2_5_0_N_v), .s_in_flit(req_1_2_5_0_N_f), .s_in_ready(req_1_2_5_0_N_r),
        .s_out_valid(req_1_1_5_0_S_v), .s_out_flit(req_1_1_5_0_S_f), .s_out_ready(req_1_1_5_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_5_0_E_v), .w_in_flit(req_0_1_5_0_E_f), .w_in_ready(req_0_1_5_0_E_r),
        .w_out_valid(req_1_1_5_0_W_v), .w_out_flit(req_1_1_5_0_W_f), .w_out_ready(req_1_1_5_0_W_r),
        .u_in_valid(req_1_1_4_0_D_v), .u_in_flit(req_1_1_4_0_D_f), .u_in_ready(req_1_1_4_0_D_r),
        .u_out_valid(req_1_1_5_0_U_v), .u_out_flit(req_1_1_5_0_U_f), .u_out_ready(req_1_1_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(req_1_1_5_1_KATA_v), .ana_in_flit(req_1_1_5_1_KATA_f), .ana_in_ready(req_1_1_5_1_KATA_r),
        .ana_out_valid(req_1_1_5_0_ANA_v), .ana_out_flit(req_1_1_5_0_ANA_f), .ana_out_ready(req_1_1_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e21_req_out_valid), .l_in_flit(e21_req_out_flit), .l_in_ready(e21_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(5), .MY_W(0)) resp_r1_1_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_5_0_S_v), .n_in_flit(resp_1_0_5_0_S_f), .n_in_ready(resp_1_0_5_0_S_r),
        .n_out_valid(resp_1_1_5_0_N_v), .n_out_flit(resp_1_1_5_0_N_f), .n_out_ready(resp_1_1_5_0_N_r),
        .s_in_valid(resp_1_2_5_0_N_v), .s_in_flit(resp_1_2_5_0_N_f), .s_in_ready(resp_1_2_5_0_N_r),
        .s_out_valid(resp_1_1_5_0_S_v), .s_out_flit(resp_1_1_5_0_S_f), .s_out_ready(resp_1_1_5_0_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_5_0_E_v), .w_in_flit(resp_0_1_5_0_E_f), .w_in_ready(resp_0_1_5_0_E_r),
        .w_out_valid(resp_1_1_5_0_W_v), .w_out_flit(resp_1_1_5_0_W_f), .w_out_ready(resp_1_1_5_0_W_r),
        .u_in_valid(resp_1_1_4_0_D_v), .u_in_flit(resp_1_1_4_0_D_f), .u_in_ready(resp_1_1_4_0_D_r),
        .u_out_valid(resp_1_1_5_0_U_v), .u_out_flit(resp_1_1_5_0_U_f), .u_out_ready(resp_1_1_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(resp_1_1_5_1_KATA_v), .ana_in_flit(resp_1_1_5_1_KATA_f), .ana_in_ready(resp_1_1_5_1_KATA_r),
        .ana_out_valid(resp_1_1_5_0_ANA_v), .ana_out_flit(resp_1_1_5_0_ANA_f), .ana_out_ready(resp_1_1_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e21_resp_in_valid), .l_out_flit(e21_resp_in_flit), .l_out_ready(e21_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(5), .MY_W(1)) req_r1_1_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_5_1_S_v), .n_in_flit(req_1_0_5_1_S_f), .n_in_ready(req_1_0_5_1_S_r),
        .n_out_valid(req_1_1_5_1_N_v), .n_out_flit(req_1_1_5_1_N_f), .n_out_ready(req_1_1_5_1_N_r),
        .s_in_valid(req_1_2_5_1_N_v), .s_in_flit(req_1_2_5_1_N_f), .s_in_ready(req_1_2_5_1_N_r),
        .s_out_valid(req_1_1_5_1_S_v), .s_out_flit(req_1_1_5_1_S_f), .s_out_ready(req_1_1_5_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_1_5_1_E_v), .w_in_flit(req_0_1_5_1_E_f), .w_in_ready(req_0_1_5_1_E_r),
        .w_out_valid(req_1_1_5_1_W_v), .w_out_flit(req_1_1_5_1_W_f), .w_out_ready(req_1_1_5_1_W_r),
        .u_in_valid(req_1_1_4_1_D_v), .u_in_flit(req_1_1_4_1_D_f), .u_in_ready(req_1_1_4_1_D_r),
        .u_out_valid(req_1_1_5_1_U_v), .u_out_flit(req_1_1_5_1_U_f), .u_out_ready(req_1_1_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_1_5_0_ANA_v), .kata_in_flit(req_1_1_5_0_ANA_f), .kata_in_ready(req_1_1_5_0_ANA_r),
        .kata_out_valid(req_1_1_5_1_KATA_v), .kata_out_flit(req_1_1_5_1_KATA_f), .kata_out_ready(req_1_1_5_1_KATA_r),
        .l_in_valid(e22_req_out_valid), .l_in_flit(e22_req_out_flit), .l_in_ready(e22_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(5), .MY_W(1)) resp_r1_1_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_5_1_S_v), .n_in_flit(resp_1_0_5_1_S_f), .n_in_ready(resp_1_0_5_1_S_r),
        .n_out_valid(resp_1_1_5_1_N_v), .n_out_flit(resp_1_1_5_1_N_f), .n_out_ready(resp_1_1_5_1_N_r),
        .s_in_valid(resp_1_2_5_1_N_v), .s_in_flit(resp_1_2_5_1_N_f), .s_in_ready(resp_1_2_5_1_N_r),
        .s_out_valid(resp_1_1_5_1_S_v), .s_out_flit(resp_1_1_5_1_S_f), .s_out_ready(resp_1_1_5_1_S_r),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_1_5_1_E_v), .w_in_flit(resp_0_1_5_1_E_f), .w_in_ready(resp_0_1_5_1_E_r),
        .w_out_valid(resp_1_1_5_1_W_v), .w_out_flit(resp_1_1_5_1_W_f), .w_out_ready(resp_1_1_5_1_W_r),
        .u_in_valid(resp_1_1_4_1_D_v), .u_in_flit(resp_1_1_4_1_D_f), .u_in_ready(resp_1_1_4_1_D_r),
        .u_out_valid(resp_1_1_5_1_U_v), .u_out_flit(resp_1_1_5_1_U_f), .u_out_ready(resp_1_1_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_1_5_0_ANA_v), .kata_in_flit(resp_1_1_5_0_ANA_f), .kata_in_ready(resp_1_1_5_0_ANA_r),
        .kata_out_valid(resp_1_1_5_1_KATA_v), .kata_out_flit(resp_1_1_5_1_KATA_f), .kata_out_ready(resp_1_1_5_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e22_resp_in_valid), .l_out_flit(e22_resp_in_flit), .l_out_ready(e22_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(0)) req_r1_2_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_0_0_S_v), .n_in_flit(req_1_1_0_0_S_f), .n_in_ready(req_1_1_0_0_S_r),
        .n_out_valid(req_1_2_0_0_N_v), .n_out_flit(req_1_2_0_0_N_f), .n_out_ready(req_1_2_0_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_0_0_E_v), .w_in_flit(req_0_2_0_0_E_f), .w_in_ready(req_0_2_0_0_E_r),
        .w_out_valid(req_1_2_0_0_W_v), .w_out_flit(req_1_2_0_0_W_f), .w_out_ready(req_1_2_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_2_1_0_U_v), .d_in_flit(req_1_2_1_0_U_f), .d_in_ready(req_1_2_1_0_U_r),
        .d_out_valid(req_1_2_0_0_D_v), .d_out_flit(req_1_2_0_0_D_f), .d_out_ready(req_1_2_0_0_D_r),
        .ana_in_valid(req_1_2_0_1_KATA_v), .ana_in_flit(req_1_2_0_1_KATA_f), .ana_in_ready(req_1_2_0_1_KATA_r),
        .ana_out_valid(req_1_2_0_0_ANA_v), .ana_out_flit(req_1_2_0_0_ANA_f), .ana_out_ready(req_1_2_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e23_req_out_valid), .l_in_flit(e23_req_out_flit), .l_in_ready(e23_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(0)) resp_r1_2_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_0_0_S_v), .n_in_flit(resp_1_1_0_0_S_f), .n_in_ready(resp_1_1_0_0_S_r),
        .n_out_valid(resp_1_2_0_0_N_v), .n_out_flit(resp_1_2_0_0_N_f), .n_out_ready(resp_1_2_0_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_0_0_E_v), .w_in_flit(resp_0_2_0_0_E_f), .w_in_ready(resp_0_2_0_0_E_r),
        .w_out_valid(resp_1_2_0_0_W_v), .w_out_flit(resp_1_2_0_0_W_f), .w_out_ready(resp_1_2_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_2_1_0_U_v), .d_in_flit(resp_1_2_1_0_U_f), .d_in_ready(resp_1_2_1_0_U_r),
        .d_out_valid(resp_1_2_0_0_D_v), .d_out_flit(resp_1_2_0_0_D_f), .d_out_ready(resp_1_2_0_0_D_r),
        .ana_in_valid(resp_1_2_0_1_KATA_v), .ana_in_flit(resp_1_2_0_1_KATA_f), .ana_in_ready(resp_1_2_0_1_KATA_r),
        .ana_out_valid(resp_1_2_0_0_ANA_v), .ana_out_flit(resp_1_2_0_0_ANA_f), .ana_out_ready(resp_1_2_0_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e23_resp_in_valid), .l_out_flit(e23_resp_in_flit), .l_out_ready(e23_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(1)) req_r1_2_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_0_1_S_v), .n_in_flit(req_1_1_0_1_S_f), .n_in_ready(req_1_1_0_1_S_r),
        .n_out_valid(req_1_2_0_1_N_v), .n_out_flit(req_1_2_0_1_N_f), .n_out_ready(req_1_2_0_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_0_1_E_v), .w_in_flit(req_0_2_0_1_E_f), .w_in_ready(req_0_2_0_1_E_r),
        .w_out_valid(req_1_2_0_1_W_v), .w_out_flit(req_1_2_0_1_W_f), .w_out_ready(req_1_2_0_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({92{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_2_1_1_U_v), .d_in_flit(req_1_2_1_1_U_f), .d_in_ready(req_1_2_1_1_U_r),
        .d_out_valid(req_1_2_0_1_D_v), .d_out_flit(req_1_2_0_1_D_f), .d_out_ready(req_1_2_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_2_0_0_ANA_v), .kata_in_flit(req_1_2_0_0_ANA_f), .kata_in_ready(req_1_2_0_0_ANA_r),
        .kata_out_valid(req_1_2_0_1_KATA_v), .kata_out_flit(req_1_2_0_1_KATA_f), .kata_out_ready(req_1_2_0_1_KATA_r),
        .l_in_valid(e24_req_out_valid), .l_in_flit(e24_req_out_flit), .l_in_ready(e24_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(1)) resp_r1_2_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_0_1_S_v), .n_in_flit(resp_1_1_0_1_S_f), .n_in_ready(resp_1_1_0_1_S_r),
        .n_out_valid(resp_1_2_0_1_N_v), .n_out_flit(resp_1_2_0_1_N_f), .n_out_ready(resp_1_2_0_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_0_1_E_v), .w_in_flit(resp_0_2_0_1_E_f), .w_in_ready(resp_0_2_0_1_E_r),
        .w_out_valid(resp_1_2_0_1_W_v), .w_out_flit(resp_1_2_0_1_W_f), .w_out_ready(resp_1_2_0_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({44{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_2_1_1_U_v), .d_in_flit(resp_1_2_1_1_U_f), .d_in_ready(resp_1_2_1_1_U_r),
        .d_out_valid(resp_1_2_0_1_D_v), .d_out_flit(resp_1_2_0_1_D_f), .d_out_ready(resp_1_2_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_2_0_0_ANA_v), .kata_in_flit(resp_1_2_0_0_ANA_f), .kata_in_ready(resp_1_2_0_0_ANA_r),
        .kata_out_valid(resp_1_2_0_1_KATA_v), .kata_out_flit(resp_1_2_0_1_KATA_f), .kata_out_ready(resp_1_2_0_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e24_resp_in_valid), .l_out_flit(e24_resp_in_flit), .l_out_ready(e24_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(1), .MY_W(0)) req_r1_2_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_1_0_S_v), .n_in_flit(req_1_1_1_0_S_f), .n_in_ready(req_1_1_1_0_S_r),
        .n_out_valid(req_1_2_1_0_N_v), .n_out_flit(req_1_2_1_0_N_f), .n_out_ready(req_1_2_1_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_1_0_E_v), .w_in_flit(req_0_2_1_0_E_f), .w_in_ready(req_0_2_1_0_E_r),
        .w_out_valid(req_1_2_1_0_W_v), .w_out_flit(req_1_2_1_0_W_f), .w_out_ready(req_1_2_1_0_W_r),
        .u_in_valid(req_1_2_0_0_D_v), .u_in_flit(req_1_2_0_0_D_f), .u_in_ready(req_1_2_0_0_D_r),
        .u_out_valid(req_1_2_1_0_U_v), .u_out_flit(req_1_2_1_0_U_f), .u_out_ready(req_1_2_1_0_U_r),
        .d_in_valid(req_1_2_2_0_U_v), .d_in_flit(req_1_2_2_0_U_f), .d_in_ready(req_1_2_2_0_U_r),
        .d_out_valid(req_1_2_1_0_D_v), .d_out_flit(req_1_2_1_0_D_f), .d_out_ready(req_1_2_1_0_D_r),
        .ana_in_valid(req_1_2_1_1_KATA_v), .ana_in_flit(req_1_2_1_1_KATA_f), .ana_in_ready(req_1_2_1_1_KATA_r),
        .ana_out_valid(req_1_2_1_0_ANA_v), .ana_out_flit(req_1_2_1_0_ANA_f), .ana_out_ready(req_1_2_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e25_req_out_valid), .l_in_flit(e25_req_out_flit), .l_in_ready(e25_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(1), .MY_W(0)) resp_r1_2_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_1_0_S_v), .n_in_flit(resp_1_1_1_0_S_f), .n_in_ready(resp_1_1_1_0_S_r),
        .n_out_valid(resp_1_2_1_0_N_v), .n_out_flit(resp_1_2_1_0_N_f), .n_out_ready(resp_1_2_1_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_1_0_E_v), .w_in_flit(resp_0_2_1_0_E_f), .w_in_ready(resp_0_2_1_0_E_r),
        .w_out_valid(resp_1_2_1_0_W_v), .w_out_flit(resp_1_2_1_0_W_f), .w_out_ready(resp_1_2_1_0_W_r),
        .u_in_valid(resp_1_2_0_0_D_v), .u_in_flit(resp_1_2_0_0_D_f), .u_in_ready(resp_1_2_0_0_D_r),
        .u_out_valid(resp_1_2_1_0_U_v), .u_out_flit(resp_1_2_1_0_U_f), .u_out_ready(resp_1_2_1_0_U_r),
        .d_in_valid(resp_1_2_2_0_U_v), .d_in_flit(resp_1_2_2_0_U_f), .d_in_ready(resp_1_2_2_0_U_r),
        .d_out_valid(resp_1_2_1_0_D_v), .d_out_flit(resp_1_2_1_0_D_f), .d_out_ready(resp_1_2_1_0_D_r),
        .ana_in_valid(resp_1_2_1_1_KATA_v), .ana_in_flit(resp_1_2_1_1_KATA_f), .ana_in_ready(resp_1_2_1_1_KATA_r),
        .ana_out_valid(resp_1_2_1_0_ANA_v), .ana_out_flit(resp_1_2_1_0_ANA_f), .ana_out_ready(resp_1_2_1_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e25_resp_in_valid), .l_out_flit(e25_resp_in_flit), .l_out_ready(e25_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(1), .MY_W(1)) req_r1_2_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_1_1_S_v), .n_in_flit(req_1_1_1_1_S_f), .n_in_ready(req_1_1_1_1_S_r),
        .n_out_valid(req_1_2_1_1_N_v), .n_out_flit(req_1_2_1_1_N_f), .n_out_ready(req_1_2_1_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_1_1_E_v), .w_in_flit(req_0_2_1_1_E_f), .w_in_ready(req_0_2_1_1_E_r),
        .w_out_valid(req_1_2_1_1_W_v), .w_out_flit(req_1_2_1_1_W_f), .w_out_ready(req_1_2_1_1_W_r),
        .u_in_valid(req_1_2_0_1_D_v), .u_in_flit(req_1_2_0_1_D_f), .u_in_ready(req_1_2_0_1_D_r),
        .u_out_valid(req_1_2_1_1_U_v), .u_out_flit(req_1_2_1_1_U_f), .u_out_ready(req_1_2_1_1_U_r),
        .d_in_valid(req_1_2_2_1_U_v), .d_in_flit(req_1_2_2_1_U_f), .d_in_ready(req_1_2_2_1_U_r),
        .d_out_valid(req_1_2_1_1_D_v), .d_out_flit(req_1_2_1_1_D_f), .d_out_ready(req_1_2_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_2_1_0_ANA_v), .kata_in_flit(req_1_2_1_0_ANA_f), .kata_in_ready(req_1_2_1_0_ANA_r),
        .kata_out_valid(req_1_2_1_1_KATA_v), .kata_out_flit(req_1_2_1_1_KATA_f), .kata_out_ready(req_1_2_1_1_KATA_r),
        .l_in_valid(e26_req_out_valid), .l_in_flit(e26_req_out_flit), .l_in_ready(e26_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(1), .MY_W(1)) resp_r1_2_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_1_1_S_v), .n_in_flit(resp_1_1_1_1_S_f), .n_in_ready(resp_1_1_1_1_S_r),
        .n_out_valid(resp_1_2_1_1_N_v), .n_out_flit(resp_1_2_1_1_N_f), .n_out_ready(resp_1_2_1_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_1_1_E_v), .w_in_flit(resp_0_2_1_1_E_f), .w_in_ready(resp_0_2_1_1_E_r),
        .w_out_valid(resp_1_2_1_1_W_v), .w_out_flit(resp_1_2_1_1_W_f), .w_out_ready(resp_1_2_1_1_W_r),
        .u_in_valid(resp_1_2_0_1_D_v), .u_in_flit(resp_1_2_0_1_D_f), .u_in_ready(resp_1_2_0_1_D_r),
        .u_out_valid(resp_1_2_1_1_U_v), .u_out_flit(resp_1_2_1_1_U_f), .u_out_ready(resp_1_2_1_1_U_r),
        .d_in_valid(resp_1_2_2_1_U_v), .d_in_flit(resp_1_2_2_1_U_f), .d_in_ready(resp_1_2_2_1_U_r),
        .d_out_valid(resp_1_2_1_1_D_v), .d_out_flit(resp_1_2_1_1_D_f), .d_out_ready(resp_1_2_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_2_1_0_ANA_v), .kata_in_flit(resp_1_2_1_0_ANA_f), .kata_in_ready(resp_1_2_1_0_ANA_r),
        .kata_out_valid(resp_1_2_1_1_KATA_v), .kata_out_flit(resp_1_2_1_1_KATA_f), .kata_out_ready(resp_1_2_1_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e26_resp_in_valid), .l_out_flit(e26_resp_in_flit), .l_out_ready(e26_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(2), .MY_W(0)) req_r1_2_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_2_0_S_v), .n_in_flit(req_1_1_2_0_S_f), .n_in_ready(req_1_1_2_0_S_r),
        .n_out_valid(req_1_2_2_0_N_v), .n_out_flit(req_1_2_2_0_N_f), .n_out_ready(req_1_2_2_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_2_0_E_v), .w_in_flit(req_0_2_2_0_E_f), .w_in_ready(req_0_2_2_0_E_r),
        .w_out_valid(req_1_2_2_0_W_v), .w_out_flit(req_1_2_2_0_W_f), .w_out_ready(req_1_2_2_0_W_r),
        .u_in_valid(req_1_2_1_0_D_v), .u_in_flit(req_1_2_1_0_D_f), .u_in_ready(req_1_2_1_0_D_r),
        .u_out_valid(req_1_2_2_0_U_v), .u_out_flit(req_1_2_2_0_U_f), .u_out_ready(req_1_2_2_0_U_r),
        .d_in_valid(req_1_2_3_0_U_v), .d_in_flit(req_1_2_3_0_U_f), .d_in_ready(req_1_2_3_0_U_r),
        .d_out_valid(req_1_2_2_0_D_v), .d_out_flit(req_1_2_2_0_D_f), .d_out_ready(req_1_2_2_0_D_r),
        .ana_in_valid(req_1_2_2_1_KATA_v), .ana_in_flit(req_1_2_2_1_KATA_f), .ana_in_ready(req_1_2_2_1_KATA_r),
        .ana_out_valid(req_1_2_2_0_ANA_v), .ana_out_flit(req_1_2_2_0_ANA_f), .ana_out_ready(req_1_2_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e27_req_out_valid), .l_in_flit(e27_req_out_flit), .l_in_ready(e27_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(2), .MY_W(0)) resp_r1_2_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_2_0_S_v), .n_in_flit(resp_1_1_2_0_S_f), .n_in_ready(resp_1_1_2_0_S_r),
        .n_out_valid(resp_1_2_2_0_N_v), .n_out_flit(resp_1_2_2_0_N_f), .n_out_ready(resp_1_2_2_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_2_0_E_v), .w_in_flit(resp_0_2_2_0_E_f), .w_in_ready(resp_0_2_2_0_E_r),
        .w_out_valid(resp_1_2_2_0_W_v), .w_out_flit(resp_1_2_2_0_W_f), .w_out_ready(resp_1_2_2_0_W_r),
        .u_in_valid(resp_1_2_1_0_D_v), .u_in_flit(resp_1_2_1_0_D_f), .u_in_ready(resp_1_2_1_0_D_r),
        .u_out_valid(resp_1_2_2_0_U_v), .u_out_flit(resp_1_2_2_0_U_f), .u_out_ready(resp_1_2_2_0_U_r),
        .d_in_valid(resp_1_2_3_0_U_v), .d_in_flit(resp_1_2_3_0_U_f), .d_in_ready(resp_1_2_3_0_U_r),
        .d_out_valid(resp_1_2_2_0_D_v), .d_out_flit(resp_1_2_2_0_D_f), .d_out_ready(resp_1_2_2_0_D_r),
        .ana_in_valid(resp_1_2_2_1_KATA_v), .ana_in_flit(resp_1_2_2_1_KATA_f), .ana_in_ready(resp_1_2_2_1_KATA_r),
        .ana_out_valid(resp_1_2_2_0_ANA_v), .ana_out_flit(resp_1_2_2_0_ANA_f), .ana_out_ready(resp_1_2_2_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e27_resp_in_valid), .l_out_flit(e27_resp_in_flit), .l_out_ready(e27_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(2), .MY_W(1)) req_r1_2_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_2_1_S_v), .n_in_flit(req_1_1_2_1_S_f), .n_in_ready(req_1_1_2_1_S_r),
        .n_out_valid(req_1_2_2_1_N_v), .n_out_flit(req_1_2_2_1_N_f), .n_out_ready(req_1_2_2_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_2_1_E_v), .w_in_flit(req_0_2_2_1_E_f), .w_in_ready(req_0_2_2_1_E_r),
        .w_out_valid(req_1_2_2_1_W_v), .w_out_flit(req_1_2_2_1_W_f), .w_out_ready(req_1_2_2_1_W_r),
        .u_in_valid(req_1_2_1_1_D_v), .u_in_flit(req_1_2_1_1_D_f), .u_in_ready(req_1_2_1_1_D_r),
        .u_out_valid(req_1_2_2_1_U_v), .u_out_flit(req_1_2_2_1_U_f), .u_out_ready(req_1_2_2_1_U_r),
        .d_in_valid(req_1_2_3_1_U_v), .d_in_flit(req_1_2_3_1_U_f), .d_in_ready(req_1_2_3_1_U_r),
        .d_out_valid(req_1_2_2_1_D_v), .d_out_flit(req_1_2_2_1_D_f), .d_out_ready(req_1_2_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_2_2_0_ANA_v), .kata_in_flit(req_1_2_2_0_ANA_f), .kata_in_ready(req_1_2_2_0_ANA_r),
        .kata_out_valid(req_1_2_2_1_KATA_v), .kata_out_flit(req_1_2_2_1_KATA_f), .kata_out_ready(req_1_2_2_1_KATA_r),
        .l_in_valid(e28_req_out_valid), .l_in_flit(e28_req_out_flit), .l_in_ready(e28_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(2), .MY_W(1)) resp_r1_2_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_2_1_S_v), .n_in_flit(resp_1_1_2_1_S_f), .n_in_ready(resp_1_1_2_1_S_r),
        .n_out_valid(resp_1_2_2_1_N_v), .n_out_flit(resp_1_2_2_1_N_f), .n_out_ready(resp_1_2_2_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_2_1_E_v), .w_in_flit(resp_0_2_2_1_E_f), .w_in_ready(resp_0_2_2_1_E_r),
        .w_out_valid(resp_1_2_2_1_W_v), .w_out_flit(resp_1_2_2_1_W_f), .w_out_ready(resp_1_2_2_1_W_r),
        .u_in_valid(resp_1_2_1_1_D_v), .u_in_flit(resp_1_2_1_1_D_f), .u_in_ready(resp_1_2_1_1_D_r),
        .u_out_valid(resp_1_2_2_1_U_v), .u_out_flit(resp_1_2_2_1_U_f), .u_out_ready(resp_1_2_2_1_U_r),
        .d_in_valid(resp_1_2_3_1_U_v), .d_in_flit(resp_1_2_3_1_U_f), .d_in_ready(resp_1_2_3_1_U_r),
        .d_out_valid(resp_1_2_2_1_D_v), .d_out_flit(resp_1_2_2_1_D_f), .d_out_ready(resp_1_2_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_2_2_0_ANA_v), .kata_in_flit(resp_1_2_2_0_ANA_f), .kata_in_ready(resp_1_2_2_0_ANA_r),
        .kata_out_valid(resp_1_2_2_1_KATA_v), .kata_out_flit(resp_1_2_2_1_KATA_f), .kata_out_ready(resp_1_2_2_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e28_resp_in_valid), .l_out_flit(e28_resp_in_flit), .l_out_ready(e28_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(3), .MY_W(0)) req_r1_2_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_3_0_S_v), .n_in_flit(req_1_1_3_0_S_f), .n_in_ready(req_1_1_3_0_S_r),
        .n_out_valid(req_1_2_3_0_N_v), .n_out_flit(req_1_2_3_0_N_f), .n_out_ready(req_1_2_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_3_0_E_v), .w_in_flit(req_0_2_3_0_E_f), .w_in_ready(req_0_2_3_0_E_r),
        .w_out_valid(req_1_2_3_0_W_v), .w_out_flit(req_1_2_3_0_W_f), .w_out_ready(req_1_2_3_0_W_r),
        .u_in_valid(req_1_2_2_0_D_v), .u_in_flit(req_1_2_2_0_D_f), .u_in_ready(req_1_2_2_0_D_r),
        .u_out_valid(req_1_2_3_0_U_v), .u_out_flit(req_1_2_3_0_U_f), .u_out_ready(req_1_2_3_0_U_r),
        .d_in_valid(req_1_2_4_0_U_v), .d_in_flit(req_1_2_4_0_U_f), .d_in_ready(req_1_2_4_0_U_r),
        .d_out_valid(req_1_2_3_0_D_v), .d_out_flit(req_1_2_3_0_D_f), .d_out_ready(req_1_2_3_0_D_r),
        .ana_in_valid(req_1_2_3_1_KATA_v), .ana_in_flit(req_1_2_3_1_KATA_f), .ana_in_ready(req_1_2_3_1_KATA_r),
        .ana_out_valid(req_1_2_3_0_ANA_v), .ana_out_flit(req_1_2_3_0_ANA_f), .ana_out_ready(req_1_2_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e29_req_out_valid), .l_in_flit(e29_req_out_flit), .l_in_ready(e29_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(3), .MY_W(0)) resp_r1_2_3_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_3_0_S_v), .n_in_flit(resp_1_1_3_0_S_f), .n_in_ready(resp_1_1_3_0_S_r),
        .n_out_valid(resp_1_2_3_0_N_v), .n_out_flit(resp_1_2_3_0_N_f), .n_out_ready(resp_1_2_3_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_3_0_E_v), .w_in_flit(resp_0_2_3_0_E_f), .w_in_ready(resp_0_2_3_0_E_r),
        .w_out_valid(resp_1_2_3_0_W_v), .w_out_flit(resp_1_2_3_0_W_f), .w_out_ready(resp_1_2_3_0_W_r),
        .u_in_valid(resp_1_2_2_0_D_v), .u_in_flit(resp_1_2_2_0_D_f), .u_in_ready(resp_1_2_2_0_D_r),
        .u_out_valid(resp_1_2_3_0_U_v), .u_out_flit(resp_1_2_3_0_U_f), .u_out_ready(resp_1_2_3_0_U_r),
        .d_in_valid(resp_1_2_4_0_U_v), .d_in_flit(resp_1_2_4_0_U_f), .d_in_ready(resp_1_2_4_0_U_r),
        .d_out_valid(resp_1_2_3_0_D_v), .d_out_flit(resp_1_2_3_0_D_f), .d_out_ready(resp_1_2_3_0_D_r),
        .ana_in_valid(resp_1_2_3_1_KATA_v), .ana_in_flit(resp_1_2_3_1_KATA_f), .ana_in_ready(resp_1_2_3_1_KATA_r),
        .ana_out_valid(resp_1_2_3_0_ANA_v), .ana_out_flit(resp_1_2_3_0_ANA_f), .ana_out_ready(resp_1_2_3_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e29_resp_in_valid), .l_out_flit(e29_resp_in_flit), .l_out_ready(e29_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(3), .MY_W(1)) req_r1_2_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_3_1_S_v), .n_in_flit(req_1_1_3_1_S_f), .n_in_ready(req_1_1_3_1_S_r),
        .n_out_valid(req_1_2_3_1_N_v), .n_out_flit(req_1_2_3_1_N_f), .n_out_ready(req_1_2_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_3_1_E_v), .w_in_flit(req_0_2_3_1_E_f), .w_in_ready(req_0_2_3_1_E_r),
        .w_out_valid(req_1_2_3_1_W_v), .w_out_flit(req_1_2_3_1_W_f), .w_out_ready(req_1_2_3_1_W_r),
        .u_in_valid(req_1_2_2_1_D_v), .u_in_flit(req_1_2_2_1_D_f), .u_in_ready(req_1_2_2_1_D_r),
        .u_out_valid(req_1_2_3_1_U_v), .u_out_flit(req_1_2_3_1_U_f), .u_out_ready(req_1_2_3_1_U_r),
        .d_in_valid(req_1_2_4_1_U_v), .d_in_flit(req_1_2_4_1_U_f), .d_in_ready(req_1_2_4_1_U_r),
        .d_out_valid(req_1_2_3_1_D_v), .d_out_flit(req_1_2_3_1_D_f), .d_out_ready(req_1_2_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_2_3_0_ANA_v), .kata_in_flit(req_1_2_3_0_ANA_f), .kata_in_ready(req_1_2_3_0_ANA_r),
        .kata_out_valid(req_1_2_3_1_KATA_v), .kata_out_flit(req_1_2_3_1_KATA_f), .kata_out_ready(req_1_2_3_1_KATA_r),
        .l_in_valid(e30_req_out_valid), .l_in_flit(e30_req_out_flit), .l_in_ready(e30_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(3), .MY_W(1)) resp_r1_2_3_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_3_1_S_v), .n_in_flit(resp_1_1_3_1_S_f), .n_in_ready(resp_1_1_3_1_S_r),
        .n_out_valid(resp_1_2_3_1_N_v), .n_out_flit(resp_1_2_3_1_N_f), .n_out_ready(resp_1_2_3_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_3_1_E_v), .w_in_flit(resp_0_2_3_1_E_f), .w_in_ready(resp_0_2_3_1_E_r),
        .w_out_valid(resp_1_2_3_1_W_v), .w_out_flit(resp_1_2_3_1_W_f), .w_out_ready(resp_1_2_3_1_W_r),
        .u_in_valid(resp_1_2_2_1_D_v), .u_in_flit(resp_1_2_2_1_D_f), .u_in_ready(resp_1_2_2_1_D_r),
        .u_out_valid(resp_1_2_3_1_U_v), .u_out_flit(resp_1_2_3_1_U_f), .u_out_ready(resp_1_2_3_1_U_r),
        .d_in_valid(resp_1_2_4_1_U_v), .d_in_flit(resp_1_2_4_1_U_f), .d_in_ready(resp_1_2_4_1_U_r),
        .d_out_valid(resp_1_2_3_1_D_v), .d_out_flit(resp_1_2_3_1_D_f), .d_out_ready(resp_1_2_3_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_2_3_0_ANA_v), .kata_in_flit(resp_1_2_3_0_ANA_f), .kata_in_ready(resp_1_2_3_0_ANA_r),
        .kata_out_valid(resp_1_2_3_1_KATA_v), .kata_out_flit(resp_1_2_3_1_KATA_f), .kata_out_ready(resp_1_2_3_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e30_resp_in_valid), .l_out_flit(e30_resp_in_flit), .l_out_ready(e30_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(4), .MY_W(0)) req_r1_2_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_4_0_S_v), .n_in_flit(req_1_1_4_0_S_f), .n_in_ready(req_1_1_4_0_S_r),
        .n_out_valid(req_1_2_4_0_N_v), .n_out_flit(req_1_2_4_0_N_f), .n_out_ready(req_1_2_4_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_4_0_E_v), .w_in_flit(req_0_2_4_0_E_f), .w_in_ready(req_0_2_4_0_E_r),
        .w_out_valid(req_1_2_4_0_W_v), .w_out_flit(req_1_2_4_0_W_f), .w_out_ready(req_1_2_4_0_W_r),
        .u_in_valid(req_1_2_3_0_D_v), .u_in_flit(req_1_2_3_0_D_f), .u_in_ready(req_1_2_3_0_D_r),
        .u_out_valid(req_1_2_4_0_U_v), .u_out_flit(req_1_2_4_0_U_f), .u_out_ready(req_1_2_4_0_U_r),
        .d_in_valid(req_1_2_5_0_U_v), .d_in_flit(req_1_2_5_0_U_f), .d_in_ready(req_1_2_5_0_U_r),
        .d_out_valid(req_1_2_4_0_D_v), .d_out_flit(req_1_2_4_0_D_f), .d_out_ready(req_1_2_4_0_D_r),
        .ana_in_valid(req_1_2_4_1_KATA_v), .ana_in_flit(req_1_2_4_1_KATA_f), .ana_in_ready(req_1_2_4_1_KATA_r),
        .ana_out_valid(req_1_2_4_0_ANA_v), .ana_out_flit(req_1_2_4_0_ANA_f), .ana_out_ready(req_1_2_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e31_req_out_valid), .l_in_flit(e31_req_out_flit), .l_in_ready(e31_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(4), .MY_W(0)) resp_r1_2_4_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_4_0_S_v), .n_in_flit(resp_1_1_4_0_S_f), .n_in_ready(resp_1_1_4_0_S_r),
        .n_out_valid(resp_1_2_4_0_N_v), .n_out_flit(resp_1_2_4_0_N_f), .n_out_ready(resp_1_2_4_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_4_0_E_v), .w_in_flit(resp_0_2_4_0_E_f), .w_in_ready(resp_0_2_4_0_E_r),
        .w_out_valid(resp_1_2_4_0_W_v), .w_out_flit(resp_1_2_4_0_W_f), .w_out_ready(resp_1_2_4_0_W_r),
        .u_in_valid(resp_1_2_3_0_D_v), .u_in_flit(resp_1_2_3_0_D_f), .u_in_ready(resp_1_2_3_0_D_r),
        .u_out_valid(resp_1_2_4_0_U_v), .u_out_flit(resp_1_2_4_0_U_f), .u_out_ready(resp_1_2_4_0_U_r),
        .d_in_valid(resp_1_2_5_0_U_v), .d_in_flit(resp_1_2_5_0_U_f), .d_in_ready(resp_1_2_5_0_U_r),
        .d_out_valid(resp_1_2_4_0_D_v), .d_out_flit(resp_1_2_4_0_D_f), .d_out_ready(resp_1_2_4_0_D_r),
        .ana_in_valid(resp_1_2_4_1_KATA_v), .ana_in_flit(resp_1_2_4_1_KATA_f), .ana_in_ready(resp_1_2_4_1_KATA_r),
        .ana_out_valid(resp_1_2_4_0_ANA_v), .ana_out_flit(resp_1_2_4_0_ANA_f), .ana_out_ready(resp_1_2_4_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e31_resp_in_valid), .l_out_flit(e31_resp_in_flit), .l_out_ready(e31_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(4), .MY_W(1)) req_r1_2_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_4_1_S_v), .n_in_flit(req_1_1_4_1_S_f), .n_in_ready(req_1_1_4_1_S_r),
        .n_out_valid(req_1_2_4_1_N_v), .n_out_flit(req_1_2_4_1_N_f), .n_out_ready(req_1_2_4_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_4_1_E_v), .w_in_flit(req_0_2_4_1_E_f), .w_in_ready(req_0_2_4_1_E_r),
        .w_out_valid(req_1_2_4_1_W_v), .w_out_flit(req_1_2_4_1_W_f), .w_out_ready(req_1_2_4_1_W_r),
        .u_in_valid(req_1_2_3_1_D_v), .u_in_flit(req_1_2_3_1_D_f), .u_in_ready(req_1_2_3_1_D_r),
        .u_out_valid(req_1_2_4_1_U_v), .u_out_flit(req_1_2_4_1_U_f), .u_out_ready(req_1_2_4_1_U_r),
        .d_in_valid(req_1_2_5_1_U_v), .d_in_flit(req_1_2_5_1_U_f), .d_in_ready(req_1_2_5_1_U_r),
        .d_out_valid(req_1_2_4_1_D_v), .d_out_flit(req_1_2_4_1_D_f), .d_out_ready(req_1_2_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_2_4_0_ANA_v), .kata_in_flit(req_1_2_4_0_ANA_f), .kata_in_ready(req_1_2_4_0_ANA_r),
        .kata_out_valid(req_1_2_4_1_KATA_v), .kata_out_flit(req_1_2_4_1_KATA_f), .kata_out_ready(req_1_2_4_1_KATA_r),
        .l_in_valid(e32_req_out_valid), .l_in_flit(e32_req_out_flit), .l_in_ready(e32_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(4), .MY_W(1)) resp_r1_2_4_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_4_1_S_v), .n_in_flit(resp_1_1_4_1_S_f), .n_in_ready(resp_1_1_4_1_S_r),
        .n_out_valid(resp_1_2_4_1_N_v), .n_out_flit(resp_1_2_4_1_N_f), .n_out_ready(resp_1_2_4_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_4_1_E_v), .w_in_flit(resp_0_2_4_1_E_f), .w_in_ready(resp_0_2_4_1_E_r),
        .w_out_valid(resp_1_2_4_1_W_v), .w_out_flit(resp_1_2_4_1_W_f), .w_out_ready(resp_1_2_4_1_W_r),
        .u_in_valid(resp_1_2_3_1_D_v), .u_in_flit(resp_1_2_3_1_D_f), .u_in_ready(resp_1_2_3_1_D_r),
        .u_out_valid(resp_1_2_4_1_U_v), .u_out_flit(resp_1_2_4_1_U_f), .u_out_ready(resp_1_2_4_1_U_r),
        .d_in_valid(resp_1_2_5_1_U_v), .d_in_flit(resp_1_2_5_1_U_f), .d_in_ready(resp_1_2_5_1_U_r),
        .d_out_valid(resp_1_2_4_1_D_v), .d_out_flit(resp_1_2_4_1_D_f), .d_out_ready(resp_1_2_4_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_2_4_0_ANA_v), .kata_in_flit(resp_1_2_4_0_ANA_f), .kata_in_ready(resp_1_2_4_0_ANA_r),
        .kata_out_valid(resp_1_2_4_1_KATA_v), .kata_out_flit(resp_1_2_4_1_KATA_f), .kata_out_ready(resp_1_2_4_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e32_resp_in_valid), .l_out_flit(e32_resp_in_flit), .l_out_ready(e32_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(5), .MY_W(0)) req_r1_2_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_5_0_S_v), .n_in_flit(req_1_1_5_0_S_f), .n_in_ready(req_1_1_5_0_S_r),
        .n_out_valid(req_1_2_5_0_N_v), .n_out_flit(req_1_2_5_0_N_f), .n_out_ready(req_1_2_5_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_5_0_E_v), .w_in_flit(req_0_2_5_0_E_f), .w_in_ready(req_0_2_5_0_E_r),
        .w_out_valid(req_1_2_5_0_W_v), .w_out_flit(req_1_2_5_0_W_f), .w_out_ready(req_1_2_5_0_W_r),
        .u_in_valid(req_1_2_4_0_D_v), .u_in_flit(req_1_2_4_0_D_f), .u_in_ready(req_1_2_4_0_D_r),
        .u_out_valid(req_1_2_5_0_U_v), .u_out_flit(req_1_2_5_0_U_f), .u_out_ready(req_1_2_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(req_1_2_5_1_KATA_v), .ana_in_flit(req_1_2_5_1_KATA_f), .ana_in_ready(req_1_2_5_1_KATA_r),
        .ana_out_valid(req_1_2_5_0_ANA_v), .ana_out_flit(req_1_2_5_0_ANA_f), .ana_out_ready(req_1_2_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({92{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(e33_req_out_valid), .l_in_flit(e33_req_out_flit), .l_in_ready(e33_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(5), .MY_W(0)) resp_r1_2_5_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_5_0_S_v), .n_in_flit(resp_1_1_5_0_S_f), .n_in_ready(resp_1_1_5_0_S_r),
        .n_out_valid(resp_1_2_5_0_N_v), .n_out_flit(resp_1_2_5_0_N_f), .n_out_ready(resp_1_2_5_0_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_5_0_E_v), .w_in_flit(resp_0_2_5_0_E_f), .w_in_ready(resp_0_2_5_0_E_r),
        .w_out_valid(resp_1_2_5_0_W_v), .w_out_flit(resp_1_2_5_0_W_f), .w_out_ready(resp_1_2_5_0_W_r),
        .u_in_valid(resp_1_2_4_0_D_v), .u_in_flit(resp_1_2_4_0_D_f), .u_in_ready(resp_1_2_4_0_D_r),
        .u_out_valid(resp_1_2_5_0_U_v), .u_out_flit(resp_1_2_5_0_U_f), .u_out_ready(resp_1_2_5_0_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(resp_1_2_5_1_KATA_v), .ana_in_flit(resp_1_2_5_1_KATA_f), .ana_in_ready(resp_1_2_5_1_KATA_r),
        .ana_out_valid(resp_1_2_5_0_ANA_v), .ana_out_flit(resp_1_2_5_0_ANA_f), .ana_out_ready(resp_1_2_5_0_ANA_r),
        .kata_in_valid(1'b0), .kata_in_flit({44{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e33_resp_in_valid), .l_out_flit(e33_resp_in_flit), .l_out_ready(e33_resp_in_ready)
    );

    router #(.FLIT_WIDTH(92), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(5), .MY_W(1)) req_r1_2_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_5_1_S_v), .n_in_flit(req_1_1_5_1_S_f), .n_in_ready(req_1_1_5_1_S_r),
        .n_out_valid(req_1_2_5_1_N_v), .n_out_flit(req_1_2_5_1_N_f), .n_out_ready(req_1_2_5_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({92{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({92{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(req_0_2_5_1_E_v), .w_in_flit(req_0_2_5_1_E_f), .w_in_ready(req_0_2_5_1_E_r),
        .w_out_valid(req_1_2_5_1_W_v), .w_out_flit(req_1_2_5_1_W_f), .w_out_ready(req_1_2_5_1_W_r),
        .u_in_valid(req_1_2_4_1_D_v), .u_in_flit(req_1_2_4_1_D_f), .u_in_ready(req_1_2_4_1_D_r),
        .u_out_valid(req_1_2_5_1_U_v), .u_out_flit(req_1_2_5_1_U_f), .u_out_ready(req_1_2_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({92{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({92{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(req_1_2_5_0_ANA_v), .kata_in_flit(req_1_2_5_0_ANA_f), .kata_in_ready(req_1_2_5_0_ANA_r),
        .kata_out_valid(req_1_2_5_1_KATA_v), .kata_out_flit(req_1_2_5_1_KATA_f), .kata_out_ready(req_1_2_5_1_KATA_r),
        .l_in_valid(e34_req_out_valid), .l_in_flit(e34_req_out_flit), .l_in_ready(e34_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(44), .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(5), .MY_W(1)) resp_r1_2_5_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_5_1_S_v), .n_in_flit(resp_1_1_5_1_S_f), .n_in_ready(resp_1_1_5_1_S_r),
        .n_out_valid(resp_1_2_5_1_N_v), .n_out_flit(resp_1_2_5_1_N_f), .n_out_ready(resp_1_2_5_1_N_r),
        .s_in_valid(1'b0), .s_in_flit({44{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({44{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .w_in_valid(resp_0_2_5_1_E_v), .w_in_flit(resp_0_2_5_1_E_f), .w_in_ready(resp_0_2_5_1_E_r),
        .w_out_valid(resp_1_2_5_1_W_v), .w_out_flit(resp_1_2_5_1_W_f), .w_out_ready(resp_1_2_5_1_W_r),
        .u_in_valid(resp_1_2_4_1_D_v), .u_in_flit(resp_1_2_4_1_D_f), .u_in_ready(resp_1_2_4_1_D_r),
        .u_out_valid(resp_1_2_5_1_U_v), .u_out_flit(resp_1_2_5_1_U_f), .u_out_ready(resp_1_2_5_1_U_r),
        .d_in_valid(1'b0), .d_in_flit({44{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({44{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(resp_1_2_5_0_ANA_v), .kata_in_flit(resp_1_2_5_0_ANA_f), .kata_in_ready(resp_1_2_5_0_ANA_r),
        .kata_out_valid(resp_1_2_5_1_KATA_v), .kata_out_flit(resp_1_2_5_1_KATA_f), .kata_out_ready(resp_1_2_5_1_KATA_r),
        .l_in_valid(1'b0), .l_in_flit({44{1'b0}}), .l_in_ready(),
        .l_out_valid(e34_resp_in_valid), .l_out_flit(e34_resp_in_flit), .l_out_ready(e34_resp_in_ready)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(1), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(1), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(2), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(2), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(3), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(3), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(4), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(4), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(5), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(0), .MY_Z(5), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(1), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(1), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(2), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(3), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p17_adap (
        .clk(clk), .reset(reset),
        .bus_req(p17_bus_req), .bus_addr(p17_bus_addr), .bus_write_data(p17_bus_write_data),
        .bus_mem_write(p17_bus_mem_write), .bus_mem_size(p17_bus_mem_size), .bus_mem_unsigned(p17_bus_mem_unsigned),
        .bus_grant(p17_bus_grant), .bus_read_data(p17_bus_read_data),
        .req_out_valid(p17_req_out_valid), .req_out_flit(p17_req_out_flit), .req_out_ready(p17_req_out_ready),
        .resp_in_valid(p17_resp_in_valid), .resp_in_flit(p17_resp_in_flit), .resp_in_ready(p17_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P18_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p18_core (
        .clk(clk), .reset(reset),
        .halted(p18_halted), .tohost_value(p18_tohost),
        .bus_req(p18_bus_req), .bus_addr(p18_bus_addr),
        .bus_write_data(p18_bus_write_data), .bus_mem_write(p18_bus_mem_write),
        .bus_mem_size(p18_bus_mem_size), .bus_mem_unsigned(p18_bus_mem_unsigned),
        .bus_grant(p18_bus_grant), .bus_read_data(p18_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(3), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p18_adap (
        .clk(clk), .reset(reset),
        .bus_req(p18_bus_req), .bus_addr(p18_bus_addr), .bus_write_data(p18_bus_write_data),
        .bus_mem_write(p18_bus_mem_write), .bus_mem_size(p18_bus_mem_size), .bus_mem_unsigned(p18_bus_mem_unsigned),
        .bus_grant(p18_bus_grant), .bus_read_data(p18_bus_read_data),
        .req_out_valid(p18_req_out_valid), .req_out_flit(p18_req_out_flit), .req_out_ready(p18_req_out_ready),
        .resp_in_valid(p18_resp_in_valid), .resp_in_flit(p18_resp_in_flit), .resp_in_ready(p18_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P19_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p19_core (
        .clk(clk), .reset(reset),
        .halted(p19_halted), .tohost_value(p19_tohost),
        .bus_req(p19_bus_req), .bus_addr(p19_bus_addr),
        .bus_write_data(p19_bus_write_data), .bus_mem_write(p19_bus_mem_write),
        .bus_mem_size(p19_bus_mem_size), .bus_mem_unsigned(p19_bus_mem_unsigned),
        .bus_grant(p19_bus_grant), .bus_read_data(p19_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(4), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p19_adap (
        .clk(clk), .reset(reset),
        .bus_req(p19_bus_req), .bus_addr(p19_bus_addr), .bus_write_data(p19_bus_write_data),
        .bus_mem_write(p19_bus_mem_write), .bus_mem_size(p19_bus_mem_size), .bus_mem_unsigned(p19_bus_mem_unsigned),
        .bus_grant(p19_bus_grant), .bus_read_data(p19_bus_read_data),
        .req_out_valid(p19_req_out_valid), .req_out_flit(p19_req_out_flit), .req_out_ready(p19_req_out_ready),
        .resp_in_valid(p19_resp_in_valid), .resp_in_flit(p19_resp_in_flit), .resp_in_ready(p19_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P20_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p20_core (
        .clk(clk), .reset(reset),
        .halted(p20_halted), .tohost_value(p20_tohost),
        .bus_req(p20_bus_req), .bus_addr(p20_bus_addr),
        .bus_write_data(p20_bus_write_data), .bus_mem_write(p20_bus_mem_write),
        .bus_mem_size(p20_bus_mem_size), .bus_mem_unsigned(p20_bus_mem_unsigned),
        .bus_grant(p20_bus_grant), .bus_read_data(p20_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(4), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p20_adap (
        .clk(clk), .reset(reset),
        .bus_req(p20_bus_req), .bus_addr(p20_bus_addr), .bus_write_data(p20_bus_write_data),
        .bus_mem_write(p20_bus_mem_write), .bus_mem_size(p20_bus_mem_size), .bus_mem_unsigned(p20_bus_mem_unsigned),
        .bus_grant(p20_bus_grant), .bus_read_data(p20_bus_read_data),
        .req_out_valid(p20_req_out_valid), .req_out_flit(p20_req_out_flit), .req_out_ready(p20_req_out_ready),
        .resp_in_valid(p20_resp_in_valid), .resp_in_flit(p20_resp_in_flit), .resp_in_ready(p20_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P21_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p21_core (
        .clk(clk), .reset(reset),
        .halted(p21_halted), .tohost_value(p21_tohost),
        .bus_req(p21_bus_req), .bus_addr(p21_bus_addr),
        .bus_write_data(p21_bus_write_data), .bus_mem_write(p21_bus_mem_write),
        .bus_mem_size(p21_bus_mem_size), .bus_mem_unsigned(p21_bus_mem_unsigned),
        .bus_grant(p21_bus_grant), .bus_read_data(p21_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(5), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p21_adap (
        .clk(clk), .reset(reset),
        .bus_req(p21_bus_req), .bus_addr(p21_bus_addr), .bus_write_data(p21_bus_write_data),
        .bus_mem_write(p21_bus_mem_write), .bus_mem_size(p21_bus_mem_size), .bus_mem_unsigned(p21_bus_mem_unsigned),
        .bus_grant(p21_bus_grant), .bus_read_data(p21_bus_read_data),
        .req_out_valid(p21_req_out_valid), .req_out_flit(p21_req_out_flit), .req_out_ready(p21_req_out_ready),
        .resp_in_valid(p21_resp_in_valid), .resp_in_flit(p21_resp_in_flit), .resp_in_ready(p21_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P22_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p22_core (
        .clk(clk), .reset(reset),
        .halted(p22_halted), .tohost_value(p22_tohost),
        .bus_req(p22_bus_req), .bus_addr(p22_bus_addr),
        .bus_write_data(p22_bus_write_data), .bus_mem_write(p22_bus_mem_write),
        .bus_mem_size(p22_bus_mem_size), .bus_mem_unsigned(p22_bus_mem_unsigned),
        .bus_grant(p22_bus_grant), .bus_read_data(p22_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(1), .MY_Z(5), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p22_adap (
        .clk(clk), .reset(reset),
        .bus_req(p22_bus_req), .bus_addr(p22_bus_addr), .bus_write_data(p22_bus_write_data),
        .bus_mem_write(p22_bus_mem_write), .bus_mem_size(p22_bus_mem_size), .bus_mem_unsigned(p22_bus_mem_unsigned),
        .bus_grant(p22_bus_grant), .bus_read_data(p22_bus_read_data),
        .req_out_valid(p22_req_out_valid), .req_out_flit(p22_req_out_flit), .req_out_ready(p22_req_out_ready),
        .resp_in_valid(p22_resp_in_valid), .resp_in_flit(p22_resp_in_flit), .resp_in_ready(p22_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P23_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p23_core (
        .clk(clk), .reset(reset),
        .halted(p23_halted), .tohost_value(p23_tohost),
        .bus_req(p23_bus_req), .bus_addr(p23_bus_addr),
        .bus_write_data(p23_bus_write_data), .bus_mem_write(p23_bus_mem_write),
        .bus_mem_size(p23_bus_mem_size), .bus_mem_unsigned(p23_bus_mem_unsigned),
        .bus_grant(p23_bus_grant), .bus_read_data(p23_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p23_adap (
        .clk(clk), .reset(reset),
        .bus_req(p23_bus_req), .bus_addr(p23_bus_addr), .bus_write_data(p23_bus_write_data),
        .bus_mem_write(p23_bus_mem_write), .bus_mem_size(p23_bus_mem_size), .bus_mem_unsigned(p23_bus_mem_unsigned),
        .bus_grant(p23_bus_grant), .bus_read_data(p23_bus_read_data),
        .req_out_valid(p23_req_out_valid), .req_out_flit(p23_req_out_flit), .req_out_ready(p23_req_out_ready),
        .resp_in_valid(p23_resp_in_valid), .resp_in_flit(p23_resp_in_flit), .resp_in_ready(p23_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P24_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p24_core (
        .clk(clk), .reset(reset),
        .halted(p24_halted), .tohost_value(p24_tohost),
        .bus_req(p24_bus_req), .bus_addr(p24_bus_addr),
        .bus_write_data(p24_bus_write_data), .bus_mem_write(p24_bus_mem_write),
        .bus_mem_size(p24_bus_mem_size), .bus_mem_unsigned(p24_bus_mem_unsigned),
        .bus_grant(p24_bus_grant), .bus_read_data(p24_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p24_adap (
        .clk(clk), .reset(reset),
        .bus_req(p24_bus_req), .bus_addr(p24_bus_addr), .bus_write_data(p24_bus_write_data),
        .bus_mem_write(p24_bus_mem_write), .bus_mem_size(p24_bus_mem_size), .bus_mem_unsigned(p24_bus_mem_unsigned),
        .bus_grant(p24_bus_grant), .bus_read_data(p24_bus_read_data),
        .req_out_valid(p24_req_out_valid), .req_out_flit(p24_req_out_flit), .req_out_ready(p24_req_out_ready),
        .resp_in_valid(p24_resp_in_valid), .resp_in_flit(p24_resp_in_flit), .resp_in_ready(p24_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P25_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p25_core (
        .clk(clk), .reset(reset),
        .halted(p25_halted), .tohost_value(p25_tohost),
        .bus_req(p25_bus_req), .bus_addr(p25_bus_addr),
        .bus_write_data(p25_bus_write_data), .bus_mem_write(p25_bus_mem_write),
        .bus_mem_size(p25_bus_mem_size), .bus_mem_unsigned(p25_bus_mem_unsigned),
        .bus_grant(p25_bus_grant), .bus_read_data(p25_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(1), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p25_adap (
        .clk(clk), .reset(reset),
        .bus_req(p25_bus_req), .bus_addr(p25_bus_addr), .bus_write_data(p25_bus_write_data),
        .bus_mem_write(p25_bus_mem_write), .bus_mem_size(p25_bus_mem_size), .bus_mem_unsigned(p25_bus_mem_unsigned),
        .bus_grant(p25_bus_grant), .bus_read_data(p25_bus_read_data),
        .req_out_valid(p25_req_out_valid), .req_out_flit(p25_req_out_flit), .req_out_ready(p25_req_out_ready),
        .resp_in_valid(p25_resp_in_valid), .resp_in_flit(p25_resp_in_flit), .resp_in_ready(p25_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P26_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p26_core (
        .clk(clk), .reset(reset),
        .halted(p26_halted), .tohost_value(p26_tohost),
        .bus_req(p26_bus_req), .bus_addr(p26_bus_addr),
        .bus_write_data(p26_bus_write_data), .bus_mem_write(p26_bus_mem_write),
        .bus_mem_size(p26_bus_mem_size), .bus_mem_unsigned(p26_bus_mem_unsigned),
        .bus_grant(p26_bus_grant), .bus_read_data(p26_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(1), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p26_adap (
        .clk(clk), .reset(reset),
        .bus_req(p26_bus_req), .bus_addr(p26_bus_addr), .bus_write_data(p26_bus_write_data),
        .bus_mem_write(p26_bus_mem_write), .bus_mem_size(p26_bus_mem_size), .bus_mem_unsigned(p26_bus_mem_unsigned),
        .bus_grant(p26_bus_grant), .bus_read_data(p26_bus_read_data),
        .req_out_valid(p26_req_out_valid), .req_out_flit(p26_req_out_flit), .req_out_ready(p26_req_out_ready),
        .resp_in_valid(p26_resp_in_valid), .resp_in_flit(p26_resp_in_flit), .resp_in_ready(p26_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P27_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p27_core (
        .clk(clk), .reset(reset),
        .halted(p27_halted), .tohost_value(p27_tohost),
        .bus_req(p27_bus_req), .bus_addr(p27_bus_addr),
        .bus_write_data(p27_bus_write_data), .bus_mem_write(p27_bus_mem_write),
        .bus_mem_size(p27_bus_mem_size), .bus_mem_unsigned(p27_bus_mem_unsigned),
        .bus_grant(p27_bus_grant), .bus_read_data(p27_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(2), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p27_adap (
        .clk(clk), .reset(reset),
        .bus_req(p27_bus_req), .bus_addr(p27_bus_addr), .bus_write_data(p27_bus_write_data),
        .bus_mem_write(p27_bus_mem_write), .bus_mem_size(p27_bus_mem_size), .bus_mem_unsigned(p27_bus_mem_unsigned),
        .bus_grant(p27_bus_grant), .bus_read_data(p27_bus_read_data),
        .req_out_valid(p27_req_out_valid), .req_out_flit(p27_req_out_flit), .req_out_ready(p27_req_out_ready),
        .resp_in_valid(p27_resp_in_valid), .resp_in_flit(p27_resp_in_flit), .resp_in_ready(p27_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P28_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p28_core (
        .clk(clk), .reset(reset),
        .halted(p28_halted), .tohost_value(p28_tohost),
        .bus_req(p28_bus_req), .bus_addr(p28_bus_addr),
        .bus_write_data(p28_bus_write_data), .bus_mem_write(p28_bus_mem_write),
        .bus_mem_size(p28_bus_mem_size), .bus_mem_unsigned(p28_bus_mem_unsigned),
        .bus_grant(p28_bus_grant), .bus_read_data(p28_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(2), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p28_adap (
        .clk(clk), .reset(reset),
        .bus_req(p28_bus_req), .bus_addr(p28_bus_addr), .bus_write_data(p28_bus_write_data),
        .bus_mem_write(p28_bus_mem_write), .bus_mem_size(p28_bus_mem_size), .bus_mem_unsigned(p28_bus_mem_unsigned),
        .bus_grant(p28_bus_grant), .bus_read_data(p28_bus_read_data),
        .req_out_valid(p28_req_out_valid), .req_out_flit(p28_req_out_flit), .req_out_ready(p28_req_out_ready),
        .resp_in_valid(p28_resp_in_valid), .resp_in_flit(p28_resp_in_flit), .resp_in_ready(p28_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P29_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p29_core (
        .clk(clk), .reset(reset),
        .halted(p29_halted), .tohost_value(p29_tohost),
        .bus_req(p29_bus_req), .bus_addr(p29_bus_addr),
        .bus_write_data(p29_bus_write_data), .bus_mem_write(p29_bus_mem_write),
        .bus_mem_size(p29_bus_mem_size), .bus_mem_unsigned(p29_bus_mem_unsigned),
        .bus_grant(p29_bus_grant), .bus_read_data(p29_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(3), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p29_adap (
        .clk(clk), .reset(reset),
        .bus_req(p29_bus_req), .bus_addr(p29_bus_addr), .bus_write_data(p29_bus_write_data),
        .bus_mem_write(p29_bus_mem_write), .bus_mem_size(p29_bus_mem_size), .bus_mem_unsigned(p29_bus_mem_unsigned),
        .bus_grant(p29_bus_grant), .bus_read_data(p29_bus_read_data),
        .req_out_valid(p29_req_out_valid), .req_out_flit(p29_req_out_flit), .req_out_ready(p29_req_out_ready),
        .resp_in_valid(p29_resp_in_valid), .resp_in_flit(p29_resp_in_flit), .resp_in_ready(p29_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P30_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p30_core (
        .clk(clk), .reset(reset),
        .halted(p30_halted), .tohost_value(p30_tohost),
        .bus_req(p30_bus_req), .bus_addr(p30_bus_addr),
        .bus_write_data(p30_bus_write_data), .bus_mem_write(p30_bus_mem_write),
        .bus_mem_size(p30_bus_mem_size), .bus_mem_unsigned(p30_bus_mem_unsigned),
        .bus_grant(p30_bus_grant), .bus_read_data(p30_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(3), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p30_adap (
        .clk(clk), .reset(reset),
        .bus_req(p30_bus_req), .bus_addr(p30_bus_addr), .bus_write_data(p30_bus_write_data),
        .bus_mem_write(p30_bus_mem_write), .bus_mem_size(p30_bus_mem_size), .bus_mem_unsigned(p30_bus_mem_unsigned),
        .bus_grant(p30_bus_grant), .bus_read_data(p30_bus_read_data),
        .req_out_valid(p30_req_out_valid), .req_out_flit(p30_req_out_flit), .req_out_ready(p30_req_out_ready),
        .resp_in_valid(p30_resp_in_valid), .resp_in_flit(p30_resp_in_flit), .resp_in_ready(p30_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P31_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p31_core (
        .clk(clk), .reset(reset),
        .halted(p31_halted), .tohost_value(p31_tohost),
        .bus_req(p31_bus_req), .bus_addr(p31_bus_addr),
        .bus_write_data(p31_bus_write_data), .bus_mem_write(p31_bus_mem_write),
        .bus_mem_size(p31_bus_mem_size), .bus_mem_unsigned(p31_bus_mem_unsigned),
        .bus_grant(p31_bus_grant), .bus_read_data(p31_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(4), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p31_adap (
        .clk(clk), .reset(reset),
        .bus_req(p31_bus_req), .bus_addr(p31_bus_addr), .bus_write_data(p31_bus_write_data),
        .bus_mem_write(p31_bus_mem_write), .bus_mem_size(p31_bus_mem_size), .bus_mem_unsigned(p31_bus_mem_unsigned),
        .bus_grant(p31_bus_grant), .bus_read_data(p31_bus_read_data),
        .req_out_valid(p31_req_out_valid), .req_out_flit(p31_req_out_flit), .req_out_ready(p31_req_out_ready),
        .resp_in_valid(p31_resp_in_valid), .resp_in_flit(p31_resp_in_flit), .resp_in_ready(p31_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P32_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p32_core (
        .clk(clk), .reset(reset),
        .halted(p32_halted), .tohost_value(p32_tohost),
        .bus_req(p32_bus_req), .bus_addr(p32_bus_addr),
        .bus_write_data(p32_bus_write_data), .bus_mem_write(p32_bus_mem_write),
        .bus_mem_size(p32_bus_mem_size), .bus_mem_unsigned(p32_bus_mem_unsigned),
        .bus_grant(p32_bus_grant), .bus_read_data(p32_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(4), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p32_adap (
        .clk(clk), .reset(reset),
        .bus_req(p32_bus_req), .bus_addr(p32_bus_addr), .bus_write_data(p32_bus_write_data),
        .bus_mem_write(p32_bus_mem_write), .bus_mem_size(p32_bus_mem_size), .bus_mem_unsigned(p32_bus_mem_unsigned),
        .bus_grant(p32_bus_grant), .bus_read_data(p32_bus_read_data),
        .req_out_valid(p32_req_out_valid), .req_out_flit(p32_req_out_flit), .req_out_ready(p32_req_out_ready),
        .resp_in_valid(p32_resp_in_valid), .resp_in_flit(p32_resp_in_flit), .resp_in_ready(p32_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P33_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p33_core (
        .clk(clk), .reset(reset),
        .halted(p33_halted), .tohost_value(p33_tohost),
        .bus_req(p33_bus_req), .bus_addr(p33_bus_addr),
        .bus_write_data(p33_bus_write_data), .bus_mem_write(p33_bus_mem_write),
        .bus_mem_size(p33_bus_mem_size), .bus_mem_unsigned(p33_bus_mem_unsigned),
        .bus_grant(p33_bus_grant), .bus_read_data(p33_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(5), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p33_adap (
        .clk(clk), .reset(reset),
        .bus_req(p33_bus_req), .bus_addr(p33_bus_addr), .bus_write_data(p33_bus_write_data),
        .bus_mem_write(p33_bus_mem_write), .bus_mem_size(p33_bus_mem_size), .bus_mem_unsigned(p33_bus_mem_unsigned),
        .bus_grant(p33_bus_grant), .bus_read_data(p33_bus_read_data),
        .req_out_valid(p33_req_out_valid), .req_out_flit(p33_req_out_flit), .req_out_ready(p33_req_out_ready),
        .resp_in_valid(p33_resp_in_valid), .resp_in_flit(p33_resp_in_flit), .resp_in_ready(p33_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P34_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p34_core (
        .clk(clk), .reset(reset),
        .halted(p34_halted), .tohost_value(p34_tohost),
        .bus_req(p34_bus_req), .bus_addr(p34_bus_addr),
        .bus_write_data(p34_bus_write_data), .bus_mem_write(p34_bus_mem_write),
        .bus_mem_size(p34_bus_mem_size), .bus_mem_unsigned(p34_bus_mem_unsigned),
        .bus_grant(p34_bus_grant), .bus_read_data(p34_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(0), .MY_Y(2), .MY_Z(5), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p34_adap (
        .clk(clk), .reset(reset),
        .bus_req(p34_bus_req), .bus_addr(p34_bus_addr), .bus_write_data(p34_bus_write_data),
        .bus_mem_write(p34_bus_mem_write), .bus_mem_size(p34_bus_mem_size), .bus_mem_unsigned(p34_bus_mem_unsigned),
        .bus_grant(p34_bus_grant), .bus_read_data(p34_bus_read_data),
        .req_out_valid(p34_req_out_valid), .req_out_flit(p34_req_out_flit), .req_out_ready(p34_req_out_ready),
        .resp_in_valid(p34_resp_in_valid), .resp_in_flit(p34_resp_in_flit), .resp_in_ready(p34_resp_in_ready)
    );

    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(P35_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) p35_core (
        .clk(clk), .reset(reset),
        .halted(p35_halted), .tohost_value(p35_tohost),
        .bus_req(p35_bus_req), .bus_addr(p35_bus_addr),
        .bus_write_data(p35_bus_write_data), .bus_mem_write(p35_bus_mem_write),
        .bus_mem_size(p35_bus_mem_size), .bus_mem_unsigned(p35_bus_mem_unsigned),
        .bus_grant(p35_bus_grant), .bus_read_data(p35_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) p35_adap (
        .clk(clk), .reset(reset),
        .bus_req(p35_bus_req), .bus_addr(p35_bus_addr), .bus_write_data(p35_bus_write_data),
        .bus_mem_write(p35_bus_mem_write), .bus_mem_size(p35_bus_mem_size), .bus_mem_unsigned(p35_bus_mem_unsigned),
        .bus_grant(p35_bus_grant), .bus_read_data(p35_bus_read_data),
        .req_out_valid(p35_req_out_valid), .req_out_flit(p35_req_out_flit), .req_out_ready(p35_req_out_ready),
        .resp_in_valid(p35_resp_in_valid), .resp_in_flit(p35_resp_in_flit), .resp_in_ready(p35_resp_in_ready)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(1), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(1), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(2), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(2), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(3), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(3), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(4), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(4), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(5), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(0), .MY_Z(5), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(1), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(1), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(2), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
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
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(2), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e16_adap (
        .clk(clk), .reset(reset),
        .bus_req(e16_bus_req), .bus_addr(e16_bus_addr), .bus_write_data(e16_bus_write_data),
        .bus_mem_write(e16_bus_mem_write), .bus_mem_size(e16_bus_mem_size), .bus_mem_unsigned(e16_bus_mem_unsigned),
        .bus_grant(e16_bus_grant), .bus_read_data(e16_bus_read_data),
        .req_out_valid(e16_req_out_valid), .req_out_flit(e16_req_out_flit), .req_out_ready(e16_req_out_ready),
        .resp_in_valid(e16_resp_in_valid), .resp_in_flit(e16_resp_in_flit), .resp_in_ready(e16_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E17_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e17_core (
        .clk(clk), .reset(reset),
        .halted(e17_halted), .tohost_value(e17_tohost),
        .bus_req(e17_bus_req), .bus_addr(e17_bus_addr),
        .bus_write_data(e17_bus_write_data), .bus_mem_write(e17_bus_mem_write),
        .bus_mem_size(e17_bus_mem_size), .bus_mem_unsigned(e17_bus_mem_unsigned),
        .bus_grant(e17_bus_grant), .bus_read_data(e17_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(3), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e17_adap (
        .clk(clk), .reset(reset),
        .bus_req(e17_bus_req), .bus_addr(e17_bus_addr), .bus_write_data(e17_bus_write_data),
        .bus_mem_write(e17_bus_mem_write), .bus_mem_size(e17_bus_mem_size), .bus_mem_unsigned(e17_bus_mem_unsigned),
        .bus_grant(e17_bus_grant), .bus_read_data(e17_bus_read_data),
        .req_out_valid(e17_req_out_valid), .req_out_flit(e17_req_out_flit), .req_out_ready(e17_req_out_ready),
        .resp_in_valid(e17_resp_in_valid), .resp_in_flit(e17_resp_in_flit), .resp_in_ready(e17_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E18_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e18_core (
        .clk(clk), .reset(reset),
        .halted(e18_halted), .tohost_value(e18_tohost),
        .bus_req(e18_bus_req), .bus_addr(e18_bus_addr),
        .bus_write_data(e18_bus_write_data), .bus_mem_write(e18_bus_mem_write),
        .bus_mem_size(e18_bus_mem_size), .bus_mem_unsigned(e18_bus_mem_unsigned),
        .bus_grant(e18_bus_grant), .bus_read_data(e18_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(3), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e18_adap (
        .clk(clk), .reset(reset),
        .bus_req(e18_bus_req), .bus_addr(e18_bus_addr), .bus_write_data(e18_bus_write_data),
        .bus_mem_write(e18_bus_mem_write), .bus_mem_size(e18_bus_mem_size), .bus_mem_unsigned(e18_bus_mem_unsigned),
        .bus_grant(e18_bus_grant), .bus_read_data(e18_bus_read_data),
        .req_out_valid(e18_req_out_valid), .req_out_flit(e18_req_out_flit), .req_out_ready(e18_req_out_ready),
        .resp_in_valid(e18_resp_in_valid), .resp_in_flit(e18_resp_in_flit), .resp_in_ready(e18_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E19_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e19_core (
        .clk(clk), .reset(reset),
        .halted(e19_halted), .tohost_value(e19_tohost),
        .bus_req(e19_bus_req), .bus_addr(e19_bus_addr),
        .bus_write_data(e19_bus_write_data), .bus_mem_write(e19_bus_mem_write),
        .bus_mem_size(e19_bus_mem_size), .bus_mem_unsigned(e19_bus_mem_unsigned),
        .bus_grant(e19_bus_grant), .bus_read_data(e19_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(4), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e19_adap (
        .clk(clk), .reset(reset),
        .bus_req(e19_bus_req), .bus_addr(e19_bus_addr), .bus_write_data(e19_bus_write_data),
        .bus_mem_write(e19_bus_mem_write), .bus_mem_size(e19_bus_mem_size), .bus_mem_unsigned(e19_bus_mem_unsigned),
        .bus_grant(e19_bus_grant), .bus_read_data(e19_bus_read_data),
        .req_out_valid(e19_req_out_valid), .req_out_flit(e19_req_out_flit), .req_out_ready(e19_req_out_ready),
        .resp_in_valid(e19_resp_in_valid), .resp_in_flit(e19_resp_in_flit), .resp_in_ready(e19_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E20_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e20_core (
        .clk(clk), .reset(reset),
        .halted(e20_halted), .tohost_value(e20_tohost),
        .bus_req(e20_bus_req), .bus_addr(e20_bus_addr),
        .bus_write_data(e20_bus_write_data), .bus_mem_write(e20_bus_mem_write),
        .bus_mem_size(e20_bus_mem_size), .bus_mem_unsigned(e20_bus_mem_unsigned),
        .bus_grant(e20_bus_grant), .bus_read_data(e20_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(4), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e20_adap (
        .clk(clk), .reset(reset),
        .bus_req(e20_bus_req), .bus_addr(e20_bus_addr), .bus_write_data(e20_bus_write_data),
        .bus_mem_write(e20_bus_mem_write), .bus_mem_size(e20_bus_mem_size), .bus_mem_unsigned(e20_bus_mem_unsigned),
        .bus_grant(e20_bus_grant), .bus_read_data(e20_bus_read_data),
        .req_out_valid(e20_req_out_valid), .req_out_flit(e20_req_out_flit), .req_out_ready(e20_req_out_ready),
        .resp_in_valid(e20_resp_in_valid), .resp_in_flit(e20_resp_in_flit), .resp_in_ready(e20_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E21_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e21_core (
        .clk(clk), .reset(reset),
        .halted(e21_halted), .tohost_value(e21_tohost),
        .bus_req(e21_bus_req), .bus_addr(e21_bus_addr),
        .bus_write_data(e21_bus_write_data), .bus_mem_write(e21_bus_mem_write),
        .bus_mem_size(e21_bus_mem_size), .bus_mem_unsigned(e21_bus_mem_unsigned),
        .bus_grant(e21_bus_grant), .bus_read_data(e21_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(5), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e21_adap (
        .clk(clk), .reset(reset),
        .bus_req(e21_bus_req), .bus_addr(e21_bus_addr), .bus_write_data(e21_bus_write_data),
        .bus_mem_write(e21_bus_mem_write), .bus_mem_size(e21_bus_mem_size), .bus_mem_unsigned(e21_bus_mem_unsigned),
        .bus_grant(e21_bus_grant), .bus_read_data(e21_bus_read_data),
        .req_out_valid(e21_req_out_valid), .req_out_flit(e21_req_out_flit), .req_out_ready(e21_req_out_ready),
        .resp_in_valid(e21_resp_in_valid), .resp_in_flit(e21_resp_in_flit), .resp_in_ready(e21_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E22_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e22_core (
        .clk(clk), .reset(reset),
        .halted(e22_halted), .tohost_value(e22_tohost),
        .bus_req(e22_bus_req), .bus_addr(e22_bus_addr),
        .bus_write_data(e22_bus_write_data), .bus_mem_write(e22_bus_mem_write),
        .bus_mem_size(e22_bus_mem_size), .bus_mem_unsigned(e22_bus_mem_unsigned),
        .bus_grant(e22_bus_grant), .bus_read_data(e22_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(1), .MY_Z(5), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e22_adap (
        .clk(clk), .reset(reset),
        .bus_req(e22_bus_req), .bus_addr(e22_bus_addr), .bus_write_data(e22_bus_write_data),
        .bus_mem_write(e22_bus_mem_write), .bus_mem_size(e22_bus_mem_size), .bus_mem_unsigned(e22_bus_mem_unsigned),
        .bus_grant(e22_bus_grant), .bus_read_data(e22_bus_read_data),
        .req_out_valid(e22_req_out_valid), .req_out_flit(e22_req_out_flit), .req_out_ready(e22_req_out_ready),
        .resp_in_valid(e22_resp_in_valid), .resp_in_flit(e22_resp_in_flit), .resp_in_ready(e22_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E23_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e23_core (
        .clk(clk), .reset(reset),
        .halted(e23_halted), .tohost_value(e23_tohost),
        .bus_req(e23_bus_req), .bus_addr(e23_bus_addr),
        .bus_write_data(e23_bus_write_data), .bus_mem_write(e23_bus_mem_write),
        .bus_mem_size(e23_bus_mem_size), .bus_mem_unsigned(e23_bus_mem_unsigned),
        .bus_grant(e23_bus_grant), .bus_read_data(e23_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e23_adap (
        .clk(clk), .reset(reset),
        .bus_req(e23_bus_req), .bus_addr(e23_bus_addr), .bus_write_data(e23_bus_write_data),
        .bus_mem_write(e23_bus_mem_write), .bus_mem_size(e23_bus_mem_size), .bus_mem_unsigned(e23_bus_mem_unsigned),
        .bus_grant(e23_bus_grant), .bus_read_data(e23_bus_read_data),
        .req_out_valid(e23_req_out_valid), .req_out_flit(e23_req_out_flit), .req_out_ready(e23_req_out_ready),
        .resp_in_valid(e23_resp_in_valid), .resp_in_flit(e23_resp_in_flit), .resp_in_ready(e23_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E24_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e24_core (
        .clk(clk), .reset(reset),
        .halted(e24_halted), .tohost_value(e24_tohost),
        .bus_req(e24_bus_req), .bus_addr(e24_bus_addr),
        .bus_write_data(e24_bus_write_data), .bus_mem_write(e24_bus_mem_write),
        .bus_mem_size(e24_bus_mem_size), .bus_mem_unsigned(e24_bus_mem_unsigned),
        .bus_grant(e24_bus_grant), .bus_read_data(e24_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e24_adap (
        .clk(clk), .reset(reset),
        .bus_req(e24_bus_req), .bus_addr(e24_bus_addr), .bus_write_data(e24_bus_write_data),
        .bus_mem_write(e24_bus_mem_write), .bus_mem_size(e24_bus_mem_size), .bus_mem_unsigned(e24_bus_mem_unsigned),
        .bus_grant(e24_bus_grant), .bus_read_data(e24_bus_read_data),
        .req_out_valid(e24_req_out_valid), .req_out_flit(e24_req_out_flit), .req_out_ready(e24_req_out_ready),
        .resp_in_valid(e24_resp_in_valid), .resp_in_flit(e24_resp_in_flit), .resp_in_ready(e24_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E25_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e25_core (
        .clk(clk), .reset(reset),
        .halted(e25_halted), .tohost_value(e25_tohost),
        .bus_req(e25_bus_req), .bus_addr(e25_bus_addr),
        .bus_write_data(e25_bus_write_data), .bus_mem_write(e25_bus_mem_write),
        .bus_mem_size(e25_bus_mem_size), .bus_mem_unsigned(e25_bus_mem_unsigned),
        .bus_grant(e25_bus_grant), .bus_read_data(e25_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(1), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e25_adap (
        .clk(clk), .reset(reset),
        .bus_req(e25_bus_req), .bus_addr(e25_bus_addr), .bus_write_data(e25_bus_write_data),
        .bus_mem_write(e25_bus_mem_write), .bus_mem_size(e25_bus_mem_size), .bus_mem_unsigned(e25_bus_mem_unsigned),
        .bus_grant(e25_bus_grant), .bus_read_data(e25_bus_read_data),
        .req_out_valid(e25_req_out_valid), .req_out_flit(e25_req_out_flit), .req_out_ready(e25_req_out_ready),
        .resp_in_valid(e25_resp_in_valid), .resp_in_flit(e25_resp_in_flit), .resp_in_ready(e25_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E26_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e26_core (
        .clk(clk), .reset(reset),
        .halted(e26_halted), .tohost_value(e26_tohost),
        .bus_req(e26_bus_req), .bus_addr(e26_bus_addr),
        .bus_write_data(e26_bus_write_data), .bus_mem_write(e26_bus_mem_write),
        .bus_mem_size(e26_bus_mem_size), .bus_mem_unsigned(e26_bus_mem_unsigned),
        .bus_grant(e26_bus_grant), .bus_read_data(e26_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(1), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e26_adap (
        .clk(clk), .reset(reset),
        .bus_req(e26_bus_req), .bus_addr(e26_bus_addr), .bus_write_data(e26_bus_write_data),
        .bus_mem_write(e26_bus_mem_write), .bus_mem_size(e26_bus_mem_size), .bus_mem_unsigned(e26_bus_mem_unsigned),
        .bus_grant(e26_bus_grant), .bus_read_data(e26_bus_read_data),
        .req_out_valid(e26_req_out_valid), .req_out_flit(e26_req_out_flit), .req_out_ready(e26_req_out_ready),
        .resp_in_valid(e26_resp_in_valid), .resp_in_flit(e26_resp_in_flit), .resp_in_ready(e26_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E27_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e27_core (
        .clk(clk), .reset(reset),
        .halted(e27_halted), .tohost_value(e27_tohost),
        .bus_req(e27_bus_req), .bus_addr(e27_bus_addr),
        .bus_write_data(e27_bus_write_data), .bus_mem_write(e27_bus_mem_write),
        .bus_mem_size(e27_bus_mem_size), .bus_mem_unsigned(e27_bus_mem_unsigned),
        .bus_grant(e27_bus_grant), .bus_read_data(e27_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(2), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e27_adap (
        .clk(clk), .reset(reset),
        .bus_req(e27_bus_req), .bus_addr(e27_bus_addr), .bus_write_data(e27_bus_write_data),
        .bus_mem_write(e27_bus_mem_write), .bus_mem_size(e27_bus_mem_size), .bus_mem_unsigned(e27_bus_mem_unsigned),
        .bus_grant(e27_bus_grant), .bus_read_data(e27_bus_read_data),
        .req_out_valid(e27_req_out_valid), .req_out_flit(e27_req_out_flit), .req_out_ready(e27_req_out_ready),
        .resp_in_valid(e27_resp_in_valid), .resp_in_flit(e27_resp_in_flit), .resp_in_ready(e27_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E28_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e28_core (
        .clk(clk), .reset(reset),
        .halted(e28_halted), .tohost_value(e28_tohost),
        .bus_req(e28_bus_req), .bus_addr(e28_bus_addr),
        .bus_write_data(e28_bus_write_data), .bus_mem_write(e28_bus_mem_write),
        .bus_mem_size(e28_bus_mem_size), .bus_mem_unsigned(e28_bus_mem_unsigned),
        .bus_grant(e28_bus_grant), .bus_read_data(e28_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(2), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e28_adap (
        .clk(clk), .reset(reset),
        .bus_req(e28_bus_req), .bus_addr(e28_bus_addr), .bus_write_data(e28_bus_write_data),
        .bus_mem_write(e28_bus_mem_write), .bus_mem_size(e28_bus_mem_size), .bus_mem_unsigned(e28_bus_mem_unsigned),
        .bus_grant(e28_bus_grant), .bus_read_data(e28_bus_read_data),
        .req_out_valid(e28_req_out_valid), .req_out_flit(e28_req_out_flit), .req_out_ready(e28_req_out_ready),
        .resp_in_valid(e28_resp_in_valid), .resp_in_flit(e28_resp_in_flit), .resp_in_ready(e28_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E29_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e29_core (
        .clk(clk), .reset(reset),
        .halted(e29_halted), .tohost_value(e29_tohost),
        .bus_req(e29_bus_req), .bus_addr(e29_bus_addr),
        .bus_write_data(e29_bus_write_data), .bus_mem_write(e29_bus_mem_write),
        .bus_mem_size(e29_bus_mem_size), .bus_mem_unsigned(e29_bus_mem_unsigned),
        .bus_grant(e29_bus_grant), .bus_read_data(e29_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(3), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e29_adap (
        .clk(clk), .reset(reset),
        .bus_req(e29_bus_req), .bus_addr(e29_bus_addr), .bus_write_data(e29_bus_write_data),
        .bus_mem_write(e29_bus_mem_write), .bus_mem_size(e29_bus_mem_size), .bus_mem_unsigned(e29_bus_mem_unsigned),
        .bus_grant(e29_bus_grant), .bus_read_data(e29_bus_read_data),
        .req_out_valid(e29_req_out_valid), .req_out_flit(e29_req_out_flit), .req_out_ready(e29_req_out_ready),
        .resp_in_valid(e29_resp_in_valid), .resp_in_flit(e29_resp_in_flit), .resp_in_ready(e29_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E30_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e30_core (
        .clk(clk), .reset(reset),
        .halted(e30_halted), .tohost_value(e30_tohost),
        .bus_req(e30_bus_req), .bus_addr(e30_bus_addr),
        .bus_write_data(e30_bus_write_data), .bus_mem_write(e30_bus_mem_write),
        .bus_mem_size(e30_bus_mem_size), .bus_mem_unsigned(e30_bus_mem_unsigned),
        .bus_grant(e30_bus_grant), .bus_read_data(e30_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(3), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e30_adap (
        .clk(clk), .reset(reset),
        .bus_req(e30_bus_req), .bus_addr(e30_bus_addr), .bus_write_data(e30_bus_write_data),
        .bus_mem_write(e30_bus_mem_write), .bus_mem_size(e30_bus_mem_size), .bus_mem_unsigned(e30_bus_mem_unsigned),
        .bus_grant(e30_bus_grant), .bus_read_data(e30_bus_read_data),
        .req_out_valid(e30_req_out_valid), .req_out_flit(e30_req_out_flit), .req_out_ready(e30_req_out_ready),
        .resp_in_valid(e30_resp_in_valid), .resp_in_flit(e30_resp_in_flit), .resp_in_ready(e30_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E31_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e31_core (
        .clk(clk), .reset(reset),
        .halted(e31_halted), .tohost_value(e31_tohost),
        .bus_req(e31_bus_req), .bus_addr(e31_bus_addr),
        .bus_write_data(e31_bus_write_data), .bus_mem_write(e31_bus_mem_write),
        .bus_mem_size(e31_bus_mem_size), .bus_mem_unsigned(e31_bus_mem_unsigned),
        .bus_grant(e31_bus_grant), .bus_read_data(e31_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(4), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e31_adap (
        .clk(clk), .reset(reset),
        .bus_req(e31_bus_req), .bus_addr(e31_bus_addr), .bus_write_data(e31_bus_write_data),
        .bus_mem_write(e31_bus_mem_write), .bus_mem_size(e31_bus_mem_size), .bus_mem_unsigned(e31_bus_mem_unsigned),
        .bus_grant(e31_bus_grant), .bus_read_data(e31_bus_read_data),
        .req_out_valid(e31_req_out_valid), .req_out_flit(e31_req_out_flit), .req_out_ready(e31_req_out_ready),
        .resp_in_valid(e31_resp_in_valid), .resp_in_flit(e31_resp_in_flit), .resp_in_ready(e31_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E32_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e32_core (
        .clk(clk), .reset(reset),
        .halted(e32_halted), .tohost_value(e32_tohost),
        .bus_req(e32_bus_req), .bus_addr(e32_bus_addr),
        .bus_write_data(e32_bus_write_data), .bus_mem_write(e32_bus_mem_write),
        .bus_mem_size(e32_bus_mem_size), .bus_mem_unsigned(e32_bus_mem_unsigned),
        .bus_grant(e32_bus_grant), .bus_read_data(e32_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(4), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e32_adap (
        .clk(clk), .reset(reset),
        .bus_req(e32_bus_req), .bus_addr(e32_bus_addr), .bus_write_data(e32_bus_write_data),
        .bus_mem_write(e32_bus_mem_write), .bus_mem_size(e32_bus_mem_size), .bus_mem_unsigned(e32_bus_mem_unsigned),
        .bus_grant(e32_bus_grant), .bus_read_data(e32_bus_read_data),
        .req_out_valid(e32_req_out_valid), .req_out_flit(e32_req_out_flit), .req_out_ready(e32_req_out_ready),
        .resp_in_valid(e32_resp_in_valid), .resp_in_flit(e32_resp_in_flit), .resp_in_ready(e32_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E33_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e33_core (
        .clk(clk), .reset(reset),
        .halted(e33_halted), .tohost_value(e33_tohost),
        .bus_req(e33_bus_req), .bus_addr(e33_bus_addr),
        .bus_write_data(e33_bus_write_data), .bus_mem_write(e33_bus_mem_write),
        .bus_mem_size(e33_bus_mem_size), .bus_mem_unsigned(e33_bus_mem_unsigned),
        .bus_grant(e33_bus_grant), .bus_read_data(e33_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(5), .MY_W(0),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e33_adap (
        .clk(clk), .reset(reset),
        .bus_req(e33_bus_req), .bus_addr(e33_bus_addr), .bus_write_data(e33_bus_write_data),
        .bus_mem_write(e33_bus_mem_write), .bus_mem_size(e33_bus_mem_size), .bus_mem_unsigned(e33_bus_mem_unsigned),
        .bus_grant(e33_bus_grant), .bus_read_data(e33_bus_read_data),
        .req_out_valid(e33_req_out_valid), .req_out_flit(e33_req_out_flit), .req_out_ready(e33_req_out_ready),
        .resp_in_valid(e33_resp_in_valid), .resp_in_flit(e33_resp_in_flit), .resp_in_ready(e33_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(E34_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) e34_core (
        .clk(clk), .reset(reset),
        .halted(e34_halted), .tohost_value(e34_tohost),
        .bus_req(e34_bus_req), .bus_addr(e34_bus_addr),
        .bus_write_data(e34_bus_write_data), .bus_mem_write(e34_bus_mem_write),
        .bus_mem_size(e34_bus_mem_size), .bus_mem_unsigned(e34_bus_mem_unsigned),
        .bus_grant(e34_bus_grant), .bus_read_data(e34_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(3), .MY_X(1), .MY_Y(2), .MY_Z(5), .MY_W(1),
        .MEM_X(0), .MEM_Y(1), .MEM_Z(2), .MEM_W(0),
        .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) e34_adap (
        .clk(clk), .reset(reset),
        .bus_req(e34_bus_req), .bus_addr(e34_bus_addr), .bus_write_data(e34_bus_write_data),
        .bus_mem_write(e34_bus_mem_write), .bus_mem_size(e34_bus_mem_size), .bus_mem_unsigned(e34_bus_mem_unsigned),
        .bus_grant(e34_bus_grant), .bus_read_data(e34_bus_read_data),
        .req_out_valid(e34_req_out_valid), .req_out_flit(e34_req_out_flit), .req_out_ready(e34_req_out_ready),
        .resp_in_valid(e34_resp_in_valid), .resp_in_flit(e34_resp_in_flit), .resp_in_ready(e34_resp_in_ready)
    );

    noc_mem_adapter #(
        .COORD_BITS(3), .MEM_BYTES(SHARED_MEM_BYTES), .REQ_FLIT_WIDTH(92), .RESP_FLIT_WIDTH(44)
    ) mem_adap (
        .clk(clk), .reset(reset),
        .req_in_valid(mem_req_in_valid), .req_in_flit(mem_req_in_flit), .req_in_ready(mem_req_in_ready),
        .resp_out_valid(mem_resp_out_valid), .resp_out_flit(mem_resp_out_flit), .resp_out_ready(mem_resp_out_ready)
    );

    assign all_halted = p0_halted && p1_halted && p2_halted && p3_halted && p4_halted && p5_halted && p6_halted && p7_halted && p8_halted && p9_halted && p10_halted && p11_halted && p12_halted && p13_halted && p14_halted && p15_halted && p16_halted && p17_halted && p18_halted && p19_halted && p20_halted && p21_halted && p22_halted && p23_halted && p24_halted && p25_halted && p26_halted && p27_halted && p28_halted && p29_halted && p30_halted && p31_halted && p32_halted && p33_halted && p34_halted && p35_halted && e0_halted && e1_halted && e2_halted && e3_halted && e4_halted && e5_halted && e6_halted && e7_halted && e8_halted && e9_halted && e10_halted && e11_halted && e12_halted && e13_halted && e14_halted && e15_halted && e16_halted && e17_halted && e18_halted && e19_halted && e20_halted && e21_halted && e22_halted && e23_halted && e24_halted && e25_halted && e26_halted && e27_halted && e28_halted && e29_halted && e30_halted && e31_halted && e32_halted && e33_halted && e34_halted;
endmodule
