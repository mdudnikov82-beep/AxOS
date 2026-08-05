// AxISA's NoC mini-SoC (hardware/axisa_core) - a real 3D 4x3x4 mesh
// of XYZW-routed routers (router.v, ported unmodified from rv32i_core),
// each grid position connected to its N/E/S/W/Up/Down neighbors (the W
// axis stays unused at this size - MY_W=0 everywhere, Ana/Kata tied off)
// plus a Local port for whatever AxISA core or memory endpoint sits
// there. TWO independent router networks span the grid - REQUEST
// (core -> memory, FLIT_WIDTH=84) and RESPONSE (memory -> core,
// FLIT_WIDTH=40) - kept as fully separate router instances with zero
// shared state, same as every rv32i_core mesh.
//
// This is AxISA's first mesh to actually EXERCISE the Z axis (every
// prior AxISA mesh tied MY_Z=0 and U/D off everywhere - router.v/
// noc_core_adapter.v/noc_mem_adapter.v already fully supported Z, since
// they were copied unmodified from rv32i_core's own already-4D-capable
// versions, so this needed ZERO RTL changes). COORD_BITS/flit widths are
// UNCHANGED from the 2D 3x3 mesh (2/84/40) - those formulas already
// assumed 4 axes regardless of whether Z/W actually varied. AxISA has
// only ONE core module (cpu_core.v, no pipelined variant), so no P/E
// split is needed.
//
// Memory lives at (1,1,1) - the lower of two symmetric center
// positions on the size-4 X and size-4 Z axes, the exact center on the
// size-3 Y axis - not a corner, same rule every prior mesh in this project
// (both rv32i_core and AxISA) already used.
//
// Grid layout (x,y,z), MEM marked - shown as Z-layer slices:
//
//   Z=0:
//     c0     c12    c23    c35  
//     c4     c16    c27    c39  
//     c8     c19    c31    c43  
//   Z=1:
//     c1     c13    c24    c36  
//     c5     MEM    c28    c40  
//     c9     c20    c32    c44  
//   Z=2:
//     c2     c14    c25    c37  
//     c6     c17    c29    c41  
//     c10    c21    c33    c45  
//   Z=3:
//     c3     c15    c26    c38  
//     c7     c18    c30    c42  
//     c11    c22    c34    c46  
//
// c0=consumer (shared_consumer.hex, busy-waits then reads the payload),
// c1=producer (shared_producer.hex, writes payload then a ready flag),
// c2-c46=independent (test1.hex, private-memory-only, proves the mesh still
// works correctly with unrelated concurrent traffic).
`timescale 1ns/1ps

module soc_top #(
    parameter C0_INSTR_HEX = "",
    parameter C1_INSTR_HEX = "",
    parameter C2_INSTR_HEX = "",
    parameter C3_INSTR_HEX = "",
    parameter C4_INSTR_HEX = "",
    parameter C5_INSTR_HEX = "",
    parameter C6_INSTR_HEX = "",
    parameter C7_INSTR_HEX = "",
    parameter C8_INSTR_HEX = "",
    parameter C9_INSTR_HEX = "",
    parameter C10_INSTR_HEX = "",
    parameter C11_INSTR_HEX = "",
    parameter C12_INSTR_HEX = "",
    parameter C13_INSTR_HEX = "",
    parameter C14_INSTR_HEX = "",
    parameter C15_INSTR_HEX = "",
    parameter C16_INSTR_HEX = "",
    parameter C17_INSTR_HEX = "",
    parameter C18_INSTR_HEX = "",
    parameter C19_INSTR_HEX = "",
    parameter C20_INSTR_HEX = "",
    parameter C21_INSTR_HEX = "",
    parameter C22_INSTR_HEX = "",
    parameter C23_INSTR_HEX = "",
    parameter C24_INSTR_HEX = "",
    parameter C25_INSTR_HEX = "",
    parameter C26_INSTR_HEX = "",
    parameter C27_INSTR_HEX = "",
    parameter C28_INSTR_HEX = "",
    parameter C29_INSTR_HEX = "",
    parameter C30_INSTR_HEX = "",
    parameter C31_INSTR_HEX = "",
    parameter C32_INSTR_HEX = "",
    parameter C33_INSTR_HEX = "",
    parameter C34_INSTR_HEX = "",
    parameter C35_INSTR_HEX = "",
    parameter C36_INSTR_HEX = "",
    parameter C37_INSTR_HEX = "",
    parameter C38_INSTR_HEX = "",
    parameter C39_INSTR_HEX = "",
    parameter C40_INSTR_HEX = "",
    parameter C41_INSTR_HEX = "",
    parameter C42_INSTR_HEX = "",
    parameter C43_INSTR_HEX = "",
    parameter C44_INSTR_HEX = "",
    parameter C45_INSTR_HEX = "",
    parameter C46_INSTR_HEX = "",
    parameter INSTR_MEM_WORDS  = 1024,
    parameter DATA_MEM_WORDS   = 1024,
    parameter SHARED_MEM_BASE  = 32'h0000_2000,
    parameter SHARED_MEM_BYTES = 256
) (
    input  wire        clk,
    input  wire        reset,
    output wire        c0_halted,
    output wire [31:0]  c0_tohost,
    output wire        c1_halted,
    output wire [31:0]  c1_tohost,
    output wire        c2_halted,
    output wire [31:0]  c2_tohost,
    output wire        c3_halted,
    output wire [31:0]  c3_tohost,
    output wire        c4_halted,
    output wire [31:0]  c4_tohost,
    output wire        c5_halted,
    output wire [31:0]  c5_tohost,
    output wire        c6_halted,
    output wire [31:0]  c6_tohost,
    output wire        c7_halted,
    output wire [31:0]  c7_tohost,
    output wire        c8_halted,
    output wire [31:0]  c8_tohost,
    output wire        c9_halted,
    output wire [31:0]  c9_tohost,
    output wire        c10_halted,
    output wire [31:0]  c10_tohost,
    output wire        c11_halted,
    output wire [31:0]  c11_tohost,
    output wire        c12_halted,
    output wire [31:0]  c12_tohost,
    output wire        c13_halted,
    output wire [31:0]  c13_tohost,
    output wire        c14_halted,
    output wire [31:0]  c14_tohost,
    output wire        c15_halted,
    output wire [31:0]  c15_tohost,
    output wire        c16_halted,
    output wire [31:0]  c16_tohost,
    output wire        c17_halted,
    output wire [31:0]  c17_tohost,
    output wire        c18_halted,
    output wire [31:0]  c18_tohost,
    output wire        c19_halted,
    output wire [31:0]  c19_tohost,
    output wire        c20_halted,
    output wire [31:0]  c20_tohost,
    output wire        c21_halted,
    output wire [31:0]  c21_tohost,
    output wire        c22_halted,
    output wire [31:0]  c22_tohost,
    output wire        c23_halted,
    output wire [31:0]  c23_tohost,
    output wire        c24_halted,
    output wire [31:0]  c24_tohost,
    output wire        c25_halted,
    output wire [31:0]  c25_tohost,
    output wire        c26_halted,
    output wire [31:0]  c26_tohost,
    output wire        c27_halted,
    output wire [31:0]  c27_tohost,
    output wire        c28_halted,
    output wire [31:0]  c28_tohost,
    output wire        c29_halted,
    output wire [31:0]  c29_tohost,
    output wire        c30_halted,
    output wire [31:0]  c30_tohost,
    output wire        c31_halted,
    output wire [31:0]  c31_tohost,
    output wire        c32_halted,
    output wire [31:0]  c32_tohost,
    output wire        c33_halted,
    output wire [31:0]  c33_tohost,
    output wire        c34_halted,
    output wire [31:0]  c34_tohost,
    output wire        c35_halted,
    output wire [31:0]  c35_tohost,
    output wire        c36_halted,
    output wire [31:0]  c36_tohost,
    output wire        c37_halted,
    output wire [31:0]  c37_tohost,
    output wire        c38_halted,
    output wire [31:0]  c38_tohost,
    output wire        c39_halted,
    output wire [31:0]  c39_tohost,
    output wire        c40_halted,
    output wire [31:0]  c40_tohost,
    output wire        c41_halted,
    output wire [31:0]  c41_tohost,
    output wire        c42_halted,
    output wire [31:0]  c42_tohost,
    output wire        c43_halted,
    output wire [31:0]  c43_tohost,
    output wire        c44_halted,
    output wire [31:0]  c44_tohost,
    output wire        c45_halted,
    output wire [31:0]  c45_tohost,
    output wire        c46_halted,
    output wire [31:0]  c46_tohost,
    output wire        all_halted
);

    // ==================== Mesh link wires ====================
    // EVERY (node,direction) pair with a real neighbor gets its own
    // uniquely-named wire - no 'owner direction' subsetting (that exact
    // shortcut caused a real, live-found wiring bug the first time
    // rv32i_core's own generator went 2D->3D; reusing the proven-correct
    // pattern verbatim here instead of re-deriving it).
    wire req_0_0_0_S_v, req_0_0_0_S_r; wire [83:0] req_0_0_0_S_f;
    wire req_0_0_0_E_v, req_0_0_0_E_r; wire [83:0] req_0_0_0_E_f;
    wire req_0_0_0_D_v, req_0_0_0_D_r; wire [83:0] req_0_0_0_D_f;
    wire req_0_0_1_S_v, req_0_0_1_S_r; wire [83:0] req_0_0_1_S_f;
    wire req_0_0_1_E_v, req_0_0_1_E_r; wire [83:0] req_0_0_1_E_f;
    wire req_0_0_1_U_v, req_0_0_1_U_r; wire [83:0] req_0_0_1_U_f;
    wire req_0_0_1_D_v, req_0_0_1_D_r; wire [83:0] req_0_0_1_D_f;
    wire req_0_0_2_S_v, req_0_0_2_S_r; wire [83:0] req_0_0_2_S_f;
    wire req_0_0_2_E_v, req_0_0_2_E_r; wire [83:0] req_0_0_2_E_f;
    wire req_0_0_2_U_v, req_0_0_2_U_r; wire [83:0] req_0_0_2_U_f;
    wire req_0_0_2_D_v, req_0_0_2_D_r; wire [83:0] req_0_0_2_D_f;
    wire req_0_0_3_S_v, req_0_0_3_S_r; wire [83:0] req_0_0_3_S_f;
    wire req_0_0_3_E_v, req_0_0_3_E_r; wire [83:0] req_0_0_3_E_f;
    wire req_0_0_3_U_v, req_0_0_3_U_r; wire [83:0] req_0_0_3_U_f;
    wire req_0_1_0_N_v, req_0_1_0_N_r; wire [83:0] req_0_1_0_N_f;
    wire req_0_1_0_S_v, req_0_1_0_S_r; wire [83:0] req_0_1_0_S_f;
    wire req_0_1_0_E_v, req_0_1_0_E_r; wire [83:0] req_0_1_0_E_f;
    wire req_0_1_0_D_v, req_0_1_0_D_r; wire [83:0] req_0_1_0_D_f;
    wire req_0_1_1_N_v, req_0_1_1_N_r; wire [83:0] req_0_1_1_N_f;
    wire req_0_1_1_S_v, req_0_1_1_S_r; wire [83:0] req_0_1_1_S_f;
    wire req_0_1_1_E_v, req_0_1_1_E_r; wire [83:0] req_0_1_1_E_f;
    wire req_0_1_1_U_v, req_0_1_1_U_r; wire [83:0] req_0_1_1_U_f;
    wire req_0_1_1_D_v, req_0_1_1_D_r; wire [83:0] req_0_1_1_D_f;
    wire req_0_1_2_N_v, req_0_1_2_N_r; wire [83:0] req_0_1_2_N_f;
    wire req_0_1_2_S_v, req_0_1_2_S_r; wire [83:0] req_0_1_2_S_f;
    wire req_0_1_2_E_v, req_0_1_2_E_r; wire [83:0] req_0_1_2_E_f;
    wire req_0_1_2_U_v, req_0_1_2_U_r; wire [83:0] req_0_1_2_U_f;
    wire req_0_1_2_D_v, req_0_1_2_D_r; wire [83:0] req_0_1_2_D_f;
    wire req_0_1_3_N_v, req_0_1_3_N_r; wire [83:0] req_0_1_3_N_f;
    wire req_0_1_3_S_v, req_0_1_3_S_r; wire [83:0] req_0_1_3_S_f;
    wire req_0_1_3_E_v, req_0_1_3_E_r; wire [83:0] req_0_1_3_E_f;
    wire req_0_1_3_U_v, req_0_1_3_U_r; wire [83:0] req_0_1_3_U_f;
    wire req_0_2_0_N_v, req_0_2_0_N_r; wire [83:0] req_0_2_0_N_f;
    wire req_0_2_0_E_v, req_0_2_0_E_r; wire [83:0] req_0_2_0_E_f;
    wire req_0_2_0_D_v, req_0_2_0_D_r; wire [83:0] req_0_2_0_D_f;
    wire req_0_2_1_N_v, req_0_2_1_N_r; wire [83:0] req_0_2_1_N_f;
    wire req_0_2_1_E_v, req_0_2_1_E_r; wire [83:0] req_0_2_1_E_f;
    wire req_0_2_1_U_v, req_0_2_1_U_r; wire [83:0] req_0_2_1_U_f;
    wire req_0_2_1_D_v, req_0_2_1_D_r; wire [83:0] req_0_2_1_D_f;
    wire req_0_2_2_N_v, req_0_2_2_N_r; wire [83:0] req_0_2_2_N_f;
    wire req_0_2_2_E_v, req_0_2_2_E_r; wire [83:0] req_0_2_2_E_f;
    wire req_0_2_2_U_v, req_0_2_2_U_r; wire [83:0] req_0_2_2_U_f;
    wire req_0_2_2_D_v, req_0_2_2_D_r; wire [83:0] req_0_2_2_D_f;
    wire req_0_2_3_N_v, req_0_2_3_N_r; wire [83:0] req_0_2_3_N_f;
    wire req_0_2_3_E_v, req_0_2_3_E_r; wire [83:0] req_0_2_3_E_f;
    wire req_0_2_3_U_v, req_0_2_3_U_r; wire [83:0] req_0_2_3_U_f;
    wire req_1_0_0_S_v, req_1_0_0_S_r; wire [83:0] req_1_0_0_S_f;
    wire req_1_0_0_E_v, req_1_0_0_E_r; wire [83:0] req_1_0_0_E_f;
    wire req_1_0_0_W_v, req_1_0_0_W_r; wire [83:0] req_1_0_0_W_f;
    wire req_1_0_0_D_v, req_1_0_0_D_r; wire [83:0] req_1_0_0_D_f;
    wire req_1_0_1_S_v, req_1_0_1_S_r; wire [83:0] req_1_0_1_S_f;
    wire req_1_0_1_E_v, req_1_0_1_E_r; wire [83:0] req_1_0_1_E_f;
    wire req_1_0_1_W_v, req_1_0_1_W_r; wire [83:0] req_1_0_1_W_f;
    wire req_1_0_1_U_v, req_1_0_1_U_r; wire [83:0] req_1_0_1_U_f;
    wire req_1_0_1_D_v, req_1_0_1_D_r; wire [83:0] req_1_0_1_D_f;
    wire req_1_0_2_S_v, req_1_0_2_S_r; wire [83:0] req_1_0_2_S_f;
    wire req_1_0_2_E_v, req_1_0_2_E_r; wire [83:0] req_1_0_2_E_f;
    wire req_1_0_2_W_v, req_1_0_2_W_r; wire [83:0] req_1_0_2_W_f;
    wire req_1_0_2_U_v, req_1_0_2_U_r; wire [83:0] req_1_0_2_U_f;
    wire req_1_0_2_D_v, req_1_0_2_D_r; wire [83:0] req_1_0_2_D_f;
    wire req_1_0_3_S_v, req_1_0_3_S_r; wire [83:0] req_1_0_3_S_f;
    wire req_1_0_3_E_v, req_1_0_3_E_r; wire [83:0] req_1_0_3_E_f;
    wire req_1_0_3_W_v, req_1_0_3_W_r; wire [83:0] req_1_0_3_W_f;
    wire req_1_0_3_U_v, req_1_0_3_U_r; wire [83:0] req_1_0_3_U_f;
    wire req_1_1_0_N_v, req_1_1_0_N_r; wire [83:0] req_1_1_0_N_f;
    wire req_1_1_0_S_v, req_1_1_0_S_r; wire [83:0] req_1_1_0_S_f;
    wire req_1_1_0_E_v, req_1_1_0_E_r; wire [83:0] req_1_1_0_E_f;
    wire req_1_1_0_W_v, req_1_1_0_W_r; wire [83:0] req_1_1_0_W_f;
    wire req_1_1_0_D_v, req_1_1_0_D_r; wire [83:0] req_1_1_0_D_f;
    wire req_1_1_1_N_v, req_1_1_1_N_r; wire [83:0] req_1_1_1_N_f;
    wire req_1_1_1_S_v, req_1_1_1_S_r; wire [83:0] req_1_1_1_S_f;
    wire req_1_1_1_E_v, req_1_1_1_E_r; wire [83:0] req_1_1_1_E_f;
    wire req_1_1_1_W_v, req_1_1_1_W_r; wire [83:0] req_1_1_1_W_f;
    wire req_1_1_1_U_v, req_1_1_1_U_r; wire [83:0] req_1_1_1_U_f;
    wire req_1_1_1_D_v, req_1_1_1_D_r; wire [83:0] req_1_1_1_D_f;
    wire req_1_1_2_N_v, req_1_1_2_N_r; wire [83:0] req_1_1_2_N_f;
    wire req_1_1_2_S_v, req_1_1_2_S_r; wire [83:0] req_1_1_2_S_f;
    wire req_1_1_2_E_v, req_1_1_2_E_r; wire [83:0] req_1_1_2_E_f;
    wire req_1_1_2_W_v, req_1_1_2_W_r; wire [83:0] req_1_1_2_W_f;
    wire req_1_1_2_U_v, req_1_1_2_U_r; wire [83:0] req_1_1_2_U_f;
    wire req_1_1_2_D_v, req_1_1_2_D_r; wire [83:0] req_1_1_2_D_f;
    wire req_1_1_3_N_v, req_1_1_3_N_r; wire [83:0] req_1_1_3_N_f;
    wire req_1_1_3_S_v, req_1_1_3_S_r; wire [83:0] req_1_1_3_S_f;
    wire req_1_1_3_E_v, req_1_1_3_E_r; wire [83:0] req_1_1_3_E_f;
    wire req_1_1_3_W_v, req_1_1_3_W_r; wire [83:0] req_1_1_3_W_f;
    wire req_1_1_3_U_v, req_1_1_3_U_r; wire [83:0] req_1_1_3_U_f;
    wire req_1_2_0_N_v, req_1_2_0_N_r; wire [83:0] req_1_2_0_N_f;
    wire req_1_2_0_E_v, req_1_2_0_E_r; wire [83:0] req_1_2_0_E_f;
    wire req_1_2_0_W_v, req_1_2_0_W_r; wire [83:0] req_1_2_0_W_f;
    wire req_1_2_0_D_v, req_1_2_0_D_r; wire [83:0] req_1_2_0_D_f;
    wire req_1_2_1_N_v, req_1_2_1_N_r; wire [83:0] req_1_2_1_N_f;
    wire req_1_2_1_E_v, req_1_2_1_E_r; wire [83:0] req_1_2_1_E_f;
    wire req_1_2_1_W_v, req_1_2_1_W_r; wire [83:0] req_1_2_1_W_f;
    wire req_1_2_1_U_v, req_1_2_1_U_r; wire [83:0] req_1_2_1_U_f;
    wire req_1_2_1_D_v, req_1_2_1_D_r; wire [83:0] req_1_2_1_D_f;
    wire req_1_2_2_N_v, req_1_2_2_N_r; wire [83:0] req_1_2_2_N_f;
    wire req_1_2_2_E_v, req_1_2_2_E_r; wire [83:0] req_1_2_2_E_f;
    wire req_1_2_2_W_v, req_1_2_2_W_r; wire [83:0] req_1_2_2_W_f;
    wire req_1_2_2_U_v, req_1_2_2_U_r; wire [83:0] req_1_2_2_U_f;
    wire req_1_2_2_D_v, req_1_2_2_D_r; wire [83:0] req_1_2_2_D_f;
    wire req_1_2_3_N_v, req_1_2_3_N_r; wire [83:0] req_1_2_3_N_f;
    wire req_1_2_3_E_v, req_1_2_3_E_r; wire [83:0] req_1_2_3_E_f;
    wire req_1_2_3_W_v, req_1_2_3_W_r; wire [83:0] req_1_2_3_W_f;
    wire req_1_2_3_U_v, req_1_2_3_U_r; wire [83:0] req_1_2_3_U_f;
    wire req_2_0_0_S_v, req_2_0_0_S_r; wire [83:0] req_2_0_0_S_f;
    wire req_2_0_0_E_v, req_2_0_0_E_r; wire [83:0] req_2_0_0_E_f;
    wire req_2_0_0_W_v, req_2_0_0_W_r; wire [83:0] req_2_0_0_W_f;
    wire req_2_0_0_D_v, req_2_0_0_D_r; wire [83:0] req_2_0_0_D_f;
    wire req_2_0_1_S_v, req_2_0_1_S_r; wire [83:0] req_2_0_1_S_f;
    wire req_2_0_1_E_v, req_2_0_1_E_r; wire [83:0] req_2_0_1_E_f;
    wire req_2_0_1_W_v, req_2_0_1_W_r; wire [83:0] req_2_0_1_W_f;
    wire req_2_0_1_U_v, req_2_0_1_U_r; wire [83:0] req_2_0_1_U_f;
    wire req_2_0_1_D_v, req_2_0_1_D_r; wire [83:0] req_2_0_1_D_f;
    wire req_2_0_2_S_v, req_2_0_2_S_r; wire [83:0] req_2_0_2_S_f;
    wire req_2_0_2_E_v, req_2_0_2_E_r; wire [83:0] req_2_0_2_E_f;
    wire req_2_0_2_W_v, req_2_0_2_W_r; wire [83:0] req_2_0_2_W_f;
    wire req_2_0_2_U_v, req_2_0_2_U_r; wire [83:0] req_2_0_2_U_f;
    wire req_2_0_2_D_v, req_2_0_2_D_r; wire [83:0] req_2_0_2_D_f;
    wire req_2_0_3_S_v, req_2_0_3_S_r; wire [83:0] req_2_0_3_S_f;
    wire req_2_0_3_E_v, req_2_0_3_E_r; wire [83:0] req_2_0_3_E_f;
    wire req_2_0_3_W_v, req_2_0_3_W_r; wire [83:0] req_2_0_3_W_f;
    wire req_2_0_3_U_v, req_2_0_3_U_r; wire [83:0] req_2_0_3_U_f;
    wire req_2_1_0_N_v, req_2_1_0_N_r; wire [83:0] req_2_1_0_N_f;
    wire req_2_1_0_S_v, req_2_1_0_S_r; wire [83:0] req_2_1_0_S_f;
    wire req_2_1_0_E_v, req_2_1_0_E_r; wire [83:0] req_2_1_0_E_f;
    wire req_2_1_0_W_v, req_2_1_0_W_r; wire [83:0] req_2_1_0_W_f;
    wire req_2_1_0_D_v, req_2_1_0_D_r; wire [83:0] req_2_1_0_D_f;
    wire req_2_1_1_N_v, req_2_1_1_N_r; wire [83:0] req_2_1_1_N_f;
    wire req_2_1_1_S_v, req_2_1_1_S_r; wire [83:0] req_2_1_1_S_f;
    wire req_2_1_1_E_v, req_2_1_1_E_r; wire [83:0] req_2_1_1_E_f;
    wire req_2_1_1_W_v, req_2_1_1_W_r; wire [83:0] req_2_1_1_W_f;
    wire req_2_1_1_U_v, req_2_1_1_U_r; wire [83:0] req_2_1_1_U_f;
    wire req_2_1_1_D_v, req_2_1_1_D_r; wire [83:0] req_2_1_1_D_f;
    wire req_2_1_2_N_v, req_2_1_2_N_r; wire [83:0] req_2_1_2_N_f;
    wire req_2_1_2_S_v, req_2_1_2_S_r; wire [83:0] req_2_1_2_S_f;
    wire req_2_1_2_E_v, req_2_1_2_E_r; wire [83:0] req_2_1_2_E_f;
    wire req_2_1_2_W_v, req_2_1_2_W_r; wire [83:0] req_2_1_2_W_f;
    wire req_2_1_2_U_v, req_2_1_2_U_r; wire [83:0] req_2_1_2_U_f;
    wire req_2_1_2_D_v, req_2_1_2_D_r; wire [83:0] req_2_1_2_D_f;
    wire req_2_1_3_N_v, req_2_1_3_N_r; wire [83:0] req_2_1_3_N_f;
    wire req_2_1_3_S_v, req_2_1_3_S_r; wire [83:0] req_2_1_3_S_f;
    wire req_2_1_3_E_v, req_2_1_3_E_r; wire [83:0] req_2_1_3_E_f;
    wire req_2_1_3_W_v, req_2_1_3_W_r; wire [83:0] req_2_1_3_W_f;
    wire req_2_1_3_U_v, req_2_1_3_U_r; wire [83:0] req_2_1_3_U_f;
    wire req_2_2_0_N_v, req_2_2_0_N_r; wire [83:0] req_2_2_0_N_f;
    wire req_2_2_0_E_v, req_2_2_0_E_r; wire [83:0] req_2_2_0_E_f;
    wire req_2_2_0_W_v, req_2_2_0_W_r; wire [83:0] req_2_2_0_W_f;
    wire req_2_2_0_D_v, req_2_2_0_D_r; wire [83:0] req_2_2_0_D_f;
    wire req_2_2_1_N_v, req_2_2_1_N_r; wire [83:0] req_2_2_1_N_f;
    wire req_2_2_1_E_v, req_2_2_1_E_r; wire [83:0] req_2_2_1_E_f;
    wire req_2_2_1_W_v, req_2_2_1_W_r; wire [83:0] req_2_2_1_W_f;
    wire req_2_2_1_U_v, req_2_2_1_U_r; wire [83:0] req_2_2_1_U_f;
    wire req_2_2_1_D_v, req_2_2_1_D_r; wire [83:0] req_2_2_1_D_f;
    wire req_2_2_2_N_v, req_2_2_2_N_r; wire [83:0] req_2_2_2_N_f;
    wire req_2_2_2_E_v, req_2_2_2_E_r; wire [83:0] req_2_2_2_E_f;
    wire req_2_2_2_W_v, req_2_2_2_W_r; wire [83:0] req_2_2_2_W_f;
    wire req_2_2_2_U_v, req_2_2_2_U_r; wire [83:0] req_2_2_2_U_f;
    wire req_2_2_2_D_v, req_2_2_2_D_r; wire [83:0] req_2_2_2_D_f;
    wire req_2_2_3_N_v, req_2_2_3_N_r; wire [83:0] req_2_2_3_N_f;
    wire req_2_2_3_E_v, req_2_2_3_E_r; wire [83:0] req_2_2_3_E_f;
    wire req_2_2_3_W_v, req_2_2_3_W_r; wire [83:0] req_2_2_3_W_f;
    wire req_2_2_3_U_v, req_2_2_3_U_r; wire [83:0] req_2_2_3_U_f;
    wire req_3_0_0_S_v, req_3_0_0_S_r; wire [83:0] req_3_0_0_S_f;
    wire req_3_0_0_W_v, req_3_0_0_W_r; wire [83:0] req_3_0_0_W_f;
    wire req_3_0_0_D_v, req_3_0_0_D_r; wire [83:0] req_3_0_0_D_f;
    wire req_3_0_1_S_v, req_3_0_1_S_r; wire [83:0] req_3_0_1_S_f;
    wire req_3_0_1_W_v, req_3_0_1_W_r; wire [83:0] req_3_0_1_W_f;
    wire req_3_0_1_U_v, req_3_0_1_U_r; wire [83:0] req_3_0_1_U_f;
    wire req_3_0_1_D_v, req_3_0_1_D_r; wire [83:0] req_3_0_1_D_f;
    wire req_3_0_2_S_v, req_3_0_2_S_r; wire [83:0] req_3_0_2_S_f;
    wire req_3_0_2_W_v, req_3_0_2_W_r; wire [83:0] req_3_0_2_W_f;
    wire req_3_0_2_U_v, req_3_0_2_U_r; wire [83:0] req_3_0_2_U_f;
    wire req_3_0_2_D_v, req_3_0_2_D_r; wire [83:0] req_3_0_2_D_f;
    wire req_3_0_3_S_v, req_3_0_3_S_r; wire [83:0] req_3_0_3_S_f;
    wire req_3_0_3_W_v, req_3_0_3_W_r; wire [83:0] req_3_0_3_W_f;
    wire req_3_0_3_U_v, req_3_0_3_U_r; wire [83:0] req_3_0_3_U_f;
    wire req_3_1_0_N_v, req_3_1_0_N_r; wire [83:0] req_3_1_0_N_f;
    wire req_3_1_0_S_v, req_3_1_0_S_r; wire [83:0] req_3_1_0_S_f;
    wire req_3_1_0_W_v, req_3_1_0_W_r; wire [83:0] req_3_1_0_W_f;
    wire req_3_1_0_D_v, req_3_1_0_D_r; wire [83:0] req_3_1_0_D_f;
    wire req_3_1_1_N_v, req_3_1_1_N_r; wire [83:0] req_3_1_1_N_f;
    wire req_3_1_1_S_v, req_3_1_1_S_r; wire [83:0] req_3_1_1_S_f;
    wire req_3_1_1_W_v, req_3_1_1_W_r; wire [83:0] req_3_1_1_W_f;
    wire req_3_1_1_U_v, req_3_1_1_U_r; wire [83:0] req_3_1_1_U_f;
    wire req_3_1_1_D_v, req_3_1_1_D_r; wire [83:0] req_3_1_1_D_f;
    wire req_3_1_2_N_v, req_3_1_2_N_r; wire [83:0] req_3_1_2_N_f;
    wire req_3_1_2_S_v, req_3_1_2_S_r; wire [83:0] req_3_1_2_S_f;
    wire req_3_1_2_W_v, req_3_1_2_W_r; wire [83:0] req_3_1_2_W_f;
    wire req_3_1_2_U_v, req_3_1_2_U_r; wire [83:0] req_3_1_2_U_f;
    wire req_3_1_2_D_v, req_3_1_2_D_r; wire [83:0] req_3_1_2_D_f;
    wire req_3_1_3_N_v, req_3_1_3_N_r; wire [83:0] req_3_1_3_N_f;
    wire req_3_1_3_S_v, req_3_1_3_S_r; wire [83:0] req_3_1_3_S_f;
    wire req_3_1_3_W_v, req_3_1_3_W_r; wire [83:0] req_3_1_3_W_f;
    wire req_3_1_3_U_v, req_3_1_3_U_r; wire [83:0] req_3_1_3_U_f;
    wire req_3_2_0_N_v, req_3_2_0_N_r; wire [83:0] req_3_2_0_N_f;
    wire req_3_2_0_W_v, req_3_2_0_W_r; wire [83:0] req_3_2_0_W_f;
    wire req_3_2_0_D_v, req_3_2_0_D_r; wire [83:0] req_3_2_0_D_f;
    wire req_3_2_1_N_v, req_3_2_1_N_r; wire [83:0] req_3_2_1_N_f;
    wire req_3_2_1_W_v, req_3_2_1_W_r; wire [83:0] req_3_2_1_W_f;
    wire req_3_2_1_U_v, req_3_2_1_U_r; wire [83:0] req_3_2_1_U_f;
    wire req_3_2_1_D_v, req_3_2_1_D_r; wire [83:0] req_3_2_1_D_f;
    wire req_3_2_2_N_v, req_3_2_2_N_r; wire [83:0] req_3_2_2_N_f;
    wire req_3_2_2_W_v, req_3_2_2_W_r; wire [83:0] req_3_2_2_W_f;
    wire req_3_2_2_U_v, req_3_2_2_U_r; wire [83:0] req_3_2_2_U_f;
    wire req_3_2_2_D_v, req_3_2_2_D_r; wire [83:0] req_3_2_2_D_f;
    wire req_3_2_3_N_v, req_3_2_3_N_r; wire [83:0] req_3_2_3_N_f;
    wire req_3_2_3_W_v, req_3_2_3_W_r; wire [83:0] req_3_2_3_W_f;
    wire req_3_2_3_U_v, req_3_2_3_U_r; wire [83:0] req_3_2_3_U_f;
    wire resp_0_0_0_S_v, resp_0_0_0_S_r; wire [39:0] resp_0_0_0_S_f;
    wire resp_0_0_0_E_v, resp_0_0_0_E_r; wire [39:0] resp_0_0_0_E_f;
    wire resp_0_0_0_D_v, resp_0_0_0_D_r; wire [39:0] resp_0_0_0_D_f;
    wire resp_0_0_1_S_v, resp_0_0_1_S_r; wire [39:0] resp_0_0_1_S_f;
    wire resp_0_0_1_E_v, resp_0_0_1_E_r; wire [39:0] resp_0_0_1_E_f;
    wire resp_0_0_1_U_v, resp_0_0_1_U_r; wire [39:0] resp_0_0_1_U_f;
    wire resp_0_0_1_D_v, resp_0_0_1_D_r; wire [39:0] resp_0_0_1_D_f;
    wire resp_0_0_2_S_v, resp_0_0_2_S_r; wire [39:0] resp_0_0_2_S_f;
    wire resp_0_0_2_E_v, resp_0_0_2_E_r; wire [39:0] resp_0_0_2_E_f;
    wire resp_0_0_2_U_v, resp_0_0_2_U_r; wire [39:0] resp_0_0_2_U_f;
    wire resp_0_0_2_D_v, resp_0_0_2_D_r; wire [39:0] resp_0_0_2_D_f;
    wire resp_0_0_3_S_v, resp_0_0_3_S_r; wire [39:0] resp_0_0_3_S_f;
    wire resp_0_0_3_E_v, resp_0_0_3_E_r; wire [39:0] resp_0_0_3_E_f;
    wire resp_0_0_3_U_v, resp_0_0_3_U_r; wire [39:0] resp_0_0_3_U_f;
    wire resp_0_1_0_N_v, resp_0_1_0_N_r; wire [39:0] resp_0_1_0_N_f;
    wire resp_0_1_0_S_v, resp_0_1_0_S_r; wire [39:0] resp_0_1_0_S_f;
    wire resp_0_1_0_E_v, resp_0_1_0_E_r; wire [39:0] resp_0_1_0_E_f;
    wire resp_0_1_0_D_v, resp_0_1_0_D_r; wire [39:0] resp_0_1_0_D_f;
    wire resp_0_1_1_N_v, resp_0_1_1_N_r; wire [39:0] resp_0_1_1_N_f;
    wire resp_0_1_1_S_v, resp_0_1_1_S_r; wire [39:0] resp_0_1_1_S_f;
    wire resp_0_1_1_E_v, resp_0_1_1_E_r; wire [39:0] resp_0_1_1_E_f;
    wire resp_0_1_1_U_v, resp_0_1_1_U_r; wire [39:0] resp_0_1_1_U_f;
    wire resp_0_1_1_D_v, resp_0_1_1_D_r; wire [39:0] resp_0_1_1_D_f;
    wire resp_0_1_2_N_v, resp_0_1_2_N_r; wire [39:0] resp_0_1_2_N_f;
    wire resp_0_1_2_S_v, resp_0_1_2_S_r; wire [39:0] resp_0_1_2_S_f;
    wire resp_0_1_2_E_v, resp_0_1_2_E_r; wire [39:0] resp_0_1_2_E_f;
    wire resp_0_1_2_U_v, resp_0_1_2_U_r; wire [39:0] resp_0_1_2_U_f;
    wire resp_0_1_2_D_v, resp_0_1_2_D_r; wire [39:0] resp_0_1_2_D_f;
    wire resp_0_1_3_N_v, resp_0_1_3_N_r; wire [39:0] resp_0_1_3_N_f;
    wire resp_0_1_3_S_v, resp_0_1_3_S_r; wire [39:0] resp_0_1_3_S_f;
    wire resp_0_1_3_E_v, resp_0_1_3_E_r; wire [39:0] resp_0_1_3_E_f;
    wire resp_0_1_3_U_v, resp_0_1_3_U_r; wire [39:0] resp_0_1_3_U_f;
    wire resp_0_2_0_N_v, resp_0_2_0_N_r; wire [39:0] resp_0_2_0_N_f;
    wire resp_0_2_0_E_v, resp_0_2_0_E_r; wire [39:0] resp_0_2_0_E_f;
    wire resp_0_2_0_D_v, resp_0_2_0_D_r; wire [39:0] resp_0_2_0_D_f;
    wire resp_0_2_1_N_v, resp_0_2_1_N_r; wire [39:0] resp_0_2_1_N_f;
    wire resp_0_2_1_E_v, resp_0_2_1_E_r; wire [39:0] resp_0_2_1_E_f;
    wire resp_0_2_1_U_v, resp_0_2_1_U_r; wire [39:0] resp_0_2_1_U_f;
    wire resp_0_2_1_D_v, resp_0_2_1_D_r; wire [39:0] resp_0_2_1_D_f;
    wire resp_0_2_2_N_v, resp_0_2_2_N_r; wire [39:0] resp_0_2_2_N_f;
    wire resp_0_2_2_E_v, resp_0_2_2_E_r; wire [39:0] resp_0_2_2_E_f;
    wire resp_0_2_2_U_v, resp_0_2_2_U_r; wire [39:0] resp_0_2_2_U_f;
    wire resp_0_2_2_D_v, resp_0_2_2_D_r; wire [39:0] resp_0_2_2_D_f;
    wire resp_0_2_3_N_v, resp_0_2_3_N_r; wire [39:0] resp_0_2_3_N_f;
    wire resp_0_2_3_E_v, resp_0_2_3_E_r; wire [39:0] resp_0_2_3_E_f;
    wire resp_0_2_3_U_v, resp_0_2_3_U_r; wire [39:0] resp_0_2_3_U_f;
    wire resp_1_0_0_S_v, resp_1_0_0_S_r; wire [39:0] resp_1_0_0_S_f;
    wire resp_1_0_0_E_v, resp_1_0_0_E_r; wire [39:0] resp_1_0_0_E_f;
    wire resp_1_0_0_W_v, resp_1_0_0_W_r; wire [39:0] resp_1_0_0_W_f;
    wire resp_1_0_0_D_v, resp_1_0_0_D_r; wire [39:0] resp_1_0_0_D_f;
    wire resp_1_0_1_S_v, resp_1_0_1_S_r; wire [39:0] resp_1_0_1_S_f;
    wire resp_1_0_1_E_v, resp_1_0_1_E_r; wire [39:0] resp_1_0_1_E_f;
    wire resp_1_0_1_W_v, resp_1_0_1_W_r; wire [39:0] resp_1_0_1_W_f;
    wire resp_1_0_1_U_v, resp_1_0_1_U_r; wire [39:0] resp_1_0_1_U_f;
    wire resp_1_0_1_D_v, resp_1_0_1_D_r; wire [39:0] resp_1_0_1_D_f;
    wire resp_1_0_2_S_v, resp_1_0_2_S_r; wire [39:0] resp_1_0_2_S_f;
    wire resp_1_0_2_E_v, resp_1_0_2_E_r; wire [39:0] resp_1_0_2_E_f;
    wire resp_1_0_2_W_v, resp_1_0_2_W_r; wire [39:0] resp_1_0_2_W_f;
    wire resp_1_0_2_U_v, resp_1_0_2_U_r; wire [39:0] resp_1_0_2_U_f;
    wire resp_1_0_2_D_v, resp_1_0_2_D_r; wire [39:0] resp_1_0_2_D_f;
    wire resp_1_0_3_S_v, resp_1_0_3_S_r; wire [39:0] resp_1_0_3_S_f;
    wire resp_1_0_3_E_v, resp_1_0_3_E_r; wire [39:0] resp_1_0_3_E_f;
    wire resp_1_0_3_W_v, resp_1_0_3_W_r; wire [39:0] resp_1_0_3_W_f;
    wire resp_1_0_3_U_v, resp_1_0_3_U_r; wire [39:0] resp_1_0_3_U_f;
    wire resp_1_1_0_N_v, resp_1_1_0_N_r; wire [39:0] resp_1_1_0_N_f;
    wire resp_1_1_0_S_v, resp_1_1_0_S_r; wire [39:0] resp_1_1_0_S_f;
    wire resp_1_1_0_E_v, resp_1_1_0_E_r; wire [39:0] resp_1_1_0_E_f;
    wire resp_1_1_0_W_v, resp_1_1_0_W_r; wire [39:0] resp_1_1_0_W_f;
    wire resp_1_1_0_D_v, resp_1_1_0_D_r; wire [39:0] resp_1_1_0_D_f;
    wire resp_1_1_1_N_v, resp_1_1_1_N_r; wire [39:0] resp_1_1_1_N_f;
    wire resp_1_1_1_S_v, resp_1_1_1_S_r; wire [39:0] resp_1_1_1_S_f;
    wire resp_1_1_1_E_v, resp_1_1_1_E_r; wire [39:0] resp_1_1_1_E_f;
    wire resp_1_1_1_W_v, resp_1_1_1_W_r; wire [39:0] resp_1_1_1_W_f;
    wire resp_1_1_1_U_v, resp_1_1_1_U_r; wire [39:0] resp_1_1_1_U_f;
    wire resp_1_1_1_D_v, resp_1_1_1_D_r; wire [39:0] resp_1_1_1_D_f;
    wire resp_1_1_2_N_v, resp_1_1_2_N_r; wire [39:0] resp_1_1_2_N_f;
    wire resp_1_1_2_S_v, resp_1_1_2_S_r; wire [39:0] resp_1_1_2_S_f;
    wire resp_1_1_2_E_v, resp_1_1_2_E_r; wire [39:0] resp_1_1_2_E_f;
    wire resp_1_1_2_W_v, resp_1_1_2_W_r; wire [39:0] resp_1_1_2_W_f;
    wire resp_1_1_2_U_v, resp_1_1_2_U_r; wire [39:0] resp_1_1_2_U_f;
    wire resp_1_1_2_D_v, resp_1_1_2_D_r; wire [39:0] resp_1_1_2_D_f;
    wire resp_1_1_3_N_v, resp_1_1_3_N_r; wire [39:0] resp_1_1_3_N_f;
    wire resp_1_1_3_S_v, resp_1_1_3_S_r; wire [39:0] resp_1_1_3_S_f;
    wire resp_1_1_3_E_v, resp_1_1_3_E_r; wire [39:0] resp_1_1_3_E_f;
    wire resp_1_1_3_W_v, resp_1_1_3_W_r; wire [39:0] resp_1_1_3_W_f;
    wire resp_1_1_3_U_v, resp_1_1_3_U_r; wire [39:0] resp_1_1_3_U_f;
    wire resp_1_2_0_N_v, resp_1_2_0_N_r; wire [39:0] resp_1_2_0_N_f;
    wire resp_1_2_0_E_v, resp_1_2_0_E_r; wire [39:0] resp_1_2_0_E_f;
    wire resp_1_2_0_W_v, resp_1_2_0_W_r; wire [39:0] resp_1_2_0_W_f;
    wire resp_1_2_0_D_v, resp_1_2_0_D_r; wire [39:0] resp_1_2_0_D_f;
    wire resp_1_2_1_N_v, resp_1_2_1_N_r; wire [39:0] resp_1_2_1_N_f;
    wire resp_1_2_1_E_v, resp_1_2_1_E_r; wire [39:0] resp_1_2_1_E_f;
    wire resp_1_2_1_W_v, resp_1_2_1_W_r; wire [39:0] resp_1_2_1_W_f;
    wire resp_1_2_1_U_v, resp_1_2_1_U_r; wire [39:0] resp_1_2_1_U_f;
    wire resp_1_2_1_D_v, resp_1_2_1_D_r; wire [39:0] resp_1_2_1_D_f;
    wire resp_1_2_2_N_v, resp_1_2_2_N_r; wire [39:0] resp_1_2_2_N_f;
    wire resp_1_2_2_E_v, resp_1_2_2_E_r; wire [39:0] resp_1_2_2_E_f;
    wire resp_1_2_2_W_v, resp_1_2_2_W_r; wire [39:0] resp_1_2_2_W_f;
    wire resp_1_2_2_U_v, resp_1_2_2_U_r; wire [39:0] resp_1_2_2_U_f;
    wire resp_1_2_2_D_v, resp_1_2_2_D_r; wire [39:0] resp_1_2_2_D_f;
    wire resp_1_2_3_N_v, resp_1_2_3_N_r; wire [39:0] resp_1_2_3_N_f;
    wire resp_1_2_3_E_v, resp_1_2_3_E_r; wire [39:0] resp_1_2_3_E_f;
    wire resp_1_2_3_W_v, resp_1_2_3_W_r; wire [39:0] resp_1_2_3_W_f;
    wire resp_1_2_3_U_v, resp_1_2_3_U_r; wire [39:0] resp_1_2_3_U_f;
    wire resp_2_0_0_S_v, resp_2_0_0_S_r; wire [39:0] resp_2_0_0_S_f;
    wire resp_2_0_0_E_v, resp_2_0_0_E_r; wire [39:0] resp_2_0_0_E_f;
    wire resp_2_0_0_W_v, resp_2_0_0_W_r; wire [39:0] resp_2_0_0_W_f;
    wire resp_2_0_0_D_v, resp_2_0_0_D_r; wire [39:0] resp_2_0_0_D_f;
    wire resp_2_0_1_S_v, resp_2_0_1_S_r; wire [39:0] resp_2_0_1_S_f;
    wire resp_2_0_1_E_v, resp_2_0_1_E_r; wire [39:0] resp_2_0_1_E_f;
    wire resp_2_0_1_W_v, resp_2_0_1_W_r; wire [39:0] resp_2_0_1_W_f;
    wire resp_2_0_1_U_v, resp_2_0_1_U_r; wire [39:0] resp_2_0_1_U_f;
    wire resp_2_0_1_D_v, resp_2_0_1_D_r; wire [39:0] resp_2_0_1_D_f;
    wire resp_2_0_2_S_v, resp_2_0_2_S_r; wire [39:0] resp_2_0_2_S_f;
    wire resp_2_0_2_E_v, resp_2_0_2_E_r; wire [39:0] resp_2_0_2_E_f;
    wire resp_2_0_2_W_v, resp_2_0_2_W_r; wire [39:0] resp_2_0_2_W_f;
    wire resp_2_0_2_U_v, resp_2_0_2_U_r; wire [39:0] resp_2_0_2_U_f;
    wire resp_2_0_2_D_v, resp_2_0_2_D_r; wire [39:0] resp_2_0_2_D_f;
    wire resp_2_0_3_S_v, resp_2_0_3_S_r; wire [39:0] resp_2_0_3_S_f;
    wire resp_2_0_3_E_v, resp_2_0_3_E_r; wire [39:0] resp_2_0_3_E_f;
    wire resp_2_0_3_W_v, resp_2_0_3_W_r; wire [39:0] resp_2_0_3_W_f;
    wire resp_2_0_3_U_v, resp_2_0_3_U_r; wire [39:0] resp_2_0_3_U_f;
    wire resp_2_1_0_N_v, resp_2_1_0_N_r; wire [39:0] resp_2_1_0_N_f;
    wire resp_2_1_0_S_v, resp_2_1_0_S_r; wire [39:0] resp_2_1_0_S_f;
    wire resp_2_1_0_E_v, resp_2_1_0_E_r; wire [39:0] resp_2_1_0_E_f;
    wire resp_2_1_0_W_v, resp_2_1_0_W_r; wire [39:0] resp_2_1_0_W_f;
    wire resp_2_1_0_D_v, resp_2_1_0_D_r; wire [39:0] resp_2_1_0_D_f;
    wire resp_2_1_1_N_v, resp_2_1_1_N_r; wire [39:0] resp_2_1_1_N_f;
    wire resp_2_1_1_S_v, resp_2_1_1_S_r; wire [39:0] resp_2_1_1_S_f;
    wire resp_2_1_1_E_v, resp_2_1_1_E_r; wire [39:0] resp_2_1_1_E_f;
    wire resp_2_1_1_W_v, resp_2_1_1_W_r; wire [39:0] resp_2_1_1_W_f;
    wire resp_2_1_1_U_v, resp_2_1_1_U_r; wire [39:0] resp_2_1_1_U_f;
    wire resp_2_1_1_D_v, resp_2_1_1_D_r; wire [39:0] resp_2_1_1_D_f;
    wire resp_2_1_2_N_v, resp_2_1_2_N_r; wire [39:0] resp_2_1_2_N_f;
    wire resp_2_1_2_S_v, resp_2_1_2_S_r; wire [39:0] resp_2_1_2_S_f;
    wire resp_2_1_2_E_v, resp_2_1_2_E_r; wire [39:0] resp_2_1_2_E_f;
    wire resp_2_1_2_W_v, resp_2_1_2_W_r; wire [39:0] resp_2_1_2_W_f;
    wire resp_2_1_2_U_v, resp_2_1_2_U_r; wire [39:0] resp_2_1_2_U_f;
    wire resp_2_1_2_D_v, resp_2_1_2_D_r; wire [39:0] resp_2_1_2_D_f;
    wire resp_2_1_3_N_v, resp_2_1_3_N_r; wire [39:0] resp_2_1_3_N_f;
    wire resp_2_1_3_S_v, resp_2_1_3_S_r; wire [39:0] resp_2_1_3_S_f;
    wire resp_2_1_3_E_v, resp_2_1_3_E_r; wire [39:0] resp_2_1_3_E_f;
    wire resp_2_1_3_W_v, resp_2_1_3_W_r; wire [39:0] resp_2_1_3_W_f;
    wire resp_2_1_3_U_v, resp_2_1_3_U_r; wire [39:0] resp_2_1_3_U_f;
    wire resp_2_2_0_N_v, resp_2_2_0_N_r; wire [39:0] resp_2_2_0_N_f;
    wire resp_2_2_0_E_v, resp_2_2_0_E_r; wire [39:0] resp_2_2_0_E_f;
    wire resp_2_2_0_W_v, resp_2_2_0_W_r; wire [39:0] resp_2_2_0_W_f;
    wire resp_2_2_0_D_v, resp_2_2_0_D_r; wire [39:0] resp_2_2_0_D_f;
    wire resp_2_2_1_N_v, resp_2_2_1_N_r; wire [39:0] resp_2_2_1_N_f;
    wire resp_2_2_1_E_v, resp_2_2_1_E_r; wire [39:0] resp_2_2_1_E_f;
    wire resp_2_2_1_W_v, resp_2_2_1_W_r; wire [39:0] resp_2_2_1_W_f;
    wire resp_2_2_1_U_v, resp_2_2_1_U_r; wire [39:0] resp_2_2_1_U_f;
    wire resp_2_2_1_D_v, resp_2_2_1_D_r; wire [39:0] resp_2_2_1_D_f;
    wire resp_2_2_2_N_v, resp_2_2_2_N_r; wire [39:0] resp_2_2_2_N_f;
    wire resp_2_2_2_E_v, resp_2_2_2_E_r; wire [39:0] resp_2_2_2_E_f;
    wire resp_2_2_2_W_v, resp_2_2_2_W_r; wire [39:0] resp_2_2_2_W_f;
    wire resp_2_2_2_U_v, resp_2_2_2_U_r; wire [39:0] resp_2_2_2_U_f;
    wire resp_2_2_2_D_v, resp_2_2_2_D_r; wire [39:0] resp_2_2_2_D_f;
    wire resp_2_2_3_N_v, resp_2_2_3_N_r; wire [39:0] resp_2_2_3_N_f;
    wire resp_2_2_3_E_v, resp_2_2_3_E_r; wire [39:0] resp_2_2_3_E_f;
    wire resp_2_2_3_W_v, resp_2_2_3_W_r; wire [39:0] resp_2_2_3_W_f;
    wire resp_2_2_3_U_v, resp_2_2_3_U_r; wire [39:0] resp_2_2_3_U_f;
    wire resp_3_0_0_S_v, resp_3_0_0_S_r; wire [39:0] resp_3_0_0_S_f;
    wire resp_3_0_0_W_v, resp_3_0_0_W_r; wire [39:0] resp_3_0_0_W_f;
    wire resp_3_0_0_D_v, resp_3_0_0_D_r; wire [39:0] resp_3_0_0_D_f;
    wire resp_3_0_1_S_v, resp_3_0_1_S_r; wire [39:0] resp_3_0_1_S_f;
    wire resp_3_0_1_W_v, resp_3_0_1_W_r; wire [39:0] resp_3_0_1_W_f;
    wire resp_3_0_1_U_v, resp_3_0_1_U_r; wire [39:0] resp_3_0_1_U_f;
    wire resp_3_0_1_D_v, resp_3_0_1_D_r; wire [39:0] resp_3_0_1_D_f;
    wire resp_3_0_2_S_v, resp_3_0_2_S_r; wire [39:0] resp_3_0_2_S_f;
    wire resp_3_0_2_W_v, resp_3_0_2_W_r; wire [39:0] resp_3_0_2_W_f;
    wire resp_3_0_2_U_v, resp_3_0_2_U_r; wire [39:0] resp_3_0_2_U_f;
    wire resp_3_0_2_D_v, resp_3_0_2_D_r; wire [39:0] resp_3_0_2_D_f;
    wire resp_3_0_3_S_v, resp_3_0_3_S_r; wire [39:0] resp_3_0_3_S_f;
    wire resp_3_0_3_W_v, resp_3_0_3_W_r; wire [39:0] resp_3_0_3_W_f;
    wire resp_3_0_3_U_v, resp_3_0_3_U_r; wire [39:0] resp_3_0_3_U_f;
    wire resp_3_1_0_N_v, resp_3_1_0_N_r; wire [39:0] resp_3_1_0_N_f;
    wire resp_3_1_0_S_v, resp_3_1_0_S_r; wire [39:0] resp_3_1_0_S_f;
    wire resp_3_1_0_W_v, resp_3_1_0_W_r; wire [39:0] resp_3_1_0_W_f;
    wire resp_3_1_0_D_v, resp_3_1_0_D_r; wire [39:0] resp_3_1_0_D_f;
    wire resp_3_1_1_N_v, resp_3_1_1_N_r; wire [39:0] resp_3_1_1_N_f;
    wire resp_3_1_1_S_v, resp_3_1_1_S_r; wire [39:0] resp_3_1_1_S_f;
    wire resp_3_1_1_W_v, resp_3_1_1_W_r; wire [39:0] resp_3_1_1_W_f;
    wire resp_3_1_1_U_v, resp_3_1_1_U_r; wire [39:0] resp_3_1_1_U_f;
    wire resp_3_1_1_D_v, resp_3_1_1_D_r; wire [39:0] resp_3_1_1_D_f;
    wire resp_3_1_2_N_v, resp_3_1_2_N_r; wire [39:0] resp_3_1_2_N_f;
    wire resp_3_1_2_S_v, resp_3_1_2_S_r; wire [39:0] resp_3_1_2_S_f;
    wire resp_3_1_2_W_v, resp_3_1_2_W_r; wire [39:0] resp_3_1_2_W_f;
    wire resp_3_1_2_U_v, resp_3_1_2_U_r; wire [39:0] resp_3_1_2_U_f;
    wire resp_3_1_2_D_v, resp_3_1_2_D_r; wire [39:0] resp_3_1_2_D_f;
    wire resp_3_1_3_N_v, resp_3_1_3_N_r; wire [39:0] resp_3_1_3_N_f;
    wire resp_3_1_3_S_v, resp_3_1_3_S_r; wire [39:0] resp_3_1_3_S_f;
    wire resp_3_1_3_W_v, resp_3_1_3_W_r; wire [39:0] resp_3_1_3_W_f;
    wire resp_3_1_3_U_v, resp_3_1_3_U_r; wire [39:0] resp_3_1_3_U_f;
    wire resp_3_2_0_N_v, resp_3_2_0_N_r; wire [39:0] resp_3_2_0_N_f;
    wire resp_3_2_0_W_v, resp_3_2_0_W_r; wire [39:0] resp_3_2_0_W_f;
    wire resp_3_2_0_D_v, resp_3_2_0_D_r; wire [39:0] resp_3_2_0_D_f;
    wire resp_3_2_1_N_v, resp_3_2_1_N_r; wire [39:0] resp_3_2_1_N_f;
    wire resp_3_2_1_W_v, resp_3_2_1_W_r; wire [39:0] resp_3_2_1_W_f;
    wire resp_3_2_1_U_v, resp_3_2_1_U_r; wire [39:0] resp_3_2_1_U_f;
    wire resp_3_2_1_D_v, resp_3_2_1_D_r; wire [39:0] resp_3_2_1_D_f;
    wire resp_3_2_2_N_v, resp_3_2_2_N_r; wire [39:0] resp_3_2_2_N_f;
    wire resp_3_2_2_W_v, resp_3_2_2_W_r; wire [39:0] resp_3_2_2_W_f;
    wire resp_3_2_2_U_v, resp_3_2_2_U_r; wire [39:0] resp_3_2_2_U_f;
    wire resp_3_2_2_D_v, resp_3_2_2_D_r; wire [39:0] resp_3_2_2_D_f;
    wire resp_3_2_3_N_v, resp_3_2_3_N_r; wire [39:0] resp_3_2_3_N_f;
    wire resp_3_2_3_W_v, resp_3_2_3_W_r; wire [39:0] resp_3_2_3_W_f;
    wire resp_3_2_3_U_v, resp_3_2_3_U_r; wire [39:0] resp_3_2_3_U_f;

    // ==================== Per-core bus + adapter wires ====================
    wire c0_bus_req, c0_bus_mem_write, c0_bus_mem_unsigned, c0_bus_grant;
    wire [31:0] c0_bus_addr, c0_bus_write_data, c0_bus_read_data;
    wire [1:0] c0_bus_mem_size;
    wire c0_req_out_valid, c0_req_out_ready, c0_resp_in_valid, c0_resp_in_ready;
    wire [83:0] c0_req_out_flit;
    wire [39:0] c0_resp_in_flit;
    wire c1_bus_req, c1_bus_mem_write, c1_bus_mem_unsigned, c1_bus_grant;
    wire [31:0] c1_bus_addr, c1_bus_write_data, c1_bus_read_data;
    wire [1:0] c1_bus_mem_size;
    wire c1_req_out_valid, c1_req_out_ready, c1_resp_in_valid, c1_resp_in_ready;
    wire [83:0] c1_req_out_flit;
    wire [39:0] c1_resp_in_flit;
    wire c2_bus_req, c2_bus_mem_write, c2_bus_mem_unsigned, c2_bus_grant;
    wire [31:0] c2_bus_addr, c2_bus_write_data, c2_bus_read_data;
    wire [1:0] c2_bus_mem_size;
    wire c2_req_out_valid, c2_req_out_ready, c2_resp_in_valid, c2_resp_in_ready;
    wire [83:0] c2_req_out_flit;
    wire [39:0] c2_resp_in_flit;
    wire c3_bus_req, c3_bus_mem_write, c3_bus_mem_unsigned, c3_bus_grant;
    wire [31:0] c3_bus_addr, c3_bus_write_data, c3_bus_read_data;
    wire [1:0] c3_bus_mem_size;
    wire c3_req_out_valid, c3_req_out_ready, c3_resp_in_valid, c3_resp_in_ready;
    wire [83:0] c3_req_out_flit;
    wire [39:0] c3_resp_in_flit;
    wire c4_bus_req, c4_bus_mem_write, c4_bus_mem_unsigned, c4_bus_grant;
    wire [31:0] c4_bus_addr, c4_bus_write_data, c4_bus_read_data;
    wire [1:0] c4_bus_mem_size;
    wire c4_req_out_valid, c4_req_out_ready, c4_resp_in_valid, c4_resp_in_ready;
    wire [83:0] c4_req_out_flit;
    wire [39:0] c4_resp_in_flit;
    wire c5_bus_req, c5_bus_mem_write, c5_bus_mem_unsigned, c5_bus_grant;
    wire [31:0] c5_bus_addr, c5_bus_write_data, c5_bus_read_data;
    wire [1:0] c5_bus_mem_size;
    wire c5_req_out_valid, c5_req_out_ready, c5_resp_in_valid, c5_resp_in_ready;
    wire [83:0] c5_req_out_flit;
    wire [39:0] c5_resp_in_flit;
    wire c6_bus_req, c6_bus_mem_write, c6_bus_mem_unsigned, c6_bus_grant;
    wire [31:0] c6_bus_addr, c6_bus_write_data, c6_bus_read_data;
    wire [1:0] c6_bus_mem_size;
    wire c6_req_out_valid, c6_req_out_ready, c6_resp_in_valid, c6_resp_in_ready;
    wire [83:0] c6_req_out_flit;
    wire [39:0] c6_resp_in_flit;
    wire c7_bus_req, c7_bus_mem_write, c7_bus_mem_unsigned, c7_bus_grant;
    wire [31:0] c7_bus_addr, c7_bus_write_data, c7_bus_read_data;
    wire [1:0] c7_bus_mem_size;
    wire c7_req_out_valid, c7_req_out_ready, c7_resp_in_valid, c7_resp_in_ready;
    wire [83:0] c7_req_out_flit;
    wire [39:0] c7_resp_in_flit;
    wire c8_bus_req, c8_bus_mem_write, c8_bus_mem_unsigned, c8_bus_grant;
    wire [31:0] c8_bus_addr, c8_bus_write_data, c8_bus_read_data;
    wire [1:0] c8_bus_mem_size;
    wire c8_req_out_valid, c8_req_out_ready, c8_resp_in_valid, c8_resp_in_ready;
    wire [83:0] c8_req_out_flit;
    wire [39:0] c8_resp_in_flit;
    wire c9_bus_req, c9_bus_mem_write, c9_bus_mem_unsigned, c9_bus_grant;
    wire [31:0] c9_bus_addr, c9_bus_write_data, c9_bus_read_data;
    wire [1:0] c9_bus_mem_size;
    wire c9_req_out_valid, c9_req_out_ready, c9_resp_in_valid, c9_resp_in_ready;
    wire [83:0] c9_req_out_flit;
    wire [39:0] c9_resp_in_flit;
    wire c10_bus_req, c10_bus_mem_write, c10_bus_mem_unsigned, c10_bus_grant;
    wire [31:0] c10_bus_addr, c10_bus_write_data, c10_bus_read_data;
    wire [1:0] c10_bus_mem_size;
    wire c10_req_out_valid, c10_req_out_ready, c10_resp_in_valid, c10_resp_in_ready;
    wire [83:0] c10_req_out_flit;
    wire [39:0] c10_resp_in_flit;
    wire c11_bus_req, c11_bus_mem_write, c11_bus_mem_unsigned, c11_bus_grant;
    wire [31:0] c11_bus_addr, c11_bus_write_data, c11_bus_read_data;
    wire [1:0] c11_bus_mem_size;
    wire c11_req_out_valid, c11_req_out_ready, c11_resp_in_valid, c11_resp_in_ready;
    wire [83:0] c11_req_out_flit;
    wire [39:0] c11_resp_in_flit;
    wire c12_bus_req, c12_bus_mem_write, c12_bus_mem_unsigned, c12_bus_grant;
    wire [31:0] c12_bus_addr, c12_bus_write_data, c12_bus_read_data;
    wire [1:0] c12_bus_mem_size;
    wire c12_req_out_valid, c12_req_out_ready, c12_resp_in_valid, c12_resp_in_ready;
    wire [83:0] c12_req_out_flit;
    wire [39:0] c12_resp_in_flit;
    wire c13_bus_req, c13_bus_mem_write, c13_bus_mem_unsigned, c13_bus_grant;
    wire [31:0] c13_bus_addr, c13_bus_write_data, c13_bus_read_data;
    wire [1:0] c13_bus_mem_size;
    wire c13_req_out_valid, c13_req_out_ready, c13_resp_in_valid, c13_resp_in_ready;
    wire [83:0] c13_req_out_flit;
    wire [39:0] c13_resp_in_flit;
    wire c14_bus_req, c14_bus_mem_write, c14_bus_mem_unsigned, c14_bus_grant;
    wire [31:0] c14_bus_addr, c14_bus_write_data, c14_bus_read_data;
    wire [1:0] c14_bus_mem_size;
    wire c14_req_out_valid, c14_req_out_ready, c14_resp_in_valid, c14_resp_in_ready;
    wire [83:0] c14_req_out_flit;
    wire [39:0] c14_resp_in_flit;
    wire c15_bus_req, c15_bus_mem_write, c15_bus_mem_unsigned, c15_bus_grant;
    wire [31:0] c15_bus_addr, c15_bus_write_data, c15_bus_read_data;
    wire [1:0] c15_bus_mem_size;
    wire c15_req_out_valid, c15_req_out_ready, c15_resp_in_valid, c15_resp_in_ready;
    wire [83:0] c15_req_out_flit;
    wire [39:0] c15_resp_in_flit;
    wire c16_bus_req, c16_bus_mem_write, c16_bus_mem_unsigned, c16_bus_grant;
    wire [31:0] c16_bus_addr, c16_bus_write_data, c16_bus_read_data;
    wire [1:0] c16_bus_mem_size;
    wire c16_req_out_valid, c16_req_out_ready, c16_resp_in_valid, c16_resp_in_ready;
    wire [83:0] c16_req_out_flit;
    wire [39:0] c16_resp_in_flit;
    wire c17_bus_req, c17_bus_mem_write, c17_bus_mem_unsigned, c17_bus_grant;
    wire [31:0] c17_bus_addr, c17_bus_write_data, c17_bus_read_data;
    wire [1:0] c17_bus_mem_size;
    wire c17_req_out_valid, c17_req_out_ready, c17_resp_in_valid, c17_resp_in_ready;
    wire [83:0] c17_req_out_flit;
    wire [39:0] c17_resp_in_flit;
    wire c18_bus_req, c18_bus_mem_write, c18_bus_mem_unsigned, c18_bus_grant;
    wire [31:0] c18_bus_addr, c18_bus_write_data, c18_bus_read_data;
    wire [1:0] c18_bus_mem_size;
    wire c18_req_out_valid, c18_req_out_ready, c18_resp_in_valid, c18_resp_in_ready;
    wire [83:0] c18_req_out_flit;
    wire [39:0] c18_resp_in_flit;
    wire c19_bus_req, c19_bus_mem_write, c19_bus_mem_unsigned, c19_bus_grant;
    wire [31:0] c19_bus_addr, c19_bus_write_data, c19_bus_read_data;
    wire [1:0] c19_bus_mem_size;
    wire c19_req_out_valid, c19_req_out_ready, c19_resp_in_valid, c19_resp_in_ready;
    wire [83:0] c19_req_out_flit;
    wire [39:0] c19_resp_in_flit;
    wire c20_bus_req, c20_bus_mem_write, c20_bus_mem_unsigned, c20_bus_grant;
    wire [31:0] c20_bus_addr, c20_bus_write_data, c20_bus_read_data;
    wire [1:0] c20_bus_mem_size;
    wire c20_req_out_valid, c20_req_out_ready, c20_resp_in_valid, c20_resp_in_ready;
    wire [83:0] c20_req_out_flit;
    wire [39:0] c20_resp_in_flit;
    wire c21_bus_req, c21_bus_mem_write, c21_bus_mem_unsigned, c21_bus_grant;
    wire [31:0] c21_bus_addr, c21_bus_write_data, c21_bus_read_data;
    wire [1:0] c21_bus_mem_size;
    wire c21_req_out_valid, c21_req_out_ready, c21_resp_in_valid, c21_resp_in_ready;
    wire [83:0] c21_req_out_flit;
    wire [39:0] c21_resp_in_flit;
    wire c22_bus_req, c22_bus_mem_write, c22_bus_mem_unsigned, c22_bus_grant;
    wire [31:0] c22_bus_addr, c22_bus_write_data, c22_bus_read_data;
    wire [1:0] c22_bus_mem_size;
    wire c22_req_out_valid, c22_req_out_ready, c22_resp_in_valid, c22_resp_in_ready;
    wire [83:0] c22_req_out_flit;
    wire [39:0] c22_resp_in_flit;
    wire c23_bus_req, c23_bus_mem_write, c23_bus_mem_unsigned, c23_bus_grant;
    wire [31:0] c23_bus_addr, c23_bus_write_data, c23_bus_read_data;
    wire [1:0] c23_bus_mem_size;
    wire c23_req_out_valid, c23_req_out_ready, c23_resp_in_valid, c23_resp_in_ready;
    wire [83:0] c23_req_out_flit;
    wire [39:0] c23_resp_in_flit;
    wire c24_bus_req, c24_bus_mem_write, c24_bus_mem_unsigned, c24_bus_grant;
    wire [31:0] c24_bus_addr, c24_bus_write_data, c24_bus_read_data;
    wire [1:0] c24_bus_mem_size;
    wire c24_req_out_valid, c24_req_out_ready, c24_resp_in_valid, c24_resp_in_ready;
    wire [83:0] c24_req_out_flit;
    wire [39:0] c24_resp_in_flit;
    wire c25_bus_req, c25_bus_mem_write, c25_bus_mem_unsigned, c25_bus_grant;
    wire [31:0] c25_bus_addr, c25_bus_write_data, c25_bus_read_data;
    wire [1:0] c25_bus_mem_size;
    wire c25_req_out_valid, c25_req_out_ready, c25_resp_in_valid, c25_resp_in_ready;
    wire [83:0] c25_req_out_flit;
    wire [39:0] c25_resp_in_flit;
    wire c26_bus_req, c26_bus_mem_write, c26_bus_mem_unsigned, c26_bus_grant;
    wire [31:0] c26_bus_addr, c26_bus_write_data, c26_bus_read_data;
    wire [1:0] c26_bus_mem_size;
    wire c26_req_out_valid, c26_req_out_ready, c26_resp_in_valid, c26_resp_in_ready;
    wire [83:0] c26_req_out_flit;
    wire [39:0] c26_resp_in_flit;
    wire c27_bus_req, c27_bus_mem_write, c27_bus_mem_unsigned, c27_bus_grant;
    wire [31:0] c27_bus_addr, c27_bus_write_data, c27_bus_read_data;
    wire [1:0] c27_bus_mem_size;
    wire c27_req_out_valid, c27_req_out_ready, c27_resp_in_valid, c27_resp_in_ready;
    wire [83:0] c27_req_out_flit;
    wire [39:0] c27_resp_in_flit;
    wire c28_bus_req, c28_bus_mem_write, c28_bus_mem_unsigned, c28_bus_grant;
    wire [31:0] c28_bus_addr, c28_bus_write_data, c28_bus_read_data;
    wire [1:0] c28_bus_mem_size;
    wire c28_req_out_valid, c28_req_out_ready, c28_resp_in_valid, c28_resp_in_ready;
    wire [83:0] c28_req_out_flit;
    wire [39:0] c28_resp_in_flit;
    wire c29_bus_req, c29_bus_mem_write, c29_bus_mem_unsigned, c29_bus_grant;
    wire [31:0] c29_bus_addr, c29_bus_write_data, c29_bus_read_data;
    wire [1:0] c29_bus_mem_size;
    wire c29_req_out_valid, c29_req_out_ready, c29_resp_in_valid, c29_resp_in_ready;
    wire [83:0] c29_req_out_flit;
    wire [39:0] c29_resp_in_flit;
    wire c30_bus_req, c30_bus_mem_write, c30_bus_mem_unsigned, c30_bus_grant;
    wire [31:0] c30_bus_addr, c30_bus_write_data, c30_bus_read_data;
    wire [1:0] c30_bus_mem_size;
    wire c30_req_out_valid, c30_req_out_ready, c30_resp_in_valid, c30_resp_in_ready;
    wire [83:0] c30_req_out_flit;
    wire [39:0] c30_resp_in_flit;
    wire c31_bus_req, c31_bus_mem_write, c31_bus_mem_unsigned, c31_bus_grant;
    wire [31:0] c31_bus_addr, c31_bus_write_data, c31_bus_read_data;
    wire [1:0] c31_bus_mem_size;
    wire c31_req_out_valid, c31_req_out_ready, c31_resp_in_valid, c31_resp_in_ready;
    wire [83:0] c31_req_out_flit;
    wire [39:0] c31_resp_in_flit;
    wire c32_bus_req, c32_bus_mem_write, c32_bus_mem_unsigned, c32_bus_grant;
    wire [31:0] c32_bus_addr, c32_bus_write_data, c32_bus_read_data;
    wire [1:0] c32_bus_mem_size;
    wire c32_req_out_valid, c32_req_out_ready, c32_resp_in_valid, c32_resp_in_ready;
    wire [83:0] c32_req_out_flit;
    wire [39:0] c32_resp_in_flit;
    wire c33_bus_req, c33_bus_mem_write, c33_bus_mem_unsigned, c33_bus_grant;
    wire [31:0] c33_bus_addr, c33_bus_write_data, c33_bus_read_data;
    wire [1:0] c33_bus_mem_size;
    wire c33_req_out_valid, c33_req_out_ready, c33_resp_in_valid, c33_resp_in_ready;
    wire [83:0] c33_req_out_flit;
    wire [39:0] c33_resp_in_flit;
    wire c34_bus_req, c34_bus_mem_write, c34_bus_mem_unsigned, c34_bus_grant;
    wire [31:0] c34_bus_addr, c34_bus_write_data, c34_bus_read_data;
    wire [1:0] c34_bus_mem_size;
    wire c34_req_out_valid, c34_req_out_ready, c34_resp_in_valid, c34_resp_in_ready;
    wire [83:0] c34_req_out_flit;
    wire [39:0] c34_resp_in_flit;
    wire c35_bus_req, c35_bus_mem_write, c35_bus_mem_unsigned, c35_bus_grant;
    wire [31:0] c35_bus_addr, c35_bus_write_data, c35_bus_read_data;
    wire [1:0] c35_bus_mem_size;
    wire c35_req_out_valid, c35_req_out_ready, c35_resp_in_valid, c35_resp_in_ready;
    wire [83:0] c35_req_out_flit;
    wire [39:0] c35_resp_in_flit;
    wire c36_bus_req, c36_bus_mem_write, c36_bus_mem_unsigned, c36_bus_grant;
    wire [31:0] c36_bus_addr, c36_bus_write_data, c36_bus_read_data;
    wire [1:0] c36_bus_mem_size;
    wire c36_req_out_valid, c36_req_out_ready, c36_resp_in_valid, c36_resp_in_ready;
    wire [83:0] c36_req_out_flit;
    wire [39:0] c36_resp_in_flit;
    wire c37_bus_req, c37_bus_mem_write, c37_bus_mem_unsigned, c37_bus_grant;
    wire [31:0] c37_bus_addr, c37_bus_write_data, c37_bus_read_data;
    wire [1:0] c37_bus_mem_size;
    wire c37_req_out_valid, c37_req_out_ready, c37_resp_in_valid, c37_resp_in_ready;
    wire [83:0] c37_req_out_flit;
    wire [39:0] c37_resp_in_flit;
    wire c38_bus_req, c38_bus_mem_write, c38_bus_mem_unsigned, c38_bus_grant;
    wire [31:0] c38_bus_addr, c38_bus_write_data, c38_bus_read_data;
    wire [1:0] c38_bus_mem_size;
    wire c38_req_out_valid, c38_req_out_ready, c38_resp_in_valid, c38_resp_in_ready;
    wire [83:0] c38_req_out_flit;
    wire [39:0] c38_resp_in_flit;
    wire c39_bus_req, c39_bus_mem_write, c39_bus_mem_unsigned, c39_bus_grant;
    wire [31:0] c39_bus_addr, c39_bus_write_data, c39_bus_read_data;
    wire [1:0] c39_bus_mem_size;
    wire c39_req_out_valid, c39_req_out_ready, c39_resp_in_valid, c39_resp_in_ready;
    wire [83:0] c39_req_out_flit;
    wire [39:0] c39_resp_in_flit;
    wire c40_bus_req, c40_bus_mem_write, c40_bus_mem_unsigned, c40_bus_grant;
    wire [31:0] c40_bus_addr, c40_bus_write_data, c40_bus_read_data;
    wire [1:0] c40_bus_mem_size;
    wire c40_req_out_valid, c40_req_out_ready, c40_resp_in_valid, c40_resp_in_ready;
    wire [83:0] c40_req_out_flit;
    wire [39:0] c40_resp_in_flit;
    wire c41_bus_req, c41_bus_mem_write, c41_bus_mem_unsigned, c41_bus_grant;
    wire [31:0] c41_bus_addr, c41_bus_write_data, c41_bus_read_data;
    wire [1:0] c41_bus_mem_size;
    wire c41_req_out_valid, c41_req_out_ready, c41_resp_in_valid, c41_resp_in_ready;
    wire [83:0] c41_req_out_flit;
    wire [39:0] c41_resp_in_flit;
    wire c42_bus_req, c42_bus_mem_write, c42_bus_mem_unsigned, c42_bus_grant;
    wire [31:0] c42_bus_addr, c42_bus_write_data, c42_bus_read_data;
    wire [1:0] c42_bus_mem_size;
    wire c42_req_out_valid, c42_req_out_ready, c42_resp_in_valid, c42_resp_in_ready;
    wire [83:0] c42_req_out_flit;
    wire [39:0] c42_resp_in_flit;
    wire c43_bus_req, c43_bus_mem_write, c43_bus_mem_unsigned, c43_bus_grant;
    wire [31:0] c43_bus_addr, c43_bus_write_data, c43_bus_read_data;
    wire [1:0] c43_bus_mem_size;
    wire c43_req_out_valid, c43_req_out_ready, c43_resp_in_valid, c43_resp_in_ready;
    wire [83:0] c43_req_out_flit;
    wire [39:0] c43_resp_in_flit;
    wire c44_bus_req, c44_bus_mem_write, c44_bus_mem_unsigned, c44_bus_grant;
    wire [31:0] c44_bus_addr, c44_bus_write_data, c44_bus_read_data;
    wire [1:0] c44_bus_mem_size;
    wire c44_req_out_valid, c44_req_out_ready, c44_resp_in_valid, c44_resp_in_ready;
    wire [83:0] c44_req_out_flit;
    wire [39:0] c44_resp_in_flit;
    wire c45_bus_req, c45_bus_mem_write, c45_bus_mem_unsigned, c45_bus_grant;
    wire [31:0] c45_bus_addr, c45_bus_write_data, c45_bus_read_data;
    wire [1:0] c45_bus_mem_size;
    wire c45_req_out_valid, c45_req_out_ready, c45_resp_in_valid, c45_resp_in_ready;
    wire [83:0] c45_req_out_flit;
    wire [39:0] c45_resp_in_flit;
    wire c46_bus_req, c46_bus_mem_write, c46_bus_mem_unsigned, c46_bus_grant;
    wire [31:0] c46_bus_addr, c46_bus_write_data, c46_bus_read_data;
    wire [1:0] c46_bus_mem_size;
    wire c46_req_out_valid, c46_req_out_ready, c46_resp_in_valid, c46_resp_in_ready;
    wire [83:0] c46_req_out_flit;
    wire [39:0] c46_resp_in_flit;
    wire mem_req_in_valid, mem_req_in_ready, mem_resp_out_valid, mem_resp_out_ready;
    wire [83:0] mem_req_in_flit;
    wire [39:0] mem_resp_out_flit;

    // ==================== Routers (2 networks x 48 grid positions) ====================
    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r0_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_1_0_0_W_v), .e_in_flit(req_1_0_0_W_f), .e_in_ready(req_1_0_0_W_r),
        .e_out_valid(req_0_0_0_E_v), .e_out_flit(req_0_0_0_E_f), .e_out_ready(req_0_0_0_E_r),
        .s_in_valid(req_0_1_0_N_v), .s_in_flit(req_0_1_0_N_f), .s_in_ready(req_0_1_0_N_r),
        .s_out_valid(req_0_0_0_S_v), .s_out_flit(req_0_0_0_S_f), .s_out_ready(req_0_0_0_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_0_1_U_v), .d_in_flit(req_0_0_1_U_f), .d_in_ready(req_0_0_1_U_r),
        .d_out_valid(req_0_0_0_D_v), .d_out_flit(req_0_0_0_D_f), .d_out_ready(req_0_0_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c0_req_out_valid), .l_in_flit(c0_req_out_flit), .l_in_ready(c0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r0_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_1_0_0_W_v), .e_in_flit(resp_1_0_0_W_f), .e_in_ready(resp_1_0_0_W_r),
        .e_out_valid(resp_0_0_0_E_v), .e_out_flit(resp_0_0_0_E_f), .e_out_ready(resp_0_0_0_E_r),
        .s_in_valid(resp_0_1_0_N_v), .s_in_flit(resp_0_1_0_N_f), .s_in_ready(resp_0_1_0_N_r),
        .s_out_valid(resp_0_0_0_S_v), .s_out_flit(resp_0_0_0_S_f), .s_out_ready(resp_0_0_0_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_0_1_U_v), .d_in_flit(resp_0_0_1_U_f), .d_in_ready(resp_0_0_1_U_r),
        .d_out_valid(resp_0_0_0_D_v), .d_out_flit(resp_0_0_0_D_f), .d_out_ready(resp_0_0_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c0_resp_in_valid), .l_out_flit(c0_resp_in_flit), .l_out_ready(c0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(1), .MY_W(0)) req_r0_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_1_0_1_W_v), .e_in_flit(req_1_0_1_W_f), .e_in_ready(req_1_0_1_W_r),
        .e_out_valid(req_0_0_1_E_v), .e_out_flit(req_0_0_1_E_f), .e_out_ready(req_0_0_1_E_r),
        .s_in_valid(req_0_1_1_N_v), .s_in_flit(req_0_1_1_N_f), .s_in_ready(req_0_1_1_N_r),
        .s_out_valid(req_0_0_1_S_v), .s_out_flit(req_0_0_1_S_f), .s_out_ready(req_0_0_1_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_0_D_v), .u_in_flit(req_0_0_0_D_f), .u_in_ready(req_0_0_0_D_r),
        .u_out_valid(req_0_0_1_U_v), .u_out_flit(req_0_0_1_U_f), .u_out_ready(req_0_0_1_U_r),
        .d_in_valid(req_0_0_2_U_v), .d_in_flit(req_0_0_2_U_f), .d_in_ready(req_0_0_2_U_r),
        .d_out_valid(req_0_0_1_D_v), .d_out_flit(req_0_0_1_D_f), .d_out_ready(req_0_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c1_req_out_valid), .l_in_flit(c1_req_out_flit), .l_in_ready(c1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(1), .MY_W(0)) resp_r0_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_1_0_1_W_v), .e_in_flit(resp_1_0_1_W_f), .e_in_ready(resp_1_0_1_W_r),
        .e_out_valid(resp_0_0_1_E_v), .e_out_flit(resp_0_0_1_E_f), .e_out_ready(resp_0_0_1_E_r),
        .s_in_valid(resp_0_1_1_N_v), .s_in_flit(resp_0_1_1_N_f), .s_in_ready(resp_0_1_1_N_r),
        .s_out_valid(resp_0_0_1_S_v), .s_out_flit(resp_0_0_1_S_f), .s_out_ready(resp_0_0_1_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_0_D_v), .u_in_flit(resp_0_0_0_D_f), .u_in_ready(resp_0_0_0_D_r),
        .u_out_valid(resp_0_0_1_U_v), .u_out_flit(resp_0_0_1_U_f), .u_out_ready(resp_0_0_1_U_r),
        .d_in_valid(resp_0_0_2_U_v), .d_in_flit(resp_0_0_2_U_f), .d_in_ready(resp_0_0_2_U_r),
        .d_out_valid(resp_0_0_1_D_v), .d_out_flit(resp_0_0_1_D_f), .d_out_ready(resp_0_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c1_resp_in_valid), .l_out_flit(c1_resp_in_flit), .l_out_ready(c1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(2), .MY_W(0)) req_r0_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_1_0_2_W_v), .e_in_flit(req_1_0_2_W_f), .e_in_ready(req_1_0_2_W_r),
        .e_out_valid(req_0_0_2_E_v), .e_out_flit(req_0_0_2_E_f), .e_out_ready(req_0_0_2_E_r),
        .s_in_valid(req_0_1_2_N_v), .s_in_flit(req_0_1_2_N_f), .s_in_ready(req_0_1_2_N_r),
        .s_out_valid(req_0_0_2_S_v), .s_out_flit(req_0_0_2_S_f), .s_out_ready(req_0_0_2_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_1_D_v), .u_in_flit(req_0_0_1_D_f), .u_in_ready(req_0_0_1_D_r),
        .u_out_valid(req_0_0_2_U_v), .u_out_flit(req_0_0_2_U_f), .u_out_ready(req_0_0_2_U_r),
        .d_in_valid(req_0_0_3_U_v), .d_in_flit(req_0_0_3_U_f), .d_in_ready(req_0_0_3_U_r),
        .d_out_valid(req_0_0_2_D_v), .d_out_flit(req_0_0_2_D_f), .d_out_ready(req_0_0_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c2_req_out_valid), .l_in_flit(c2_req_out_flit), .l_in_ready(c2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(2), .MY_W(0)) resp_r0_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_1_0_2_W_v), .e_in_flit(resp_1_0_2_W_f), .e_in_ready(resp_1_0_2_W_r),
        .e_out_valid(resp_0_0_2_E_v), .e_out_flit(resp_0_0_2_E_f), .e_out_ready(resp_0_0_2_E_r),
        .s_in_valid(resp_0_1_2_N_v), .s_in_flit(resp_0_1_2_N_f), .s_in_ready(resp_0_1_2_N_r),
        .s_out_valid(resp_0_0_2_S_v), .s_out_flit(resp_0_0_2_S_f), .s_out_ready(resp_0_0_2_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_1_D_v), .u_in_flit(resp_0_0_1_D_f), .u_in_ready(resp_0_0_1_D_r),
        .u_out_valid(resp_0_0_2_U_v), .u_out_flit(resp_0_0_2_U_f), .u_out_ready(resp_0_0_2_U_r),
        .d_in_valid(resp_0_0_3_U_v), .d_in_flit(resp_0_0_3_U_f), .d_in_ready(resp_0_0_3_U_r),
        .d_out_valid(resp_0_0_2_D_v), .d_out_flit(resp_0_0_2_D_f), .d_out_ready(resp_0_0_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c2_resp_in_valid), .l_out_flit(c2_resp_in_flit), .l_out_ready(c2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(3), .MY_W(0)) req_r0_0_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_1_0_3_W_v), .e_in_flit(req_1_0_3_W_f), .e_in_ready(req_1_0_3_W_r),
        .e_out_valid(req_0_0_3_E_v), .e_out_flit(req_0_0_3_E_f), .e_out_ready(req_0_0_3_E_r),
        .s_in_valid(req_0_1_3_N_v), .s_in_flit(req_0_1_3_N_f), .s_in_ready(req_0_1_3_N_r),
        .s_out_valid(req_0_0_3_S_v), .s_out_flit(req_0_0_3_S_f), .s_out_ready(req_0_0_3_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_0_2_D_v), .u_in_flit(req_0_0_2_D_f), .u_in_ready(req_0_0_2_D_r),
        .u_out_valid(req_0_0_3_U_v), .u_out_flit(req_0_0_3_U_f), .u_out_ready(req_0_0_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c3_req_out_valid), .l_in_flit(c3_req_out_flit), .l_in_ready(c3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(3), .MY_W(0)) resp_r0_0_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_1_0_3_W_v), .e_in_flit(resp_1_0_3_W_f), .e_in_ready(resp_1_0_3_W_r),
        .e_out_valid(resp_0_0_3_E_v), .e_out_flit(resp_0_0_3_E_f), .e_out_ready(resp_0_0_3_E_r),
        .s_in_valid(resp_0_1_3_N_v), .s_in_flit(resp_0_1_3_N_f), .s_in_ready(resp_0_1_3_N_r),
        .s_out_valid(resp_0_0_3_S_v), .s_out_flit(resp_0_0_3_S_f), .s_out_ready(resp_0_0_3_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_0_2_D_v), .u_in_flit(resp_0_0_2_D_f), .u_in_ready(resp_0_0_2_D_r),
        .u_out_valid(resp_0_0_3_U_v), .u_out_flit(resp_0_0_3_U_f), .u_out_ready(resp_0_0_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c3_resp_in_valid), .l_out_flit(c3_resp_in_flit), .l_out_ready(c3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(0)) req_r0_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_0_S_v), .n_in_flit(req_0_0_0_S_f), .n_in_ready(req_0_0_0_S_r),
        .n_out_valid(req_0_1_0_N_v), .n_out_flit(req_0_1_0_N_f), .n_out_ready(req_0_1_0_N_r),
        .e_in_valid(req_1_1_0_W_v), .e_in_flit(req_1_1_0_W_f), .e_in_ready(req_1_1_0_W_r),
        .e_out_valid(req_0_1_0_E_v), .e_out_flit(req_0_1_0_E_f), .e_out_ready(req_0_1_0_E_r),
        .s_in_valid(req_0_2_0_N_v), .s_in_flit(req_0_2_0_N_f), .s_in_ready(req_0_2_0_N_r),
        .s_out_valid(req_0_1_0_S_v), .s_out_flit(req_0_1_0_S_f), .s_out_ready(req_0_1_0_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_1_1_U_v), .d_in_flit(req_0_1_1_U_f), .d_in_ready(req_0_1_1_U_r),
        .d_out_valid(req_0_1_0_D_v), .d_out_flit(req_0_1_0_D_f), .d_out_ready(req_0_1_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c4_req_out_valid), .l_in_flit(c4_req_out_flit), .l_in_ready(c4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(0)) resp_r0_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_0_S_v), .n_in_flit(resp_0_0_0_S_f), .n_in_ready(resp_0_0_0_S_r),
        .n_out_valid(resp_0_1_0_N_v), .n_out_flit(resp_0_1_0_N_f), .n_out_ready(resp_0_1_0_N_r),
        .e_in_valid(resp_1_1_0_W_v), .e_in_flit(resp_1_1_0_W_f), .e_in_ready(resp_1_1_0_W_r),
        .e_out_valid(resp_0_1_0_E_v), .e_out_flit(resp_0_1_0_E_f), .e_out_ready(resp_0_1_0_E_r),
        .s_in_valid(resp_0_2_0_N_v), .s_in_flit(resp_0_2_0_N_f), .s_in_ready(resp_0_2_0_N_r),
        .s_out_valid(resp_0_1_0_S_v), .s_out_flit(resp_0_1_0_S_f), .s_out_ready(resp_0_1_0_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_1_1_U_v), .d_in_flit(resp_0_1_1_U_f), .d_in_ready(resp_0_1_1_U_r),
        .d_out_valid(resp_0_1_0_D_v), .d_out_flit(resp_0_1_0_D_f), .d_out_ready(resp_0_1_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c4_resp_in_valid), .l_out_flit(c4_resp_in_flit), .l_out_ready(c4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(1), .MY_W(0)) req_r0_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_1_S_v), .n_in_flit(req_0_0_1_S_f), .n_in_ready(req_0_0_1_S_r),
        .n_out_valid(req_0_1_1_N_v), .n_out_flit(req_0_1_1_N_f), .n_out_ready(req_0_1_1_N_r),
        .e_in_valid(req_1_1_1_W_v), .e_in_flit(req_1_1_1_W_f), .e_in_ready(req_1_1_1_W_r),
        .e_out_valid(req_0_1_1_E_v), .e_out_flit(req_0_1_1_E_f), .e_out_ready(req_0_1_1_E_r),
        .s_in_valid(req_0_2_1_N_v), .s_in_flit(req_0_2_1_N_f), .s_in_ready(req_0_2_1_N_r),
        .s_out_valid(req_0_1_1_S_v), .s_out_flit(req_0_1_1_S_f), .s_out_ready(req_0_1_1_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_0_D_v), .u_in_flit(req_0_1_0_D_f), .u_in_ready(req_0_1_0_D_r),
        .u_out_valid(req_0_1_1_U_v), .u_out_flit(req_0_1_1_U_f), .u_out_ready(req_0_1_1_U_r),
        .d_in_valid(req_0_1_2_U_v), .d_in_flit(req_0_1_2_U_f), .d_in_ready(req_0_1_2_U_r),
        .d_out_valid(req_0_1_1_D_v), .d_out_flit(req_0_1_1_D_f), .d_out_ready(req_0_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c5_req_out_valid), .l_in_flit(c5_req_out_flit), .l_in_ready(c5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(1), .MY_W(0)) resp_r0_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_1_S_v), .n_in_flit(resp_0_0_1_S_f), .n_in_ready(resp_0_0_1_S_r),
        .n_out_valid(resp_0_1_1_N_v), .n_out_flit(resp_0_1_1_N_f), .n_out_ready(resp_0_1_1_N_r),
        .e_in_valid(resp_1_1_1_W_v), .e_in_flit(resp_1_1_1_W_f), .e_in_ready(resp_1_1_1_W_r),
        .e_out_valid(resp_0_1_1_E_v), .e_out_flit(resp_0_1_1_E_f), .e_out_ready(resp_0_1_1_E_r),
        .s_in_valid(resp_0_2_1_N_v), .s_in_flit(resp_0_2_1_N_f), .s_in_ready(resp_0_2_1_N_r),
        .s_out_valid(resp_0_1_1_S_v), .s_out_flit(resp_0_1_1_S_f), .s_out_ready(resp_0_1_1_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_0_D_v), .u_in_flit(resp_0_1_0_D_f), .u_in_ready(resp_0_1_0_D_r),
        .u_out_valid(resp_0_1_1_U_v), .u_out_flit(resp_0_1_1_U_f), .u_out_ready(resp_0_1_1_U_r),
        .d_in_valid(resp_0_1_2_U_v), .d_in_flit(resp_0_1_2_U_f), .d_in_ready(resp_0_1_2_U_r),
        .d_out_valid(resp_0_1_1_D_v), .d_out_flit(resp_0_1_1_D_f), .d_out_ready(resp_0_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c5_resp_in_valid), .l_out_flit(c5_resp_in_flit), .l_out_ready(c5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(2), .MY_W(0)) req_r0_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_2_S_v), .n_in_flit(req_0_0_2_S_f), .n_in_ready(req_0_0_2_S_r),
        .n_out_valid(req_0_1_2_N_v), .n_out_flit(req_0_1_2_N_f), .n_out_ready(req_0_1_2_N_r),
        .e_in_valid(req_1_1_2_W_v), .e_in_flit(req_1_1_2_W_f), .e_in_ready(req_1_1_2_W_r),
        .e_out_valid(req_0_1_2_E_v), .e_out_flit(req_0_1_2_E_f), .e_out_ready(req_0_1_2_E_r),
        .s_in_valid(req_0_2_2_N_v), .s_in_flit(req_0_2_2_N_f), .s_in_ready(req_0_2_2_N_r),
        .s_out_valid(req_0_1_2_S_v), .s_out_flit(req_0_1_2_S_f), .s_out_ready(req_0_1_2_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_1_D_v), .u_in_flit(req_0_1_1_D_f), .u_in_ready(req_0_1_1_D_r),
        .u_out_valid(req_0_1_2_U_v), .u_out_flit(req_0_1_2_U_f), .u_out_ready(req_0_1_2_U_r),
        .d_in_valid(req_0_1_3_U_v), .d_in_flit(req_0_1_3_U_f), .d_in_ready(req_0_1_3_U_r),
        .d_out_valid(req_0_1_2_D_v), .d_out_flit(req_0_1_2_D_f), .d_out_ready(req_0_1_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c6_req_out_valid), .l_in_flit(c6_req_out_flit), .l_in_ready(c6_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(2), .MY_W(0)) resp_r0_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_2_S_v), .n_in_flit(resp_0_0_2_S_f), .n_in_ready(resp_0_0_2_S_r),
        .n_out_valid(resp_0_1_2_N_v), .n_out_flit(resp_0_1_2_N_f), .n_out_ready(resp_0_1_2_N_r),
        .e_in_valid(resp_1_1_2_W_v), .e_in_flit(resp_1_1_2_W_f), .e_in_ready(resp_1_1_2_W_r),
        .e_out_valid(resp_0_1_2_E_v), .e_out_flit(resp_0_1_2_E_f), .e_out_ready(resp_0_1_2_E_r),
        .s_in_valid(resp_0_2_2_N_v), .s_in_flit(resp_0_2_2_N_f), .s_in_ready(resp_0_2_2_N_r),
        .s_out_valid(resp_0_1_2_S_v), .s_out_flit(resp_0_1_2_S_f), .s_out_ready(resp_0_1_2_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_1_D_v), .u_in_flit(resp_0_1_1_D_f), .u_in_ready(resp_0_1_1_D_r),
        .u_out_valid(resp_0_1_2_U_v), .u_out_flit(resp_0_1_2_U_f), .u_out_ready(resp_0_1_2_U_r),
        .d_in_valid(resp_0_1_3_U_v), .d_in_flit(resp_0_1_3_U_f), .d_in_ready(resp_0_1_3_U_r),
        .d_out_valid(resp_0_1_2_D_v), .d_out_flit(resp_0_1_2_D_f), .d_out_ready(resp_0_1_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c6_resp_in_valid), .l_out_flit(c6_resp_in_flit), .l_out_ready(c6_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(3), .MY_W(0)) req_r0_1_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_3_S_v), .n_in_flit(req_0_0_3_S_f), .n_in_ready(req_0_0_3_S_r),
        .n_out_valid(req_0_1_3_N_v), .n_out_flit(req_0_1_3_N_f), .n_out_ready(req_0_1_3_N_r),
        .e_in_valid(req_1_1_3_W_v), .e_in_flit(req_1_1_3_W_f), .e_in_ready(req_1_1_3_W_r),
        .e_out_valid(req_0_1_3_E_v), .e_out_flit(req_0_1_3_E_f), .e_out_ready(req_0_1_3_E_r),
        .s_in_valid(req_0_2_3_N_v), .s_in_flit(req_0_2_3_N_f), .s_in_ready(req_0_2_3_N_r),
        .s_out_valid(req_0_1_3_S_v), .s_out_flit(req_0_1_3_S_f), .s_out_ready(req_0_1_3_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_1_2_D_v), .u_in_flit(req_0_1_2_D_f), .u_in_ready(req_0_1_2_D_r),
        .u_out_valid(req_0_1_3_U_v), .u_out_flit(req_0_1_3_U_f), .u_out_ready(req_0_1_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c7_req_out_valid), .l_in_flit(c7_req_out_flit), .l_in_ready(c7_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(3), .MY_W(0)) resp_r0_1_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_3_S_v), .n_in_flit(resp_0_0_3_S_f), .n_in_ready(resp_0_0_3_S_r),
        .n_out_valid(resp_0_1_3_N_v), .n_out_flit(resp_0_1_3_N_f), .n_out_ready(resp_0_1_3_N_r),
        .e_in_valid(resp_1_1_3_W_v), .e_in_flit(resp_1_1_3_W_f), .e_in_ready(resp_1_1_3_W_r),
        .e_out_valid(resp_0_1_3_E_v), .e_out_flit(resp_0_1_3_E_f), .e_out_ready(resp_0_1_3_E_r),
        .s_in_valid(resp_0_2_3_N_v), .s_in_flit(resp_0_2_3_N_f), .s_in_ready(resp_0_2_3_N_r),
        .s_out_valid(resp_0_1_3_S_v), .s_out_flit(resp_0_1_3_S_f), .s_out_ready(resp_0_1_3_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_1_2_D_v), .u_in_flit(resp_0_1_2_D_f), .u_in_ready(resp_0_1_2_D_r),
        .u_out_valid(resp_0_1_3_U_v), .u_out_flit(resp_0_1_3_U_f), .u_out_ready(resp_0_1_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c7_resp_in_valid), .l_out_flit(c7_resp_in_flit), .l_out_ready(c7_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(0)) req_r0_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_0_S_v), .n_in_flit(req_0_1_0_S_f), .n_in_ready(req_0_1_0_S_r),
        .n_out_valid(req_0_2_0_N_v), .n_out_flit(req_0_2_0_N_f), .n_out_ready(req_0_2_0_N_r),
        .e_in_valid(req_1_2_0_W_v), .e_in_flit(req_1_2_0_W_f), .e_in_ready(req_1_2_0_W_r),
        .e_out_valid(req_0_2_0_E_v), .e_out_flit(req_0_2_0_E_f), .e_out_ready(req_0_2_0_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_0_2_1_U_v), .d_in_flit(req_0_2_1_U_f), .d_in_ready(req_0_2_1_U_r),
        .d_out_valid(req_0_2_0_D_v), .d_out_flit(req_0_2_0_D_f), .d_out_ready(req_0_2_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c8_req_out_valid), .l_in_flit(c8_req_out_flit), .l_in_ready(c8_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(0)) resp_r0_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_0_S_v), .n_in_flit(resp_0_1_0_S_f), .n_in_ready(resp_0_1_0_S_r),
        .n_out_valid(resp_0_2_0_N_v), .n_out_flit(resp_0_2_0_N_f), .n_out_ready(resp_0_2_0_N_r),
        .e_in_valid(resp_1_2_0_W_v), .e_in_flit(resp_1_2_0_W_f), .e_in_ready(resp_1_2_0_W_r),
        .e_out_valid(resp_0_2_0_E_v), .e_out_flit(resp_0_2_0_E_f), .e_out_ready(resp_0_2_0_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_0_2_1_U_v), .d_in_flit(resp_0_2_1_U_f), .d_in_ready(resp_0_2_1_U_r),
        .d_out_valid(resp_0_2_0_D_v), .d_out_flit(resp_0_2_0_D_f), .d_out_ready(resp_0_2_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c8_resp_in_valid), .l_out_flit(c8_resp_in_flit), .l_out_ready(c8_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(1), .MY_W(0)) req_r0_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_1_S_v), .n_in_flit(req_0_1_1_S_f), .n_in_ready(req_0_1_1_S_r),
        .n_out_valid(req_0_2_1_N_v), .n_out_flit(req_0_2_1_N_f), .n_out_ready(req_0_2_1_N_r),
        .e_in_valid(req_1_2_1_W_v), .e_in_flit(req_1_2_1_W_f), .e_in_ready(req_1_2_1_W_r),
        .e_out_valid(req_0_2_1_E_v), .e_out_flit(req_0_2_1_E_f), .e_out_ready(req_0_2_1_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_0_D_v), .u_in_flit(req_0_2_0_D_f), .u_in_ready(req_0_2_0_D_r),
        .u_out_valid(req_0_2_1_U_v), .u_out_flit(req_0_2_1_U_f), .u_out_ready(req_0_2_1_U_r),
        .d_in_valid(req_0_2_2_U_v), .d_in_flit(req_0_2_2_U_f), .d_in_ready(req_0_2_2_U_r),
        .d_out_valid(req_0_2_1_D_v), .d_out_flit(req_0_2_1_D_f), .d_out_ready(req_0_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c9_req_out_valid), .l_in_flit(c9_req_out_flit), .l_in_ready(c9_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(1), .MY_W(0)) resp_r0_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_1_S_v), .n_in_flit(resp_0_1_1_S_f), .n_in_ready(resp_0_1_1_S_r),
        .n_out_valid(resp_0_2_1_N_v), .n_out_flit(resp_0_2_1_N_f), .n_out_ready(resp_0_2_1_N_r),
        .e_in_valid(resp_1_2_1_W_v), .e_in_flit(resp_1_2_1_W_f), .e_in_ready(resp_1_2_1_W_r),
        .e_out_valid(resp_0_2_1_E_v), .e_out_flit(resp_0_2_1_E_f), .e_out_ready(resp_0_2_1_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_0_D_v), .u_in_flit(resp_0_2_0_D_f), .u_in_ready(resp_0_2_0_D_r),
        .u_out_valid(resp_0_2_1_U_v), .u_out_flit(resp_0_2_1_U_f), .u_out_ready(resp_0_2_1_U_r),
        .d_in_valid(resp_0_2_2_U_v), .d_in_flit(resp_0_2_2_U_f), .d_in_ready(resp_0_2_2_U_r),
        .d_out_valid(resp_0_2_1_D_v), .d_out_flit(resp_0_2_1_D_f), .d_out_ready(resp_0_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c9_resp_in_valid), .l_out_flit(c9_resp_in_flit), .l_out_ready(c9_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(2), .MY_W(0)) req_r0_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_2_S_v), .n_in_flit(req_0_1_2_S_f), .n_in_ready(req_0_1_2_S_r),
        .n_out_valid(req_0_2_2_N_v), .n_out_flit(req_0_2_2_N_f), .n_out_ready(req_0_2_2_N_r),
        .e_in_valid(req_1_2_2_W_v), .e_in_flit(req_1_2_2_W_f), .e_in_ready(req_1_2_2_W_r),
        .e_out_valid(req_0_2_2_E_v), .e_out_flit(req_0_2_2_E_f), .e_out_ready(req_0_2_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_1_D_v), .u_in_flit(req_0_2_1_D_f), .u_in_ready(req_0_2_1_D_r),
        .u_out_valid(req_0_2_2_U_v), .u_out_flit(req_0_2_2_U_f), .u_out_ready(req_0_2_2_U_r),
        .d_in_valid(req_0_2_3_U_v), .d_in_flit(req_0_2_3_U_f), .d_in_ready(req_0_2_3_U_r),
        .d_out_valid(req_0_2_2_D_v), .d_out_flit(req_0_2_2_D_f), .d_out_ready(req_0_2_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c10_req_out_valid), .l_in_flit(c10_req_out_flit), .l_in_ready(c10_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(2), .MY_W(0)) resp_r0_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_2_S_v), .n_in_flit(resp_0_1_2_S_f), .n_in_ready(resp_0_1_2_S_r),
        .n_out_valid(resp_0_2_2_N_v), .n_out_flit(resp_0_2_2_N_f), .n_out_ready(resp_0_2_2_N_r),
        .e_in_valid(resp_1_2_2_W_v), .e_in_flit(resp_1_2_2_W_f), .e_in_ready(resp_1_2_2_W_r),
        .e_out_valid(resp_0_2_2_E_v), .e_out_flit(resp_0_2_2_E_f), .e_out_ready(resp_0_2_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_1_D_v), .u_in_flit(resp_0_2_1_D_f), .u_in_ready(resp_0_2_1_D_r),
        .u_out_valid(resp_0_2_2_U_v), .u_out_flit(resp_0_2_2_U_f), .u_out_ready(resp_0_2_2_U_r),
        .d_in_valid(resp_0_2_3_U_v), .d_in_flit(resp_0_2_3_U_f), .d_in_ready(resp_0_2_3_U_r),
        .d_out_valid(resp_0_2_2_D_v), .d_out_flit(resp_0_2_2_D_f), .d_out_ready(resp_0_2_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c10_resp_in_valid), .l_out_flit(c10_resp_in_flit), .l_out_ready(c10_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(3), .MY_W(0)) req_r0_2_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_3_S_v), .n_in_flit(req_0_1_3_S_f), .n_in_ready(req_0_1_3_S_r),
        .n_out_valid(req_0_2_3_N_v), .n_out_flit(req_0_2_3_N_f), .n_out_ready(req_0_2_3_N_r),
        .e_in_valid(req_1_2_3_W_v), .e_in_flit(req_1_2_3_W_f), .e_in_ready(req_1_2_3_W_r),
        .e_out_valid(req_0_2_3_E_v), .e_out_flit(req_0_2_3_E_f), .e_out_ready(req_0_2_3_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(req_0_2_2_D_v), .u_in_flit(req_0_2_2_D_f), .u_in_ready(req_0_2_2_D_r),
        .u_out_valid(req_0_2_3_U_v), .u_out_flit(req_0_2_3_U_f), .u_out_ready(req_0_2_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c11_req_out_valid), .l_in_flit(c11_req_out_flit), .l_in_ready(c11_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(3), .MY_W(0)) resp_r0_2_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_3_S_v), .n_in_flit(resp_0_1_3_S_f), .n_in_ready(resp_0_1_3_S_r),
        .n_out_valid(resp_0_2_3_N_v), .n_out_flit(resp_0_2_3_N_f), .n_out_ready(resp_0_2_3_N_r),
        .e_in_valid(resp_1_2_3_W_v), .e_in_flit(resp_1_2_3_W_f), .e_in_ready(resp_1_2_3_W_r),
        .e_out_valid(resp_0_2_3_E_v), .e_out_flit(resp_0_2_3_E_f), .e_out_ready(resp_0_2_3_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(resp_0_2_2_D_v), .u_in_flit(resp_0_2_2_D_f), .u_in_ready(resp_0_2_2_D_r),
        .u_out_valid(resp_0_2_3_U_v), .u_out_flit(resp_0_2_3_U_f), .u_out_ready(resp_0_2_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c11_resp_in_valid), .l_out_flit(c11_resp_in_flit), .l_out_ready(c11_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r1_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_2_0_0_W_v), .e_in_flit(req_2_0_0_W_f), .e_in_ready(req_2_0_0_W_r),
        .e_out_valid(req_1_0_0_E_v), .e_out_flit(req_1_0_0_E_f), .e_out_ready(req_1_0_0_E_r),
        .s_in_valid(req_1_1_0_N_v), .s_in_flit(req_1_1_0_N_f), .s_in_ready(req_1_1_0_N_r),
        .s_out_valid(req_1_0_0_S_v), .s_out_flit(req_1_0_0_S_f), .s_out_ready(req_1_0_0_S_r),
        .w_in_valid(req_0_0_0_E_v), .w_in_flit(req_0_0_0_E_f), .w_in_ready(req_0_0_0_E_r),
        .w_out_valid(req_1_0_0_W_v), .w_out_flit(req_1_0_0_W_f), .w_out_ready(req_1_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_0_1_U_v), .d_in_flit(req_1_0_1_U_f), .d_in_ready(req_1_0_1_U_r),
        .d_out_valid(req_1_0_0_D_v), .d_out_flit(req_1_0_0_D_f), .d_out_ready(req_1_0_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c12_req_out_valid), .l_in_flit(c12_req_out_flit), .l_in_ready(c12_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r1_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_2_0_0_W_v), .e_in_flit(resp_2_0_0_W_f), .e_in_ready(resp_2_0_0_W_r),
        .e_out_valid(resp_1_0_0_E_v), .e_out_flit(resp_1_0_0_E_f), .e_out_ready(resp_1_0_0_E_r),
        .s_in_valid(resp_1_1_0_N_v), .s_in_flit(resp_1_1_0_N_f), .s_in_ready(resp_1_1_0_N_r),
        .s_out_valid(resp_1_0_0_S_v), .s_out_flit(resp_1_0_0_S_f), .s_out_ready(resp_1_0_0_S_r),
        .w_in_valid(resp_0_0_0_E_v), .w_in_flit(resp_0_0_0_E_f), .w_in_ready(resp_0_0_0_E_r),
        .w_out_valid(resp_1_0_0_W_v), .w_out_flit(resp_1_0_0_W_f), .w_out_ready(resp_1_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_0_1_U_v), .d_in_flit(resp_1_0_1_U_f), .d_in_ready(resp_1_0_1_U_r),
        .d_out_valid(resp_1_0_0_D_v), .d_out_flit(resp_1_0_0_D_f), .d_out_ready(resp_1_0_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c12_resp_in_valid), .l_out_flit(c12_resp_in_flit), .l_out_ready(c12_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(1), .MY_W(0)) req_r1_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_2_0_1_W_v), .e_in_flit(req_2_0_1_W_f), .e_in_ready(req_2_0_1_W_r),
        .e_out_valid(req_1_0_1_E_v), .e_out_flit(req_1_0_1_E_f), .e_out_ready(req_1_0_1_E_r),
        .s_in_valid(req_1_1_1_N_v), .s_in_flit(req_1_1_1_N_f), .s_in_ready(req_1_1_1_N_r),
        .s_out_valid(req_1_0_1_S_v), .s_out_flit(req_1_0_1_S_f), .s_out_ready(req_1_0_1_S_r),
        .w_in_valid(req_0_0_1_E_v), .w_in_flit(req_0_0_1_E_f), .w_in_ready(req_0_0_1_E_r),
        .w_out_valid(req_1_0_1_W_v), .w_out_flit(req_1_0_1_W_f), .w_out_ready(req_1_0_1_W_r),
        .u_in_valid(req_1_0_0_D_v), .u_in_flit(req_1_0_0_D_f), .u_in_ready(req_1_0_0_D_r),
        .u_out_valid(req_1_0_1_U_v), .u_out_flit(req_1_0_1_U_f), .u_out_ready(req_1_0_1_U_r),
        .d_in_valid(req_1_0_2_U_v), .d_in_flit(req_1_0_2_U_f), .d_in_ready(req_1_0_2_U_r),
        .d_out_valid(req_1_0_1_D_v), .d_out_flit(req_1_0_1_D_f), .d_out_ready(req_1_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c13_req_out_valid), .l_in_flit(c13_req_out_flit), .l_in_ready(c13_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(1), .MY_W(0)) resp_r1_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_2_0_1_W_v), .e_in_flit(resp_2_0_1_W_f), .e_in_ready(resp_2_0_1_W_r),
        .e_out_valid(resp_1_0_1_E_v), .e_out_flit(resp_1_0_1_E_f), .e_out_ready(resp_1_0_1_E_r),
        .s_in_valid(resp_1_1_1_N_v), .s_in_flit(resp_1_1_1_N_f), .s_in_ready(resp_1_1_1_N_r),
        .s_out_valid(resp_1_0_1_S_v), .s_out_flit(resp_1_0_1_S_f), .s_out_ready(resp_1_0_1_S_r),
        .w_in_valid(resp_0_0_1_E_v), .w_in_flit(resp_0_0_1_E_f), .w_in_ready(resp_0_0_1_E_r),
        .w_out_valid(resp_1_0_1_W_v), .w_out_flit(resp_1_0_1_W_f), .w_out_ready(resp_1_0_1_W_r),
        .u_in_valid(resp_1_0_0_D_v), .u_in_flit(resp_1_0_0_D_f), .u_in_ready(resp_1_0_0_D_r),
        .u_out_valid(resp_1_0_1_U_v), .u_out_flit(resp_1_0_1_U_f), .u_out_ready(resp_1_0_1_U_r),
        .d_in_valid(resp_1_0_2_U_v), .d_in_flit(resp_1_0_2_U_f), .d_in_ready(resp_1_0_2_U_r),
        .d_out_valid(resp_1_0_1_D_v), .d_out_flit(resp_1_0_1_D_f), .d_out_ready(resp_1_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c13_resp_in_valid), .l_out_flit(c13_resp_in_flit), .l_out_ready(c13_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(2), .MY_W(0)) req_r1_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_2_0_2_W_v), .e_in_flit(req_2_0_2_W_f), .e_in_ready(req_2_0_2_W_r),
        .e_out_valid(req_1_0_2_E_v), .e_out_flit(req_1_0_2_E_f), .e_out_ready(req_1_0_2_E_r),
        .s_in_valid(req_1_1_2_N_v), .s_in_flit(req_1_1_2_N_f), .s_in_ready(req_1_1_2_N_r),
        .s_out_valid(req_1_0_2_S_v), .s_out_flit(req_1_0_2_S_f), .s_out_ready(req_1_0_2_S_r),
        .w_in_valid(req_0_0_2_E_v), .w_in_flit(req_0_0_2_E_f), .w_in_ready(req_0_0_2_E_r),
        .w_out_valid(req_1_0_2_W_v), .w_out_flit(req_1_0_2_W_f), .w_out_ready(req_1_0_2_W_r),
        .u_in_valid(req_1_0_1_D_v), .u_in_flit(req_1_0_1_D_f), .u_in_ready(req_1_0_1_D_r),
        .u_out_valid(req_1_0_2_U_v), .u_out_flit(req_1_0_2_U_f), .u_out_ready(req_1_0_2_U_r),
        .d_in_valid(req_1_0_3_U_v), .d_in_flit(req_1_0_3_U_f), .d_in_ready(req_1_0_3_U_r),
        .d_out_valid(req_1_0_2_D_v), .d_out_flit(req_1_0_2_D_f), .d_out_ready(req_1_0_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c14_req_out_valid), .l_in_flit(c14_req_out_flit), .l_in_ready(c14_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(2), .MY_W(0)) resp_r1_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_2_0_2_W_v), .e_in_flit(resp_2_0_2_W_f), .e_in_ready(resp_2_0_2_W_r),
        .e_out_valid(resp_1_0_2_E_v), .e_out_flit(resp_1_0_2_E_f), .e_out_ready(resp_1_0_2_E_r),
        .s_in_valid(resp_1_1_2_N_v), .s_in_flit(resp_1_1_2_N_f), .s_in_ready(resp_1_1_2_N_r),
        .s_out_valid(resp_1_0_2_S_v), .s_out_flit(resp_1_0_2_S_f), .s_out_ready(resp_1_0_2_S_r),
        .w_in_valid(resp_0_0_2_E_v), .w_in_flit(resp_0_0_2_E_f), .w_in_ready(resp_0_0_2_E_r),
        .w_out_valid(resp_1_0_2_W_v), .w_out_flit(resp_1_0_2_W_f), .w_out_ready(resp_1_0_2_W_r),
        .u_in_valid(resp_1_0_1_D_v), .u_in_flit(resp_1_0_1_D_f), .u_in_ready(resp_1_0_1_D_r),
        .u_out_valid(resp_1_0_2_U_v), .u_out_flit(resp_1_0_2_U_f), .u_out_ready(resp_1_0_2_U_r),
        .d_in_valid(resp_1_0_3_U_v), .d_in_flit(resp_1_0_3_U_f), .d_in_ready(resp_1_0_3_U_r),
        .d_out_valid(resp_1_0_2_D_v), .d_out_flit(resp_1_0_2_D_f), .d_out_ready(resp_1_0_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c14_resp_in_valid), .l_out_flit(c14_resp_in_flit), .l_out_ready(c14_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(3), .MY_W(0)) req_r1_0_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_2_0_3_W_v), .e_in_flit(req_2_0_3_W_f), .e_in_ready(req_2_0_3_W_r),
        .e_out_valid(req_1_0_3_E_v), .e_out_flit(req_1_0_3_E_f), .e_out_ready(req_1_0_3_E_r),
        .s_in_valid(req_1_1_3_N_v), .s_in_flit(req_1_1_3_N_f), .s_in_ready(req_1_1_3_N_r),
        .s_out_valid(req_1_0_3_S_v), .s_out_flit(req_1_0_3_S_f), .s_out_ready(req_1_0_3_S_r),
        .w_in_valid(req_0_0_3_E_v), .w_in_flit(req_0_0_3_E_f), .w_in_ready(req_0_0_3_E_r),
        .w_out_valid(req_1_0_3_W_v), .w_out_flit(req_1_0_3_W_f), .w_out_ready(req_1_0_3_W_r),
        .u_in_valid(req_1_0_2_D_v), .u_in_flit(req_1_0_2_D_f), .u_in_ready(req_1_0_2_D_r),
        .u_out_valid(req_1_0_3_U_v), .u_out_flit(req_1_0_3_U_f), .u_out_ready(req_1_0_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c15_req_out_valid), .l_in_flit(c15_req_out_flit), .l_in_ready(c15_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(3), .MY_W(0)) resp_r1_0_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_2_0_3_W_v), .e_in_flit(resp_2_0_3_W_f), .e_in_ready(resp_2_0_3_W_r),
        .e_out_valid(resp_1_0_3_E_v), .e_out_flit(resp_1_0_3_E_f), .e_out_ready(resp_1_0_3_E_r),
        .s_in_valid(resp_1_1_3_N_v), .s_in_flit(resp_1_1_3_N_f), .s_in_ready(resp_1_1_3_N_r),
        .s_out_valid(resp_1_0_3_S_v), .s_out_flit(resp_1_0_3_S_f), .s_out_ready(resp_1_0_3_S_r),
        .w_in_valid(resp_0_0_3_E_v), .w_in_flit(resp_0_0_3_E_f), .w_in_ready(resp_0_0_3_E_r),
        .w_out_valid(resp_1_0_3_W_v), .w_out_flit(resp_1_0_3_W_f), .w_out_ready(resp_1_0_3_W_r),
        .u_in_valid(resp_1_0_2_D_v), .u_in_flit(resp_1_0_2_D_f), .u_in_ready(resp_1_0_2_D_r),
        .u_out_valid(resp_1_0_3_U_v), .u_out_flit(resp_1_0_3_U_f), .u_out_ready(resp_1_0_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c15_resp_in_valid), .l_out_flit(c15_resp_in_flit), .l_out_ready(c15_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(0)) req_r1_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_0_S_v), .n_in_flit(req_1_0_0_S_f), .n_in_ready(req_1_0_0_S_r),
        .n_out_valid(req_1_1_0_N_v), .n_out_flit(req_1_1_0_N_f), .n_out_ready(req_1_1_0_N_r),
        .e_in_valid(req_2_1_0_W_v), .e_in_flit(req_2_1_0_W_f), .e_in_ready(req_2_1_0_W_r),
        .e_out_valid(req_1_1_0_E_v), .e_out_flit(req_1_1_0_E_f), .e_out_ready(req_1_1_0_E_r),
        .s_in_valid(req_1_2_0_N_v), .s_in_flit(req_1_2_0_N_f), .s_in_ready(req_1_2_0_N_r),
        .s_out_valid(req_1_1_0_S_v), .s_out_flit(req_1_1_0_S_f), .s_out_ready(req_1_1_0_S_r),
        .w_in_valid(req_0_1_0_E_v), .w_in_flit(req_0_1_0_E_f), .w_in_ready(req_0_1_0_E_r),
        .w_out_valid(req_1_1_0_W_v), .w_out_flit(req_1_1_0_W_f), .w_out_ready(req_1_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_1_1_U_v), .d_in_flit(req_1_1_1_U_f), .d_in_ready(req_1_1_1_U_r),
        .d_out_valid(req_1_1_0_D_v), .d_out_flit(req_1_1_0_D_f), .d_out_ready(req_1_1_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c16_req_out_valid), .l_in_flit(c16_req_out_flit), .l_in_ready(c16_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(0)) resp_r1_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_0_S_v), .n_in_flit(resp_1_0_0_S_f), .n_in_ready(resp_1_0_0_S_r),
        .n_out_valid(resp_1_1_0_N_v), .n_out_flit(resp_1_1_0_N_f), .n_out_ready(resp_1_1_0_N_r),
        .e_in_valid(resp_2_1_0_W_v), .e_in_flit(resp_2_1_0_W_f), .e_in_ready(resp_2_1_0_W_r),
        .e_out_valid(resp_1_1_0_E_v), .e_out_flit(resp_1_1_0_E_f), .e_out_ready(resp_1_1_0_E_r),
        .s_in_valid(resp_1_2_0_N_v), .s_in_flit(resp_1_2_0_N_f), .s_in_ready(resp_1_2_0_N_r),
        .s_out_valid(resp_1_1_0_S_v), .s_out_flit(resp_1_1_0_S_f), .s_out_ready(resp_1_1_0_S_r),
        .w_in_valid(resp_0_1_0_E_v), .w_in_flit(resp_0_1_0_E_f), .w_in_ready(resp_0_1_0_E_r),
        .w_out_valid(resp_1_1_0_W_v), .w_out_flit(resp_1_1_0_W_f), .w_out_ready(resp_1_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_1_1_U_v), .d_in_flit(resp_1_1_1_U_f), .d_in_ready(resp_1_1_1_U_r),
        .d_out_valid(resp_1_1_0_D_v), .d_out_flit(resp_1_1_0_D_f), .d_out_ready(resp_1_1_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c16_resp_in_valid), .l_out_flit(c16_resp_in_flit), .l_out_ready(c16_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(1), .MY_W(0)) req_r1_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_1_S_v), .n_in_flit(req_1_0_1_S_f), .n_in_ready(req_1_0_1_S_r),
        .n_out_valid(req_1_1_1_N_v), .n_out_flit(req_1_1_1_N_f), .n_out_ready(req_1_1_1_N_r),
        .e_in_valid(req_2_1_1_W_v), .e_in_flit(req_2_1_1_W_f), .e_in_ready(req_2_1_1_W_r),
        .e_out_valid(req_1_1_1_E_v), .e_out_flit(req_1_1_1_E_f), .e_out_ready(req_1_1_1_E_r),
        .s_in_valid(req_1_2_1_N_v), .s_in_flit(req_1_2_1_N_f), .s_in_ready(req_1_2_1_N_r),
        .s_out_valid(req_1_1_1_S_v), .s_out_flit(req_1_1_1_S_f), .s_out_ready(req_1_1_1_S_r),
        .w_in_valid(req_0_1_1_E_v), .w_in_flit(req_0_1_1_E_f), .w_in_ready(req_0_1_1_E_r),
        .w_out_valid(req_1_1_1_W_v), .w_out_flit(req_1_1_1_W_f), .w_out_ready(req_1_1_1_W_r),
        .u_in_valid(req_1_1_0_D_v), .u_in_flit(req_1_1_0_D_f), .u_in_ready(req_1_1_0_D_r),
        .u_out_valid(req_1_1_1_U_v), .u_out_flit(req_1_1_1_U_f), .u_out_ready(req_1_1_1_U_r),
        .d_in_valid(req_1_1_2_U_v), .d_in_flit(req_1_1_2_U_f), .d_in_ready(req_1_1_2_U_r),
        .d_out_valid(req_1_1_1_D_v), .d_out_flit(req_1_1_1_D_f), .d_out_ready(req_1_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({84{1'b0}}), .l_in_ready(),
        .l_out_valid(mem_req_in_valid), .l_out_flit(mem_req_in_flit), .l_out_ready(mem_req_in_ready)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(1), .MY_W(0)) resp_r1_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_1_S_v), .n_in_flit(resp_1_0_1_S_f), .n_in_ready(resp_1_0_1_S_r),
        .n_out_valid(resp_1_1_1_N_v), .n_out_flit(resp_1_1_1_N_f), .n_out_ready(resp_1_1_1_N_r),
        .e_in_valid(resp_2_1_1_W_v), .e_in_flit(resp_2_1_1_W_f), .e_in_ready(resp_2_1_1_W_r),
        .e_out_valid(resp_1_1_1_E_v), .e_out_flit(resp_1_1_1_E_f), .e_out_ready(resp_1_1_1_E_r),
        .s_in_valid(resp_1_2_1_N_v), .s_in_flit(resp_1_2_1_N_f), .s_in_ready(resp_1_2_1_N_r),
        .s_out_valid(resp_1_1_1_S_v), .s_out_flit(resp_1_1_1_S_f), .s_out_ready(resp_1_1_1_S_r),
        .w_in_valid(resp_0_1_1_E_v), .w_in_flit(resp_0_1_1_E_f), .w_in_ready(resp_0_1_1_E_r),
        .w_out_valid(resp_1_1_1_W_v), .w_out_flit(resp_1_1_1_W_f), .w_out_ready(resp_1_1_1_W_r),
        .u_in_valid(resp_1_1_0_D_v), .u_in_flit(resp_1_1_0_D_f), .u_in_ready(resp_1_1_0_D_r),
        .u_out_valid(resp_1_1_1_U_v), .u_out_flit(resp_1_1_1_U_f), .u_out_ready(resp_1_1_1_U_r),
        .d_in_valid(resp_1_1_2_U_v), .d_in_flit(resp_1_1_2_U_f), .d_in_ready(resp_1_1_2_U_r),
        .d_out_valid(resp_1_1_1_D_v), .d_out_flit(resp_1_1_1_D_f), .d_out_ready(resp_1_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(mem_resp_out_valid), .l_in_flit(mem_resp_out_flit), .l_in_ready(mem_resp_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(2), .MY_W(0)) req_r1_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_2_S_v), .n_in_flit(req_1_0_2_S_f), .n_in_ready(req_1_0_2_S_r),
        .n_out_valid(req_1_1_2_N_v), .n_out_flit(req_1_1_2_N_f), .n_out_ready(req_1_1_2_N_r),
        .e_in_valid(req_2_1_2_W_v), .e_in_flit(req_2_1_2_W_f), .e_in_ready(req_2_1_2_W_r),
        .e_out_valid(req_1_1_2_E_v), .e_out_flit(req_1_1_2_E_f), .e_out_ready(req_1_1_2_E_r),
        .s_in_valid(req_1_2_2_N_v), .s_in_flit(req_1_2_2_N_f), .s_in_ready(req_1_2_2_N_r),
        .s_out_valid(req_1_1_2_S_v), .s_out_flit(req_1_1_2_S_f), .s_out_ready(req_1_1_2_S_r),
        .w_in_valid(req_0_1_2_E_v), .w_in_flit(req_0_1_2_E_f), .w_in_ready(req_0_1_2_E_r),
        .w_out_valid(req_1_1_2_W_v), .w_out_flit(req_1_1_2_W_f), .w_out_ready(req_1_1_2_W_r),
        .u_in_valid(req_1_1_1_D_v), .u_in_flit(req_1_1_1_D_f), .u_in_ready(req_1_1_1_D_r),
        .u_out_valid(req_1_1_2_U_v), .u_out_flit(req_1_1_2_U_f), .u_out_ready(req_1_1_2_U_r),
        .d_in_valid(req_1_1_3_U_v), .d_in_flit(req_1_1_3_U_f), .d_in_ready(req_1_1_3_U_r),
        .d_out_valid(req_1_1_2_D_v), .d_out_flit(req_1_1_2_D_f), .d_out_ready(req_1_1_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c17_req_out_valid), .l_in_flit(c17_req_out_flit), .l_in_ready(c17_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(2), .MY_W(0)) resp_r1_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_2_S_v), .n_in_flit(resp_1_0_2_S_f), .n_in_ready(resp_1_0_2_S_r),
        .n_out_valid(resp_1_1_2_N_v), .n_out_flit(resp_1_1_2_N_f), .n_out_ready(resp_1_1_2_N_r),
        .e_in_valid(resp_2_1_2_W_v), .e_in_flit(resp_2_1_2_W_f), .e_in_ready(resp_2_1_2_W_r),
        .e_out_valid(resp_1_1_2_E_v), .e_out_flit(resp_1_1_2_E_f), .e_out_ready(resp_1_1_2_E_r),
        .s_in_valid(resp_1_2_2_N_v), .s_in_flit(resp_1_2_2_N_f), .s_in_ready(resp_1_2_2_N_r),
        .s_out_valid(resp_1_1_2_S_v), .s_out_flit(resp_1_1_2_S_f), .s_out_ready(resp_1_1_2_S_r),
        .w_in_valid(resp_0_1_2_E_v), .w_in_flit(resp_0_1_2_E_f), .w_in_ready(resp_0_1_2_E_r),
        .w_out_valid(resp_1_1_2_W_v), .w_out_flit(resp_1_1_2_W_f), .w_out_ready(resp_1_1_2_W_r),
        .u_in_valid(resp_1_1_1_D_v), .u_in_flit(resp_1_1_1_D_f), .u_in_ready(resp_1_1_1_D_r),
        .u_out_valid(resp_1_1_2_U_v), .u_out_flit(resp_1_1_2_U_f), .u_out_ready(resp_1_1_2_U_r),
        .d_in_valid(resp_1_1_3_U_v), .d_in_flit(resp_1_1_3_U_f), .d_in_ready(resp_1_1_3_U_r),
        .d_out_valid(resp_1_1_2_D_v), .d_out_flit(resp_1_1_2_D_f), .d_out_ready(resp_1_1_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c17_resp_in_valid), .l_out_flit(c17_resp_in_flit), .l_out_ready(c17_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(3), .MY_W(0)) req_r1_1_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_3_S_v), .n_in_flit(req_1_0_3_S_f), .n_in_ready(req_1_0_3_S_r),
        .n_out_valid(req_1_1_3_N_v), .n_out_flit(req_1_1_3_N_f), .n_out_ready(req_1_1_3_N_r),
        .e_in_valid(req_2_1_3_W_v), .e_in_flit(req_2_1_3_W_f), .e_in_ready(req_2_1_3_W_r),
        .e_out_valid(req_1_1_3_E_v), .e_out_flit(req_1_1_3_E_f), .e_out_ready(req_1_1_3_E_r),
        .s_in_valid(req_1_2_3_N_v), .s_in_flit(req_1_2_3_N_f), .s_in_ready(req_1_2_3_N_r),
        .s_out_valid(req_1_1_3_S_v), .s_out_flit(req_1_1_3_S_f), .s_out_ready(req_1_1_3_S_r),
        .w_in_valid(req_0_1_3_E_v), .w_in_flit(req_0_1_3_E_f), .w_in_ready(req_0_1_3_E_r),
        .w_out_valid(req_1_1_3_W_v), .w_out_flit(req_1_1_3_W_f), .w_out_ready(req_1_1_3_W_r),
        .u_in_valid(req_1_1_2_D_v), .u_in_flit(req_1_1_2_D_f), .u_in_ready(req_1_1_2_D_r),
        .u_out_valid(req_1_1_3_U_v), .u_out_flit(req_1_1_3_U_f), .u_out_ready(req_1_1_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c18_req_out_valid), .l_in_flit(c18_req_out_flit), .l_in_ready(c18_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(3), .MY_W(0)) resp_r1_1_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_3_S_v), .n_in_flit(resp_1_0_3_S_f), .n_in_ready(resp_1_0_3_S_r),
        .n_out_valid(resp_1_1_3_N_v), .n_out_flit(resp_1_1_3_N_f), .n_out_ready(resp_1_1_3_N_r),
        .e_in_valid(resp_2_1_3_W_v), .e_in_flit(resp_2_1_3_W_f), .e_in_ready(resp_2_1_3_W_r),
        .e_out_valid(resp_1_1_3_E_v), .e_out_flit(resp_1_1_3_E_f), .e_out_ready(resp_1_1_3_E_r),
        .s_in_valid(resp_1_2_3_N_v), .s_in_flit(resp_1_2_3_N_f), .s_in_ready(resp_1_2_3_N_r),
        .s_out_valid(resp_1_1_3_S_v), .s_out_flit(resp_1_1_3_S_f), .s_out_ready(resp_1_1_3_S_r),
        .w_in_valid(resp_0_1_3_E_v), .w_in_flit(resp_0_1_3_E_f), .w_in_ready(resp_0_1_3_E_r),
        .w_out_valid(resp_1_1_3_W_v), .w_out_flit(resp_1_1_3_W_f), .w_out_ready(resp_1_1_3_W_r),
        .u_in_valid(resp_1_1_2_D_v), .u_in_flit(resp_1_1_2_D_f), .u_in_ready(resp_1_1_2_D_r),
        .u_out_valid(resp_1_1_3_U_v), .u_out_flit(resp_1_1_3_U_f), .u_out_ready(resp_1_1_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c18_resp_in_valid), .l_out_flit(c18_resp_in_flit), .l_out_ready(c18_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(0)) req_r1_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_0_S_v), .n_in_flit(req_1_1_0_S_f), .n_in_ready(req_1_1_0_S_r),
        .n_out_valid(req_1_2_0_N_v), .n_out_flit(req_1_2_0_N_f), .n_out_ready(req_1_2_0_N_r),
        .e_in_valid(req_2_2_0_W_v), .e_in_flit(req_2_2_0_W_f), .e_in_ready(req_2_2_0_W_r),
        .e_out_valid(req_1_2_0_E_v), .e_out_flit(req_1_2_0_E_f), .e_out_ready(req_1_2_0_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_0_2_0_E_v), .w_in_flit(req_0_2_0_E_f), .w_in_ready(req_0_2_0_E_r),
        .w_out_valid(req_1_2_0_W_v), .w_out_flit(req_1_2_0_W_f), .w_out_ready(req_1_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_1_2_1_U_v), .d_in_flit(req_1_2_1_U_f), .d_in_ready(req_1_2_1_U_r),
        .d_out_valid(req_1_2_0_D_v), .d_out_flit(req_1_2_0_D_f), .d_out_ready(req_1_2_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c19_req_out_valid), .l_in_flit(c19_req_out_flit), .l_in_ready(c19_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(0)) resp_r1_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_0_S_v), .n_in_flit(resp_1_1_0_S_f), .n_in_ready(resp_1_1_0_S_r),
        .n_out_valid(resp_1_2_0_N_v), .n_out_flit(resp_1_2_0_N_f), .n_out_ready(resp_1_2_0_N_r),
        .e_in_valid(resp_2_2_0_W_v), .e_in_flit(resp_2_2_0_W_f), .e_in_ready(resp_2_2_0_W_r),
        .e_out_valid(resp_1_2_0_E_v), .e_out_flit(resp_1_2_0_E_f), .e_out_ready(resp_1_2_0_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_0_2_0_E_v), .w_in_flit(resp_0_2_0_E_f), .w_in_ready(resp_0_2_0_E_r),
        .w_out_valid(resp_1_2_0_W_v), .w_out_flit(resp_1_2_0_W_f), .w_out_ready(resp_1_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_1_2_1_U_v), .d_in_flit(resp_1_2_1_U_f), .d_in_ready(resp_1_2_1_U_r),
        .d_out_valid(resp_1_2_0_D_v), .d_out_flit(resp_1_2_0_D_f), .d_out_ready(resp_1_2_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c19_resp_in_valid), .l_out_flit(c19_resp_in_flit), .l_out_ready(c19_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(1), .MY_W(0)) req_r1_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_1_S_v), .n_in_flit(req_1_1_1_S_f), .n_in_ready(req_1_1_1_S_r),
        .n_out_valid(req_1_2_1_N_v), .n_out_flit(req_1_2_1_N_f), .n_out_ready(req_1_2_1_N_r),
        .e_in_valid(req_2_2_1_W_v), .e_in_flit(req_2_2_1_W_f), .e_in_ready(req_2_2_1_W_r),
        .e_out_valid(req_1_2_1_E_v), .e_out_flit(req_1_2_1_E_f), .e_out_ready(req_1_2_1_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_0_2_1_E_v), .w_in_flit(req_0_2_1_E_f), .w_in_ready(req_0_2_1_E_r),
        .w_out_valid(req_1_2_1_W_v), .w_out_flit(req_1_2_1_W_f), .w_out_ready(req_1_2_1_W_r),
        .u_in_valid(req_1_2_0_D_v), .u_in_flit(req_1_2_0_D_f), .u_in_ready(req_1_2_0_D_r),
        .u_out_valid(req_1_2_1_U_v), .u_out_flit(req_1_2_1_U_f), .u_out_ready(req_1_2_1_U_r),
        .d_in_valid(req_1_2_2_U_v), .d_in_flit(req_1_2_2_U_f), .d_in_ready(req_1_2_2_U_r),
        .d_out_valid(req_1_2_1_D_v), .d_out_flit(req_1_2_1_D_f), .d_out_ready(req_1_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c20_req_out_valid), .l_in_flit(c20_req_out_flit), .l_in_ready(c20_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(1), .MY_W(0)) resp_r1_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_1_S_v), .n_in_flit(resp_1_1_1_S_f), .n_in_ready(resp_1_1_1_S_r),
        .n_out_valid(resp_1_2_1_N_v), .n_out_flit(resp_1_2_1_N_f), .n_out_ready(resp_1_2_1_N_r),
        .e_in_valid(resp_2_2_1_W_v), .e_in_flit(resp_2_2_1_W_f), .e_in_ready(resp_2_2_1_W_r),
        .e_out_valid(resp_1_2_1_E_v), .e_out_flit(resp_1_2_1_E_f), .e_out_ready(resp_1_2_1_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_0_2_1_E_v), .w_in_flit(resp_0_2_1_E_f), .w_in_ready(resp_0_2_1_E_r),
        .w_out_valid(resp_1_2_1_W_v), .w_out_flit(resp_1_2_1_W_f), .w_out_ready(resp_1_2_1_W_r),
        .u_in_valid(resp_1_2_0_D_v), .u_in_flit(resp_1_2_0_D_f), .u_in_ready(resp_1_2_0_D_r),
        .u_out_valid(resp_1_2_1_U_v), .u_out_flit(resp_1_2_1_U_f), .u_out_ready(resp_1_2_1_U_r),
        .d_in_valid(resp_1_2_2_U_v), .d_in_flit(resp_1_2_2_U_f), .d_in_ready(resp_1_2_2_U_r),
        .d_out_valid(resp_1_2_1_D_v), .d_out_flit(resp_1_2_1_D_f), .d_out_ready(resp_1_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c20_resp_in_valid), .l_out_flit(c20_resp_in_flit), .l_out_ready(c20_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(2), .MY_W(0)) req_r1_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_2_S_v), .n_in_flit(req_1_1_2_S_f), .n_in_ready(req_1_1_2_S_r),
        .n_out_valid(req_1_2_2_N_v), .n_out_flit(req_1_2_2_N_f), .n_out_ready(req_1_2_2_N_r),
        .e_in_valid(req_2_2_2_W_v), .e_in_flit(req_2_2_2_W_f), .e_in_ready(req_2_2_2_W_r),
        .e_out_valid(req_1_2_2_E_v), .e_out_flit(req_1_2_2_E_f), .e_out_ready(req_1_2_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_0_2_2_E_v), .w_in_flit(req_0_2_2_E_f), .w_in_ready(req_0_2_2_E_r),
        .w_out_valid(req_1_2_2_W_v), .w_out_flit(req_1_2_2_W_f), .w_out_ready(req_1_2_2_W_r),
        .u_in_valid(req_1_2_1_D_v), .u_in_flit(req_1_2_1_D_f), .u_in_ready(req_1_2_1_D_r),
        .u_out_valid(req_1_2_2_U_v), .u_out_flit(req_1_2_2_U_f), .u_out_ready(req_1_2_2_U_r),
        .d_in_valid(req_1_2_3_U_v), .d_in_flit(req_1_2_3_U_f), .d_in_ready(req_1_2_3_U_r),
        .d_out_valid(req_1_2_2_D_v), .d_out_flit(req_1_2_2_D_f), .d_out_ready(req_1_2_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c21_req_out_valid), .l_in_flit(c21_req_out_flit), .l_in_ready(c21_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(2), .MY_W(0)) resp_r1_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_2_S_v), .n_in_flit(resp_1_1_2_S_f), .n_in_ready(resp_1_1_2_S_r),
        .n_out_valid(resp_1_2_2_N_v), .n_out_flit(resp_1_2_2_N_f), .n_out_ready(resp_1_2_2_N_r),
        .e_in_valid(resp_2_2_2_W_v), .e_in_flit(resp_2_2_2_W_f), .e_in_ready(resp_2_2_2_W_r),
        .e_out_valid(resp_1_2_2_E_v), .e_out_flit(resp_1_2_2_E_f), .e_out_ready(resp_1_2_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_0_2_2_E_v), .w_in_flit(resp_0_2_2_E_f), .w_in_ready(resp_0_2_2_E_r),
        .w_out_valid(resp_1_2_2_W_v), .w_out_flit(resp_1_2_2_W_f), .w_out_ready(resp_1_2_2_W_r),
        .u_in_valid(resp_1_2_1_D_v), .u_in_flit(resp_1_2_1_D_f), .u_in_ready(resp_1_2_1_D_r),
        .u_out_valid(resp_1_2_2_U_v), .u_out_flit(resp_1_2_2_U_f), .u_out_ready(resp_1_2_2_U_r),
        .d_in_valid(resp_1_2_3_U_v), .d_in_flit(resp_1_2_3_U_f), .d_in_ready(resp_1_2_3_U_r),
        .d_out_valid(resp_1_2_2_D_v), .d_out_flit(resp_1_2_2_D_f), .d_out_ready(resp_1_2_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c21_resp_in_valid), .l_out_flit(c21_resp_in_flit), .l_out_ready(c21_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(3), .MY_W(0)) req_r1_2_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_3_S_v), .n_in_flit(req_1_1_3_S_f), .n_in_ready(req_1_1_3_S_r),
        .n_out_valid(req_1_2_3_N_v), .n_out_flit(req_1_2_3_N_f), .n_out_ready(req_1_2_3_N_r),
        .e_in_valid(req_2_2_3_W_v), .e_in_flit(req_2_2_3_W_f), .e_in_ready(req_2_2_3_W_r),
        .e_out_valid(req_1_2_3_E_v), .e_out_flit(req_1_2_3_E_f), .e_out_ready(req_1_2_3_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_0_2_3_E_v), .w_in_flit(req_0_2_3_E_f), .w_in_ready(req_0_2_3_E_r),
        .w_out_valid(req_1_2_3_W_v), .w_out_flit(req_1_2_3_W_f), .w_out_ready(req_1_2_3_W_r),
        .u_in_valid(req_1_2_2_D_v), .u_in_flit(req_1_2_2_D_f), .u_in_ready(req_1_2_2_D_r),
        .u_out_valid(req_1_2_3_U_v), .u_out_flit(req_1_2_3_U_f), .u_out_ready(req_1_2_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c22_req_out_valid), .l_in_flit(c22_req_out_flit), .l_in_ready(c22_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(3), .MY_W(0)) resp_r1_2_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_3_S_v), .n_in_flit(resp_1_1_3_S_f), .n_in_ready(resp_1_1_3_S_r),
        .n_out_valid(resp_1_2_3_N_v), .n_out_flit(resp_1_2_3_N_f), .n_out_ready(resp_1_2_3_N_r),
        .e_in_valid(resp_2_2_3_W_v), .e_in_flit(resp_2_2_3_W_f), .e_in_ready(resp_2_2_3_W_r),
        .e_out_valid(resp_1_2_3_E_v), .e_out_flit(resp_1_2_3_E_f), .e_out_ready(resp_1_2_3_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_0_2_3_E_v), .w_in_flit(resp_0_2_3_E_f), .w_in_ready(resp_0_2_3_E_r),
        .w_out_valid(resp_1_2_3_W_v), .w_out_flit(resp_1_2_3_W_f), .w_out_ready(resp_1_2_3_W_r),
        .u_in_valid(resp_1_2_2_D_v), .u_in_flit(resp_1_2_2_D_f), .u_in_ready(resp_1_2_2_D_r),
        .u_out_valid(resp_1_2_3_U_v), .u_out_flit(resp_1_2_3_U_f), .u_out_ready(resp_1_2_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c22_resp_in_valid), .l_out_flit(c22_resp_in_flit), .l_out_ready(c22_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r2_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_3_0_0_W_v), .e_in_flit(req_3_0_0_W_f), .e_in_ready(req_3_0_0_W_r),
        .e_out_valid(req_2_0_0_E_v), .e_out_flit(req_2_0_0_E_f), .e_out_ready(req_2_0_0_E_r),
        .s_in_valid(req_2_1_0_N_v), .s_in_flit(req_2_1_0_N_f), .s_in_ready(req_2_1_0_N_r),
        .s_out_valid(req_2_0_0_S_v), .s_out_flit(req_2_0_0_S_f), .s_out_ready(req_2_0_0_S_r),
        .w_in_valid(req_1_0_0_E_v), .w_in_flit(req_1_0_0_E_f), .w_in_ready(req_1_0_0_E_r),
        .w_out_valid(req_2_0_0_W_v), .w_out_flit(req_2_0_0_W_f), .w_out_ready(req_2_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_2_0_1_U_v), .d_in_flit(req_2_0_1_U_f), .d_in_ready(req_2_0_1_U_r),
        .d_out_valid(req_2_0_0_D_v), .d_out_flit(req_2_0_0_D_f), .d_out_ready(req_2_0_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c23_req_out_valid), .l_in_flit(c23_req_out_flit), .l_in_ready(c23_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r2_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_3_0_0_W_v), .e_in_flit(resp_3_0_0_W_f), .e_in_ready(resp_3_0_0_W_r),
        .e_out_valid(resp_2_0_0_E_v), .e_out_flit(resp_2_0_0_E_f), .e_out_ready(resp_2_0_0_E_r),
        .s_in_valid(resp_2_1_0_N_v), .s_in_flit(resp_2_1_0_N_f), .s_in_ready(resp_2_1_0_N_r),
        .s_out_valid(resp_2_0_0_S_v), .s_out_flit(resp_2_0_0_S_f), .s_out_ready(resp_2_0_0_S_r),
        .w_in_valid(resp_1_0_0_E_v), .w_in_flit(resp_1_0_0_E_f), .w_in_ready(resp_1_0_0_E_r),
        .w_out_valid(resp_2_0_0_W_v), .w_out_flit(resp_2_0_0_W_f), .w_out_ready(resp_2_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_2_0_1_U_v), .d_in_flit(resp_2_0_1_U_f), .d_in_ready(resp_2_0_1_U_r),
        .d_out_valid(resp_2_0_0_D_v), .d_out_flit(resp_2_0_0_D_f), .d_out_ready(resp_2_0_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c23_resp_in_valid), .l_out_flit(c23_resp_in_flit), .l_out_ready(c23_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(1), .MY_W(0)) req_r2_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_3_0_1_W_v), .e_in_flit(req_3_0_1_W_f), .e_in_ready(req_3_0_1_W_r),
        .e_out_valid(req_2_0_1_E_v), .e_out_flit(req_2_0_1_E_f), .e_out_ready(req_2_0_1_E_r),
        .s_in_valid(req_2_1_1_N_v), .s_in_flit(req_2_1_1_N_f), .s_in_ready(req_2_1_1_N_r),
        .s_out_valid(req_2_0_1_S_v), .s_out_flit(req_2_0_1_S_f), .s_out_ready(req_2_0_1_S_r),
        .w_in_valid(req_1_0_1_E_v), .w_in_flit(req_1_0_1_E_f), .w_in_ready(req_1_0_1_E_r),
        .w_out_valid(req_2_0_1_W_v), .w_out_flit(req_2_0_1_W_f), .w_out_ready(req_2_0_1_W_r),
        .u_in_valid(req_2_0_0_D_v), .u_in_flit(req_2_0_0_D_f), .u_in_ready(req_2_0_0_D_r),
        .u_out_valid(req_2_0_1_U_v), .u_out_flit(req_2_0_1_U_f), .u_out_ready(req_2_0_1_U_r),
        .d_in_valid(req_2_0_2_U_v), .d_in_flit(req_2_0_2_U_f), .d_in_ready(req_2_0_2_U_r),
        .d_out_valid(req_2_0_1_D_v), .d_out_flit(req_2_0_1_D_f), .d_out_ready(req_2_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c24_req_out_valid), .l_in_flit(c24_req_out_flit), .l_in_ready(c24_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(1), .MY_W(0)) resp_r2_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_3_0_1_W_v), .e_in_flit(resp_3_0_1_W_f), .e_in_ready(resp_3_0_1_W_r),
        .e_out_valid(resp_2_0_1_E_v), .e_out_flit(resp_2_0_1_E_f), .e_out_ready(resp_2_0_1_E_r),
        .s_in_valid(resp_2_1_1_N_v), .s_in_flit(resp_2_1_1_N_f), .s_in_ready(resp_2_1_1_N_r),
        .s_out_valid(resp_2_0_1_S_v), .s_out_flit(resp_2_0_1_S_f), .s_out_ready(resp_2_0_1_S_r),
        .w_in_valid(resp_1_0_1_E_v), .w_in_flit(resp_1_0_1_E_f), .w_in_ready(resp_1_0_1_E_r),
        .w_out_valid(resp_2_0_1_W_v), .w_out_flit(resp_2_0_1_W_f), .w_out_ready(resp_2_0_1_W_r),
        .u_in_valid(resp_2_0_0_D_v), .u_in_flit(resp_2_0_0_D_f), .u_in_ready(resp_2_0_0_D_r),
        .u_out_valid(resp_2_0_1_U_v), .u_out_flit(resp_2_0_1_U_f), .u_out_ready(resp_2_0_1_U_r),
        .d_in_valid(resp_2_0_2_U_v), .d_in_flit(resp_2_0_2_U_f), .d_in_ready(resp_2_0_2_U_r),
        .d_out_valid(resp_2_0_1_D_v), .d_out_flit(resp_2_0_1_D_f), .d_out_ready(resp_2_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c24_resp_in_valid), .l_out_flit(c24_resp_in_flit), .l_out_ready(c24_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(2), .MY_W(0)) req_r2_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_3_0_2_W_v), .e_in_flit(req_3_0_2_W_f), .e_in_ready(req_3_0_2_W_r),
        .e_out_valid(req_2_0_2_E_v), .e_out_flit(req_2_0_2_E_f), .e_out_ready(req_2_0_2_E_r),
        .s_in_valid(req_2_1_2_N_v), .s_in_flit(req_2_1_2_N_f), .s_in_ready(req_2_1_2_N_r),
        .s_out_valid(req_2_0_2_S_v), .s_out_flit(req_2_0_2_S_f), .s_out_ready(req_2_0_2_S_r),
        .w_in_valid(req_1_0_2_E_v), .w_in_flit(req_1_0_2_E_f), .w_in_ready(req_1_0_2_E_r),
        .w_out_valid(req_2_0_2_W_v), .w_out_flit(req_2_0_2_W_f), .w_out_ready(req_2_0_2_W_r),
        .u_in_valid(req_2_0_1_D_v), .u_in_flit(req_2_0_1_D_f), .u_in_ready(req_2_0_1_D_r),
        .u_out_valid(req_2_0_2_U_v), .u_out_flit(req_2_0_2_U_f), .u_out_ready(req_2_0_2_U_r),
        .d_in_valid(req_2_0_3_U_v), .d_in_flit(req_2_0_3_U_f), .d_in_ready(req_2_0_3_U_r),
        .d_out_valid(req_2_0_2_D_v), .d_out_flit(req_2_0_2_D_f), .d_out_ready(req_2_0_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c25_req_out_valid), .l_in_flit(c25_req_out_flit), .l_in_ready(c25_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(2), .MY_W(0)) resp_r2_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_3_0_2_W_v), .e_in_flit(resp_3_0_2_W_f), .e_in_ready(resp_3_0_2_W_r),
        .e_out_valid(resp_2_0_2_E_v), .e_out_flit(resp_2_0_2_E_f), .e_out_ready(resp_2_0_2_E_r),
        .s_in_valid(resp_2_1_2_N_v), .s_in_flit(resp_2_1_2_N_f), .s_in_ready(resp_2_1_2_N_r),
        .s_out_valid(resp_2_0_2_S_v), .s_out_flit(resp_2_0_2_S_f), .s_out_ready(resp_2_0_2_S_r),
        .w_in_valid(resp_1_0_2_E_v), .w_in_flit(resp_1_0_2_E_f), .w_in_ready(resp_1_0_2_E_r),
        .w_out_valid(resp_2_0_2_W_v), .w_out_flit(resp_2_0_2_W_f), .w_out_ready(resp_2_0_2_W_r),
        .u_in_valid(resp_2_0_1_D_v), .u_in_flit(resp_2_0_1_D_f), .u_in_ready(resp_2_0_1_D_r),
        .u_out_valid(resp_2_0_2_U_v), .u_out_flit(resp_2_0_2_U_f), .u_out_ready(resp_2_0_2_U_r),
        .d_in_valid(resp_2_0_3_U_v), .d_in_flit(resp_2_0_3_U_f), .d_in_ready(resp_2_0_3_U_r),
        .d_out_valid(resp_2_0_2_D_v), .d_out_flit(resp_2_0_2_D_f), .d_out_ready(resp_2_0_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c25_resp_in_valid), .l_out_flit(c25_resp_in_flit), .l_out_ready(c25_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(3), .MY_W(0)) req_r2_0_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_3_0_3_W_v), .e_in_flit(req_3_0_3_W_f), .e_in_ready(req_3_0_3_W_r),
        .e_out_valid(req_2_0_3_E_v), .e_out_flit(req_2_0_3_E_f), .e_out_ready(req_2_0_3_E_r),
        .s_in_valid(req_2_1_3_N_v), .s_in_flit(req_2_1_3_N_f), .s_in_ready(req_2_1_3_N_r),
        .s_out_valid(req_2_0_3_S_v), .s_out_flit(req_2_0_3_S_f), .s_out_ready(req_2_0_3_S_r),
        .w_in_valid(req_1_0_3_E_v), .w_in_flit(req_1_0_3_E_f), .w_in_ready(req_1_0_3_E_r),
        .w_out_valid(req_2_0_3_W_v), .w_out_flit(req_2_0_3_W_f), .w_out_ready(req_2_0_3_W_r),
        .u_in_valid(req_2_0_2_D_v), .u_in_flit(req_2_0_2_D_f), .u_in_ready(req_2_0_2_D_r),
        .u_out_valid(req_2_0_3_U_v), .u_out_flit(req_2_0_3_U_f), .u_out_ready(req_2_0_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c26_req_out_valid), .l_in_flit(c26_req_out_flit), .l_in_ready(c26_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(3), .MY_W(0)) resp_r2_0_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_3_0_3_W_v), .e_in_flit(resp_3_0_3_W_f), .e_in_ready(resp_3_0_3_W_r),
        .e_out_valid(resp_2_0_3_E_v), .e_out_flit(resp_2_0_3_E_f), .e_out_ready(resp_2_0_3_E_r),
        .s_in_valid(resp_2_1_3_N_v), .s_in_flit(resp_2_1_3_N_f), .s_in_ready(resp_2_1_3_N_r),
        .s_out_valid(resp_2_0_3_S_v), .s_out_flit(resp_2_0_3_S_f), .s_out_ready(resp_2_0_3_S_r),
        .w_in_valid(resp_1_0_3_E_v), .w_in_flit(resp_1_0_3_E_f), .w_in_ready(resp_1_0_3_E_r),
        .w_out_valid(resp_2_0_3_W_v), .w_out_flit(resp_2_0_3_W_f), .w_out_ready(resp_2_0_3_W_r),
        .u_in_valid(resp_2_0_2_D_v), .u_in_flit(resp_2_0_2_D_f), .u_in_ready(resp_2_0_2_D_r),
        .u_out_valid(resp_2_0_3_U_v), .u_out_flit(resp_2_0_3_U_f), .u_out_ready(resp_2_0_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c26_resp_in_valid), .l_out_flit(c26_resp_in_flit), .l_out_ready(c26_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(0), .MY_W(0)) req_r2_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_0_0_S_v), .n_in_flit(req_2_0_0_S_f), .n_in_ready(req_2_0_0_S_r),
        .n_out_valid(req_2_1_0_N_v), .n_out_flit(req_2_1_0_N_f), .n_out_ready(req_2_1_0_N_r),
        .e_in_valid(req_3_1_0_W_v), .e_in_flit(req_3_1_0_W_f), .e_in_ready(req_3_1_0_W_r),
        .e_out_valid(req_2_1_0_E_v), .e_out_flit(req_2_1_0_E_f), .e_out_ready(req_2_1_0_E_r),
        .s_in_valid(req_2_2_0_N_v), .s_in_flit(req_2_2_0_N_f), .s_in_ready(req_2_2_0_N_r),
        .s_out_valid(req_2_1_0_S_v), .s_out_flit(req_2_1_0_S_f), .s_out_ready(req_2_1_0_S_r),
        .w_in_valid(req_1_1_0_E_v), .w_in_flit(req_1_1_0_E_f), .w_in_ready(req_1_1_0_E_r),
        .w_out_valid(req_2_1_0_W_v), .w_out_flit(req_2_1_0_W_f), .w_out_ready(req_2_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_2_1_1_U_v), .d_in_flit(req_2_1_1_U_f), .d_in_ready(req_2_1_1_U_r),
        .d_out_valid(req_2_1_0_D_v), .d_out_flit(req_2_1_0_D_f), .d_out_ready(req_2_1_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c27_req_out_valid), .l_in_flit(c27_req_out_flit), .l_in_ready(c27_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(0), .MY_W(0)) resp_r2_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_0_0_S_v), .n_in_flit(resp_2_0_0_S_f), .n_in_ready(resp_2_0_0_S_r),
        .n_out_valid(resp_2_1_0_N_v), .n_out_flit(resp_2_1_0_N_f), .n_out_ready(resp_2_1_0_N_r),
        .e_in_valid(resp_3_1_0_W_v), .e_in_flit(resp_3_1_0_W_f), .e_in_ready(resp_3_1_0_W_r),
        .e_out_valid(resp_2_1_0_E_v), .e_out_flit(resp_2_1_0_E_f), .e_out_ready(resp_2_1_0_E_r),
        .s_in_valid(resp_2_2_0_N_v), .s_in_flit(resp_2_2_0_N_f), .s_in_ready(resp_2_2_0_N_r),
        .s_out_valid(resp_2_1_0_S_v), .s_out_flit(resp_2_1_0_S_f), .s_out_ready(resp_2_1_0_S_r),
        .w_in_valid(resp_1_1_0_E_v), .w_in_flit(resp_1_1_0_E_f), .w_in_ready(resp_1_1_0_E_r),
        .w_out_valid(resp_2_1_0_W_v), .w_out_flit(resp_2_1_0_W_f), .w_out_ready(resp_2_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_2_1_1_U_v), .d_in_flit(resp_2_1_1_U_f), .d_in_ready(resp_2_1_1_U_r),
        .d_out_valid(resp_2_1_0_D_v), .d_out_flit(resp_2_1_0_D_f), .d_out_ready(resp_2_1_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c27_resp_in_valid), .l_out_flit(c27_resp_in_flit), .l_out_ready(c27_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(1), .MY_W(0)) req_r2_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_0_1_S_v), .n_in_flit(req_2_0_1_S_f), .n_in_ready(req_2_0_1_S_r),
        .n_out_valid(req_2_1_1_N_v), .n_out_flit(req_2_1_1_N_f), .n_out_ready(req_2_1_1_N_r),
        .e_in_valid(req_3_1_1_W_v), .e_in_flit(req_3_1_1_W_f), .e_in_ready(req_3_1_1_W_r),
        .e_out_valid(req_2_1_1_E_v), .e_out_flit(req_2_1_1_E_f), .e_out_ready(req_2_1_1_E_r),
        .s_in_valid(req_2_2_1_N_v), .s_in_flit(req_2_2_1_N_f), .s_in_ready(req_2_2_1_N_r),
        .s_out_valid(req_2_1_1_S_v), .s_out_flit(req_2_1_1_S_f), .s_out_ready(req_2_1_1_S_r),
        .w_in_valid(req_1_1_1_E_v), .w_in_flit(req_1_1_1_E_f), .w_in_ready(req_1_1_1_E_r),
        .w_out_valid(req_2_1_1_W_v), .w_out_flit(req_2_1_1_W_f), .w_out_ready(req_2_1_1_W_r),
        .u_in_valid(req_2_1_0_D_v), .u_in_flit(req_2_1_0_D_f), .u_in_ready(req_2_1_0_D_r),
        .u_out_valid(req_2_1_1_U_v), .u_out_flit(req_2_1_1_U_f), .u_out_ready(req_2_1_1_U_r),
        .d_in_valid(req_2_1_2_U_v), .d_in_flit(req_2_1_2_U_f), .d_in_ready(req_2_1_2_U_r),
        .d_out_valid(req_2_1_1_D_v), .d_out_flit(req_2_1_1_D_f), .d_out_ready(req_2_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c28_req_out_valid), .l_in_flit(c28_req_out_flit), .l_in_ready(c28_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(1), .MY_W(0)) resp_r2_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_0_1_S_v), .n_in_flit(resp_2_0_1_S_f), .n_in_ready(resp_2_0_1_S_r),
        .n_out_valid(resp_2_1_1_N_v), .n_out_flit(resp_2_1_1_N_f), .n_out_ready(resp_2_1_1_N_r),
        .e_in_valid(resp_3_1_1_W_v), .e_in_flit(resp_3_1_1_W_f), .e_in_ready(resp_3_1_1_W_r),
        .e_out_valid(resp_2_1_1_E_v), .e_out_flit(resp_2_1_1_E_f), .e_out_ready(resp_2_1_1_E_r),
        .s_in_valid(resp_2_2_1_N_v), .s_in_flit(resp_2_2_1_N_f), .s_in_ready(resp_2_2_1_N_r),
        .s_out_valid(resp_2_1_1_S_v), .s_out_flit(resp_2_1_1_S_f), .s_out_ready(resp_2_1_1_S_r),
        .w_in_valid(resp_1_1_1_E_v), .w_in_flit(resp_1_1_1_E_f), .w_in_ready(resp_1_1_1_E_r),
        .w_out_valid(resp_2_1_1_W_v), .w_out_flit(resp_2_1_1_W_f), .w_out_ready(resp_2_1_1_W_r),
        .u_in_valid(resp_2_1_0_D_v), .u_in_flit(resp_2_1_0_D_f), .u_in_ready(resp_2_1_0_D_r),
        .u_out_valid(resp_2_1_1_U_v), .u_out_flit(resp_2_1_1_U_f), .u_out_ready(resp_2_1_1_U_r),
        .d_in_valid(resp_2_1_2_U_v), .d_in_flit(resp_2_1_2_U_f), .d_in_ready(resp_2_1_2_U_r),
        .d_out_valid(resp_2_1_1_D_v), .d_out_flit(resp_2_1_1_D_f), .d_out_ready(resp_2_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c28_resp_in_valid), .l_out_flit(c28_resp_in_flit), .l_out_ready(c28_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(2), .MY_W(0)) req_r2_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_0_2_S_v), .n_in_flit(req_2_0_2_S_f), .n_in_ready(req_2_0_2_S_r),
        .n_out_valid(req_2_1_2_N_v), .n_out_flit(req_2_1_2_N_f), .n_out_ready(req_2_1_2_N_r),
        .e_in_valid(req_3_1_2_W_v), .e_in_flit(req_3_1_2_W_f), .e_in_ready(req_3_1_2_W_r),
        .e_out_valid(req_2_1_2_E_v), .e_out_flit(req_2_1_2_E_f), .e_out_ready(req_2_1_2_E_r),
        .s_in_valid(req_2_2_2_N_v), .s_in_flit(req_2_2_2_N_f), .s_in_ready(req_2_2_2_N_r),
        .s_out_valid(req_2_1_2_S_v), .s_out_flit(req_2_1_2_S_f), .s_out_ready(req_2_1_2_S_r),
        .w_in_valid(req_1_1_2_E_v), .w_in_flit(req_1_1_2_E_f), .w_in_ready(req_1_1_2_E_r),
        .w_out_valid(req_2_1_2_W_v), .w_out_flit(req_2_1_2_W_f), .w_out_ready(req_2_1_2_W_r),
        .u_in_valid(req_2_1_1_D_v), .u_in_flit(req_2_1_1_D_f), .u_in_ready(req_2_1_1_D_r),
        .u_out_valid(req_2_1_2_U_v), .u_out_flit(req_2_1_2_U_f), .u_out_ready(req_2_1_2_U_r),
        .d_in_valid(req_2_1_3_U_v), .d_in_flit(req_2_1_3_U_f), .d_in_ready(req_2_1_3_U_r),
        .d_out_valid(req_2_1_2_D_v), .d_out_flit(req_2_1_2_D_f), .d_out_ready(req_2_1_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c29_req_out_valid), .l_in_flit(c29_req_out_flit), .l_in_ready(c29_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(2), .MY_W(0)) resp_r2_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_0_2_S_v), .n_in_flit(resp_2_0_2_S_f), .n_in_ready(resp_2_0_2_S_r),
        .n_out_valid(resp_2_1_2_N_v), .n_out_flit(resp_2_1_2_N_f), .n_out_ready(resp_2_1_2_N_r),
        .e_in_valid(resp_3_1_2_W_v), .e_in_flit(resp_3_1_2_W_f), .e_in_ready(resp_3_1_2_W_r),
        .e_out_valid(resp_2_1_2_E_v), .e_out_flit(resp_2_1_2_E_f), .e_out_ready(resp_2_1_2_E_r),
        .s_in_valid(resp_2_2_2_N_v), .s_in_flit(resp_2_2_2_N_f), .s_in_ready(resp_2_2_2_N_r),
        .s_out_valid(resp_2_1_2_S_v), .s_out_flit(resp_2_1_2_S_f), .s_out_ready(resp_2_1_2_S_r),
        .w_in_valid(resp_1_1_2_E_v), .w_in_flit(resp_1_1_2_E_f), .w_in_ready(resp_1_1_2_E_r),
        .w_out_valid(resp_2_1_2_W_v), .w_out_flit(resp_2_1_2_W_f), .w_out_ready(resp_2_1_2_W_r),
        .u_in_valid(resp_2_1_1_D_v), .u_in_flit(resp_2_1_1_D_f), .u_in_ready(resp_2_1_1_D_r),
        .u_out_valid(resp_2_1_2_U_v), .u_out_flit(resp_2_1_2_U_f), .u_out_ready(resp_2_1_2_U_r),
        .d_in_valid(resp_2_1_3_U_v), .d_in_flit(resp_2_1_3_U_f), .d_in_ready(resp_2_1_3_U_r),
        .d_out_valid(resp_2_1_2_D_v), .d_out_flit(resp_2_1_2_D_f), .d_out_ready(resp_2_1_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c29_resp_in_valid), .l_out_flit(c29_resp_in_flit), .l_out_ready(c29_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(3), .MY_W(0)) req_r2_1_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_0_3_S_v), .n_in_flit(req_2_0_3_S_f), .n_in_ready(req_2_0_3_S_r),
        .n_out_valid(req_2_1_3_N_v), .n_out_flit(req_2_1_3_N_f), .n_out_ready(req_2_1_3_N_r),
        .e_in_valid(req_3_1_3_W_v), .e_in_flit(req_3_1_3_W_f), .e_in_ready(req_3_1_3_W_r),
        .e_out_valid(req_2_1_3_E_v), .e_out_flit(req_2_1_3_E_f), .e_out_ready(req_2_1_3_E_r),
        .s_in_valid(req_2_2_3_N_v), .s_in_flit(req_2_2_3_N_f), .s_in_ready(req_2_2_3_N_r),
        .s_out_valid(req_2_1_3_S_v), .s_out_flit(req_2_1_3_S_f), .s_out_ready(req_2_1_3_S_r),
        .w_in_valid(req_1_1_3_E_v), .w_in_flit(req_1_1_3_E_f), .w_in_ready(req_1_1_3_E_r),
        .w_out_valid(req_2_1_3_W_v), .w_out_flit(req_2_1_3_W_f), .w_out_ready(req_2_1_3_W_r),
        .u_in_valid(req_2_1_2_D_v), .u_in_flit(req_2_1_2_D_f), .u_in_ready(req_2_1_2_D_r),
        .u_out_valid(req_2_1_3_U_v), .u_out_flit(req_2_1_3_U_f), .u_out_ready(req_2_1_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c30_req_out_valid), .l_in_flit(c30_req_out_flit), .l_in_ready(c30_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(3), .MY_W(0)) resp_r2_1_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_0_3_S_v), .n_in_flit(resp_2_0_3_S_f), .n_in_ready(resp_2_0_3_S_r),
        .n_out_valid(resp_2_1_3_N_v), .n_out_flit(resp_2_1_3_N_f), .n_out_ready(resp_2_1_3_N_r),
        .e_in_valid(resp_3_1_3_W_v), .e_in_flit(resp_3_1_3_W_f), .e_in_ready(resp_3_1_3_W_r),
        .e_out_valid(resp_2_1_3_E_v), .e_out_flit(resp_2_1_3_E_f), .e_out_ready(resp_2_1_3_E_r),
        .s_in_valid(resp_2_2_3_N_v), .s_in_flit(resp_2_2_3_N_f), .s_in_ready(resp_2_2_3_N_r),
        .s_out_valid(resp_2_1_3_S_v), .s_out_flit(resp_2_1_3_S_f), .s_out_ready(resp_2_1_3_S_r),
        .w_in_valid(resp_1_1_3_E_v), .w_in_flit(resp_1_1_3_E_f), .w_in_ready(resp_1_1_3_E_r),
        .w_out_valid(resp_2_1_3_W_v), .w_out_flit(resp_2_1_3_W_f), .w_out_ready(resp_2_1_3_W_r),
        .u_in_valid(resp_2_1_2_D_v), .u_in_flit(resp_2_1_2_D_f), .u_in_ready(resp_2_1_2_D_r),
        .u_out_valid(resp_2_1_3_U_v), .u_out_flit(resp_2_1_3_U_f), .u_out_ready(resp_2_1_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c30_resp_in_valid), .l_out_flit(c30_resp_in_flit), .l_out_ready(c30_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(0), .MY_W(0)) req_r2_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_1_0_S_v), .n_in_flit(req_2_1_0_S_f), .n_in_ready(req_2_1_0_S_r),
        .n_out_valid(req_2_2_0_N_v), .n_out_flit(req_2_2_0_N_f), .n_out_ready(req_2_2_0_N_r),
        .e_in_valid(req_3_2_0_W_v), .e_in_flit(req_3_2_0_W_f), .e_in_ready(req_3_2_0_W_r),
        .e_out_valid(req_2_2_0_E_v), .e_out_flit(req_2_2_0_E_f), .e_out_ready(req_2_2_0_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_1_2_0_E_v), .w_in_flit(req_1_2_0_E_f), .w_in_ready(req_1_2_0_E_r),
        .w_out_valid(req_2_2_0_W_v), .w_out_flit(req_2_2_0_W_f), .w_out_ready(req_2_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_2_2_1_U_v), .d_in_flit(req_2_2_1_U_f), .d_in_ready(req_2_2_1_U_r),
        .d_out_valid(req_2_2_0_D_v), .d_out_flit(req_2_2_0_D_f), .d_out_ready(req_2_2_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c31_req_out_valid), .l_in_flit(c31_req_out_flit), .l_in_ready(c31_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(0), .MY_W(0)) resp_r2_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_1_0_S_v), .n_in_flit(resp_2_1_0_S_f), .n_in_ready(resp_2_1_0_S_r),
        .n_out_valid(resp_2_2_0_N_v), .n_out_flit(resp_2_2_0_N_f), .n_out_ready(resp_2_2_0_N_r),
        .e_in_valid(resp_3_2_0_W_v), .e_in_flit(resp_3_2_0_W_f), .e_in_ready(resp_3_2_0_W_r),
        .e_out_valid(resp_2_2_0_E_v), .e_out_flit(resp_2_2_0_E_f), .e_out_ready(resp_2_2_0_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_1_2_0_E_v), .w_in_flit(resp_1_2_0_E_f), .w_in_ready(resp_1_2_0_E_r),
        .w_out_valid(resp_2_2_0_W_v), .w_out_flit(resp_2_2_0_W_f), .w_out_ready(resp_2_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_2_2_1_U_v), .d_in_flit(resp_2_2_1_U_f), .d_in_ready(resp_2_2_1_U_r),
        .d_out_valid(resp_2_2_0_D_v), .d_out_flit(resp_2_2_0_D_f), .d_out_ready(resp_2_2_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c31_resp_in_valid), .l_out_flit(c31_resp_in_flit), .l_out_ready(c31_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(1), .MY_W(0)) req_r2_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_1_1_S_v), .n_in_flit(req_2_1_1_S_f), .n_in_ready(req_2_1_1_S_r),
        .n_out_valid(req_2_2_1_N_v), .n_out_flit(req_2_2_1_N_f), .n_out_ready(req_2_2_1_N_r),
        .e_in_valid(req_3_2_1_W_v), .e_in_flit(req_3_2_1_W_f), .e_in_ready(req_3_2_1_W_r),
        .e_out_valid(req_2_2_1_E_v), .e_out_flit(req_2_2_1_E_f), .e_out_ready(req_2_2_1_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_1_2_1_E_v), .w_in_flit(req_1_2_1_E_f), .w_in_ready(req_1_2_1_E_r),
        .w_out_valid(req_2_2_1_W_v), .w_out_flit(req_2_2_1_W_f), .w_out_ready(req_2_2_1_W_r),
        .u_in_valid(req_2_2_0_D_v), .u_in_flit(req_2_2_0_D_f), .u_in_ready(req_2_2_0_D_r),
        .u_out_valid(req_2_2_1_U_v), .u_out_flit(req_2_2_1_U_f), .u_out_ready(req_2_2_1_U_r),
        .d_in_valid(req_2_2_2_U_v), .d_in_flit(req_2_2_2_U_f), .d_in_ready(req_2_2_2_U_r),
        .d_out_valid(req_2_2_1_D_v), .d_out_flit(req_2_2_1_D_f), .d_out_ready(req_2_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c32_req_out_valid), .l_in_flit(c32_req_out_flit), .l_in_ready(c32_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(1), .MY_W(0)) resp_r2_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_1_1_S_v), .n_in_flit(resp_2_1_1_S_f), .n_in_ready(resp_2_1_1_S_r),
        .n_out_valid(resp_2_2_1_N_v), .n_out_flit(resp_2_2_1_N_f), .n_out_ready(resp_2_2_1_N_r),
        .e_in_valid(resp_3_2_1_W_v), .e_in_flit(resp_3_2_1_W_f), .e_in_ready(resp_3_2_1_W_r),
        .e_out_valid(resp_2_2_1_E_v), .e_out_flit(resp_2_2_1_E_f), .e_out_ready(resp_2_2_1_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_1_2_1_E_v), .w_in_flit(resp_1_2_1_E_f), .w_in_ready(resp_1_2_1_E_r),
        .w_out_valid(resp_2_2_1_W_v), .w_out_flit(resp_2_2_1_W_f), .w_out_ready(resp_2_2_1_W_r),
        .u_in_valid(resp_2_2_0_D_v), .u_in_flit(resp_2_2_0_D_f), .u_in_ready(resp_2_2_0_D_r),
        .u_out_valid(resp_2_2_1_U_v), .u_out_flit(resp_2_2_1_U_f), .u_out_ready(resp_2_2_1_U_r),
        .d_in_valid(resp_2_2_2_U_v), .d_in_flit(resp_2_2_2_U_f), .d_in_ready(resp_2_2_2_U_r),
        .d_out_valid(resp_2_2_1_D_v), .d_out_flit(resp_2_2_1_D_f), .d_out_ready(resp_2_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c32_resp_in_valid), .l_out_flit(c32_resp_in_flit), .l_out_ready(c32_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(2), .MY_W(0)) req_r2_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_1_2_S_v), .n_in_flit(req_2_1_2_S_f), .n_in_ready(req_2_1_2_S_r),
        .n_out_valid(req_2_2_2_N_v), .n_out_flit(req_2_2_2_N_f), .n_out_ready(req_2_2_2_N_r),
        .e_in_valid(req_3_2_2_W_v), .e_in_flit(req_3_2_2_W_f), .e_in_ready(req_3_2_2_W_r),
        .e_out_valid(req_2_2_2_E_v), .e_out_flit(req_2_2_2_E_f), .e_out_ready(req_2_2_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_1_2_2_E_v), .w_in_flit(req_1_2_2_E_f), .w_in_ready(req_1_2_2_E_r),
        .w_out_valid(req_2_2_2_W_v), .w_out_flit(req_2_2_2_W_f), .w_out_ready(req_2_2_2_W_r),
        .u_in_valid(req_2_2_1_D_v), .u_in_flit(req_2_2_1_D_f), .u_in_ready(req_2_2_1_D_r),
        .u_out_valid(req_2_2_2_U_v), .u_out_flit(req_2_2_2_U_f), .u_out_ready(req_2_2_2_U_r),
        .d_in_valid(req_2_2_3_U_v), .d_in_flit(req_2_2_3_U_f), .d_in_ready(req_2_2_3_U_r),
        .d_out_valid(req_2_2_2_D_v), .d_out_flit(req_2_2_2_D_f), .d_out_ready(req_2_2_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c33_req_out_valid), .l_in_flit(c33_req_out_flit), .l_in_ready(c33_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(2), .MY_W(0)) resp_r2_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_1_2_S_v), .n_in_flit(resp_2_1_2_S_f), .n_in_ready(resp_2_1_2_S_r),
        .n_out_valid(resp_2_2_2_N_v), .n_out_flit(resp_2_2_2_N_f), .n_out_ready(resp_2_2_2_N_r),
        .e_in_valid(resp_3_2_2_W_v), .e_in_flit(resp_3_2_2_W_f), .e_in_ready(resp_3_2_2_W_r),
        .e_out_valid(resp_2_2_2_E_v), .e_out_flit(resp_2_2_2_E_f), .e_out_ready(resp_2_2_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_1_2_2_E_v), .w_in_flit(resp_1_2_2_E_f), .w_in_ready(resp_1_2_2_E_r),
        .w_out_valid(resp_2_2_2_W_v), .w_out_flit(resp_2_2_2_W_f), .w_out_ready(resp_2_2_2_W_r),
        .u_in_valid(resp_2_2_1_D_v), .u_in_flit(resp_2_2_1_D_f), .u_in_ready(resp_2_2_1_D_r),
        .u_out_valid(resp_2_2_2_U_v), .u_out_flit(resp_2_2_2_U_f), .u_out_ready(resp_2_2_2_U_r),
        .d_in_valid(resp_2_2_3_U_v), .d_in_flit(resp_2_2_3_U_f), .d_in_ready(resp_2_2_3_U_r),
        .d_out_valid(resp_2_2_2_D_v), .d_out_flit(resp_2_2_2_D_f), .d_out_ready(resp_2_2_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c33_resp_in_valid), .l_out_flit(c33_resp_in_flit), .l_out_ready(c33_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(3), .MY_W(0)) req_r2_2_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_1_3_S_v), .n_in_flit(req_2_1_3_S_f), .n_in_ready(req_2_1_3_S_r),
        .n_out_valid(req_2_2_3_N_v), .n_out_flit(req_2_2_3_N_f), .n_out_ready(req_2_2_3_N_r),
        .e_in_valid(req_3_2_3_W_v), .e_in_flit(req_3_2_3_W_f), .e_in_ready(req_3_2_3_W_r),
        .e_out_valid(req_2_2_3_E_v), .e_out_flit(req_2_2_3_E_f), .e_out_ready(req_2_2_3_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_1_2_3_E_v), .w_in_flit(req_1_2_3_E_f), .w_in_ready(req_1_2_3_E_r),
        .w_out_valid(req_2_2_3_W_v), .w_out_flit(req_2_2_3_W_f), .w_out_ready(req_2_2_3_W_r),
        .u_in_valid(req_2_2_2_D_v), .u_in_flit(req_2_2_2_D_f), .u_in_ready(req_2_2_2_D_r),
        .u_out_valid(req_2_2_3_U_v), .u_out_flit(req_2_2_3_U_f), .u_out_ready(req_2_2_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c34_req_out_valid), .l_in_flit(c34_req_out_flit), .l_in_ready(c34_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(3), .MY_W(0)) resp_r2_2_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_1_3_S_v), .n_in_flit(resp_2_1_3_S_f), .n_in_ready(resp_2_1_3_S_r),
        .n_out_valid(resp_2_2_3_N_v), .n_out_flit(resp_2_2_3_N_f), .n_out_ready(resp_2_2_3_N_r),
        .e_in_valid(resp_3_2_3_W_v), .e_in_flit(resp_3_2_3_W_f), .e_in_ready(resp_3_2_3_W_r),
        .e_out_valid(resp_2_2_3_E_v), .e_out_flit(resp_2_2_3_E_f), .e_out_ready(resp_2_2_3_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_1_2_3_E_v), .w_in_flit(resp_1_2_3_E_f), .w_in_ready(resp_1_2_3_E_r),
        .w_out_valid(resp_2_2_3_W_v), .w_out_flit(resp_2_2_3_W_f), .w_out_ready(resp_2_2_3_W_r),
        .u_in_valid(resp_2_2_2_D_v), .u_in_flit(resp_2_2_2_D_f), .u_in_ready(resp_2_2_2_D_r),
        .u_out_valid(resp_2_2_3_U_v), .u_out_flit(resp_2_2_3_U_f), .u_out_ready(resp_2_2_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c34_resp_in_valid), .l_out_flit(c34_resp_in_flit), .l_out_ready(c34_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r3_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_3_1_0_N_v), .s_in_flit(req_3_1_0_N_f), .s_in_ready(req_3_1_0_N_r),
        .s_out_valid(req_3_0_0_S_v), .s_out_flit(req_3_0_0_S_f), .s_out_ready(req_3_0_0_S_r),
        .w_in_valid(req_2_0_0_E_v), .w_in_flit(req_2_0_0_E_f), .w_in_ready(req_2_0_0_E_r),
        .w_out_valid(req_3_0_0_W_v), .w_out_flit(req_3_0_0_W_f), .w_out_ready(req_3_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_3_0_1_U_v), .d_in_flit(req_3_0_1_U_f), .d_in_ready(req_3_0_1_U_r),
        .d_out_valid(req_3_0_0_D_v), .d_out_flit(req_3_0_0_D_f), .d_out_ready(req_3_0_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c35_req_out_valid), .l_in_flit(c35_req_out_flit), .l_in_ready(c35_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r3_0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_3_1_0_N_v), .s_in_flit(resp_3_1_0_N_f), .s_in_ready(resp_3_1_0_N_r),
        .s_out_valid(resp_3_0_0_S_v), .s_out_flit(resp_3_0_0_S_f), .s_out_ready(resp_3_0_0_S_r),
        .w_in_valid(resp_2_0_0_E_v), .w_in_flit(resp_2_0_0_E_f), .w_in_ready(resp_2_0_0_E_r),
        .w_out_valid(resp_3_0_0_W_v), .w_out_flit(resp_3_0_0_W_f), .w_out_ready(resp_3_0_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_3_0_1_U_v), .d_in_flit(resp_3_0_1_U_f), .d_in_ready(resp_3_0_1_U_r),
        .d_out_valid(resp_3_0_0_D_v), .d_out_flit(resp_3_0_0_D_f), .d_out_ready(resp_3_0_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c35_resp_in_valid), .l_out_flit(c35_resp_in_flit), .l_out_ready(c35_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(1), .MY_W(0)) req_r3_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_3_1_1_N_v), .s_in_flit(req_3_1_1_N_f), .s_in_ready(req_3_1_1_N_r),
        .s_out_valid(req_3_0_1_S_v), .s_out_flit(req_3_0_1_S_f), .s_out_ready(req_3_0_1_S_r),
        .w_in_valid(req_2_0_1_E_v), .w_in_flit(req_2_0_1_E_f), .w_in_ready(req_2_0_1_E_r),
        .w_out_valid(req_3_0_1_W_v), .w_out_flit(req_3_0_1_W_f), .w_out_ready(req_3_0_1_W_r),
        .u_in_valid(req_3_0_0_D_v), .u_in_flit(req_3_0_0_D_f), .u_in_ready(req_3_0_0_D_r),
        .u_out_valid(req_3_0_1_U_v), .u_out_flit(req_3_0_1_U_f), .u_out_ready(req_3_0_1_U_r),
        .d_in_valid(req_3_0_2_U_v), .d_in_flit(req_3_0_2_U_f), .d_in_ready(req_3_0_2_U_r),
        .d_out_valid(req_3_0_1_D_v), .d_out_flit(req_3_0_1_D_f), .d_out_ready(req_3_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c36_req_out_valid), .l_in_flit(c36_req_out_flit), .l_in_ready(c36_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(1), .MY_W(0)) resp_r3_0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_3_1_1_N_v), .s_in_flit(resp_3_1_1_N_f), .s_in_ready(resp_3_1_1_N_r),
        .s_out_valid(resp_3_0_1_S_v), .s_out_flit(resp_3_0_1_S_f), .s_out_ready(resp_3_0_1_S_r),
        .w_in_valid(resp_2_0_1_E_v), .w_in_flit(resp_2_0_1_E_f), .w_in_ready(resp_2_0_1_E_r),
        .w_out_valid(resp_3_0_1_W_v), .w_out_flit(resp_3_0_1_W_f), .w_out_ready(resp_3_0_1_W_r),
        .u_in_valid(resp_3_0_0_D_v), .u_in_flit(resp_3_0_0_D_f), .u_in_ready(resp_3_0_0_D_r),
        .u_out_valid(resp_3_0_1_U_v), .u_out_flit(resp_3_0_1_U_f), .u_out_ready(resp_3_0_1_U_r),
        .d_in_valid(resp_3_0_2_U_v), .d_in_flit(resp_3_0_2_U_f), .d_in_ready(resp_3_0_2_U_r),
        .d_out_valid(resp_3_0_1_D_v), .d_out_flit(resp_3_0_1_D_f), .d_out_ready(resp_3_0_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c36_resp_in_valid), .l_out_flit(c36_resp_in_flit), .l_out_ready(c36_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(2), .MY_W(0)) req_r3_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_3_1_2_N_v), .s_in_flit(req_3_1_2_N_f), .s_in_ready(req_3_1_2_N_r),
        .s_out_valid(req_3_0_2_S_v), .s_out_flit(req_3_0_2_S_f), .s_out_ready(req_3_0_2_S_r),
        .w_in_valid(req_2_0_2_E_v), .w_in_flit(req_2_0_2_E_f), .w_in_ready(req_2_0_2_E_r),
        .w_out_valid(req_3_0_2_W_v), .w_out_flit(req_3_0_2_W_f), .w_out_ready(req_3_0_2_W_r),
        .u_in_valid(req_3_0_1_D_v), .u_in_flit(req_3_0_1_D_f), .u_in_ready(req_3_0_1_D_r),
        .u_out_valid(req_3_0_2_U_v), .u_out_flit(req_3_0_2_U_f), .u_out_ready(req_3_0_2_U_r),
        .d_in_valid(req_3_0_3_U_v), .d_in_flit(req_3_0_3_U_f), .d_in_ready(req_3_0_3_U_r),
        .d_out_valid(req_3_0_2_D_v), .d_out_flit(req_3_0_2_D_f), .d_out_ready(req_3_0_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c37_req_out_valid), .l_in_flit(c37_req_out_flit), .l_in_ready(c37_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(2), .MY_W(0)) resp_r3_0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_3_1_2_N_v), .s_in_flit(resp_3_1_2_N_f), .s_in_ready(resp_3_1_2_N_r),
        .s_out_valid(resp_3_0_2_S_v), .s_out_flit(resp_3_0_2_S_f), .s_out_ready(resp_3_0_2_S_r),
        .w_in_valid(resp_2_0_2_E_v), .w_in_flit(resp_2_0_2_E_f), .w_in_ready(resp_2_0_2_E_r),
        .w_out_valid(resp_3_0_2_W_v), .w_out_flit(resp_3_0_2_W_f), .w_out_ready(resp_3_0_2_W_r),
        .u_in_valid(resp_3_0_1_D_v), .u_in_flit(resp_3_0_1_D_f), .u_in_ready(resp_3_0_1_D_r),
        .u_out_valid(resp_3_0_2_U_v), .u_out_flit(resp_3_0_2_U_f), .u_out_ready(resp_3_0_2_U_r),
        .d_in_valid(resp_3_0_3_U_v), .d_in_flit(resp_3_0_3_U_f), .d_in_ready(resp_3_0_3_U_r),
        .d_out_valid(resp_3_0_2_D_v), .d_out_flit(resp_3_0_2_D_f), .d_out_ready(resp_3_0_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c37_resp_in_valid), .l_out_flit(c37_resp_in_flit), .l_out_ready(c37_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(3), .MY_W(0)) req_r3_0_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_3_1_3_N_v), .s_in_flit(req_3_1_3_N_f), .s_in_ready(req_3_1_3_N_r),
        .s_out_valid(req_3_0_3_S_v), .s_out_flit(req_3_0_3_S_f), .s_out_ready(req_3_0_3_S_r),
        .w_in_valid(req_2_0_3_E_v), .w_in_flit(req_2_0_3_E_f), .w_in_ready(req_2_0_3_E_r),
        .w_out_valid(req_3_0_3_W_v), .w_out_flit(req_3_0_3_W_f), .w_out_ready(req_3_0_3_W_r),
        .u_in_valid(req_3_0_2_D_v), .u_in_flit(req_3_0_2_D_f), .u_in_ready(req_3_0_2_D_r),
        .u_out_valid(req_3_0_3_U_v), .u_out_flit(req_3_0_3_U_f), .u_out_ready(req_3_0_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c38_req_out_valid), .l_in_flit(c38_req_out_flit), .l_in_ready(c38_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(3), .MY_W(0)) resp_r3_0_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_3_1_3_N_v), .s_in_flit(resp_3_1_3_N_f), .s_in_ready(resp_3_1_3_N_r),
        .s_out_valid(resp_3_0_3_S_v), .s_out_flit(resp_3_0_3_S_f), .s_out_ready(resp_3_0_3_S_r),
        .w_in_valid(resp_2_0_3_E_v), .w_in_flit(resp_2_0_3_E_f), .w_in_ready(resp_2_0_3_E_r),
        .w_out_valid(resp_3_0_3_W_v), .w_out_flit(resp_3_0_3_W_f), .w_out_ready(resp_3_0_3_W_r),
        .u_in_valid(resp_3_0_2_D_v), .u_in_flit(resp_3_0_2_D_f), .u_in_ready(resp_3_0_2_D_r),
        .u_out_valid(resp_3_0_3_U_v), .u_out_flit(resp_3_0_3_U_f), .u_out_ready(resp_3_0_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c38_resp_in_valid), .l_out_flit(c38_resp_in_flit), .l_out_ready(c38_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(0), .MY_W(0)) req_r3_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_3_0_0_S_v), .n_in_flit(req_3_0_0_S_f), .n_in_ready(req_3_0_0_S_r),
        .n_out_valid(req_3_1_0_N_v), .n_out_flit(req_3_1_0_N_f), .n_out_ready(req_3_1_0_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_3_2_0_N_v), .s_in_flit(req_3_2_0_N_f), .s_in_ready(req_3_2_0_N_r),
        .s_out_valid(req_3_1_0_S_v), .s_out_flit(req_3_1_0_S_f), .s_out_ready(req_3_1_0_S_r),
        .w_in_valid(req_2_1_0_E_v), .w_in_flit(req_2_1_0_E_f), .w_in_ready(req_2_1_0_E_r),
        .w_out_valid(req_3_1_0_W_v), .w_out_flit(req_3_1_0_W_f), .w_out_ready(req_3_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_3_1_1_U_v), .d_in_flit(req_3_1_1_U_f), .d_in_ready(req_3_1_1_U_r),
        .d_out_valid(req_3_1_0_D_v), .d_out_flit(req_3_1_0_D_f), .d_out_ready(req_3_1_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c39_req_out_valid), .l_in_flit(c39_req_out_flit), .l_in_ready(c39_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(0), .MY_W(0)) resp_r3_1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_3_0_0_S_v), .n_in_flit(resp_3_0_0_S_f), .n_in_ready(resp_3_0_0_S_r),
        .n_out_valid(resp_3_1_0_N_v), .n_out_flit(resp_3_1_0_N_f), .n_out_ready(resp_3_1_0_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_3_2_0_N_v), .s_in_flit(resp_3_2_0_N_f), .s_in_ready(resp_3_2_0_N_r),
        .s_out_valid(resp_3_1_0_S_v), .s_out_flit(resp_3_1_0_S_f), .s_out_ready(resp_3_1_0_S_r),
        .w_in_valid(resp_2_1_0_E_v), .w_in_flit(resp_2_1_0_E_f), .w_in_ready(resp_2_1_0_E_r),
        .w_out_valid(resp_3_1_0_W_v), .w_out_flit(resp_3_1_0_W_f), .w_out_ready(resp_3_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_3_1_1_U_v), .d_in_flit(resp_3_1_1_U_f), .d_in_ready(resp_3_1_1_U_r),
        .d_out_valid(resp_3_1_0_D_v), .d_out_flit(resp_3_1_0_D_f), .d_out_ready(resp_3_1_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c39_resp_in_valid), .l_out_flit(c39_resp_in_flit), .l_out_ready(c39_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(1), .MY_W(0)) req_r3_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_3_0_1_S_v), .n_in_flit(req_3_0_1_S_f), .n_in_ready(req_3_0_1_S_r),
        .n_out_valid(req_3_1_1_N_v), .n_out_flit(req_3_1_1_N_f), .n_out_ready(req_3_1_1_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_3_2_1_N_v), .s_in_flit(req_3_2_1_N_f), .s_in_ready(req_3_2_1_N_r),
        .s_out_valid(req_3_1_1_S_v), .s_out_flit(req_3_1_1_S_f), .s_out_ready(req_3_1_1_S_r),
        .w_in_valid(req_2_1_1_E_v), .w_in_flit(req_2_1_1_E_f), .w_in_ready(req_2_1_1_E_r),
        .w_out_valid(req_3_1_1_W_v), .w_out_flit(req_3_1_1_W_f), .w_out_ready(req_3_1_1_W_r),
        .u_in_valid(req_3_1_0_D_v), .u_in_flit(req_3_1_0_D_f), .u_in_ready(req_3_1_0_D_r),
        .u_out_valid(req_3_1_1_U_v), .u_out_flit(req_3_1_1_U_f), .u_out_ready(req_3_1_1_U_r),
        .d_in_valid(req_3_1_2_U_v), .d_in_flit(req_3_1_2_U_f), .d_in_ready(req_3_1_2_U_r),
        .d_out_valid(req_3_1_1_D_v), .d_out_flit(req_3_1_1_D_f), .d_out_ready(req_3_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c40_req_out_valid), .l_in_flit(c40_req_out_flit), .l_in_ready(c40_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(1), .MY_W(0)) resp_r3_1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_3_0_1_S_v), .n_in_flit(resp_3_0_1_S_f), .n_in_ready(resp_3_0_1_S_r),
        .n_out_valid(resp_3_1_1_N_v), .n_out_flit(resp_3_1_1_N_f), .n_out_ready(resp_3_1_1_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_3_2_1_N_v), .s_in_flit(resp_3_2_1_N_f), .s_in_ready(resp_3_2_1_N_r),
        .s_out_valid(resp_3_1_1_S_v), .s_out_flit(resp_3_1_1_S_f), .s_out_ready(resp_3_1_1_S_r),
        .w_in_valid(resp_2_1_1_E_v), .w_in_flit(resp_2_1_1_E_f), .w_in_ready(resp_2_1_1_E_r),
        .w_out_valid(resp_3_1_1_W_v), .w_out_flit(resp_3_1_1_W_f), .w_out_ready(resp_3_1_1_W_r),
        .u_in_valid(resp_3_1_0_D_v), .u_in_flit(resp_3_1_0_D_f), .u_in_ready(resp_3_1_0_D_r),
        .u_out_valid(resp_3_1_1_U_v), .u_out_flit(resp_3_1_1_U_f), .u_out_ready(resp_3_1_1_U_r),
        .d_in_valid(resp_3_1_2_U_v), .d_in_flit(resp_3_1_2_U_f), .d_in_ready(resp_3_1_2_U_r),
        .d_out_valid(resp_3_1_1_D_v), .d_out_flit(resp_3_1_1_D_f), .d_out_ready(resp_3_1_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c40_resp_in_valid), .l_out_flit(c40_resp_in_flit), .l_out_ready(c40_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(2), .MY_W(0)) req_r3_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_3_0_2_S_v), .n_in_flit(req_3_0_2_S_f), .n_in_ready(req_3_0_2_S_r),
        .n_out_valid(req_3_1_2_N_v), .n_out_flit(req_3_1_2_N_f), .n_out_ready(req_3_1_2_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_3_2_2_N_v), .s_in_flit(req_3_2_2_N_f), .s_in_ready(req_3_2_2_N_r),
        .s_out_valid(req_3_1_2_S_v), .s_out_flit(req_3_1_2_S_f), .s_out_ready(req_3_1_2_S_r),
        .w_in_valid(req_2_1_2_E_v), .w_in_flit(req_2_1_2_E_f), .w_in_ready(req_2_1_2_E_r),
        .w_out_valid(req_3_1_2_W_v), .w_out_flit(req_3_1_2_W_f), .w_out_ready(req_3_1_2_W_r),
        .u_in_valid(req_3_1_1_D_v), .u_in_flit(req_3_1_1_D_f), .u_in_ready(req_3_1_1_D_r),
        .u_out_valid(req_3_1_2_U_v), .u_out_flit(req_3_1_2_U_f), .u_out_ready(req_3_1_2_U_r),
        .d_in_valid(req_3_1_3_U_v), .d_in_flit(req_3_1_3_U_f), .d_in_ready(req_3_1_3_U_r),
        .d_out_valid(req_3_1_2_D_v), .d_out_flit(req_3_1_2_D_f), .d_out_ready(req_3_1_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c41_req_out_valid), .l_in_flit(c41_req_out_flit), .l_in_ready(c41_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(2), .MY_W(0)) resp_r3_1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_3_0_2_S_v), .n_in_flit(resp_3_0_2_S_f), .n_in_ready(resp_3_0_2_S_r),
        .n_out_valid(resp_3_1_2_N_v), .n_out_flit(resp_3_1_2_N_f), .n_out_ready(resp_3_1_2_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_3_2_2_N_v), .s_in_flit(resp_3_2_2_N_f), .s_in_ready(resp_3_2_2_N_r),
        .s_out_valid(resp_3_1_2_S_v), .s_out_flit(resp_3_1_2_S_f), .s_out_ready(resp_3_1_2_S_r),
        .w_in_valid(resp_2_1_2_E_v), .w_in_flit(resp_2_1_2_E_f), .w_in_ready(resp_2_1_2_E_r),
        .w_out_valid(resp_3_1_2_W_v), .w_out_flit(resp_3_1_2_W_f), .w_out_ready(resp_3_1_2_W_r),
        .u_in_valid(resp_3_1_1_D_v), .u_in_flit(resp_3_1_1_D_f), .u_in_ready(resp_3_1_1_D_r),
        .u_out_valid(resp_3_1_2_U_v), .u_out_flit(resp_3_1_2_U_f), .u_out_ready(resp_3_1_2_U_r),
        .d_in_valid(resp_3_1_3_U_v), .d_in_flit(resp_3_1_3_U_f), .d_in_ready(resp_3_1_3_U_r),
        .d_out_valid(resp_3_1_2_D_v), .d_out_flit(resp_3_1_2_D_f), .d_out_ready(resp_3_1_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c41_resp_in_valid), .l_out_flit(c41_resp_in_flit), .l_out_ready(c41_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(3), .MY_W(0)) req_r3_1_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_3_0_3_S_v), .n_in_flit(req_3_0_3_S_f), .n_in_ready(req_3_0_3_S_r),
        .n_out_valid(req_3_1_3_N_v), .n_out_flit(req_3_1_3_N_f), .n_out_ready(req_3_1_3_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_3_2_3_N_v), .s_in_flit(req_3_2_3_N_f), .s_in_ready(req_3_2_3_N_r),
        .s_out_valid(req_3_1_3_S_v), .s_out_flit(req_3_1_3_S_f), .s_out_ready(req_3_1_3_S_r),
        .w_in_valid(req_2_1_3_E_v), .w_in_flit(req_2_1_3_E_f), .w_in_ready(req_2_1_3_E_r),
        .w_out_valid(req_3_1_3_W_v), .w_out_flit(req_3_1_3_W_f), .w_out_ready(req_3_1_3_W_r),
        .u_in_valid(req_3_1_2_D_v), .u_in_flit(req_3_1_2_D_f), .u_in_ready(req_3_1_2_D_r),
        .u_out_valid(req_3_1_3_U_v), .u_out_flit(req_3_1_3_U_f), .u_out_ready(req_3_1_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c42_req_out_valid), .l_in_flit(c42_req_out_flit), .l_in_ready(c42_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(3), .MY_W(0)) resp_r3_1_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_3_0_3_S_v), .n_in_flit(resp_3_0_3_S_f), .n_in_ready(resp_3_0_3_S_r),
        .n_out_valid(resp_3_1_3_N_v), .n_out_flit(resp_3_1_3_N_f), .n_out_ready(resp_3_1_3_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_3_2_3_N_v), .s_in_flit(resp_3_2_3_N_f), .s_in_ready(resp_3_2_3_N_r),
        .s_out_valid(resp_3_1_3_S_v), .s_out_flit(resp_3_1_3_S_f), .s_out_ready(resp_3_1_3_S_r),
        .w_in_valid(resp_2_1_3_E_v), .w_in_flit(resp_2_1_3_E_f), .w_in_ready(resp_2_1_3_E_r),
        .w_out_valid(resp_3_1_3_W_v), .w_out_flit(resp_3_1_3_W_f), .w_out_ready(resp_3_1_3_W_r),
        .u_in_valid(resp_3_1_2_D_v), .u_in_flit(resp_3_1_2_D_f), .u_in_ready(resp_3_1_2_D_r),
        .u_out_valid(resp_3_1_3_U_v), .u_out_flit(resp_3_1_3_U_f), .u_out_ready(resp_3_1_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c42_resp_in_valid), .l_out_flit(c42_resp_in_flit), .l_out_ready(c42_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(0), .MY_W(0)) req_r3_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_3_1_0_S_v), .n_in_flit(req_3_1_0_S_f), .n_in_ready(req_3_1_0_S_r),
        .n_out_valid(req_3_2_0_N_v), .n_out_flit(req_3_2_0_N_f), .n_out_ready(req_3_2_0_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_2_2_0_E_v), .w_in_flit(req_2_2_0_E_f), .w_in_ready(req_2_2_0_E_r),
        .w_out_valid(req_3_2_0_W_v), .w_out_flit(req_3_2_0_W_f), .w_out_ready(req_3_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(req_3_2_1_U_v), .d_in_flit(req_3_2_1_U_f), .d_in_ready(req_3_2_1_U_r),
        .d_out_valid(req_3_2_0_D_v), .d_out_flit(req_3_2_0_D_f), .d_out_ready(req_3_2_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c43_req_out_valid), .l_in_flit(c43_req_out_flit), .l_in_ready(c43_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(0), .MY_W(0)) resp_r3_2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_3_1_0_S_v), .n_in_flit(resp_3_1_0_S_f), .n_in_ready(resp_3_1_0_S_r),
        .n_out_valid(resp_3_2_0_N_v), .n_out_flit(resp_3_2_0_N_f), .n_out_ready(resp_3_2_0_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_2_2_0_E_v), .w_in_flit(resp_2_2_0_E_f), .w_in_ready(resp_2_2_0_E_r),
        .w_out_valid(resp_3_2_0_W_v), .w_out_flit(resp_3_2_0_W_f), .w_out_ready(resp_3_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(resp_3_2_1_U_v), .d_in_flit(resp_3_2_1_U_f), .d_in_ready(resp_3_2_1_U_r),
        .d_out_valid(resp_3_2_0_D_v), .d_out_flit(resp_3_2_0_D_f), .d_out_ready(resp_3_2_0_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c43_resp_in_valid), .l_out_flit(c43_resp_in_flit), .l_out_ready(c43_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(1), .MY_W(0)) req_r3_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_3_1_1_S_v), .n_in_flit(req_3_1_1_S_f), .n_in_ready(req_3_1_1_S_r),
        .n_out_valid(req_3_2_1_N_v), .n_out_flit(req_3_2_1_N_f), .n_out_ready(req_3_2_1_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_2_2_1_E_v), .w_in_flit(req_2_2_1_E_f), .w_in_ready(req_2_2_1_E_r),
        .w_out_valid(req_3_2_1_W_v), .w_out_flit(req_3_2_1_W_f), .w_out_ready(req_3_2_1_W_r),
        .u_in_valid(req_3_2_0_D_v), .u_in_flit(req_3_2_0_D_f), .u_in_ready(req_3_2_0_D_r),
        .u_out_valid(req_3_2_1_U_v), .u_out_flit(req_3_2_1_U_f), .u_out_ready(req_3_2_1_U_r),
        .d_in_valid(req_3_2_2_U_v), .d_in_flit(req_3_2_2_U_f), .d_in_ready(req_3_2_2_U_r),
        .d_out_valid(req_3_2_1_D_v), .d_out_flit(req_3_2_1_D_f), .d_out_ready(req_3_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c44_req_out_valid), .l_in_flit(c44_req_out_flit), .l_in_ready(c44_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(1), .MY_W(0)) resp_r3_2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_3_1_1_S_v), .n_in_flit(resp_3_1_1_S_f), .n_in_ready(resp_3_1_1_S_r),
        .n_out_valid(resp_3_2_1_N_v), .n_out_flit(resp_3_2_1_N_f), .n_out_ready(resp_3_2_1_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_2_2_1_E_v), .w_in_flit(resp_2_2_1_E_f), .w_in_ready(resp_2_2_1_E_r),
        .w_out_valid(resp_3_2_1_W_v), .w_out_flit(resp_3_2_1_W_f), .w_out_ready(resp_3_2_1_W_r),
        .u_in_valid(resp_3_2_0_D_v), .u_in_flit(resp_3_2_0_D_f), .u_in_ready(resp_3_2_0_D_r),
        .u_out_valid(resp_3_2_1_U_v), .u_out_flit(resp_3_2_1_U_f), .u_out_ready(resp_3_2_1_U_r),
        .d_in_valid(resp_3_2_2_U_v), .d_in_flit(resp_3_2_2_U_f), .d_in_ready(resp_3_2_2_U_r),
        .d_out_valid(resp_3_2_1_D_v), .d_out_flit(resp_3_2_1_D_f), .d_out_ready(resp_3_2_1_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c44_resp_in_valid), .l_out_flit(c44_resp_in_flit), .l_out_ready(c44_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(2), .MY_W(0)) req_r3_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_3_1_2_S_v), .n_in_flit(req_3_1_2_S_f), .n_in_ready(req_3_1_2_S_r),
        .n_out_valid(req_3_2_2_N_v), .n_out_flit(req_3_2_2_N_f), .n_out_ready(req_3_2_2_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_2_2_2_E_v), .w_in_flit(req_2_2_2_E_f), .w_in_ready(req_2_2_2_E_r),
        .w_out_valid(req_3_2_2_W_v), .w_out_flit(req_3_2_2_W_f), .w_out_ready(req_3_2_2_W_r),
        .u_in_valid(req_3_2_1_D_v), .u_in_flit(req_3_2_1_D_f), .u_in_ready(req_3_2_1_D_r),
        .u_out_valid(req_3_2_2_U_v), .u_out_flit(req_3_2_2_U_f), .u_out_ready(req_3_2_2_U_r),
        .d_in_valid(req_3_2_3_U_v), .d_in_flit(req_3_2_3_U_f), .d_in_ready(req_3_2_3_U_r),
        .d_out_valid(req_3_2_2_D_v), .d_out_flit(req_3_2_2_D_f), .d_out_ready(req_3_2_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c45_req_out_valid), .l_in_flit(c45_req_out_flit), .l_in_ready(c45_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(2), .MY_W(0)) resp_r3_2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_3_1_2_S_v), .n_in_flit(resp_3_1_2_S_f), .n_in_ready(resp_3_1_2_S_r),
        .n_out_valid(resp_3_2_2_N_v), .n_out_flit(resp_3_2_2_N_f), .n_out_ready(resp_3_2_2_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_2_2_2_E_v), .w_in_flit(resp_2_2_2_E_f), .w_in_ready(resp_2_2_2_E_r),
        .w_out_valid(resp_3_2_2_W_v), .w_out_flit(resp_3_2_2_W_f), .w_out_ready(resp_3_2_2_W_r),
        .u_in_valid(resp_3_2_1_D_v), .u_in_flit(resp_3_2_1_D_f), .u_in_ready(resp_3_2_1_D_r),
        .u_out_valid(resp_3_2_2_U_v), .u_out_flit(resp_3_2_2_U_f), .u_out_ready(resp_3_2_2_U_r),
        .d_in_valid(resp_3_2_3_U_v), .d_in_flit(resp_3_2_3_U_f), .d_in_ready(resp_3_2_3_U_r),
        .d_out_valid(resp_3_2_2_D_v), .d_out_flit(resp_3_2_2_D_f), .d_out_ready(resp_3_2_2_D_r),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c45_resp_in_valid), .l_out_flit(c45_resp_in_flit), .l_out_ready(c45_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(3), .MY_W(0)) req_r3_2_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_3_1_3_S_v), .n_in_flit(req_3_1_3_S_f), .n_in_ready(req_3_1_3_S_r),
        .n_out_valid(req_3_2_3_N_v), .n_out_flit(req_3_2_3_N_f), .n_out_ready(req_3_2_3_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_2_2_3_E_v), .w_in_flit(req_2_2_3_E_f), .w_in_ready(req_2_2_3_E_r),
        .w_out_valid(req_3_2_3_W_v), .w_out_flit(req_3_2_3_W_f), .w_out_ready(req_3_2_3_W_r),
        .u_in_valid(req_3_2_2_D_v), .u_in_flit(req_3_2_2_D_f), .u_in_ready(req_3_2_2_D_r),
        .u_out_valid(req_3_2_3_U_v), .u_out_flit(req_3_2_3_U_f), .u_out_ready(req_3_2_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c46_req_out_valid), .l_in_flit(c46_req_out_flit), .l_in_ready(c46_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(3), .MY_W(0)) resp_r3_2_3 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_3_1_3_S_v), .n_in_flit(resp_3_1_3_S_f), .n_in_ready(resp_3_1_3_S_r),
        .n_out_valid(resp_3_2_3_N_v), .n_out_flit(resp_3_2_3_N_f), .n_out_ready(resp_3_2_3_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_2_2_3_E_v), .w_in_flit(resp_2_2_3_E_f), .w_in_ready(resp_2_2_3_E_r),
        .w_out_valid(resp_3_2_3_W_v), .w_out_flit(resp_3_2_3_W_f), .w_out_ready(resp_3_2_3_W_r),
        .u_in_valid(resp_3_2_2_D_v), .u_in_flit(resp_3_2_2_D_f), .u_in_ready(resp_3_2_2_D_r),
        .u_out_valid(resp_3_2_3_U_v), .u_out_flit(resp_3_2_3_U_f), .u_out_ready(resp_3_2_3_U_r),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c46_resp_in_valid), .l_out_flit(c46_resp_in_flit), .l_out_ready(c46_resp_in_ready)
    );

    // ==================== Cores + adapters ====================
    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C0_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c0_core (
        .clk(clk), .reset(reset),
        .halted(c0_halted), .tohost_value(c0_tohost),
        .bus_req(c0_bus_req), .bus_addr(c0_bus_addr), .bus_write_data(c0_bus_write_data),
        .bus_mem_write(c0_bus_mem_write), .bus_mem_size(c0_bus_mem_size), .bus_mem_unsigned(c0_bus_mem_unsigned),
        .bus_grant(c0_bus_grant), .bus_read_data(c0_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c0_adap (
        .clk(clk), .reset(reset),
        .bus_req(c0_bus_req), .bus_addr(c0_bus_addr), .bus_write_data(c0_bus_write_data),
        .bus_mem_write(c0_bus_mem_write), .bus_mem_size(c0_bus_mem_size), .bus_mem_unsigned(c0_bus_mem_unsigned),
        .bus_grant(c0_bus_grant), .bus_read_data(c0_bus_read_data),
        .req_out_valid(c0_req_out_valid), .req_out_flit(c0_req_out_flit), .req_out_ready(c0_req_out_ready),
        .resp_in_valid(c0_resp_in_valid), .resp_in_flit(c0_resp_in_flit), .resp_in_ready(c0_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C1_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c1_core (
        .clk(clk), .reset(reset),
        .halted(c1_halted), .tohost_value(c1_tohost),
        .bus_req(c1_bus_req), .bus_addr(c1_bus_addr), .bus_write_data(c1_bus_write_data),
        .bus_mem_write(c1_bus_mem_write), .bus_mem_size(c1_bus_mem_size), .bus_mem_unsigned(c1_bus_mem_unsigned),
        .bus_grant(c1_bus_grant), .bus_read_data(c1_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c1_adap (
        .clk(clk), .reset(reset),
        .bus_req(c1_bus_req), .bus_addr(c1_bus_addr), .bus_write_data(c1_bus_write_data),
        .bus_mem_write(c1_bus_mem_write), .bus_mem_size(c1_bus_mem_size), .bus_mem_unsigned(c1_bus_mem_unsigned),
        .bus_grant(c1_bus_grant), .bus_read_data(c1_bus_read_data),
        .req_out_valid(c1_req_out_valid), .req_out_flit(c1_req_out_flit), .req_out_ready(c1_req_out_ready),
        .resp_in_valid(c1_resp_in_valid), .resp_in_flit(c1_resp_in_flit), .resp_in_ready(c1_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C2_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c2_core (
        .clk(clk), .reset(reset),
        .halted(c2_halted), .tohost_value(c2_tohost),
        .bus_req(c2_bus_req), .bus_addr(c2_bus_addr), .bus_write_data(c2_bus_write_data),
        .bus_mem_write(c2_bus_mem_write), .bus_mem_size(c2_bus_mem_size), .bus_mem_unsigned(c2_bus_mem_unsigned),
        .bus_grant(c2_bus_grant), .bus_read_data(c2_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c2_adap (
        .clk(clk), .reset(reset),
        .bus_req(c2_bus_req), .bus_addr(c2_bus_addr), .bus_write_data(c2_bus_write_data),
        .bus_mem_write(c2_bus_mem_write), .bus_mem_size(c2_bus_mem_size), .bus_mem_unsigned(c2_bus_mem_unsigned),
        .bus_grant(c2_bus_grant), .bus_read_data(c2_bus_read_data),
        .req_out_valid(c2_req_out_valid), .req_out_flit(c2_req_out_flit), .req_out_ready(c2_req_out_ready),
        .resp_in_valid(c2_resp_in_valid), .resp_in_flit(c2_resp_in_flit), .resp_in_ready(c2_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C3_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c3_core (
        .clk(clk), .reset(reset),
        .halted(c3_halted), .tohost_value(c3_tohost),
        .bus_req(c3_bus_req), .bus_addr(c3_bus_addr), .bus_write_data(c3_bus_write_data),
        .bus_mem_write(c3_bus_mem_write), .bus_mem_size(c3_bus_mem_size), .bus_mem_unsigned(c3_bus_mem_unsigned),
        .bus_grant(c3_bus_grant), .bus_read_data(c3_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c3_adap (
        .clk(clk), .reset(reset),
        .bus_req(c3_bus_req), .bus_addr(c3_bus_addr), .bus_write_data(c3_bus_write_data),
        .bus_mem_write(c3_bus_mem_write), .bus_mem_size(c3_bus_mem_size), .bus_mem_unsigned(c3_bus_mem_unsigned),
        .bus_grant(c3_bus_grant), .bus_read_data(c3_bus_read_data),
        .req_out_valid(c3_req_out_valid), .req_out_flit(c3_req_out_flit), .req_out_ready(c3_req_out_ready),
        .resp_in_valid(c3_resp_in_valid), .resp_in_flit(c3_resp_in_flit), .resp_in_ready(c3_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C4_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c4_core (
        .clk(clk), .reset(reset),
        .halted(c4_halted), .tohost_value(c4_tohost),
        .bus_req(c4_bus_req), .bus_addr(c4_bus_addr), .bus_write_data(c4_bus_write_data),
        .bus_mem_write(c4_bus_mem_write), .bus_mem_size(c4_bus_mem_size), .bus_mem_unsigned(c4_bus_mem_unsigned),
        .bus_grant(c4_bus_grant), .bus_read_data(c4_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c4_adap (
        .clk(clk), .reset(reset),
        .bus_req(c4_bus_req), .bus_addr(c4_bus_addr), .bus_write_data(c4_bus_write_data),
        .bus_mem_write(c4_bus_mem_write), .bus_mem_size(c4_bus_mem_size), .bus_mem_unsigned(c4_bus_mem_unsigned),
        .bus_grant(c4_bus_grant), .bus_read_data(c4_bus_read_data),
        .req_out_valid(c4_req_out_valid), .req_out_flit(c4_req_out_flit), .req_out_ready(c4_req_out_ready),
        .resp_in_valid(c4_resp_in_valid), .resp_in_flit(c4_resp_in_flit), .resp_in_ready(c4_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C5_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c5_core (
        .clk(clk), .reset(reset),
        .halted(c5_halted), .tohost_value(c5_tohost),
        .bus_req(c5_bus_req), .bus_addr(c5_bus_addr), .bus_write_data(c5_bus_write_data),
        .bus_mem_write(c5_bus_mem_write), .bus_mem_size(c5_bus_mem_size), .bus_mem_unsigned(c5_bus_mem_unsigned),
        .bus_grant(c5_bus_grant), .bus_read_data(c5_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c5_adap (
        .clk(clk), .reset(reset),
        .bus_req(c5_bus_req), .bus_addr(c5_bus_addr), .bus_write_data(c5_bus_write_data),
        .bus_mem_write(c5_bus_mem_write), .bus_mem_size(c5_bus_mem_size), .bus_mem_unsigned(c5_bus_mem_unsigned),
        .bus_grant(c5_bus_grant), .bus_read_data(c5_bus_read_data),
        .req_out_valid(c5_req_out_valid), .req_out_flit(c5_req_out_flit), .req_out_ready(c5_req_out_ready),
        .resp_in_valid(c5_resp_in_valid), .resp_in_flit(c5_resp_in_flit), .resp_in_ready(c5_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C6_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c6_core (
        .clk(clk), .reset(reset),
        .halted(c6_halted), .tohost_value(c6_tohost),
        .bus_req(c6_bus_req), .bus_addr(c6_bus_addr), .bus_write_data(c6_bus_write_data),
        .bus_mem_write(c6_bus_mem_write), .bus_mem_size(c6_bus_mem_size), .bus_mem_unsigned(c6_bus_mem_unsigned),
        .bus_grant(c6_bus_grant), .bus_read_data(c6_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c6_adap (
        .clk(clk), .reset(reset),
        .bus_req(c6_bus_req), .bus_addr(c6_bus_addr), .bus_write_data(c6_bus_write_data),
        .bus_mem_write(c6_bus_mem_write), .bus_mem_size(c6_bus_mem_size), .bus_mem_unsigned(c6_bus_mem_unsigned),
        .bus_grant(c6_bus_grant), .bus_read_data(c6_bus_read_data),
        .req_out_valid(c6_req_out_valid), .req_out_flit(c6_req_out_flit), .req_out_ready(c6_req_out_ready),
        .resp_in_valid(c6_resp_in_valid), .resp_in_flit(c6_resp_in_flit), .resp_in_ready(c6_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C7_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c7_core (
        .clk(clk), .reset(reset),
        .halted(c7_halted), .tohost_value(c7_tohost),
        .bus_req(c7_bus_req), .bus_addr(c7_bus_addr), .bus_write_data(c7_bus_write_data),
        .bus_mem_write(c7_bus_mem_write), .bus_mem_size(c7_bus_mem_size), .bus_mem_unsigned(c7_bus_mem_unsigned),
        .bus_grant(c7_bus_grant), .bus_read_data(c7_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c7_adap (
        .clk(clk), .reset(reset),
        .bus_req(c7_bus_req), .bus_addr(c7_bus_addr), .bus_write_data(c7_bus_write_data),
        .bus_mem_write(c7_bus_mem_write), .bus_mem_size(c7_bus_mem_size), .bus_mem_unsigned(c7_bus_mem_unsigned),
        .bus_grant(c7_bus_grant), .bus_read_data(c7_bus_read_data),
        .req_out_valid(c7_req_out_valid), .req_out_flit(c7_req_out_flit), .req_out_ready(c7_req_out_ready),
        .resp_in_valid(c7_resp_in_valid), .resp_in_flit(c7_resp_in_flit), .resp_in_ready(c7_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C8_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c8_core (
        .clk(clk), .reset(reset),
        .halted(c8_halted), .tohost_value(c8_tohost),
        .bus_req(c8_bus_req), .bus_addr(c8_bus_addr), .bus_write_data(c8_bus_write_data),
        .bus_mem_write(c8_bus_mem_write), .bus_mem_size(c8_bus_mem_size), .bus_mem_unsigned(c8_bus_mem_unsigned),
        .bus_grant(c8_bus_grant), .bus_read_data(c8_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c8_adap (
        .clk(clk), .reset(reset),
        .bus_req(c8_bus_req), .bus_addr(c8_bus_addr), .bus_write_data(c8_bus_write_data),
        .bus_mem_write(c8_bus_mem_write), .bus_mem_size(c8_bus_mem_size), .bus_mem_unsigned(c8_bus_mem_unsigned),
        .bus_grant(c8_bus_grant), .bus_read_data(c8_bus_read_data),
        .req_out_valid(c8_req_out_valid), .req_out_flit(c8_req_out_flit), .req_out_ready(c8_req_out_ready),
        .resp_in_valid(c8_resp_in_valid), .resp_in_flit(c8_resp_in_flit), .resp_in_ready(c8_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C9_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c9_core (
        .clk(clk), .reset(reset),
        .halted(c9_halted), .tohost_value(c9_tohost),
        .bus_req(c9_bus_req), .bus_addr(c9_bus_addr), .bus_write_data(c9_bus_write_data),
        .bus_mem_write(c9_bus_mem_write), .bus_mem_size(c9_bus_mem_size), .bus_mem_unsigned(c9_bus_mem_unsigned),
        .bus_grant(c9_bus_grant), .bus_read_data(c9_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c9_adap (
        .clk(clk), .reset(reset),
        .bus_req(c9_bus_req), .bus_addr(c9_bus_addr), .bus_write_data(c9_bus_write_data),
        .bus_mem_write(c9_bus_mem_write), .bus_mem_size(c9_bus_mem_size), .bus_mem_unsigned(c9_bus_mem_unsigned),
        .bus_grant(c9_bus_grant), .bus_read_data(c9_bus_read_data),
        .req_out_valid(c9_req_out_valid), .req_out_flit(c9_req_out_flit), .req_out_ready(c9_req_out_ready),
        .resp_in_valid(c9_resp_in_valid), .resp_in_flit(c9_resp_in_flit), .resp_in_ready(c9_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C10_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c10_core (
        .clk(clk), .reset(reset),
        .halted(c10_halted), .tohost_value(c10_tohost),
        .bus_req(c10_bus_req), .bus_addr(c10_bus_addr), .bus_write_data(c10_bus_write_data),
        .bus_mem_write(c10_bus_mem_write), .bus_mem_size(c10_bus_mem_size), .bus_mem_unsigned(c10_bus_mem_unsigned),
        .bus_grant(c10_bus_grant), .bus_read_data(c10_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c10_adap (
        .clk(clk), .reset(reset),
        .bus_req(c10_bus_req), .bus_addr(c10_bus_addr), .bus_write_data(c10_bus_write_data),
        .bus_mem_write(c10_bus_mem_write), .bus_mem_size(c10_bus_mem_size), .bus_mem_unsigned(c10_bus_mem_unsigned),
        .bus_grant(c10_bus_grant), .bus_read_data(c10_bus_read_data),
        .req_out_valid(c10_req_out_valid), .req_out_flit(c10_req_out_flit), .req_out_ready(c10_req_out_ready),
        .resp_in_valid(c10_resp_in_valid), .resp_in_flit(c10_resp_in_flit), .resp_in_ready(c10_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C11_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c11_core (
        .clk(clk), .reset(reset),
        .halted(c11_halted), .tohost_value(c11_tohost),
        .bus_req(c11_bus_req), .bus_addr(c11_bus_addr), .bus_write_data(c11_bus_write_data),
        .bus_mem_write(c11_bus_mem_write), .bus_mem_size(c11_bus_mem_size), .bus_mem_unsigned(c11_bus_mem_unsigned),
        .bus_grant(c11_bus_grant), .bus_read_data(c11_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c11_adap (
        .clk(clk), .reset(reset),
        .bus_req(c11_bus_req), .bus_addr(c11_bus_addr), .bus_write_data(c11_bus_write_data),
        .bus_mem_write(c11_bus_mem_write), .bus_mem_size(c11_bus_mem_size), .bus_mem_unsigned(c11_bus_mem_unsigned),
        .bus_grant(c11_bus_grant), .bus_read_data(c11_bus_read_data),
        .req_out_valid(c11_req_out_valid), .req_out_flit(c11_req_out_flit), .req_out_ready(c11_req_out_ready),
        .resp_in_valid(c11_resp_in_valid), .resp_in_flit(c11_resp_in_flit), .resp_in_ready(c11_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C12_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c12_core (
        .clk(clk), .reset(reset),
        .halted(c12_halted), .tohost_value(c12_tohost),
        .bus_req(c12_bus_req), .bus_addr(c12_bus_addr), .bus_write_data(c12_bus_write_data),
        .bus_mem_write(c12_bus_mem_write), .bus_mem_size(c12_bus_mem_size), .bus_mem_unsigned(c12_bus_mem_unsigned),
        .bus_grant(c12_bus_grant), .bus_read_data(c12_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c12_adap (
        .clk(clk), .reset(reset),
        .bus_req(c12_bus_req), .bus_addr(c12_bus_addr), .bus_write_data(c12_bus_write_data),
        .bus_mem_write(c12_bus_mem_write), .bus_mem_size(c12_bus_mem_size), .bus_mem_unsigned(c12_bus_mem_unsigned),
        .bus_grant(c12_bus_grant), .bus_read_data(c12_bus_read_data),
        .req_out_valid(c12_req_out_valid), .req_out_flit(c12_req_out_flit), .req_out_ready(c12_req_out_ready),
        .resp_in_valid(c12_resp_in_valid), .resp_in_flit(c12_resp_in_flit), .resp_in_ready(c12_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C13_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c13_core (
        .clk(clk), .reset(reset),
        .halted(c13_halted), .tohost_value(c13_tohost),
        .bus_req(c13_bus_req), .bus_addr(c13_bus_addr), .bus_write_data(c13_bus_write_data),
        .bus_mem_write(c13_bus_mem_write), .bus_mem_size(c13_bus_mem_size), .bus_mem_unsigned(c13_bus_mem_unsigned),
        .bus_grant(c13_bus_grant), .bus_read_data(c13_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c13_adap (
        .clk(clk), .reset(reset),
        .bus_req(c13_bus_req), .bus_addr(c13_bus_addr), .bus_write_data(c13_bus_write_data),
        .bus_mem_write(c13_bus_mem_write), .bus_mem_size(c13_bus_mem_size), .bus_mem_unsigned(c13_bus_mem_unsigned),
        .bus_grant(c13_bus_grant), .bus_read_data(c13_bus_read_data),
        .req_out_valid(c13_req_out_valid), .req_out_flit(c13_req_out_flit), .req_out_ready(c13_req_out_ready),
        .resp_in_valid(c13_resp_in_valid), .resp_in_flit(c13_resp_in_flit), .resp_in_ready(c13_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C14_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c14_core (
        .clk(clk), .reset(reset),
        .halted(c14_halted), .tohost_value(c14_tohost),
        .bus_req(c14_bus_req), .bus_addr(c14_bus_addr), .bus_write_data(c14_bus_write_data),
        .bus_mem_write(c14_bus_mem_write), .bus_mem_size(c14_bus_mem_size), .bus_mem_unsigned(c14_bus_mem_unsigned),
        .bus_grant(c14_bus_grant), .bus_read_data(c14_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c14_adap (
        .clk(clk), .reset(reset),
        .bus_req(c14_bus_req), .bus_addr(c14_bus_addr), .bus_write_data(c14_bus_write_data),
        .bus_mem_write(c14_bus_mem_write), .bus_mem_size(c14_bus_mem_size), .bus_mem_unsigned(c14_bus_mem_unsigned),
        .bus_grant(c14_bus_grant), .bus_read_data(c14_bus_read_data),
        .req_out_valid(c14_req_out_valid), .req_out_flit(c14_req_out_flit), .req_out_ready(c14_req_out_ready),
        .resp_in_valid(c14_resp_in_valid), .resp_in_flit(c14_resp_in_flit), .resp_in_ready(c14_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C15_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c15_core (
        .clk(clk), .reset(reset),
        .halted(c15_halted), .tohost_value(c15_tohost),
        .bus_req(c15_bus_req), .bus_addr(c15_bus_addr), .bus_write_data(c15_bus_write_data),
        .bus_mem_write(c15_bus_mem_write), .bus_mem_size(c15_bus_mem_size), .bus_mem_unsigned(c15_bus_mem_unsigned),
        .bus_grant(c15_bus_grant), .bus_read_data(c15_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c15_adap (
        .clk(clk), .reset(reset),
        .bus_req(c15_bus_req), .bus_addr(c15_bus_addr), .bus_write_data(c15_bus_write_data),
        .bus_mem_write(c15_bus_mem_write), .bus_mem_size(c15_bus_mem_size), .bus_mem_unsigned(c15_bus_mem_unsigned),
        .bus_grant(c15_bus_grant), .bus_read_data(c15_bus_read_data),
        .req_out_valid(c15_req_out_valid), .req_out_flit(c15_req_out_flit), .req_out_ready(c15_req_out_ready),
        .resp_in_valid(c15_resp_in_valid), .resp_in_flit(c15_resp_in_flit), .resp_in_ready(c15_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C16_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c16_core (
        .clk(clk), .reset(reset),
        .halted(c16_halted), .tohost_value(c16_tohost),
        .bus_req(c16_bus_req), .bus_addr(c16_bus_addr), .bus_write_data(c16_bus_write_data),
        .bus_mem_write(c16_bus_mem_write), .bus_mem_size(c16_bus_mem_size), .bus_mem_unsigned(c16_bus_mem_unsigned),
        .bus_grant(c16_bus_grant), .bus_read_data(c16_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c16_adap (
        .clk(clk), .reset(reset),
        .bus_req(c16_bus_req), .bus_addr(c16_bus_addr), .bus_write_data(c16_bus_write_data),
        .bus_mem_write(c16_bus_mem_write), .bus_mem_size(c16_bus_mem_size), .bus_mem_unsigned(c16_bus_mem_unsigned),
        .bus_grant(c16_bus_grant), .bus_read_data(c16_bus_read_data),
        .req_out_valid(c16_req_out_valid), .req_out_flit(c16_req_out_flit), .req_out_ready(c16_req_out_ready),
        .resp_in_valid(c16_resp_in_valid), .resp_in_flit(c16_resp_in_flit), .resp_in_ready(c16_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C17_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c17_core (
        .clk(clk), .reset(reset),
        .halted(c17_halted), .tohost_value(c17_tohost),
        .bus_req(c17_bus_req), .bus_addr(c17_bus_addr), .bus_write_data(c17_bus_write_data),
        .bus_mem_write(c17_bus_mem_write), .bus_mem_size(c17_bus_mem_size), .bus_mem_unsigned(c17_bus_mem_unsigned),
        .bus_grant(c17_bus_grant), .bus_read_data(c17_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c17_adap (
        .clk(clk), .reset(reset),
        .bus_req(c17_bus_req), .bus_addr(c17_bus_addr), .bus_write_data(c17_bus_write_data),
        .bus_mem_write(c17_bus_mem_write), .bus_mem_size(c17_bus_mem_size), .bus_mem_unsigned(c17_bus_mem_unsigned),
        .bus_grant(c17_bus_grant), .bus_read_data(c17_bus_read_data),
        .req_out_valid(c17_req_out_valid), .req_out_flit(c17_req_out_flit), .req_out_ready(c17_req_out_ready),
        .resp_in_valid(c17_resp_in_valid), .resp_in_flit(c17_resp_in_flit), .resp_in_ready(c17_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C18_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c18_core (
        .clk(clk), .reset(reset),
        .halted(c18_halted), .tohost_value(c18_tohost),
        .bus_req(c18_bus_req), .bus_addr(c18_bus_addr), .bus_write_data(c18_bus_write_data),
        .bus_mem_write(c18_bus_mem_write), .bus_mem_size(c18_bus_mem_size), .bus_mem_unsigned(c18_bus_mem_unsigned),
        .bus_grant(c18_bus_grant), .bus_read_data(c18_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c18_adap (
        .clk(clk), .reset(reset),
        .bus_req(c18_bus_req), .bus_addr(c18_bus_addr), .bus_write_data(c18_bus_write_data),
        .bus_mem_write(c18_bus_mem_write), .bus_mem_size(c18_bus_mem_size), .bus_mem_unsigned(c18_bus_mem_unsigned),
        .bus_grant(c18_bus_grant), .bus_read_data(c18_bus_read_data),
        .req_out_valid(c18_req_out_valid), .req_out_flit(c18_req_out_flit), .req_out_ready(c18_req_out_ready),
        .resp_in_valid(c18_resp_in_valid), .resp_in_flit(c18_resp_in_flit), .resp_in_ready(c18_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C19_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c19_core (
        .clk(clk), .reset(reset),
        .halted(c19_halted), .tohost_value(c19_tohost),
        .bus_req(c19_bus_req), .bus_addr(c19_bus_addr), .bus_write_data(c19_bus_write_data),
        .bus_mem_write(c19_bus_mem_write), .bus_mem_size(c19_bus_mem_size), .bus_mem_unsigned(c19_bus_mem_unsigned),
        .bus_grant(c19_bus_grant), .bus_read_data(c19_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c19_adap (
        .clk(clk), .reset(reset),
        .bus_req(c19_bus_req), .bus_addr(c19_bus_addr), .bus_write_data(c19_bus_write_data),
        .bus_mem_write(c19_bus_mem_write), .bus_mem_size(c19_bus_mem_size), .bus_mem_unsigned(c19_bus_mem_unsigned),
        .bus_grant(c19_bus_grant), .bus_read_data(c19_bus_read_data),
        .req_out_valid(c19_req_out_valid), .req_out_flit(c19_req_out_flit), .req_out_ready(c19_req_out_ready),
        .resp_in_valid(c19_resp_in_valid), .resp_in_flit(c19_resp_in_flit), .resp_in_ready(c19_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C20_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c20_core (
        .clk(clk), .reset(reset),
        .halted(c20_halted), .tohost_value(c20_tohost),
        .bus_req(c20_bus_req), .bus_addr(c20_bus_addr), .bus_write_data(c20_bus_write_data),
        .bus_mem_write(c20_bus_mem_write), .bus_mem_size(c20_bus_mem_size), .bus_mem_unsigned(c20_bus_mem_unsigned),
        .bus_grant(c20_bus_grant), .bus_read_data(c20_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c20_adap (
        .clk(clk), .reset(reset),
        .bus_req(c20_bus_req), .bus_addr(c20_bus_addr), .bus_write_data(c20_bus_write_data),
        .bus_mem_write(c20_bus_mem_write), .bus_mem_size(c20_bus_mem_size), .bus_mem_unsigned(c20_bus_mem_unsigned),
        .bus_grant(c20_bus_grant), .bus_read_data(c20_bus_read_data),
        .req_out_valid(c20_req_out_valid), .req_out_flit(c20_req_out_flit), .req_out_ready(c20_req_out_ready),
        .resp_in_valid(c20_resp_in_valid), .resp_in_flit(c20_resp_in_flit), .resp_in_ready(c20_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C21_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c21_core (
        .clk(clk), .reset(reset),
        .halted(c21_halted), .tohost_value(c21_tohost),
        .bus_req(c21_bus_req), .bus_addr(c21_bus_addr), .bus_write_data(c21_bus_write_data),
        .bus_mem_write(c21_bus_mem_write), .bus_mem_size(c21_bus_mem_size), .bus_mem_unsigned(c21_bus_mem_unsigned),
        .bus_grant(c21_bus_grant), .bus_read_data(c21_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c21_adap (
        .clk(clk), .reset(reset),
        .bus_req(c21_bus_req), .bus_addr(c21_bus_addr), .bus_write_data(c21_bus_write_data),
        .bus_mem_write(c21_bus_mem_write), .bus_mem_size(c21_bus_mem_size), .bus_mem_unsigned(c21_bus_mem_unsigned),
        .bus_grant(c21_bus_grant), .bus_read_data(c21_bus_read_data),
        .req_out_valid(c21_req_out_valid), .req_out_flit(c21_req_out_flit), .req_out_ready(c21_req_out_ready),
        .resp_in_valid(c21_resp_in_valid), .resp_in_flit(c21_resp_in_flit), .resp_in_ready(c21_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C22_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c22_core (
        .clk(clk), .reset(reset),
        .halted(c22_halted), .tohost_value(c22_tohost),
        .bus_req(c22_bus_req), .bus_addr(c22_bus_addr), .bus_write_data(c22_bus_write_data),
        .bus_mem_write(c22_bus_mem_write), .bus_mem_size(c22_bus_mem_size), .bus_mem_unsigned(c22_bus_mem_unsigned),
        .bus_grant(c22_bus_grant), .bus_read_data(c22_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c22_adap (
        .clk(clk), .reset(reset),
        .bus_req(c22_bus_req), .bus_addr(c22_bus_addr), .bus_write_data(c22_bus_write_data),
        .bus_mem_write(c22_bus_mem_write), .bus_mem_size(c22_bus_mem_size), .bus_mem_unsigned(c22_bus_mem_unsigned),
        .bus_grant(c22_bus_grant), .bus_read_data(c22_bus_read_data),
        .req_out_valid(c22_req_out_valid), .req_out_flit(c22_req_out_flit), .req_out_ready(c22_req_out_ready),
        .resp_in_valid(c22_resp_in_valid), .resp_in_flit(c22_resp_in_flit), .resp_in_ready(c22_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C23_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c23_core (
        .clk(clk), .reset(reset),
        .halted(c23_halted), .tohost_value(c23_tohost),
        .bus_req(c23_bus_req), .bus_addr(c23_bus_addr), .bus_write_data(c23_bus_write_data),
        .bus_mem_write(c23_bus_mem_write), .bus_mem_size(c23_bus_mem_size), .bus_mem_unsigned(c23_bus_mem_unsigned),
        .bus_grant(c23_bus_grant), .bus_read_data(c23_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c23_adap (
        .clk(clk), .reset(reset),
        .bus_req(c23_bus_req), .bus_addr(c23_bus_addr), .bus_write_data(c23_bus_write_data),
        .bus_mem_write(c23_bus_mem_write), .bus_mem_size(c23_bus_mem_size), .bus_mem_unsigned(c23_bus_mem_unsigned),
        .bus_grant(c23_bus_grant), .bus_read_data(c23_bus_read_data),
        .req_out_valid(c23_req_out_valid), .req_out_flit(c23_req_out_flit), .req_out_ready(c23_req_out_ready),
        .resp_in_valid(c23_resp_in_valid), .resp_in_flit(c23_resp_in_flit), .resp_in_ready(c23_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C24_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c24_core (
        .clk(clk), .reset(reset),
        .halted(c24_halted), .tohost_value(c24_tohost),
        .bus_req(c24_bus_req), .bus_addr(c24_bus_addr), .bus_write_data(c24_bus_write_data),
        .bus_mem_write(c24_bus_mem_write), .bus_mem_size(c24_bus_mem_size), .bus_mem_unsigned(c24_bus_mem_unsigned),
        .bus_grant(c24_bus_grant), .bus_read_data(c24_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c24_adap (
        .clk(clk), .reset(reset),
        .bus_req(c24_bus_req), .bus_addr(c24_bus_addr), .bus_write_data(c24_bus_write_data),
        .bus_mem_write(c24_bus_mem_write), .bus_mem_size(c24_bus_mem_size), .bus_mem_unsigned(c24_bus_mem_unsigned),
        .bus_grant(c24_bus_grant), .bus_read_data(c24_bus_read_data),
        .req_out_valid(c24_req_out_valid), .req_out_flit(c24_req_out_flit), .req_out_ready(c24_req_out_ready),
        .resp_in_valid(c24_resp_in_valid), .resp_in_flit(c24_resp_in_flit), .resp_in_ready(c24_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C25_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c25_core (
        .clk(clk), .reset(reset),
        .halted(c25_halted), .tohost_value(c25_tohost),
        .bus_req(c25_bus_req), .bus_addr(c25_bus_addr), .bus_write_data(c25_bus_write_data),
        .bus_mem_write(c25_bus_mem_write), .bus_mem_size(c25_bus_mem_size), .bus_mem_unsigned(c25_bus_mem_unsigned),
        .bus_grant(c25_bus_grant), .bus_read_data(c25_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c25_adap (
        .clk(clk), .reset(reset),
        .bus_req(c25_bus_req), .bus_addr(c25_bus_addr), .bus_write_data(c25_bus_write_data),
        .bus_mem_write(c25_bus_mem_write), .bus_mem_size(c25_bus_mem_size), .bus_mem_unsigned(c25_bus_mem_unsigned),
        .bus_grant(c25_bus_grant), .bus_read_data(c25_bus_read_data),
        .req_out_valid(c25_req_out_valid), .req_out_flit(c25_req_out_flit), .req_out_ready(c25_req_out_ready),
        .resp_in_valid(c25_resp_in_valid), .resp_in_flit(c25_resp_in_flit), .resp_in_ready(c25_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C26_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c26_core (
        .clk(clk), .reset(reset),
        .halted(c26_halted), .tohost_value(c26_tohost),
        .bus_req(c26_bus_req), .bus_addr(c26_bus_addr), .bus_write_data(c26_bus_write_data),
        .bus_mem_write(c26_bus_mem_write), .bus_mem_size(c26_bus_mem_size), .bus_mem_unsigned(c26_bus_mem_unsigned),
        .bus_grant(c26_bus_grant), .bus_read_data(c26_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c26_adap (
        .clk(clk), .reset(reset),
        .bus_req(c26_bus_req), .bus_addr(c26_bus_addr), .bus_write_data(c26_bus_write_data),
        .bus_mem_write(c26_bus_mem_write), .bus_mem_size(c26_bus_mem_size), .bus_mem_unsigned(c26_bus_mem_unsigned),
        .bus_grant(c26_bus_grant), .bus_read_data(c26_bus_read_data),
        .req_out_valid(c26_req_out_valid), .req_out_flit(c26_req_out_flit), .req_out_ready(c26_req_out_ready),
        .resp_in_valid(c26_resp_in_valid), .resp_in_flit(c26_resp_in_flit), .resp_in_ready(c26_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C27_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c27_core (
        .clk(clk), .reset(reset),
        .halted(c27_halted), .tohost_value(c27_tohost),
        .bus_req(c27_bus_req), .bus_addr(c27_bus_addr), .bus_write_data(c27_bus_write_data),
        .bus_mem_write(c27_bus_mem_write), .bus_mem_size(c27_bus_mem_size), .bus_mem_unsigned(c27_bus_mem_unsigned),
        .bus_grant(c27_bus_grant), .bus_read_data(c27_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c27_adap (
        .clk(clk), .reset(reset),
        .bus_req(c27_bus_req), .bus_addr(c27_bus_addr), .bus_write_data(c27_bus_write_data),
        .bus_mem_write(c27_bus_mem_write), .bus_mem_size(c27_bus_mem_size), .bus_mem_unsigned(c27_bus_mem_unsigned),
        .bus_grant(c27_bus_grant), .bus_read_data(c27_bus_read_data),
        .req_out_valid(c27_req_out_valid), .req_out_flit(c27_req_out_flit), .req_out_ready(c27_req_out_ready),
        .resp_in_valid(c27_resp_in_valid), .resp_in_flit(c27_resp_in_flit), .resp_in_ready(c27_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C28_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c28_core (
        .clk(clk), .reset(reset),
        .halted(c28_halted), .tohost_value(c28_tohost),
        .bus_req(c28_bus_req), .bus_addr(c28_bus_addr), .bus_write_data(c28_bus_write_data),
        .bus_mem_write(c28_bus_mem_write), .bus_mem_size(c28_bus_mem_size), .bus_mem_unsigned(c28_bus_mem_unsigned),
        .bus_grant(c28_bus_grant), .bus_read_data(c28_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c28_adap (
        .clk(clk), .reset(reset),
        .bus_req(c28_bus_req), .bus_addr(c28_bus_addr), .bus_write_data(c28_bus_write_data),
        .bus_mem_write(c28_bus_mem_write), .bus_mem_size(c28_bus_mem_size), .bus_mem_unsigned(c28_bus_mem_unsigned),
        .bus_grant(c28_bus_grant), .bus_read_data(c28_bus_read_data),
        .req_out_valid(c28_req_out_valid), .req_out_flit(c28_req_out_flit), .req_out_ready(c28_req_out_ready),
        .resp_in_valid(c28_resp_in_valid), .resp_in_flit(c28_resp_in_flit), .resp_in_ready(c28_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C29_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c29_core (
        .clk(clk), .reset(reset),
        .halted(c29_halted), .tohost_value(c29_tohost),
        .bus_req(c29_bus_req), .bus_addr(c29_bus_addr), .bus_write_data(c29_bus_write_data),
        .bus_mem_write(c29_bus_mem_write), .bus_mem_size(c29_bus_mem_size), .bus_mem_unsigned(c29_bus_mem_unsigned),
        .bus_grant(c29_bus_grant), .bus_read_data(c29_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c29_adap (
        .clk(clk), .reset(reset),
        .bus_req(c29_bus_req), .bus_addr(c29_bus_addr), .bus_write_data(c29_bus_write_data),
        .bus_mem_write(c29_bus_mem_write), .bus_mem_size(c29_bus_mem_size), .bus_mem_unsigned(c29_bus_mem_unsigned),
        .bus_grant(c29_bus_grant), .bus_read_data(c29_bus_read_data),
        .req_out_valid(c29_req_out_valid), .req_out_flit(c29_req_out_flit), .req_out_ready(c29_req_out_ready),
        .resp_in_valid(c29_resp_in_valid), .resp_in_flit(c29_resp_in_flit), .resp_in_ready(c29_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C30_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c30_core (
        .clk(clk), .reset(reset),
        .halted(c30_halted), .tohost_value(c30_tohost),
        .bus_req(c30_bus_req), .bus_addr(c30_bus_addr), .bus_write_data(c30_bus_write_data),
        .bus_mem_write(c30_bus_mem_write), .bus_mem_size(c30_bus_mem_size), .bus_mem_unsigned(c30_bus_mem_unsigned),
        .bus_grant(c30_bus_grant), .bus_read_data(c30_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c30_adap (
        .clk(clk), .reset(reset),
        .bus_req(c30_bus_req), .bus_addr(c30_bus_addr), .bus_write_data(c30_bus_write_data),
        .bus_mem_write(c30_bus_mem_write), .bus_mem_size(c30_bus_mem_size), .bus_mem_unsigned(c30_bus_mem_unsigned),
        .bus_grant(c30_bus_grant), .bus_read_data(c30_bus_read_data),
        .req_out_valid(c30_req_out_valid), .req_out_flit(c30_req_out_flit), .req_out_ready(c30_req_out_ready),
        .resp_in_valid(c30_resp_in_valid), .resp_in_flit(c30_resp_in_flit), .resp_in_ready(c30_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C31_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c31_core (
        .clk(clk), .reset(reset),
        .halted(c31_halted), .tohost_value(c31_tohost),
        .bus_req(c31_bus_req), .bus_addr(c31_bus_addr), .bus_write_data(c31_bus_write_data),
        .bus_mem_write(c31_bus_mem_write), .bus_mem_size(c31_bus_mem_size), .bus_mem_unsigned(c31_bus_mem_unsigned),
        .bus_grant(c31_bus_grant), .bus_read_data(c31_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c31_adap (
        .clk(clk), .reset(reset),
        .bus_req(c31_bus_req), .bus_addr(c31_bus_addr), .bus_write_data(c31_bus_write_data),
        .bus_mem_write(c31_bus_mem_write), .bus_mem_size(c31_bus_mem_size), .bus_mem_unsigned(c31_bus_mem_unsigned),
        .bus_grant(c31_bus_grant), .bus_read_data(c31_bus_read_data),
        .req_out_valid(c31_req_out_valid), .req_out_flit(c31_req_out_flit), .req_out_ready(c31_req_out_ready),
        .resp_in_valid(c31_resp_in_valid), .resp_in_flit(c31_resp_in_flit), .resp_in_ready(c31_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C32_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c32_core (
        .clk(clk), .reset(reset),
        .halted(c32_halted), .tohost_value(c32_tohost),
        .bus_req(c32_bus_req), .bus_addr(c32_bus_addr), .bus_write_data(c32_bus_write_data),
        .bus_mem_write(c32_bus_mem_write), .bus_mem_size(c32_bus_mem_size), .bus_mem_unsigned(c32_bus_mem_unsigned),
        .bus_grant(c32_bus_grant), .bus_read_data(c32_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c32_adap (
        .clk(clk), .reset(reset),
        .bus_req(c32_bus_req), .bus_addr(c32_bus_addr), .bus_write_data(c32_bus_write_data),
        .bus_mem_write(c32_bus_mem_write), .bus_mem_size(c32_bus_mem_size), .bus_mem_unsigned(c32_bus_mem_unsigned),
        .bus_grant(c32_bus_grant), .bus_read_data(c32_bus_read_data),
        .req_out_valid(c32_req_out_valid), .req_out_flit(c32_req_out_flit), .req_out_ready(c32_req_out_ready),
        .resp_in_valid(c32_resp_in_valid), .resp_in_flit(c32_resp_in_flit), .resp_in_ready(c32_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C33_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c33_core (
        .clk(clk), .reset(reset),
        .halted(c33_halted), .tohost_value(c33_tohost),
        .bus_req(c33_bus_req), .bus_addr(c33_bus_addr), .bus_write_data(c33_bus_write_data),
        .bus_mem_write(c33_bus_mem_write), .bus_mem_size(c33_bus_mem_size), .bus_mem_unsigned(c33_bus_mem_unsigned),
        .bus_grant(c33_bus_grant), .bus_read_data(c33_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c33_adap (
        .clk(clk), .reset(reset),
        .bus_req(c33_bus_req), .bus_addr(c33_bus_addr), .bus_write_data(c33_bus_write_data),
        .bus_mem_write(c33_bus_mem_write), .bus_mem_size(c33_bus_mem_size), .bus_mem_unsigned(c33_bus_mem_unsigned),
        .bus_grant(c33_bus_grant), .bus_read_data(c33_bus_read_data),
        .req_out_valid(c33_req_out_valid), .req_out_flit(c33_req_out_flit), .req_out_ready(c33_req_out_ready),
        .resp_in_valid(c33_resp_in_valid), .resp_in_flit(c33_resp_in_flit), .resp_in_ready(c33_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C34_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c34_core (
        .clk(clk), .reset(reset),
        .halted(c34_halted), .tohost_value(c34_tohost),
        .bus_req(c34_bus_req), .bus_addr(c34_bus_addr), .bus_write_data(c34_bus_write_data),
        .bus_mem_write(c34_bus_mem_write), .bus_mem_size(c34_bus_mem_size), .bus_mem_unsigned(c34_bus_mem_unsigned),
        .bus_grant(c34_bus_grant), .bus_read_data(c34_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c34_adap (
        .clk(clk), .reset(reset),
        .bus_req(c34_bus_req), .bus_addr(c34_bus_addr), .bus_write_data(c34_bus_write_data),
        .bus_mem_write(c34_bus_mem_write), .bus_mem_size(c34_bus_mem_size), .bus_mem_unsigned(c34_bus_mem_unsigned),
        .bus_grant(c34_bus_grant), .bus_read_data(c34_bus_read_data),
        .req_out_valid(c34_req_out_valid), .req_out_flit(c34_req_out_flit), .req_out_ready(c34_req_out_ready),
        .resp_in_valid(c34_resp_in_valid), .resp_in_flit(c34_resp_in_flit), .resp_in_ready(c34_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C35_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c35_core (
        .clk(clk), .reset(reset),
        .halted(c35_halted), .tohost_value(c35_tohost),
        .bus_req(c35_bus_req), .bus_addr(c35_bus_addr), .bus_write_data(c35_bus_write_data),
        .bus_mem_write(c35_bus_mem_write), .bus_mem_size(c35_bus_mem_size), .bus_mem_unsigned(c35_bus_mem_unsigned),
        .bus_grant(c35_bus_grant), .bus_read_data(c35_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c35_adap (
        .clk(clk), .reset(reset),
        .bus_req(c35_bus_req), .bus_addr(c35_bus_addr), .bus_write_data(c35_bus_write_data),
        .bus_mem_write(c35_bus_mem_write), .bus_mem_size(c35_bus_mem_size), .bus_mem_unsigned(c35_bus_mem_unsigned),
        .bus_grant(c35_bus_grant), .bus_read_data(c35_bus_read_data),
        .req_out_valid(c35_req_out_valid), .req_out_flit(c35_req_out_flit), .req_out_ready(c35_req_out_ready),
        .resp_in_valid(c35_resp_in_valid), .resp_in_flit(c35_resp_in_flit), .resp_in_ready(c35_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C36_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c36_core (
        .clk(clk), .reset(reset),
        .halted(c36_halted), .tohost_value(c36_tohost),
        .bus_req(c36_bus_req), .bus_addr(c36_bus_addr), .bus_write_data(c36_bus_write_data),
        .bus_mem_write(c36_bus_mem_write), .bus_mem_size(c36_bus_mem_size), .bus_mem_unsigned(c36_bus_mem_unsigned),
        .bus_grant(c36_bus_grant), .bus_read_data(c36_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c36_adap (
        .clk(clk), .reset(reset),
        .bus_req(c36_bus_req), .bus_addr(c36_bus_addr), .bus_write_data(c36_bus_write_data),
        .bus_mem_write(c36_bus_mem_write), .bus_mem_size(c36_bus_mem_size), .bus_mem_unsigned(c36_bus_mem_unsigned),
        .bus_grant(c36_bus_grant), .bus_read_data(c36_bus_read_data),
        .req_out_valid(c36_req_out_valid), .req_out_flit(c36_req_out_flit), .req_out_ready(c36_req_out_ready),
        .resp_in_valid(c36_resp_in_valid), .resp_in_flit(c36_resp_in_flit), .resp_in_ready(c36_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C37_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c37_core (
        .clk(clk), .reset(reset),
        .halted(c37_halted), .tohost_value(c37_tohost),
        .bus_req(c37_bus_req), .bus_addr(c37_bus_addr), .bus_write_data(c37_bus_write_data),
        .bus_mem_write(c37_bus_mem_write), .bus_mem_size(c37_bus_mem_size), .bus_mem_unsigned(c37_bus_mem_unsigned),
        .bus_grant(c37_bus_grant), .bus_read_data(c37_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c37_adap (
        .clk(clk), .reset(reset),
        .bus_req(c37_bus_req), .bus_addr(c37_bus_addr), .bus_write_data(c37_bus_write_data),
        .bus_mem_write(c37_bus_mem_write), .bus_mem_size(c37_bus_mem_size), .bus_mem_unsigned(c37_bus_mem_unsigned),
        .bus_grant(c37_bus_grant), .bus_read_data(c37_bus_read_data),
        .req_out_valid(c37_req_out_valid), .req_out_flit(c37_req_out_flit), .req_out_ready(c37_req_out_ready),
        .resp_in_valid(c37_resp_in_valid), .resp_in_flit(c37_resp_in_flit), .resp_in_ready(c37_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C38_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c38_core (
        .clk(clk), .reset(reset),
        .halted(c38_halted), .tohost_value(c38_tohost),
        .bus_req(c38_bus_req), .bus_addr(c38_bus_addr), .bus_write_data(c38_bus_write_data),
        .bus_mem_write(c38_bus_mem_write), .bus_mem_size(c38_bus_mem_size), .bus_mem_unsigned(c38_bus_mem_unsigned),
        .bus_grant(c38_bus_grant), .bus_read_data(c38_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(0), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c38_adap (
        .clk(clk), .reset(reset),
        .bus_req(c38_bus_req), .bus_addr(c38_bus_addr), .bus_write_data(c38_bus_write_data),
        .bus_mem_write(c38_bus_mem_write), .bus_mem_size(c38_bus_mem_size), .bus_mem_unsigned(c38_bus_mem_unsigned),
        .bus_grant(c38_bus_grant), .bus_read_data(c38_bus_read_data),
        .req_out_valid(c38_req_out_valid), .req_out_flit(c38_req_out_flit), .req_out_ready(c38_req_out_ready),
        .resp_in_valid(c38_resp_in_valid), .resp_in_flit(c38_resp_in_flit), .resp_in_ready(c38_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C39_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c39_core (
        .clk(clk), .reset(reset),
        .halted(c39_halted), .tohost_value(c39_tohost),
        .bus_req(c39_bus_req), .bus_addr(c39_bus_addr), .bus_write_data(c39_bus_write_data),
        .bus_mem_write(c39_bus_mem_write), .bus_mem_size(c39_bus_mem_size), .bus_mem_unsigned(c39_bus_mem_unsigned),
        .bus_grant(c39_bus_grant), .bus_read_data(c39_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c39_adap (
        .clk(clk), .reset(reset),
        .bus_req(c39_bus_req), .bus_addr(c39_bus_addr), .bus_write_data(c39_bus_write_data),
        .bus_mem_write(c39_bus_mem_write), .bus_mem_size(c39_bus_mem_size), .bus_mem_unsigned(c39_bus_mem_unsigned),
        .bus_grant(c39_bus_grant), .bus_read_data(c39_bus_read_data),
        .req_out_valid(c39_req_out_valid), .req_out_flit(c39_req_out_flit), .req_out_ready(c39_req_out_ready),
        .resp_in_valid(c39_resp_in_valid), .resp_in_flit(c39_resp_in_flit), .resp_in_ready(c39_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C40_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c40_core (
        .clk(clk), .reset(reset),
        .halted(c40_halted), .tohost_value(c40_tohost),
        .bus_req(c40_bus_req), .bus_addr(c40_bus_addr), .bus_write_data(c40_bus_write_data),
        .bus_mem_write(c40_bus_mem_write), .bus_mem_size(c40_bus_mem_size), .bus_mem_unsigned(c40_bus_mem_unsigned),
        .bus_grant(c40_bus_grant), .bus_read_data(c40_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c40_adap (
        .clk(clk), .reset(reset),
        .bus_req(c40_bus_req), .bus_addr(c40_bus_addr), .bus_write_data(c40_bus_write_data),
        .bus_mem_write(c40_bus_mem_write), .bus_mem_size(c40_bus_mem_size), .bus_mem_unsigned(c40_bus_mem_unsigned),
        .bus_grant(c40_bus_grant), .bus_read_data(c40_bus_read_data),
        .req_out_valid(c40_req_out_valid), .req_out_flit(c40_req_out_flit), .req_out_ready(c40_req_out_ready),
        .resp_in_valid(c40_resp_in_valid), .resp_in_flit(c40_resp_in_flit), .resp_in_ready(c40_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C41_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c41_core (
        .clk(clk), .reset(reset),
        .halted(c41_halted), .tohost_value(c41_tohost),
        .bus_req(c41_bus_req), .bus_addr(c41_bus_addr), .bus_write_data(c41_bus_write_data),
        .bus_mem_write(c41_bus_mem_write), .bus_mem_size(c41_bus_mem_size), .bus_mem_unsigned(c41_bus_mem_unsigned),
        .bus_grant(c41_bus_grant), .bus_read_data(c41_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c41_adap (
        .clk(clk), .reset(reset),
        .bus_req(c41_bus_req), .bus_addr(c41_bus_addr), .bus_write_data(c41_bus_write_data),
        .bus_mem_write(c41_bus_mem_write), .bus_mem_size(c41_bus_mem_size), .bus_mem_unsigned(c41_bus_mem_unsigned),
        .bus_grant(c41_bus_grant), .bus_read_data(c41_bus_read_data),
        .req_out_valid(c41_req_out_valid), .req_out_flit(c41_req_out_flit), .req_out_ready(c41_req_out_ready),
        .resp_in_valid(c41_resp_in_valid), .resp_in_flit(c41_resp_in_flit), .resp_in_ready(c41_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C42_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c42_core (
        .clk(clk), .reset(reset),
        .halted(c42_halted), .tohost_value(c42_tohost),
        .bus_req(c42_bus_req), .bus_addr(c42_bus_addr), .bus_write_data(c42_bus_write_data),
        .bus_mem_write(c42_bus_mem_write), .bus_mem_size(c42_bus_mem_size), .bus_mem_unsigned(c42_bus_mem_unsigned),
        .bus_grant(c42_bus_grant), .bus_read_data(c42_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(1), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c42_adap (
        .clk(clk), .reset(reset),
        .bus_req(c42_bus_req), .bus_addr(c42_bus_addr), .bus_write_data(c42_bus_write_data),
        .bus_mem_write(c42_bus_mem_write), .bus_mem_size(c42_bus_mem_size), .bus_mem_unsigned(c42_bus_mem_unsigned),
        .bus_grant(c42_bus_grant), .bus_read_data(c42_bus_read_data),
        .req_out_valid(c42_req_out_valid), .req_out_flit(c42_req_out_flit), .req_out_ready(c42_req_out_ready),
        .resp_in_valid(c42_resp_in_valid), .resp_in_flit(c42_resp_in_flit), .resp_in_ready(c42_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C43_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c43_core (
        .clk(clk), .reset(reset),
        .halted(c43_halted), .tohost_value(c43_tohost),
        .bus_req(c43_bus_req), .bus_addr(c43_bus_addr), .bus_write_data(c43_bus_write_data),
        .bus_mem_write(c43_bus_mem_write), .bus_mem_size(c43_bus_mem_size), .bus_mem_unsigned(c43_bus_mem_unsigned),
        .bus_grant(c43_bus_grant), .bus_read_data(c43_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c43_adap (
        .clk(clk), .reset(reset),
        .bus_req(c43_bus_req), .bus_addr(c43_bus_addr), .bus_write_data(c43_bus_write_data),
        .bus_mem_write(c43_bus_mem_write), .bus_mem_size(c43_bus_mem_size), .bus_mem_unsigned(c43_bus_mem_unsigned),
        .bus_grant(c43_bus_grant), .bus_read_data(c43_bus_read_data),
        .req_out_valid(c43_req_out_valid), .req_out_flit(c43_req_out_flit), .req_out_ready(c43_req_out_ready),
        .resp_in_valid(c43_resp_in_valid), .resp_in_flit(c43_resp_in_flit), .resp_in_ready(c43_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C44_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c44_core (
        .clk(clk), .reset(reset),
        .halted(c44_halted), .tohost_value(c44_tohost),
        .bus_req(c44_bus_req), .bus_addr(c44_bus_addr), .bus_write_data(c44_bus_write_data),
        .bus_mem_write(c44_bus_mem_write), .bus_mem_size(c44_bus_mem_size), .bus_mem_unsigned(c44_bus_mem_unsigned),
        .bus_grant(c44_bus_grant), .bus_read_data(c44_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(1), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c44_adap (
        .clk(clk), .reset(reset),
        .bus_req(c44_bus_req), .bus_addr(c44_bus_addr), .bus_write_data(c44_bus_write_data),
        .bus_mem_write(c44_bus_mem_write), .bus_mem_size(c44_bus_mem_size), .bus_mem_unsigned(c44_bus_mem_unsigned),
        .bus_grant(c44_bus_grant), .bus_read_data(c44_bus_read_data),
        .req_out_valid(c44_req_out_valid), .req_out_flit(c44_req_out_flit), .req_out_ready(c44_req_out_ready),
        .resp_in_valid(c44_resp_in_valid), .resp_in_flit(c44_resp_in_flit), .resp_in_ready(c44_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C45_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c45_core (
        .clk(clk), .reset(reset),
        .halted(c45_halted), .tohost_value(c45_tohost),
        .bus_req(c45_bus_req), .bus_addr(c45_bus_addr), .bus_write_data(c45_bus_write_data),
        .bus_mem_write(c45_bus_mem_write), .bus_mem_size(c45_bus_mem_size), .bus_mem_unsigned(c45_bus_mem_unsigned),
        .bus_grant(c45_bus_grant), .bus_read_data(c45_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(2), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c45_adap (
        .clk(clk), .reset(reset),
        .bus_req(c45_bus_req), .bus_addr(c45_bus_addr), .bus_write_data(c45_bus_write_data),
        .bus_mem_write(c45_bus_mem_write), .bus_mem_size(c45_bus_mem_size), .bus_mem_unsigned(c45_bus_mem_unsigned),
        .bus_grant(c45_bus_grant), .bus_read_data(c45_bus_read_data),
        .req_out_valid(c45_req_out_valid), .req_out_flit(c45_req_out_flit), .req_out_ready(c45_req_out_ready),
        .resp_in_valid(c45_resp_in_valid), .resp_in_flit(c45_resp_in_flit), .resp_in_ready(c45_resp_in_ready)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS), .INSTR_INIT_FILE(C46_INSTR_HEX),
        .DATA_MEM_WORDS(DATA_MEM_WORDS),
        .SHARED_MEM_BASE(SHARED_MEM_BASE), .SHARED_MEM_BYTES(SHARED_MEM_BYTES)
    ) c46_core (
        .clk(clk), .reset(reset),
        .halted(c46_halted), .tohost_value(c46_tohost),
        .bus_req(c46_bus_req), .bus_addr(c46_bus_addr), .bus_write_data(c46_bus_write_data),
        .bus_mem_write(c46_bus_mem_write), .bus_mem_size(c46_bus_mem_size), .bus_mem_unsigned(c46_bus_mem_unsigned),
        .bus_grant(c46_bus_grant), .bus_read_data(c46_bus_read_data)
    );

    noc_core_adapter #(
        .COORD_BITS(2), .MY_X(3), .MY_Y(2), .MY_Z(3), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(1), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c46_adap (
        .clk(clk), .reset(reset),
        .bus_req(c46_bus_req), .bus_addr(c46_bus_addr), .bus_write_data(c46_bus_write_data),
        .bus_mem_write(c46_bus_mem_write), .bus_mem_size(c46_bus_mem_size), .bus_mem_unsigned(c46_bus_mem_unsigned),
        .bus_grant(c46_bus_grant), .bus_read_data(c46_bus_read_data),
        .req_out_valid(c46_req_out_valid), .req_out_flit(c46_req_out_flit), .req_out_ready(c46_req_out_ready),
        .resp_in_valid(c46_resp_in_valid), .resp_in_flit(c46_resp_in_flit), .resp_in_ready(c46_resp_in_ready)
    );

    noc_mem_adapter #(
        .COORD_BITS(2), .MEM_BYTES(SHARED_MEM_BYTES), .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) mem_adap (
        .clk(clk), .reset(reset),
        .req_in_valid(mem_req_in_valid), .req_in_flit(mem_req_in_flit), .req_in_ready(mem_req_in_ready),
        .resp_out_valid(mem_resp_out_valid), .resp_out_flit(mem_resp_out_flit), .resp_out_ready(mem_resp_out_ready)
    );

    assign all_halted = c0_halted && c1_halted && c2_halted && c3_halted && c4_halted && c5_halted && c6_halted && c7_halted && c8_halted && c9_halted && c10_halted && c11_halted && c12_halted && c13_halted && c14_halted && c15_halted && c16_halted && c17_halted && c18_halted && c19_halted && c20_halted && c21_halted && c22_halted && c23_halted && c24_halted && c25_halted && c26_halted && c27_halted && c28_halted && c29_halted && c30_halted && c31_halted && c32_halted && c33_halted && c34_halted && c35_halted && c36_halted && c37_halted && c38_halted && c39_halted && c40_halted && c41_halted && c42_halted && c43_halted && c44_halted && c45_halted && c46_halted;
endmodule
