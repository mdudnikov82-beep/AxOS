// AxISA's NoC mini-SoC (hardware/axisa_core) - a real 3x3 mesh of
// XYZW-routed routers (router.v, ported unmodified from rv32i_core), each
// grid position connected to its N/E/S/W neighbors (Z/W axes unused at
// this size - MY_Z=MY_W=0 everywhere, Up/Down/Ana/Kata all tied off)
// plus a Local port for whatever AxISA core or memory endpoint sits
// there. TWO independent router networks span the grid - REQUEST
// (core -> memory, FLIT_WIDTH=84) and RESPONSE (memory -> core,
// FLIT_WIDTH=40) - kept as fully separate router instances with zero
// shared state, same as every rv32i_core mesh.
//
// Scaled up MECHANICALLY (no fresh design review - same architecture/
// generator logic already reviewed and live-verified at 2x2, matching
// this project's own established 2D scale-up precedent) from AxISA's
// first-ever 2x2/3-core mesh to this 3x3/8-core one. AxISA has only
// ONE core module (cpu_core.v, no pipelined variant), so no P/E split is
// needed. COORD_BITS bumped 1->2 (X/Y now need values 0-2).
//
// Memory lives at (1,1) - the exact center on both size-3 axes.
// Grid layout (x,y):
//
//   c0     c3     c5   
//   c1     MEM    c6   
//   c2     c4     c7   
//
// c0=consumer (shared_consumer.hex, busy-waits then reads the payload),
// c1=producer (shared_producer.hex, writes payload then a ready flag),
// c2-c7=independent (test1.hex, private-memory-only, proves the mesh still
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
    output wire        all_halted
);

    // ==================== Mesh link wires ====================
    wire req_0_0_S_v, req_0_0_S_r; wire [83:0] req_0_0_S_f;
    wire req_0_0_E_v, req_0_0_E_r; wire [83:0] req_0_0_E_f;
    wire req_0_1_N_v, req_0_1_N_r; wire [83:0] req_0_1_N_f;
    wire req_0_1_S_v, req_0_1_S_r; wire [83:0] req_0_1_S_f;
    wire req_0_1_E_v, req_0_1_E_r; wire [83:0] req_0_1_E_f;
    wire req_0_2_N_v, req_0_2_N_r; wire [83:0] req_0_2_N_f;
    wire req_0_2_E_v, req_0_2_E_r; wire [83:0] req_0_2_E_f;
    wire req_1_0_S_v, req_1_0_S_r; wire [83:0] req_1_0_S_f;
    wire req_1_0_E_v, req_1_0_E_r; wire [83:0] req_1_0_E_f;
    wire req_1_0_W_v, req_1_0_W_r; wire [83:0] req_1_0_W_f;
    wire req_1_1_N_v, req_1_1_N_r; wire [83:0] req_1_1_N_f;
    wire req_1_1_S_v, req_1_1_S_r; wire [83:0] req_1_1_S_f;
    wire req_1_1_E_v, req_1_1_E_r; wire [83:0] req_1_1_E_f;
    wire req_1_1_W_v, req_1_1_W_r; wire [83:0] req_1_1_W_f;
    wire req_1_2_N_v, req_1_2_N_r; wire [83:0] req_1_2_N_f;
    wire req_1_2_E_v, req_1_2_E_r; wire [83:0] req_1_2_E_f;
    wire req_1_2_W_v, req_1_2_W_r; wire [83:0] req_1_2_W_f;
    wire req_2_0_S_v, req_2_0_S_r; wire [83:0] req_2_0_S_f;
    wire req_2_0_W_v, req_2_0_W_r; wire [83:0] req_2_0_W_f;
    wire req_2_1_N_v, req_2_1_N_r; wire [83:0] req_2_1_N_f;
    wire req_2_1_S_v, req_2_1_S_r; wire [83:0] req_2_1_S_f;
    wire req_2_1_W_v, req_2_1_W_r; wire [83:0] req_2_1_W_f;
    wire req_2_2_N_v, req_2_2_N_r; wire [83:0] req_2_2_N_f;
    wire req_2_2_W_v, req_2_2_W_r; wire [83:0] req_2_2_W_f;
    wire resp_0_0_S_v, resp_0_0_S_r; wire [39:0] resp_0_0_S_f;
    wire resp_0_0_E_v, resp_0_0_E_r; wire [39:0] resp_0_0_E_f;
    wire resp_0_1_N_v, resp_0_1_N_r; wire [39:0] resp_0_1_N_f;
    wire resp_0_1_S_v, resp_0_1_S_r; wire [39:0] resp_0_1_S_f;
    wire resp_0_1_E_v, resp_0_1_E_r; wire [39:0] resp_0_1_E_f;
    wire resp_0_2_N_v, resp_0_2_N_r; wire [39:0] resp_0_2_N_f;
    wire resp_0_2_E_v, resp_0_2_E_r; wire [39:0] resp_0_2_E_f;
    wire resp_1_0_S_v, resp_1_0_S_r; wire [39:0] resp_1_0_S_f;
    wire resp_1_0_E_v, resp_1_0_E_r; wire [39:0] resp_1_0_E_f;
    wire resp_1_0_W_v, resp_1_0_W_r; wire [39:0] resp_1_0_W_f;
    wire resp_1_1_N_v, resp_1_1_N_r; wire [39:0] resp_1_1_N_f;
    wire resp_1_1_S_v, resp_1_1_S_r; wire [39:0] resp_1_1_S_f;
    wire resp_1_1_E_v, resp_1_1_E_r; wire [39:0] resp_1_1_E_f;
    wire resp_1_1_W_v, resp_1_1_W_r; wire [39:0] resp_1_1_W_f;
    wire resp_1_2_N_v, resp_1_2_N_r; wire [39:0] resp_1_2_N_f;
    wire resp_1_2_E_v, resp_1_2_E_r; wire [39:0] resp_1_2_E_f;
    wire resp_1_2_W_v, resp_1_2_W_r; wire [39:0] resp_1_2_W_f;
    wire resp_2_0_S_v, resp_2_0_S_r; wire [39:0] resp_2_0_S_f;
    wire resp_2_0_W_v, resp_2_0_W_r; wire [39:0] resp_2_0_W_f;
    wire resp_2_1_N_v, resp_2_1_N_r; wire [39:0] resp_2_1_N_f;
    wire resp_2_1_S_v, resp_2_1_S_r; wire [39:0] resp_2_1_S_f;
    wire resp_2_1_W_v, resp_2_1_W_r; wire [39:0] resp_2_1_W_f;
    wire resp_2_2_N_v, resp_2_2_N_r; wire [39:0] resp_2_2_N_f;
    wire resp_2_2_W_v, resp_2_2_W_r; wire [39:0] resp_2_2_W_f;

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
    wire mem_req_in_valid, mem_req_in_ready, mem_resp_out_valid, mem_resp_out_ready;
    wire [83:0] mem_req_in_flit;
    wire [39:0] mem_resp_out_flit;

    // ==================== Routers (2 networks x 9 grid positions) ====================
    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_1_0_W_v), .e_in_flit(req_1_0_W_f), .e_in_ready(req_1_0_W_r),
        .e_out_valid(req_0_0_E_v), .e_out_flit(req_0_0_E_f), .e_out_ready(req_0_0_E_r),
        .s_in_valid(req_0_1_N_v), .s_in_flit(req_0_1_N_f), .s_in_ready(req_0_1_N_r),
        .s_out_valid(req_0_0_S_v), .s_out_flit(req_0_0_S_f), .s_out_ready(req_0_0_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c0_req_out_valid), .l_in_flit(c0_req_out_flit), .l_in_ready(c0_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r0_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_1_0_W_v), .e_in_flit(resp_1_0_W_f), .e_in_ready(resp_1_0_W_r),
        .e_out_valid(resp_0_0_E_v), .e_out_flit(resp_0_0_E_f), .e_out_ready(resp_0_0_E_r),
        .s_in_valid(resp_0_1_N_v), .s_in_flit(resp_0_1_N_f), .s_in_ready(resp_0_1_N_r),
        .s_out_valid(resp_0_0_S_v), .s_out_flit(resp_0_0_S_f), .s_out_ready(resp_0_0_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c0_resp_in_valid), .l_out_flit(c0_resp_in_flit), .l_out_ready(c0_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(0)) req_r0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_0_S_v), .n_in_flit(req_0_0_S_f), .n_in_ready(req_0_0_S_r),
        .n_out_valid(req_0_1_N_v), .n_out_flit(req_0_1_N_f), .n_out_ready(req_0_1_N_r),
        .e_in_valid(req_1_1_W_v), .e_in_flit(req_1_1_W_f), .e_in_ready(req_1_1_W_r),
        .e_out_valid(req_0_1_E_v), .e_out_flit(req_0_1_E_f), .e_out_ready(req_0_1_E_r),
        .s_in_valid(req_0_2_N_v), .s_in_flit(req_0_2_N_f), .s_in_ready(req_0_2_N_r),
        .s_out_valid(req_0_1_S_v), .s_out_flit(req_0_1_S_f), .s_out_ready(req_0_1_S_r),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c1_req_out_valid), .l_in_flit(c1_req_out_flit), .l_in_ready(c1_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(0)) resp_r0_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_0_S_v), .n_in_flit(resp_0_0_S_f), .n_in_ready(resp_0_0_S_r),
        .n_out_valid(resp_0_1_N_v), .n_out_flit(resp_0_1_N_f), .n_out_ready(resp_0_1_N_r),
        .e_in_valid(resp_1_1_W_v), .e_in_flit(resp_1_1_W_f), .e_in_ready(resp_1_1_W_r),
        .e_out_valid(resp_0_1_E_v), .e_out_flit(resp_0_1_E_f), .e_out_ready(resp_0_1_E_r),
        .s_in_valid(resp_0_2_N_v), .s_in_flit(resp_0_2_N_f), .s_in_ready(resp_0_2_N_r),
        .s_out_valid(resp_0_1_S_v), .s_out_flit(resp_0_1_S_f), .s_out_ready(resp_0_1_S_r),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c1_resp_in_valid), .l_out_flit(c1_resp_in_flit), .l_out_ready(c1_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(0)) req_r0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_0_1_S_v), .n_in_flit(req_0_1_S_f), .n_in_ready(req_0_1_S_r),
        .n_out_valid(req_0_2_N_v), .n_out_flit(req_0_2_N_f), .n_out_ready(req_0_2_N_r),
        .e_in_valid(req_1_2_W_v), .e_in_flit(req_1_2_W_f), .e_in_ready(req_1_2_W_r),
        .e_out_valid(req_0_2_E_v), .e_out_flit(req_0_2_E_f), .e_out_ready(req_0_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({84{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c2_req_out_valid), .l_in_flit(c2_req_out_flit), .l_in_ready(c2_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(0)) resp_r0_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_0_1_S_v), .n_in_flit(resp_0_1_S_f), .n_in_ready(resp_0_1_S_r),
        .n_out_valid(resp_0_2_N_v), .n_out_flit(resp_0_2_N_f), .n_out_ready(resp_0_2_N_r),
        .e_in_valid(resp_1_2_W_v), .e_in_flit(resp_1_2_W_f), .e_in_ready(resp_1_2_W_r),
        .e_out_valid(resp_0_2_E_v), .e_out_flit(resp_0_2_E_f), .e_out_ready(resp_0_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(1'b0), .w_in_flit({40{1'b0}}), .w_in_ready(),
        .w_out_valid(), .w_out_flit(), .w_out_ready(1'b0),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c2_resp_in_valid), .l_out_flit(c2_resp_in_flit), .l_out_ready(c2_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(req_2_0_W_v), .e_in_flit(req_2_0_W_f), .e_in_ready(req_2_0_W_r),
        .e_out_valid(req_1_0_E_v), .e_out_flit(req_1_0_E_f), .e_out_ready(req_1_0_E_r),
        .s_in_valid(req_1_1_N_v), .s_in_flit(req_1_1_N_f), .s_in_ready(req_1_1_N_r),
        .s_out_valid(req_1_0_S_v), .s_out_flit(req_1_0_S_f), .s_out_ready(req_1_0_S_r),
        .w_in_valid(req_0_0_E_v), .w_in_flit(req_0_0_E_f), .w_in_ready(req_0_0_E_r),
        .w_out_valid(req_1_0_W_v), .w_out_flit(req_1_0_W_f), .w_out_ready(req_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c3_req_out_valid), .l_in_flit(c3_req_out_flit), .l_in_ready(c3_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r1_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(resp_2_0_W_v), .e_in_flit(resp_2_0_W_f), .e_in_ready(resp_2_0_W_r),
        .e_out_valid(resp_1_0_E_v), .e_out_flit(resp_1_0_E_f), .e_out_ready(resp_1_0_E_r),
        .s_in_valid(resp_1_1_N_v), .s_in_flit(resp_1_1_N_f), .s_in_ready(resp_1_1_N_r),
        .s_out_valid(resp_1_0_S_v), .s_out_flit(resp_1_0_S_f), .s_out_ready(resp_1_0_S_r),
        .w_in_valid(resp_0_0_E_v), .w_in_flit(resp_0_0_E_f), .w_in_ready(resp_0_0_E_r),
        .w_out_valid(resp_1_0_W_v), .w_out_flit(resp_1_0_W_f), .w_out_ready(resp_1_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c3_resp_in_valid), .l_out_flit(c3_resp_in_flit), .l_out_ready(c3_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(0)) req_r1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_0_S_v), .n_in_flit(req_1_0_S_f), .n_in_ready(req_1_0_S_r),
        .n_out_valid(req_1_1_N_v), .n_out_flit(req_1_1_N_f), .n_out_ready(req_1_1_N_r),
        .e_in_valid(req_2_1_W_v), .e_in_flit(req_2_1_W_f), .e_in_ready(req_2_1_W_r),
        .e_out_valid(req_1_1_E_v), .e_out_flit(req_1_1_E_f), .e_out_ready(req_1_1_E_r),
        .s_in_valid(req_1_2_N_v), .s_in_flit(req_1_2_N_f), .s_in_ready(req_1_2_N_r),
        .s_out_valid(req_1_1_S_v), .s_out_flit(req_1_1_S_f), .s_out_ready(req_1_1_S_r),
        .w_in_valid(req_0_1_E_v), .w_in_flit(req_0_1_E_f), .w_in_ready(req_0_1_E_r),
        .w_out_valid(req_1_1_W_v), .w_out_flit(req_1_1_W_f), .w_out_ready(req_1_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({84{1'b0}}), .l_in_ready(),
        .l_out_valid(mem_req_in_valid), .l_out_flit(mem_req_in_flit), .l_out_ready(mem_req_in_ready)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(1), .MY_Z(0), .MY_W(0)) resp_r1_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_0_S_v), .n_in_flit(resp_1_0_S_f), .n_in_ready(resp_1_0_S_r),
        .n_out_valid(resp_1_1_N_v), .n_out_flit(resp_1_1_N_f), .n_out_ready(resp_1_1_N_r),
        .e_in_valid(resp_2_1_W_v), .e_in_flit(resp_2_1_W_f), .e_in_ready(resp_2_1_W_r),
        .e_out_valid(resp_1_1_E_v), .e_out_flit(resp_1_1_E_f), .e_out_ready(resp_1_1_E_r),
        .s_in_valid(resp_1_2_N_v), .s_in_flit(resp_1_2_N_f), .s_in_ready(resp_1_2_N_r),
        .s_out_valid(resp_1_1_S_v), .s_out_flit(resp_1_1_S_f), .s_out_ready(resp_1_1_S_r),
        .w_in_valid(resp_0_1_E_v), .w_in_flit(resp_0_1_E_f), .w_in_ready(resp_0_1_E_r),
        .w_out_valid(resp_1_1_W_v), .w_out_flit(resp_1_1_W_f), .w_out_ready(resp_1_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(mem_resp_out_valid), .l_in_flit(mem_resp_out_flit), .l_in_ready(mem_resp_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(0)) req_r1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_1_1_S_v), .n_in_flit(req_1_1_S_f), .n_in_ready(req_1_1_S_r),
        .n_out_valid(req_1_2_N_v), .n_out_flit(req_1_2_N_f), .n_out_ready(req_1_2_N_r),
        .e_in_valid(req_2_2_W_v), .e_in_flit(req_2_2_W_f), .e_in_ready(req_2_2_W_r),
        .e_out_valid(req_1_2_E_v), .e_out_flit(req_1_2_E_f), .e_out_ready(req_1_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_0_2_E_v), .w_in_flit(req_0_2_E_f), .w_in_ready(req_0_2_E_r),
        .w_out_valid(req_1_2_W_v), .w_out_flit(req_1_2_W_f), .w_out_ready(req_1_2_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c4_req_out_valid), .l_in_flit(c4_req_out_flit), .l_in_ready(c4_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(0)) resp_r1_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_1_1_S_v), .n_in_flit(resp_1_1_S_f), .n_in_ready(resp_1_1_S_r),
        .n_out_valid(resp_1_2_N_v), .n_out_flit(resp_1_2_N_f), .n_out_ready(resp_1_2_N_r),
        .e_in_valid(resp_2_2_W_v), .e_in_flit(resp_2_2_W_f), .e_in_ready(resp_2_2_W_r),
        .e_out_valid(resp_1_2_E_v), .e_out_flit(resp_1_2_E_f), .e_out_ready(resp_1_2_E_r),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_0_2_E_v), .w_in_flit(resp_0_2_E_f), .w_in_ready(resp_0_2_E_r),
        .w_out_valid(resp_1_2_W_v), .w_out_flit(resp_1_2_W_f), .w_out_ready(resp_1_2_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c4_resp_in_valid), .l_out_flit(c4_resp_in_flit), .l_out_ready(c4_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(0), .MY_W(0)) req_r2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({84{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_2_1_N_v), .s_in_flit(req_2_1_N_f), .s_in_ready(req_2_1_N_r),
        .s_out_valid(req_2_0_S_v), .s_out_flit(req_2_0_S_f), .s_out_ready(req_2_0_S_r),
        .w_in_valid(req_1_0_E_v), .w_in_flit(req_1_0_E_f), .w_in_ready(req_1_0_E_r),
        .w_out_valid(req_2_0_W_v), .w_out_flit(req_2_0_W_f), .w_out_ready(req_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c5_req_out_valid), .l_in_flit(c5_req_out_flit), .l_in_ready(c5_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(0), .MY_W(0)) resp_r2_0 (
        .clk(clk), .reset(reset),
        .n_in_valid(1'b0), .n_in_flit({40{1'b0}}), .n_in_ready(),
        .n_out_valid(), .n_out_flit(), .n_out_ready(1'b0),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_2_1_N_v), .s_in_flit(resp_2_1_N_f), .s_in_ready(resp_2_1_N_r),
        .s_out_valid(resp_2_0_S_v), .s_out_flit(resp_2_0_S_f), .s_out_ready(resp_2_0_S_r),
        .w_in_valid(resp_1_0_E_v), .w_in_flit(resp_1_0_E_f), .w_in_ready(resp_1_0_E_r),
        .w_out_valid(resp_2_0_W_v), .w_out_flit(resp_2_0_W_f), .w_out_ready(resp_2_0_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c5_resp_in_valid), .l_out_flit(c5_resp_in_flit), .l_out_ready(c5_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(0), .MY_W(0)) req_r2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_0_S_v), .n_in_flit(req_2_0_S_f), .n_in_ready(req_2_0_S_r),
        .n_out_valid(req_2_1_N_v), .n_out_flit(req_2_1_N_f), .n_out_ready(req_2_1_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(req_2_2_N_v), .s_in_flit(req_2_2_N_f), .s_in_ready(req_2_2_N_r),
        .s_out_valid(req_2_1_S_v), .s_out_flit(req_2_1_S_f), .s_out_ready(req_2_1_S_r),
        .w_in_valid(req_1_1_E_v), .w_in_flit(req_1_1_E_f), .w_in_ready(req_1_1_E_r),
        .w_out_valid(req_2_1_W_v), .w_out_flit(req_2_1_W_f), .w_out_ready(req_2_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c6_req_out_valid), .l_in_flit(c6_req_out_flit), .l_in_ready(c6_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(0), .MY_W(0)) resp_r2_1 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_0_S_v), .n_in_flit(resp_2_0_S_f), .n_in_ready(resp_2_0_S_r),
        .n_out_valid(resp_2_1_N_v), .n_out_flit(resp_2_1_N_f), .n_out_ready(resp_2_1_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(resp_2_2_N_v), .s_in_flit(resp_2_2_N_f), .s_in_ready(resp_2_2_N_r),
        .s_out_valid(resp_2_1_S_v), .s_out_flit(resp_2_1_S_f), .s_out_ready(resp_2_1_S_r),
        .w_in_valid(resp_1_1_E_v), .w_in_flit(resp_1_1_E_f), .w_in_ready(resp_1_1_E_r),
        .w_out_valid(resp_2_1_W_v), .w_out_flit(resp_2_1_W_f), .w_out_ready(resp_2_1_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c6_resp_in_valid), .l_out_flit(c6_resp_in_flit), .l_out_ready(c6_resp_in_ready)
    );

    router #(.FLIT_WIDTH(84), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(0), .MY_W(0)) req_r2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(req_2_1_S_v), .n_in_flit(req_2_1_S_f), .n_in_ready(req_2_1_S_r),
        .n_out_valid(req_2_2_N_v), .n_out_flit(req_2_2_N_f), .n_out_ready(req_2_2_N_r),
        .e_in_valid(1'b0), .e_in_flit({84{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({84{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(req_1_2_E_v), .w_in_flit(req_1_2_E_f), .w_in_ready(req_1_2_E_r),
        .w_out_valid(req_2_2_W_v), .w_out_flit(req_2_2_W_f), .w_out_ready(req_2_2_W_r),
        .u_in_valid(1'b0), .u_in_flit({84{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({84{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({84{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({84{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(c7_req_out_valid), .l_in_flit(c7_req_out_flit), .l_in_ready(c7_req_out_ready),
        .l_out_valid(), .l_out_flit(), .l_out_ready(1'b0)
    );

    router #(.FLIT_WIDTH(40), .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(0), .MY_W(0)) resp_r2_2 (
        .clk(clk), .reset(reset),
        .n_in_valid(resp_2_1_S_v), .n_in_flit(resp_2_1_S_f), .n_in_ready(resp_2_1_S_r),
        .n_out_valid(resp_2_2_N_v), .n_out_flit(resp_2_2_N_f), .n_out_ready(resp_2_2_N_r),
        .e_in_valid(1'b0), .e_in_flit({40{1'b0}}), .e_in_ready(),
        .e_out_valid(), .e_out_flit(), .e_out_ready(1'b0),
        .s_in_valid(1'b0), .s_in_flit({40{1'b0}}), .s_in_ready(),
        .s_out_valid(), .s_out_flit(), .s_out_ready(1'b0),
        .w_in_valid(resp_1_2_E_v), .w_in_flit(resp_1_2_E_f), .w_in_ready(resp_1_2_E_r),
        .w_out_valid(resp_2_2_W_v), .w_out_flit(resp_2_2_W_f), .w_out_ready(resp_2_2_W_r),
        .u_in_valid(1'b0), .u_in_flit({40{1'b0}}), .u_in_ready(),
        .u_out_valid(), .u_out_flit(), .u_out_ready(1'b0),
        .d_in_valid(1'b0), .d_in_flit({40{1'b0}}), .d_in_ready(),
        .d_out_valid(), .d_out_flit(), .d_out_ready(1'b0),
        .ana_in_valid(1'b0), .ana_in_flit({40{1'b0}}), .ana_in_ready(),
        .ana_out_valid(), .ana_out_flit(), .ana_out_ready(1'b0),
        .kata_in_valid(1'b0), .kata_in_flit({40{1'b0}}), .kata_in_ready(),
        .kata_out_valid(), .kata_out_flit(), .kata_out_ready(1'b0),
        .l_in_valid(1'b0), .l_in_flit({40{1'b0}}), .l_in_ready(),
        .l_out_valid(c7_resp_in_valid), .l_out_flit(c7_resp_in_flit), .l_out_ready(c7_resp_in_ready)
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
        .MEM_X(1), .MEM_Y(1), .MEM_Z(0), .MEM_W(0),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(1), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(0), .MEM_W(0),
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
        .COORD_BITS(2), .MY_X(0), .MY_Y(2), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(0), .MEM_W(0),
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
        .COORD_BITS(2), .MY_X(1), .MY_Y(0), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(0), .MEM_W(0),
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
        .COORD_BITS(2), .MY_X(1), .MY_Y(2), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(0), .MEM_W(0),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(0), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(0), .MEM_W(0),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(1), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(0), .MEM_W(0),
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
        .COORD_BITS(2), .MY_X(2), .MY_Y(2), .MY_Z(0), .MY_W(0),
        .MEM_X(1), .MEM_Y(1), .MEM_Z(0), .MEM_W(0),
        .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) c7_adap (
        .clk(clk), .reset(reset),
        .bus_req(c7_bus_req), .bus_addr(c7_bus_addr), .bus_write_data(c7_bus_write_data),
        .bus_mem_write(c7_bus_mem_write), .bus_mem_size(c7_bus_mem_size), .bus_mem_unsigned(c7_bus_mem_unsigned),
        .bus_grant(c7_bus_grant), .bus_read_data(c7_bus_read_data),
        .req_out_valid(c7_req_out_valid), .req_out_flit(c7_req_out_flit), .req_out_ready(c7_req_out_ready),
        .resp_in_valid(c7_resp_in_valid), .resp_in_flit(c7_resp_in_flit), .resp_in_ready(c7_resp_in_ready)
    );

    noc_mem_adapter #(
        .COORD_BITS(2), .MEM_BYTES(SHARED_MEM_BYTES), .REQ_FLIT_WIDTH(84), .RESP_FLIT_WIDTH(40)
    ) mem_adap (
        .clk(clk), .reset(reset),
        .req_in_valid(mem_req_in_valid), .req_in_flit(mem_req_in_flit), .req_in_ready(mem_req_in_ready),
        .resp_out_valid(mem_resp_out_valid), .resp_out_flit(mem_resp_out_flit), .resp_out_ready(mem_resp_out_ready)
    );

    assign all_halted = c0_halted && c1_halted && c2_halted && c3_halted && c4_halted && c5_halted && c6_halted && c7_halted;
endmodule
