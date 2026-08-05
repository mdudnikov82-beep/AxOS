// Cross-core communication test: e0-core (sw/shared_producer.hex, at grid
// position (1,0,0,1)) writes a payload + ready flag into shared memory;
// p0-core (sw/shared_consumer.hex, at (0,0,0,0)) polls for it, reads the
// payload, and computes a result that can only be correct (127) if it
// genuinely observed the OTHER core's write through the arbitrated
// NoC - not just "cores ran without crashing" like tb_soc.v proves.
// This is the FIRST 4D mesh (2x3x6x2, mem at (0,1,2,0)) - a genuinely
// new dimension (W, via router.v's ana/kata ports), not a mechanical
// scale-up, so per design review this test is NON-NEGOTIABLE (the one
// that caught this project's real wiring bug the first time a new
// dimension was added): p0 is 3 hops from memory (|0|+|1|+|2|+|0|) and
// sits at W=0 (same W as memory); e0 is 5 hops (|1|+|1|+|2|+|1|) and,
// critically, sits at W=1 - DIFFERENT from memory's W=0 - so this test
// genuinely exercises a real Kata hop (W:1->0) on the request path and
// a real Ana hop (W:0->1) on the response path, not just X/Y/Z routing
// with the W axis coincidentally never actually crossed.
// Every other
// core (69 of them) runs an independent private-memory-only program
// alongside, proving the cross-core handshake still works correctly
// through the mesh with 69 other cores concurrently contending for
// the same physical network, not just as a 2-core degenerate case.
`timescale 1ns/1ps

`ifndef P0_INSTR_HEX
`define P0_INSTR_HEX "sw/shared_consumer.hex"
`endif
`ifndef P1_INSTR_HEX
`define P1_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P2_INSTR_HEX
`define P2_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P3_INSTR_HEX
`define P3_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P4_INSTR_HEX
`define P4_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P5_INSTR_HEX
`define P5_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P6_INSTR_HEX
`define P6_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P7_INSTR_HEX
`define P7_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P8_INSTR_HEX
`define P8_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P9_INSTR_HEX
`define P9_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P10_INSTR_HEX
`define P10_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P11_INSTR_HEX
`define P11_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P12_INSTR_HEX
`define P12_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P13_INSTR_HEX
`define P13_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P14_INSTR_HEX
`define P14_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P15_INSTR_HEX
`define P15_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P16_INSTR_HEX
`define P16_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P17_INSTR_HEX
`define P17_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P18_INSTR_HEX
`define P18_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P19_INSTR_HEX
`define P19_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P20_INSTR_HEX
`define P20_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P21_INSTR_HEX
`define P21_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P22_INSTR_HEX
`define P22_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P23_INSTR_HEX
`define P23_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P24_INSTR_HEX
`define P24_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P25_INSTR_HEX
`define P25_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P26_INSTR_HEX
`define P26_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P27_INSTR_HEX
`define P27_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P28_INSTR_HEX
`define P28_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P29_INSTR_HEX
`define P29_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P30_INSTR_HEX
`define P30_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P31_INSTR_HEX
`define P31_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P32_INSTR_HEX
`define P32_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P33_INSTR_HEX
`define P33_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P34_INSTR_HEX
`define P34_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P35_INSTR_HEX
`define P35_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E0_INSTR_HEX
`define E0_INSTR_HEX "sw/shared_producer.hex"
`endif
`ifndef E1_INSTR_HEX
`define E1_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E2_INSTR_HEX
`define E2_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E3_INSTR_HEX
`define E3_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E4_INSTR_HEX
`define E4_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E5_INSTR_HEX
`define E5_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E6_INSTR_HEX
`define E6_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E7_INSTR_HEX
`define E7_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E8_INSTR_HEX
`define E8_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E9_INSTR_HEX
`define E9_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E10_INSTR_HEX
`define E10_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E11_INSTR_HEX
`define E11_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E12_INSTR_HEX
`define E12_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E13_INSTR_HEX
`define E13_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E14_INSTR_HEX
`define E14_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E15_INSTR_HEX
`define E15_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E16_INSTR_HEX
`define E16_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E17_INSTR_HEX
`define E17_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E18_INSTR_HEX
`define E18_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E19_INSTR_HEX
`define E19_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E20_INSTR_HEX
`define E20_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E21_INSTR_HEX
`define E21_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E22_INSTR_HEX
`define E22_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E23_INSTR_HEX
`define E23_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E24_INSTR_HEX
`define E24_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E25_INSTR_HEX
`define E25_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E26_INSTR_HEX
`define E26_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E27_INSTR_HEX
`define E27_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E28_INSTR_HEX
`define E28_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E29_INSTR_HEX
`define E29_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E30_INSTR_HEX
`define E30_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E31_INSTR_HEX
`define E31_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E32_INSTR_HEX
`define E32_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E33_INSTR_HEX
`define E33_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E34_INSTR_HEX
`define E34_INSTR_HEX "sw/test1.hex"
`endif

module tb_shared_soc;
    reg clk;
    reg reset;
    wire p0_halted, p1_halted, p2_halted, p3_halted, p4_halted, p5_halted, p6_halted, p7_halted, p8_halted, p9_halted, p10_halted, p11_halted, p12_halted, p13_halted, p14_halted, p15_halted, p16_halted, p17_halted, p18_halted, p19_halted, p20_halted, p21_halted, p22_halted, p23_halted, p24_halted, p25_halted, p26_halted, p27_halted, p28_halted, p29_halted, p30_halted, p31_halted, p32_halted, p33_halted, p34_halted, p35_halted, e0_halted, e1_halted, e2_halted, e3_halted, e4_halted, e5_halted, e6_halted, e7_halted, e8_halted, e9_halted, e10_halted, e11_halted, e12_halted, e13_halted, e14_halted, e15_halted, e16_halted, e17_halted, e18_halted, e19_halted, e20_halted, e21_halted, e22_halted, e23_halted, e24_halted, e25_halted, e26_halted, e27_halted, e28_halted, e29_halted, e30_halted, e31_halted, e32_halted, e33_halted, e34_halted, all_halted;
    wire [31:0] p0_tohost, p1_tohost, p2_tohost, p3_tohost, p4_tohost, p5_tohost, p6_tohost, p7_tohost, p8_tohost, p9_tohost, p10_tohost, p11_tohost, p12_tohost, p13_tohost, p14_tohost, p15_tohost, p16_tohost, p17_tohost, p18_tohost, p19_tohost, p20_tohost, p21_tohost, p22_tohost, p23_tohost, p24_tohost, p25_tohost, p26_tohost, p27_tohost, p28_tohost, p29_tohost, p30_tohost, p31_tohost, p32_tohost, p33_tohost, p34_tohost, p35_tohost, e0_tohost, e1_tohost, e2_tohost, e3_tohost, e4_tohost, e5_tohost, e6_tohost, e7_tohost, e8_tohost, e9_tohost, e10_tohost, e11_tohost, e12_tohost, e13_tohost, e14_tohost, e15_tohost, e16_tohost, e17_tohost, e18_tohost, e19_tohost, e20_tohost, e21_tohost, e22_tohost, e23_tohost, e24_tohost, e25_tohost, e26_tohost, e27_tohost, e28_tohost, e29_tohost, e30_tohost, e31_tohost, e32_tohost, e33_tohost, e34_tohost;

    integer expect_p0, expect_p1, expect_p2, expect_p3, expect_p4, expect_p5, expect_p6, expect_p7, expect_p8, expect_p9, expect_p10, expect_p11, expect_p12, expect_p13, expect_p14, expect_p15, expect_p16, expect_p17, expect_p18, expect_p19, expect_p20, expect_p21, expect_p22, expect_p23, expect_p24, expect_p25, expect_p26, expect_p27, expect_p28, expect_p29, expect_p30, expect_p31, expect_p32, expect_p33, expect_p34, expect_p35, expect_e0, expect_e1, expect_e2, expect_e3, expect_e4, expect_e5, expect_e6, expect_e7, expect_e8, expect_e9, expect_e10, expect_e11, expect_e12, expect_e13, expect_e14, expect_e15, expect_e16, expect_e17, expect_e18, expect_e19, expect_e20, expect_e21, expect_e22, expect_e23, expect_e24, expect_e25, expect_e26, expect_e27, expect_e28, expect_e29, expect_e30, expect_e31, expect_e32, expect_e33, expect_e34;
    integer max_cycles;
    integer cycle_count;
    integer trace_enabled;
    integer any_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024),
        .P0_INSTR_HEX(`P0_INSTR_HEX), .P1_INSTR_HEX(`P1_INSTR_HEX), .P2_INSTR_HEX(`P2_INSTR_HEX), .P3_INSTR_HEX(`P3_INSTR_HEX), .P4_INSTR_HEX(`P4_INSTR_HEX), .P5_INSTR_HEX(`P5_INSTR_HEX), .P6_INSTR_HEX(`P6_INSTR_HEX), .P7_INSTR_HEX(`P7_INSTR_HEX), .P8_INSTR_HEX(`P8_INSTR_HEX), .P9_INSTR_HEX(`P9_INSTR_HEX), .P10_INSTR_HEX(`P10_INSTR_HEX), .P11_INSTR_HEX(`P11_INSTR_HEX), .P12_INSTR_HEX(`P12_INSTR_HEX), .P13_INSTR_HEX(`P13_INSTR_HEX), .P14_INSTR_HEX(`P14_INSTR_HEX), .P15_INSTR_HEX(`P15_INSTR_HEX), .P16_INSTR_HEX(`P16_INSTR_HEX), .P17_INSTR_HEX(`P17_INSTR_HEX), .P18_INSTR_HEX(`P18_INSTR_HEX), .P19_INSTR_HEX(`P19_INSTR_HEX), .P20_INSTR_HEX(`P20_INSTR_HEX), .P21_INSTR_HEX(`P21_INSTR_HEX), .P22_INSTR_HEX(`P22_INSTR_HEX), .P23_INSTR_HEX(`P23_INSTR_HEX), .P24_INSTR_HEX(`P24_INSTR_HEX), .P25_INSTR_HEX(`P25_INSTR_HEX), .P26_INSTR_HEX(`P26_INSTR_HEX), .P27_INSTR_HEX(`P27_INSTR_HEX), .P28_INSTR_HEX(`P28_INSTR_HEX), .P29_INSTR_HEX(`P29_INSTR_HEX), .P30_INSTR_HEX(`P30_INSTR_HEX), .P31_INSTR_HEX(`P31_INSTR_HEX), .P32_INSTR_HEX(`P32_INSTR_HEX), .P33_INSTR_HEX(`P33_INSTR_HEX), .P34_INSTR_HEX(`P34_INSTR_HEX), .P35_INSTR_HEX(`P35_INSTR_HEX), .E0_INSTR_HEX(`E0_INSTR_HEX), .E1_INSTR_HEX(`E1_INSTR_HEX), .E2_INSTR_HEX(`E2_INSTR_HEX), .E3_INSTR_HEX(`E3_INSTR_HEX), .E4_INSTR_HEX(`E4_INSTR_HEX), .E5_INSTR_HEX(`E5_INSTR_HEX), .E6_INSTR_HEX(`E6_INSTR_HEX), .E7_INSTR_HEX(`E7_INSTR_HEX), .E8_INSTR_HEX(`E8_INSTR_HEX), .E9_INSTR_HEX(`E9_INSTR_HEX), .E10_INSTR_HEX(`E10_INSTR_HEX), .E11_INSTR_HEX(`E11_INSTR_HEX), .E12_INSTR_HEX(`E12_INSTR_HEX), .E13_INSTR_HEX(`E13_INSTR_HEX), .E14_INSTR_HEX(`E14_INSTR_HEX), .E15_INSTR_HEX(`E15_INSTR_HEX), .E16_INSTR_HEX(`E16_INSTR_HEX), .E17_INSTR_HEX(`E17_INSTR_HEX), .E18_INSTR_HEX(`E18_INSTR_HEX), .E19_INSTR_HEX(`E19_INSTR_HEX), .E20_INSTR_HEX(`E20_INSTR_HEX), .E21_INSTR_HEX(`E21_INSTR_HEX), .E22_INSTR_HEX(`E22_INSTR_HEX), .E23_INSTR_HEX(`E23_INSTR_HEX), .E24_INSTR_HEX(`E24_INSTR_HEX), .E25_INSTR_HEX(`E25_INSTR_HEX), .E26_INSTR_HEX(`E26_INSTR_HEX), .E27_INSTR_HEX(`E27_INSTR_HEX), .E28_INSTR_HEX(`E28_INSTR_HEX), .E29_INSTR_HEX(`E29_INSTR_HEX), .E30_INSTR_HEX(`E30_INSTR_HEX), .E31_INSTR_HEX(`E31_INSTR_HEX), .E32_INSTR_HEX(`E32_INSTR_HEX), .E33_INSTR_HEX(`E33_INSTR_HEX), .E34_INSTR_HEX(`E34_INSTR_HEX),
        .DATA_MEM_BYTES(8192)
    ) dut (
        .clk(clk), .reset(reset),
        .p0_halted(p0_halted), .p0_tohost(p0_tohost),
        .p1_halted(p1_halted), .p1_tohost(p1_tohost),
        .p2_halted(p2_halted), .p2_tohost(p2_tohost),
        .p3_halted(p3_halted), .p3_tohost(p3_tohost),
        .p4_halted(p4_halted), .p4_tohost(p4_tohost),
        .p5_halted(p5_halted), .p5_tohost(p5_tohost),
        .p6_halted(p6_halted), .p6_tohost(p6_tohost),
        .p7_halted(p7_halted), .p7_tohost(p7_tohost),
        .p8_halted(p8_halted), .p8_tohost(p8_tohost),
        .p9_halted(p9_halted), .p9_tohost(p9_tohost),
        .p10_halted(p10_halted), .p10_tohost(p10_tohost),
        .p11_halted(p11_halted), .p11_tohost(p11_tohost),
        .p12_halted(p12_halted), .p12_tohost(p12_tohost),
        .p13_halted(p13_halted), .p13_tohost(p13_tohost),
        .p14_halted(p14_halted), .p14_tohost(p14_tohost),
        .p15_halted(p15_halted), .p15_tohost(p15_tohost),
        .p16_halted(p16_halted), .p16_tohost(p16_tohost),
        .p17_halted(p17_halted), .p17_tohost(p17_tohost),
        .p18_halted(p18_halted), .p18_tohost(p18_tohost),
        .p19_halted(p19_halted), .p19_tohost(p19_tohost),
        .p20_halted(p20_halted), .p20_tohost(p20_tohost),
        .p21_halted(p21_halted), .p21_tohost(p21_tohost),
        .p22_halted(p22_halted), .p22_tohost(p22_tohost),
        .p23_halted(p23_halted), .p23_tohost(p23_tohost),
        .p24_halted(p24_halted), .p24_tohost(p24_tohost),
        .p25_halted(p25_halted), .p25_tohost(p25_tohost),
        .p26_halted(p26_halted), .p26_tohost(p26_tohost),
        .p27_halted(p27_halted), .p27_tohost(p27_tohost),
        .p28_halted(p28_halted), .p28_tohost(p28_tohost),
        .p29_halted(p29_halted), .p29_tohost(p29_tohost),
        .p30_halted(p30_halted), .p30_tohost(p30_tohost),
        .p31_halted(p31_halted), .p31_tohost(p31_tohost),
        .p32_halted(p32_halted), .p32_tohost(p32_tohost),
        .p33_halted(p33_halted), .p33_tohost(p33_tohost),
        .p34_halted(p34_halted), .p34_tohost(p34_tohost),
        .p35_halted(p35_halted), .p35_tohost(p35_tohost),
        .e0_halted(e0_halted), .e0_tohost(e0_tohost),
        .e1_halted(e1_halted), .e1_tohost(e1_tohost),
        .e2_halted(e2_halted), .e2_tohost(e2_tohost),
        .e3_halted(e3_halted), .e3_tohost(e3_tohost),
        .e4_halted(e4_halted), .e4_tohost(e4_tohost),
        .e5_halted(e5_halted), .e5_tohost(e5_tohost),
        .e6_halted(e6_halted), .e6_tohost(e6_tohost),
        .e7_halted(e7_halted), .e7_tohost(e7_tohost),
        .e8_halted(e8_halted), .e8_tohost(e8_tohost),
        .e9_halted(e9_halted), .e9_tohost(e9_tohost),
        .e10_halted(e10_halted), .e10_tohost(e10_tohost),
        .e11_halted(e11_halted), .e11_tohost(e11_tohost),
        .e12_halted(e12_halted), .e12_tohost(e12_tohost),
        .e13_halted(e13_halted), .e13_tohost(e13_tohost),
        .e14_halted(e14_halted), .e14_tohost(e14_tohost),
        .e15_halted(e15_halted), .e15_tohost(e15_tohost),
        .e16_halted(e16_halted), .e16_tohost(e16_tohost),
        .e17_halted(e17_halted), .e17_tohost(e17_tohost),
        .e18_halted(e18_halted), .e18_tohost(e18_tohost),
        .e19_halted(e19_halted), .e19_tohost(e19_tohost),
        .e20_halted(e20_halted), .e20_tohost(e20_tohost),
        .e21_halted(e21_halted), .e21_tohost(e21_tohost),
        .e22_halted(e22_halted), .e22_tohost(e22_tohost),
        .e23_halted(e23_halted), .e23_tohost(e23_tohost),
        .e24_halted(e24_halted), .e24_tohost(e24_tohost),
        .e25_halted(e25_halted), .e25_tohost(e25_tohost),
        .e26_halted(e26_halted), .e26_tohost(e26_tohost),
        .e27_halted(e27_halted), .e27_tohost(e27_tohost),
        .e28_halted(e28_halted), .e28_tohost(e28_tohost),
        .e29_halted(e29_halted), .e29_tohost(e29_tohost),
        .e30_halted(e30_halted), .e30_tohost(e30_tohost),
        .e31_halted(e31_halted), .e31_tohost(e31_tohost),
        .e32_halted(e32_halted), .e32_tohost(e32_tohost),
        .e33_halted(e33_halted), .e33_tohost(e33_tohost),
        .e34_halted(e34_halted), .e34_tohost(e34_tohost),
        .all_halted(all_halted)
    );

    always #5 clk = ~clk;

    task check_core(input [31:0] got, input [31:0] expected, input [24*8-1:0] name);
        begin
            $display("%0s: tohost=%0d (0x%h)", name, got, got);
            if (got === expected) begin
                $display("PASS: %0s matches expected value %0d", name, expected);
            end else begin
                $display("FAIL: %0s tohost=%0d, expected=%0d", name, got, expected);
                any_fail = 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_shared_soc.vcd");
        $dumpvars(0, tb_shared_soc);

        if (!$value$plusargs("EXPECT_P0_TOHOST=%d", expect_p0)) expect_p0 = 127;
        if (!$value$plusargs("EXPECT_P1_TOHOST=%d", expect_p1)) expect_p1 = 42;
        if (!$value$plusargs("EXPECT_P2_TOHOST=%d", expect_p2)) expect_p2 = 42;
        if (!$value$plusargs("EXPECT_P3_TOHOST=%d", expect_p3)) expect_p3 = 42;
        if (!$value$plusargs("EXPECT_P4_TOHOST=%d", expect_p4)) expect_p4 = 42;
        if (!$value$plusargs("EXPECT_P5_TOHOST=%d", expect_p5)) expect_p5 = 42;
        if (!$value$plusargs("EXPECT_P6_TOHOST=%d", expect_p6)) expect_p6 = 42;
        if (!$value$plusargs("EXPECT_P7_TOHOST=%d", expect_p7)) expect_p7 = 42;
        if (!$value$plusargs("EXPECT_P8_TOHOST=%d", expect_p8)) expect_p8 = 42;
        if (!$value$plusargs("EXPECT_P9_TOHOST=%d", expect_p9)) expect_p9 = 42;
        if (!$value$plusargs("EXPECT_P10_TOHOST=%d", expect_p10)) expect_p10 = 42;
        if (!$value$plusargs("EXPECT_P11_TOHOST=%d", expect_p11)) expect_p11 = 42;
        if (!$value$plusargs("EXPECT_P12_TOHOST=%d", expect_p12)) expect_p12 = 42;
        if (!$value$plusargs("EXPECT_P13_TOHOST=%d", expect_p13)) expect_p13 = 42;
        if (!$value$plusargs("EXPECT_P14_TOHOST=%d", expect_p14)) expect_p14 = 42;
        if (!$value$plusargs("EXPECT_P15_TOHOST=%d", expect_p15)) expect_p15 = 42;
        if (!$value$plusargs("EXPECT_P16_TOHOST=%d", expect_p16)) expect_p16 = 42;
        if (!$value$plusargs("EXPECT_P17_TOHOST=%d", expect_p17)) expect_p17 = 42;
        if (!$value$plusargs("EXPECT_P18_TOHOST=%d", expect_p18)) expect_p18 = 42;
        if (!$value$plusargs("EXPECT_P19_TOHOST=%d", expect_p19)) expect_p19 = 42;
        if (!$value$plusargs("EXPECT_P20_TOHOST=%d", expect_p20)) expect_p20 = 42;
        if (!$value$plusargs("EXPECT_P21_TOHOST=%d", expect_p21)) expect_p21 = 42;
        if (!$value$plusargs("EXPECT_P22_TOHOST=%d", expect_p22)) expect_p22 = 42;
        if (!$value$plusargs("EXPECT_P23_TOHOST=%d", expect_p23)) expect_p23 = 42;
        if (!$value$plusargs("EXPECT_P24_TOHOST=%d", expect_p24)) expect_p24 = 42;
        if (!$value$plusargs("EXPECT_P25_TOHOST=%d", expect_p25)) expect_p25 = 42;
        if (!$value$plusargs("EXPECT_P26_TOHOST=%d", expect_p26)) expect_p26 = 42;
        if (!$value$plusargs("EXPECT_P27_TOHOST=%d", expect_p27)) expect_p27 = 42;
        if (!$value$plusargs("EXPECT_P28_TOHOST=%d", expect_p28)) expect_p28 = 42;
        if (!$value$plusargs("EXPECT_P29_TOHOST=%d", expect_p29)) expect_p29 = 42;
        if (!$value$plusargs("EXPECT_P30_TOHOST=%d", expect_p30)) expect_p30 = 42;
        if (!$value$plusargs("EXPECT_P31_TOHOST=%d", expect_p31)) expect_p31 = 42;
        if (!$value$plusargs("EXPECT_P32_TOHOST=%d", expect_p32)) expect_p32 = 42;
        if (!$value$plusargs("EXPECT_P33_TOHOST=%d", expect_p33)) expect_p33 = 42;
        if (!$value$plusargs("EXPECT_P34_TOHOST=%d", expect_p34)) expect_p34 = 42;
        if (!$value$plusargs("EXPECT_P35_TOHOST=%d", expect_p35)) expect_p35 = 42;
        if (!$value$plusargs("EXPECT_E0_TOHOST=%d", expect_e0)) expect_e0 = 77;
        if (!$value$plusargs("EXPECT_E1_TOHOST=%d", expect_e1)) expect_e1 = 42;
        if (!$value$plusargs("EXPECT_E2_TOHOST=%d", expect_e2)) expect_e2 = 42;
        if (!$value$plusargs("EXPECT_E3_TOHOST=%d", expect_e3)) expect_e3 = 42;
        if (!$value$plusargs("EXPECT_E4_TOHOST=%d", expect_e4)) expect_e4 = 42;
        if (!$value$plusargs("EXPECT_E5_TOHOST=%d", expect_e5)) expect_e5 = 42;
        if (!$value$plusargs("EXPECT_E6_TOHOST=%d", expect_e6)) expect_e6 = 42;
        if (!$value$plusargs("EXPECT_E7_TOHOST=%d", expect_e7)) expect_e7 = 42;
        if (!$value$plusargs("EXPECT_E8_TOHOST=%d", expect_e8)) expect_e8 = 42;
        if (!$value$plusargs("EXPECT_E9_TOHOST=%d", expect_e9)) expect_e9 = 42;
        if (!$value$plusargs("EXPECT_E10_TOHOST=%d", expect_e10)) expect_e10 = 42;
        if (!$value$plusargs("EXPECT_E11_TOHOST=%d", expect_e11)) expect_e11 = 42;
        if (!$value$plusargs("EXPECT_E12_TOHOST=%d", expect_e12)) expect_e12 = 42;
        if (!$value$plusargs("EXPECT_E13_TOHOST=%d", expect_e13)) expect_e13 = 42;
        if (!$value$plusargs("EXPECT_E14_TOHOST=%d", expect_e14)) expect_e14 = 42;
        if (!$value$plusargs("EXPECT_E15_TOHOST=%d", expect_e15)) expect_e15 = 42;
        if (!$value$plusargs("EXPECT_E16_TOHOST=%d", expect_e16)) expect_e16 = 42;
        if (!$value$plusargs("EXPECT_E17_TOHOST=%d", expect_e17)) expect_e17 = 42;
        if (!$value$plusargs("EXPECT_E18_TOHOST=%d", expect_e18)) expect_e18 = 42;
        if (!$value$plusargs("EXPECT_E19_TOHOST=%d", expect_e19)) expect_e19 = 42;
        if (!$value$plusargs("EXPECT_E20_TOHOST=%d", expect_e20)) expect_e20 = 42;
        if (!$value$plusargs("EXPECT_E21_TOHOST=%d", expect_e21)) expect_e21 = 42;
        if (!$value$plusargs("EXPECT_E22_TOHOST=%d", expect_e22)) expect_e22 = 42;
        if (!$value$plusargs("EXPECT_E23_TOHOST=%d", expect_e23)) expect_e23 = 42;
        if (!$value$plusargs("EXPECT_E24_TOHOST=%d", expect_e24)) expect_e24 = 42;
        if (!$value$plusargs("EXPECT_E25_TOHOST=%d", expect_e25)) expect_e25 = 42;
        if (!$value$plusargs("EXPECT_E26_TOHOST=%d", expect_e26)) expect_e26 = 42;
        if (!$value$plusargs("EXPECT_E27_TOHOST=%d", expect_e27)) expect_e27 = 42;
        if (!$value$plusargs("EXPECT_E28_TOHOST=%d", expect_e28)) expect_e28 = 42;
        if (!$value$plusargs("EXPECT_E29_TOHOST=%d", expect_e29)) expect_e29 = 42;
        if (!$value$plusargs("EXPECT_E30_TOHOST=%d", expect_e30)) expect_e30 = 42;
        if (!$value$plusargs("EXPECT_E31_TOHOST=%d", expect_e31)) expect_e31 = 42;
        if (!$value$plusargs("EXPECT_E32_TOHOST=%d", expect_e32)) expect_e32 = 42;
        if (!$value$plusargs("EXPECT_E33_TOHOST=%d", expect_e33)) expect_e33 = 42;
        if (!$value$plusargs("EXPECT_E34_TOHOST=%d", expect_e34)) expect_e34 = 42;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 150;
        trace_enabled = $test$plusargs("TRACE");

        clk = 0;
        reset = 1;
        cycle_count = 0;
        any_fail = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        while (!all_halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!all_halted) begin
            $display("FAIL: not all 71 cores halted within %0d cycles (p0=%b p1=%b p2=%b p3=%b p4=%b p5=%b p6=%b p7=%b p8=%b p9=%b p10=%b p11=%b p12=%b p13=%b p14=%b p15=%b p16=%b p17=%b p18=%b p19=%b p20=%b p21=%b p22=%b p23=%b p24=%b p25=%b p26=%b p27=%b p28=%b p29=%b p30=%b p31=%b p32=%b p33=%b p34=%b p35=%b e0=%b e1=%b e2=%b e3=%b e4=%b e5=%b e6=%b e7=%b e8=%b e9=%b e10=%b e11=%b e12=%b e13=%b e14=%b e15=%b e16=%b e17=%b e18=%b e19=%b e20=%b e21=%b e22=%b e23=%b e24=%b e25=%b e26=%b e27=%b e28=%b e29=%b e30=%b e31=%b e32=%b e33=%b e34=%b)",
                      max_cycles, p0_halted, p1_halted, p2_halted, p3_halted, p4_halted, p5_halted, p6_halted, p7_halted, p8_halted, p9_halted, p10_halted, p11_halted, p12_halted, p13_halted, p14_halted, p15_halted, p16_halted, p17_halted, p18_halted, p19_halted, p20_halted, p21_halted, p22_halted, p23_halted, p24_halted, p25_halted, p26_halted, p27_halted, p28_halted, p29_halted, p30_halted, p31_halted, p32_halted, p33_halted, p34_halted, p35_halted, e0_halted, e1_halted, e2_halted, e3_halted, e4_halted, e5_halted, e6_halted, e7_halted, e8_halted, e9_halted, e10_halted, e11_halted, e12_halted, e13_halted, e14_halted, e15_halted, e16_halted, e17_halted, e18_halted, e19_halted, e20_halted, e21_halted, e22_halted, e23_halted, e24_halted, e25_halted, e26_halted, e27_halted, e28_halted, e29_halted, e30_halted, e31_halted, e32_halted, e33_halted, e34_halted);
        end else begin
            $display("All 71 cores halted after %0d cycles.", cycle_count);
            check_core(p0_tohost, expect_p0, "p0-core (consumer)");
            check_core(e0_tohost, expect_e0, "e0-core (producer)");
            check_core(p1_tohost, expect_p1, "p1-core (independent)");
            check_core(p2_tohost, expect_p2, "p2-core (independent)");
            check_core(p3_tohost, expect_p3, "p3-core (independent)");
            check_core(p4_tohost, expect_p4, "p4-core (independent)");
            check_core(p5_tohost, expect_p5, "p5-core (independent)");
            check_core(p6_tohost, expect_p6, "p6-core (independent)");
            check_core(p7_tohost, expect_p7, "p7-core (independent)");
            check_core(p8_tohost, expect_p8, "p8-core (independent)");
            check_core(p9_tohost, expect_p9, "p9-core (independent)");
            check_core(p10_tohost, expect_p10, "p10-core (independent)");
            check_core(p11_tohost, expect_p11, "p11-core (independent)");
            check_core(p12_tohost, expect_p12, "p12-core (independent)");
            check_core(p13_tohost, expect_p13, "p13-core (independent)");
            check_core(p14_tohost, expect_p14, "p14-core (independent)");
            check_core(p15_tohost, expect_p15, "p15-core (independent)");
            check_core(p16_tohost, expect_p16, "p16-core (independent)");
            check_core(p17_tohost, expect_p17, "p17-core (independent)");
            check_core(p18_tohost, expect_p18, "p18-core (independent)");
            check_core(p19_tohost, expect_p19, "p19-core (independent)");
            check_core(p20_tohost, expect_p20, "p20-core (independent)");
            check_core(p21_tohost, expect_p21, "p21-core (independent)");
            check_core(p22_tohost, expect_p22, "p22-core (independent)");
            check_core(p23_tohost, expect_p23, "p23-core (independent)");
            check_core(p24_tohost, expect_p24, "p24-core (independent)");
            check_core(p25_tohost, expect_p25, "p25-core (independent)");
            check_core(p26_tohost, expect_p26, "p26-core (independent)");
            check_core(p27_tohost, expect_p27, "p27-core (independent)");
            check_core(p28_tohost, expect_p28, "p28-core (independent)");
            check_core(p29_tohost, expect_p29, "p29-core (independent)");
            check_core(p30_tohost, expect_p30, "p30-core (independent)");
            check_core(p31_tohost, expect_p31, "p31-core (independent)");
            check_core(p32_tohost, expect_p32, "p32-core (independent)");
            check_core(p33_tohost, expect_p33, "p33-core (independent)");
            check_core(p34_tohost, expect_p34, "p34-core (independent)");
            check_core(p35_tohost, expect_p35, "p35-core (independent)");
            check_core(e1_tohost, expect_e1, "e1-core (independent)");
            check_core(e2_tohost, expect_e2, "e2-core (independent)");
            check_core(e3_tohost, expect_e3, "e3-core (independent)");
            check_core(e4_tohost, expect_e4, "e4-core (independent)");
            check_core(e5_tohost, expect_e5, "e5-core (independent)");
            check_core(e6_tohost, expect_e6, "e6-core (independent)");
            check_core(e7_tohost, expect_e7, "e7-core (independent)");
            check_core(e8_tohost, expect_e8, "e8-core (independent)");
            check_core(e9_tohost, expect_e9, "e9-core (independent)");
            check_core(e10_tohost, expect_e10, "e10-core (independent)");
            check_core(e11_tohost, expect_e11, "e11-core (independent)");
            check_core(e12_tohost, expect_e12, "e12-core (independent)");
            check_core(e13_tohost, expect_e13, "e13-core (independent)");
            check_core(e14_tohost, expect_e14, "e14-core (independent)");
            check_core(e15_tohost, expect_e15, "e15-core (independent)");
            check_core(e16_tohost, expect_e16, "e16-core (independent)");
            check_core(e17_tohost, expect_e17, "e17-core (independent)");
            check_core(e18_tohost, expect_e18, "e18-core (independent)");
            check_core(e19_tohost, expect_e19, "e19-core (independent)");
            check_core(e20_tohost, expect_e20, "e20-core (independent)");
            check_core(e21_tohost, expect_e21, "e21-core (independent)");
            check_core(e22_tohost, expect_e22, "e22-core (independent)");
            check_core(e23_tohost, expect_e23, "e23-core (independent)");
            check_core(e24_tohost, expect_e24, "e24-core (independent)");
            check_core(e25_tohost, expect_e25, "e25-core (independent)");
            check_core(e26_tohost, expect_e26, "e26-core (independent)");
            check_core(e27_tohost, expect_e27, "e27-core (independent)");
            check_core(e28_tohost, expect_e28, "e28-core (independent)");
            check_core(e29_tohost, expect_e29, "e29-core (independent)");
            check_core(e30_tohost, expect_e30, "e30-core (independent)");
            check_core(e31_tohost, expect_e31, "e31-core (independent)");
            check_core(e32_tohost, expect_e32, "e32-core (independent)");
            check_core(e33_tohost, expect_e33, "e33-core (independent)");
            check_core(e34_tohost, expect_e34, "e34-core (independent)");
            if (!any_fail) $display("PASS: cross-core communication verified (p0 read e0's write)");
        end

        $finish;
    end
endmodule
