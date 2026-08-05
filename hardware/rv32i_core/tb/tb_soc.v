// SoC-level testbench: one shared clk/reset drives all 179 cores in
// soc_top at once (scaled up to the 3D 5x6x6/180-node mesh - 90 P-cores +
// 89 E-cores + 1 memory node; just more core instantiations, soc_top.v
// itself is a bigger/deeper mesh, but this testbench only ever sees the
// same external port/param shape), proving they all run concurrently
// rather than being separately-simulated instances. Each core runs its
// own INDEPENDENT private-memory-only program (no shared-bus traffic
// here - that cross-core-communication proof lives in tb_shared_soc.v
// instead). Waits for all_halted (not just any one core - a slow core
// shouldn't let a fast one's premature halt end the run), then checks
// each core's own tohost value independently.
`timescale 1ns/1ps

`ifndef P0_INSTR_HEX
`define P0_INSTR_HEX "sw/hazard_test.hex"
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
`ifndef P36_INSTR_HEX
`define P36_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P37_INSTR_HEX
`define P37_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P38_INSTR_HEX
`define P38_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P39_INSTR_HEX
`define P39_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P40_INSTR_HEX
`define P40_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P41_INSTR_HEX
`define P41_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P42_INSTR_HEX
`define P42_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P43_INSTR_HEX
`define P43_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P44_INSTR_HEX
`define P44_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P45_INSTR_HEX
`define P45_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P46_INSTR_HEX
`define P46_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P47_INSTR_HEX
`define P47_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P48_INSTR_HEX
`define P48_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P49_INSTR_HEX
`define P49_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P50_INSTR_HEX
`define P50_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P51_INSTR_HEX
`define P51_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P52_INSTR_HEX
`define P52_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P53_INSTR_HEX
`define P53_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P54_INSTR_HEX
`define P54_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P55_INSTR_HEX
`define P55_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P56_INSTR_HEX
`define P56_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P57_INSTR_HEX
`define P57_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P58_INSTR_HEX
`define P58_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P59_INSTR_HEX
`define P59_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P60_INSTR_HEX
`define P60_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P61_INSTR_HEX
`define P61_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P62_INSTR_HEX
`define P62_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P63_INSTR_HEX
`define P63_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P64_INSTR_HEX
`define P64_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P65_INSTR_HEX
`define P65_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P66_INSTR_HEX
`define P66_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P67_INSTR_HEX
`define P67_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P68_INSTR_HEX
`define P68_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P69_INSTR_HEX
`define P69_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P70_INSTR_HEX
`define P70_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P71_INSTR_HEX
`define P71_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P72_INSTR_HEX
`define P72_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P73_INSTR_HEX
`define P73_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P74_INSTR_HEX
`define P74_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P75_INSTR_HEX
`define P75_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P76_INSTR_HEX
`define P76_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P77_INSTR_HEX
`define P77_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P78_INSTR_HEX
`define P78_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P79_INSTR_HEX
`define P79_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P80_INSTR_HEX
`define P80_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P81_INSTR_HEX
`define P81_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P82_INSTR_HEX
`define P82_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P83_INSTR_HEX
`define P83_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P84_INSTR_HEX
`define P84_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P85_INSTR_HEX
`define P85_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P86_INSTR_HEX
`define P86_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P87_INSTR_HEX
`define P87_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P88_INSTR_HEX
`define P88_INSTR_HEX "sw/test1.hex"
`endif
`ifndef P89_INSTR_HEX
`define P89_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E0_INSTR_HEX
`define E0_INSTR_HEX "sw/test_basic.hex"
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
`ifndef E35_INSTR_HEX
`define E35_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E36_INSTR_HEX
`define E36_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E37_INSTR_HEX
`define E37_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E38_INSTR_HEX
`define E38_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E39_INSTR_HEX
`define E39_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E40_INSTR_HEX
`define E40_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E41_INSTR_HEX
`define E41_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E42_INSTR_HEX
`define E42_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E43_INSTR_HEX
`define E43_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E44_INSTR_HEX
`define E44_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E45_INSTR_HEX
`define E45_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E46_INSTR_HEX
`define E46_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E47_INSTR_HEX
`define E47_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E48_INSTR_HEX
`define E48_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E49_INSTR_HEX
`define E49_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E50_INSTR_HEX
`define E50_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E51_INSTR_HEX
`define E51_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E52_INSTR_HEX
`define E52_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E53_INSTR_HEX
`define E53_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E54_INSTR_HEX
`define E54_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E55_INSTR_HEX
`define E55_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E56_INSTR_HEX
`define E56_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E57_INSTR_HEX
`define E57_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E58_INSTR_HEX
`define E58_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E59_INSTR_HEX
`define E59_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E60_INSTR_HEX
`define E60_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E61_INSTR_HEX
`define E61_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E62_INSTR_HEX
`define E62_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E63_INSTR_HEX
`define E63_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E64_INSTR_HEX
`define E64_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E65_INSTR_HEX
`define E65_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E66_INSTR_HEX
`define E66_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E67_INSTR_HEX
`define E67_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E68_INSTR_HEX
`define E68_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E69_INSTR_HEX
`define E69_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E70_INSTR_HEX
`define E70_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E71_INSTR_HEX
`define E71_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E72_INSTR_HEX
`define E72_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E73_INSTR_HEX
`define E73_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E74_INSTR_HEX
`define E74_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E75_INSTR_HEX
`define E75_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E76_INSTR_HEX
`define E76_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E77_INSTR_HEX
`define E77_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E78_INSTR_HEX
`define E78_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E79_INSTR_HEX
`define E79_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E80_INSTR_HEX
`define E80_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E81_INSTR_HEX
`define E81_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E82_INSTR_HEX
`define E82_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E83_INSTR_HEX
`define E83_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E84_INSTR_HEX
`define E84_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E85_INSTR_HEX
`define E85_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E86_INSTR_HEX
`define E86_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E87_INSTR_HEX
`define E87_INSTR_HEX "sw/test1.hex"
`endif
`ifndef E88_INSTR_HEX
`define E88_INSTR_HEX "sw/test1.hex"
`endif

module tb_soc;
    reg clk;
    reg reset;
    wire p0_halted, p1_halted, p2_halted, p3_halted, p4_halted, p5_halted, p6_halted, p7_halted, p8_halted, p9_halted, p10_halted, p11_halted, p12_halted, p13_halted, p14_halted, p15_halted, p16_halted, p17_halted, p18_halted, p19_halted, p20_halted, p21_halted, p22_halted, p23_halted, p24_halted, p25_halted, p26_halted, p27_halted, p28_halted, p29_halted, p30_halted, p31_halted, p32_halted, p33_halted, p34_halted, p35_halted, p36_halted, p37_halted, p38_halted, p39_halted, p40_halted, p41_halted, p42_halted, p43_halted, p44_halted, p45_halted, p46_halted, p47_halted, p48_halted, p49_halted, p50_halted, p51_halted, p52_halted, p53_halted, p54_halted, p55_halted, p56_halted, p57_halted, p58_halted, p59_halted, p60_halted, p61_halted, p62_halted, p63_halted, p64_halted, p65_halted, p66_halted, p67_halted, p68_halted, p69_halted, p70_halted, p71_halted, p72_halted, p73_halted, p74_halted, p75_halted, p76_halted, p77_halted, p78_halted, p79_halted, p80_halted, p81_halted, p82_halted, p83_halted, p84_halted, p85_halted, p86_halted, p87_halted, p88_halted, p89_halted, e0_halted, e1_halted, e2_halted, e3_halted, e4_halted, e5_halted, e6_halted, e7_halted, e8_halted, e9_halted, e10_halted, e11_halted, e12_halted, e13_halted, e14_halted, e15_halted, e16_halted, e17_halted, e18_halted, e19_halted, e20_halted, e21_halted, e22_halted, e23_halted, e24_halted, e25_halted, e26_halted, e27_halted, e28_halted, e29_halted, e30_halted, e31_halted, e32_halted, e33_halted, e34_halted, e35_halted, e36_halted, e37_halted, e38_halted, e39_halted, e40_halted, e41_halted, e42_halted, e43_halted, e44_halted, e45_halted, e46_halted, e47_halted, e48_halted, e49_halted, e50_halted, e51_halted, e52_halted, e53_halted, e54_halted, e55_halted, e56_halted, e57_halted, e58_halted, e59_halted, e60_halted, e61_halted, e62_halted, e63_halted, e64_halted, e65_halted, e66_halted, e67_halted, e68_halted, e69_halted, e70_halted, e71_halted, e72_halted, e73_halted, e74_halted, e75_halted, e76_halted, e77_halted, e78_halted, e79_halted, e80_halted, e81_halted, e82_halted, e83_halted, e84_halted, e85_halted, e86_halted, e87_halted, e88_halted, all_halted;
    wire [31:0] p0_tohost, p1_tohost, p2_tohost, p3_tohost, p4_tohost, p5_tohost, p6_tohost, p7_tohost, p8_tohost, p9_tohost, p10_tohost, p11_tohost, p12_tohost, p13_tohost, p14_tohost, p15_tohost, p16_tohost, p17_tohost, p18_tohost, p19_tohost, p20_tohost, p21_tohost, p22_tohost, p23_tohost, p24_tohost, p25_tohost, p26_tohost, p27_tohost, p28_tohost, p29_tohost, p30_tohost, p31_tohost, p32_tohost, p33_tohost, p34_tohost, p35_tohost, p36_tohost, p37_tohost, p38_tohost, p39_tohost, p40_tohost, p41_tohost, p42_tohost, p43_tohost, p44_tohost, p45_tohost, p46_tohost, p47_tohost, p48_tohost, p49_tohost, p50_tohost, p51_tohost, p52_tohost, p53_tohost, p54_tohost, p55_tohost, p56_tohost, p57_tohost, p58_tohost, p59_tohost, p60_tohost, p61_tohost, p62_tohost, p63_tohost, p64_tohost, p65_tohost, p66_tohost, p67_tohost, p68_tohost, p69_tohost, p70_tohost, p71_tohost, p72_tohost, p73_tohost, p74_tohost, p75_tohost, p76_tohost, p77_tohost, p78_tohost, p79_tohost, p80_tohost, p81_tohost, p82_tohost, p83_tohost, p84_tohost, p85_tohost, p86_tohost, p87_tohost, p88_tohost, p89_tohost, e0_tohost, e1_tohost, e2_tohost, e3_tohost, e4_tohost, e5_tohost, e6_tohost, e7_tohost, e8_tohost, e9_tohost, e10_tohost, e11_tohost, e12_tohost, e13_tohost, e14_tohost, e15_tohost, e16_tohost, e17_tohost, e18_tohost, e19_tohost, e20_tohost, e21_tohost, e22_tohost, e23_tohost, e24_tohost, e25_tohost, e26_tohost, e27_tohost, e28_tohost, e29_tohost, e30_tohost, e31_tohost, e32_tohost, e33_tohost, e34_tohost, e35_tohost, e36_tohost, e37_tohost, e38_tohost, e39_tohost, e40_tohost, e41_tohost, e42_tohost, e43_tohost, e44_tohost, e45_tohost, e46_tohost, e47_tohost, e48_tohost, e49_tohost, e50_tohost, e51_tohost, e52_tohost, e53_tohost, e54_tohost, e55_tohost, e56_tohost, e57_tohost, e58_tohost, e59_tohost, e60_tohost, e61_tohost, e62_tohost, e63_tohost, e64_tohost, e65_tohost, e66_tohost, e67_tohost, e68_tohost, e69_tohost, e70_tohost, e71_tohost, e72_tohost, e73_tohost, e74_tohost, e75_tohost, e76_tohost, e77_tohost, e78_tohost, e79_tohost, e80_tohost, e81_tohost, e82_tohost, e83_tohost, e84_tohost, e85_tohost, e86_tohost, e87_tohost, e88_tohost;

    integer expect_p0, expect_p1, expect_p2, expect_p3, expect_p4, expect_p5, expect_p6, expect_p7, expect_p8, expect_p9, expect_p10, expect_p11, expect_p12, expect_p13, expect_p14, expect_p15, expect_p16, expect_p17, expect_p18, expect_p19, expect_p20, expect_p21, expect_p22, expect_p23, expect_p24, expect_p25, expect_p26, expect_p27, expect_p28, expect_p29, expect_p30, expect_p31, expect_p32, expect_p33, expect_p34, expect_p35, expect_p36, expect_p37, expect_p38, expect_p39, expect_p40, expect_p41, expect_p42, expect_p43, expect_p44, expect_p45, expect_p46, expect_p47, expect_p48, expect_p49, expect_p50, expect_p51, expect_p52, expect_p53, expect_p54, expect_p55, expect_p56, expect_p57, expect_p58, expect_p59, expect_p60, expect_p61, expect_p62, expect_p63, expect_p64, expect_p65, expect_p66, expect_p67, expect_p68, expect_p69, expect_p70, expect_p71, expect_p72, expect_p73, expect_p74, expect_p75, expect_p76, expect_p77, expect_p78, expect_p79, expect_p80, expect_p81, expect_p82, expect_p83, expect_p84, expect_p85, expect_p86, expect_p87, expect_p88, expect_p89, expect_e0, expect_e1, expect_e2, expect_e3, expect_e4, expect_e5, expect_e6, expect_e7, expect_e8, expect_e9, expect_e10, expect_e11, expect_e12, expect_e13, expect_e14, expect_e15, expect_e16, expect_e17, expect_e18, expect_e19, expect_e20, expect_e21, expect_e22, expect_e23, expect_e24, expect_e25, expect_e26, expect_e27, expect_e28, expect_e29, expect_e30, expect_e31, expect_e32, expect_e33, expect_e34, expect_e35, expect_e36, expect_e37, expect_e38, expect_e39, expect_e40, expect_e41, expect_e42, expect_e43, expect_e44, expect_e45, expect_e46, expect_e47, expect_e48, expect_e49, expect_e50, expect_e51, expect_e52, expect_e53, expect_e54, expect_e55, expect_e56, expect_e57, expect_e58, expect_e59, expect_e60, expect_e61, expect_e62, expect_e63, expect_e64, expect_e65, expect_e66, expect_e67, expect_e68, expect_e69, expect_e70, expect_e71, expect_e72, expect_e73, expect_e74, expect_e75, expect_e76, expect_e77, expect_e78, expect_e79, expect_e80, expect_e81, expect_e82, expect_e83, expect_e84, expect_e85, expect_e86, expect_e87, expect_e88;
    integer max_cycles;
    integer cycle_count;
    integer any_fail;

    soc_top #(
        .INSTR_MEM_WORDS(1024),
        .P0_INSTR_HEX(`P0_INSTR_HEX), .P1_INSTR_HEX(`P1_INSTR_HEX), .P2_INSTR_HEX(`P2_INSTR_HEX), .P3_INSTR_HEX(`P3_INSTR_HEX), .P4_INSTR_HEX(`P4_INSTR_HEX), .P5_INSTR_HEX(`P5_INSTR_HEX), .P6_INSTR_HEX(`P6_INSTR_HEX), .P7_INSTR_HEX(`P7_INSTR_HEX), .P8_INSTR_HEX(`P8_INSTR_HEX), .P9_INSTR_HEX(`P9_INSTR_HEX), .P10_INSTR_HEX(`P10_INSTR_HEX), .P11_INSTR_HEX(`P11_INSTR_HEX), .P12_INSTR_HEX(`P12_INSTR_HEX), .P13_INSTR_HEX(`P13_INSTR_HEX), .P14_INSTR_HEX(`P14_INSTR_HEX), .P15_INSTR_HEX(`P15_INSTR_HEX), .P16_INSTR_HEX(`P16_INSTR_HEX), .P17_INSTR_HEX(`P17_INSTR_HEX), .P18_INSTR_HEX(`P18_INSTR_HEX), .P19_INSTR_HEX(`P19_INSTR_HEX), .P20_INSTR_HEX(`P20_INSTR_HEX), .P21_INSTR_HEX(`P21_INSTR_HEX), .P22_INSTR_HEX(`P22_INSTR_HEX), .P23_INSTR_HEX(`P23_INSTR_HEX), .P24_INSTR_HEX(`P24_INSTR_HEX), .P25_INSTR_HEX(`P25_INSTR_HEX), .P26_INSTR_HEX(`P26_INSTR_HEX), .P27_INSTR_HEX(`P27_INSTR_HEX), .P28_INSTR_HEX(`P28_INSTR_HEX), .P29_INSTR_HEX(`P29_INSTR_HEX), .P30_INSTR_HEX(`P30_INSTR_HEX), .P31_INSTR_HEX(`P31_INSTR_HEX), .P32_INSTR_HEX(`P32_INSTR_HEX), .P33_INSTR_HEX(`P33_INSTR_HEX), .P34_INSTR_HEX(`P34_INSTR_HEX), .P35_INSTR_HEX(`P35_INSTR_HEX), .P36_INSTR_HEX(`P36_INSTR_HEX), .P37_INSTR_HEX(`P37_INSTR_HEX), .P38_INSTR_HEX(`P38_INSTR_HEX), .P39_INSTR_HEX(`P39_INSTR_HEX), .P40_INSTR_HEX(`P40_INSTR_HEX), .P41_INSTR_HEX(`P41_INSTR_HEX), .P42_INSTR_HEX(`P42_INSTR_HEX), .P43_INSTR_HEX(`P43_INSTR_HEX), .P44_INSTR_HEX(`P44_INSTR_HEX), .P45_INSTR_HEX(`P45_INSTR_HEX), .P46_INSTR_HEX(`P46_INSTR_HEX), .P47_INSTR_HEX(`P47_INSTR_HEX), .P48_INSTR_HEX(`P48_INSTR_HEX), .P49_INSTR_HEX(`P49_INSTR_HEX), .P50_INSTR_HEX(`P50_INSTR_HEX), .P51_INSTR_HEX(`P51_INSTR_HEX), .P52_INSTR_HEX(`P52_INSTR_HEX), .P53_INSTR_HEX(`P53_INSTR_HEX), .P54_INSTR_HEX(`P54_INSTR_HEX), .P55_INSTR_HEX(`P55_INSTR_HEX), .P56_INSTR_HEX(`P56_INSTR_HEX), .P57_INSTR_HEX(`P57_INSTR_HEX), .P58_INSTR_HEX(`P58_INSTR_HEX), .P59_INSTR_HEX(`P59_INSTR_HEX), .P60_INSTR_HEX(`P60_INSTR_HEX), .P61_INSTR_HEX(`P61_INSTR_HEX), .P62_INSTR_HEX(`P62_INSTR_HEX), .P63_INSTR_HEX(`P63_INSTR_HEX), .P64_INSTR_HEX(`P64_INSTR_HEX), .P65_INSTR_HEX(`P65_INSTR_HEX), .P66_INSTR_HEX(`P66_INSTR_HEX), .P67_INSTR_HEX(`P67_INSTR_HEX), .P68_INSTR_HEX(`P68_INSTR_HEX), .P69_INSTR_HEX(`P69_INSTR_HEX), .P70_INSTR_HEX(`P70_INSTR_HEX), .P71_INSTR_HEX(`P71_INSTR_HEX), .P72_INSTR_HEX(`P72_INSTR_HEX), .P73_INSTR_HEX(`P73_INSTR_HEX), .P74_INSTR_HEX(`P74_INSTR_HEX), .P75_INSTR_HEX(`P75_INSTR_HEX), .P76_INSTR_HEX(`P76_INSTR_HEX), .P77_INSTR_HEX(`P77_INSTR_HEX), .P78_INSTR_HEX(`P78_INSTR_HEX), .P79_INSTR_HEX(`P79_INSTR_HEX), .P80_INSTR_HEX(`P80_INSTR_HEX), .P81_INSTR_HEX(`P81_INSTR_HEX), .P82_INSTR_HEX(`P82_INSTR_HEX), .P83_INSTR_HEX(`P83_INSTR_HEX), .P84_INSTR_HEX(`P84_INSTR_HEX), .P85_INSTR_HEX(`P85_INSTR_HEX), .P86_INSTR_HEX(`P86_INSTR_HEX), .P87_INSTR_HEX(`P87_INSTR_HEX), .P88_INSTR_HEX(`P88_INSTR_HEX), .P89_INSTR_HEX(`P89_INSTR_HEX), .E0_INSTR_HEX(`E0_INSTR_HEX), .E1_INSTR_HEX(`E1_INSTR_HEX), .E2_INSTR_HEX(`E2_INSTR_HEX), .E3_INSTR_HEX(`E3_INSTR_HEX), .E4_INSTR_HEX(`E4_INSTR_HEX), .E5_INSTR_HEX(`E5_INSTR_HEX), .E6_INSTR_HEX(`E6_INSTR_HEX), .E7_INSTR_HEX(`E7_INSTR_HEX), .E8_INSTR_HEX(`E8_INSTR_HEX), .E9_INSTR_HEX(`E9_INSTR_HEX), .E10_INSTR_HEX(`E10_INSTR_HEX), .E11_INSTR_HEX(`E11_INSTR_HEX), .E12_INSTR_HEX(`E12_INSTR_HEX), .E13_INSTR_HEX(`E13_INSTR_HEX), .E14_INSTR_HEX(`E14_INSTR_HEX), .E15_INSTR_HEX(`E15_INSTR_HEX), .E16_INSTR_HEX(`E16_INSTR_HEX), .E17_INSTR_HEX(`E17_INSTR_HEX), .E18_INSTR_HEX(`E18_INSTR_HEX), .E19_INSTR_HEX(`E19_INSTR_HEX), .E20_INSTR_HEX(`E20_INSTR_HEX), .E21_INSTR_HEX(`E21_INSTR_HEX), .E22_INSTR_HEX(`E22_INSTR_HEX), .E23_INSTR_HEX(`E23_INSTR_HEX), .E24_INSTR_HEX(`E24_INSTR_HEX), .E25_INSTR_HEX(`E25_INSTR_HEX), .E26_INSTR_HEX(`E26_INSTR_HEX), .E27_INSTR_HEX(`E27_INSTR_HEX), .E28_INSTR_HEX(`E28_INSTR_HEX), .E29_INSTR_HEX(`E29_INSTR_HEX), .E30_INSTR_HEX(`E30_INSTR_HEX), .E31_INSTR_HEX(`E31_INSTR_HEX), .E32_INSTR_HEX(`E32_INSTR_HEX), .E33_INSTR_HEX(`E33_INSTR_HEX), .E34_INSTR_HEX(`E34_INSTR_HEX), .E35_INSTR_HEX(`E35_INSTR_HEX), .E36_INSTR_HEX(`E36_INSTR_HEX), .E37_INSTR_HEX(`E37_INSTR_HEX), .E38_INSTR_HEX(`E38_INSTR_HEX), .E39_INSTR_HEX(`E39_INSTR_HEX), .E40_INSTR_HEX(`E40_INSTR_HEX), .E41_INSTR_HEX(`E41_INSTR_HEX), .E42_INSTR_HEX(`E42_INSTR_HEX), .E43_INSTR_HEX(`E43_INSTR_HEX), .E44_INSTR_HEX(`E44_INSTR_HEX), .E45_INSTR_HEX(`E45_INSTR_HEX), .E46_INSTR_HEX(`E46_INSTR_HEX), .E47_INSTR_HEX(`E47_INSTR_HEX), .E48_INSTR_HEX(`E48_INSTR_HEX), .E49_INSTR_HEX(`E49_INSTR_HEX), .E50_INSTR_HEX(`E50_INSTR_HEX), .E51_INSTR_HEX(`E51_INSTR_HEX), .E52_INSTR_HEX(`E52_INSTR_HEX), .E53_INSTR_HEX(`E53_INSTR_HEX), .E54_INSTR_HEX(`E54_INSTR_HEX), .E55_INSTR_HEX(`E55_INSTR_HEX), .E56_INSTR_HEX(`E56_INSTR_HEX), .E57_INSTR_HEX(`E57_INSTR_HEX), .E58_INSTR_HEX(`E58_INSTR_HEX), .E59_INSTR_HEX(`E59_INSTR_HEX), .E60_INSTR_HEX(`E60_INSTR_HEX), .E61_INSTR_HEX(`E61_INSTR_HEX), .E62_INSTR_HEX(`E62_INSTR_HEX), .E63_INSTR_HEX(`E63_INSTR_HEX), .E64_INSTR_HEX(`E64_INSTR_HEX), .E65_INSTR_HEX(`E65_INSTR_HEX), .E66_INSTR_HEX(`E66_INSTR_HEX), .E67_INSTR_HEX(`E67_INSTR_HEX), .E68_INSTR_HEX(`E68_INSTR_HEX), .E69_INSTR_HEX(`E69_INSTR_HEX), .E70_INSTR_HEX(`E70_INSTR_HEX), .E71_INSTR_HEX(`E71_INSTR_HEX), .E72_INSTR_HEX(`E72_INSTR_HEX), .E73_INSTR_HEX(`E73_INSTR_HEX), .E74_INSTR_HEX(`E74_INSTR_HEX), .E75_INSTR_HEX(`E75_INSTR_HEX), .E76_INSTR_HEX(`E76_INSTR_HEX), .E77_INSTR_HEX(`E77_INSTR_HEX), .E78_INSTR_HEX(`E78_INSTR_HEX), .E79_INSTR_HEX(`E79_INSTR_HEX), .E80_INSTR_HEX(`E80_INSTR_HEX), .E81_INSTR_HEX(`E81_INSTR_HEX), .E82_INSTR_HEX(`E82_INSTR_HEX), .E83_INSTR_HEX(`E83_INSTR_HEX), .E84_INSTR_HEX(`E84_INSTR_HEX), .E85_INSTR_HEX(`E85_INSTR_HEX), .E86_INSTR_HEX(`E86_INSTR_HEX), .E87_INSTR_HEX(`E87_INSTR_HEX), .E88_INSTR_HEX(`E88_INSTR_HEX),
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
        .p36_halted(p36_halted), .p36_tohost(p36_tohost),
        .p37_halted(p37_halted), .p37_tohost(p37_tohost),
        .p38_halted(p38_halted), .p38_tohost(p38_tohost),
        .p39_halted(p39_halted), .p39_tohost(p39_tohost),
        .p40_halted(p40_halted), .p40_tohost(p40_tohost),
        .p41_halted(p41_halted), .p41_tohost(p41_tohost),
        .p42_halted(p42_halted), .p42_tohost(p42_tohost),
        .p43_halted(p43_halted), .p43_tohost(p43_tohost),
        .p44_halted(p44_halted), .p44_tohost(p44_tohost),
        .p45_halted(p45_halted), .p45_tohost(p45_tohost),
        .p46_halted(p46_halted), .p46_tohost(p46_tohost),
        .p47_halted(p47_halted), .p47_tohost(p47_tohost),
        .p48_halted(p48_halted), .p48_tohost(p48_tohost),
        .p49_halted(p49_halted), .p49_tohost(p49_tohost),
        .p50_halted(p50_halted), .p50_tohost(p50_tohost),
        .p51_halted(p51_halted), .p51_tohost(p51_tohost),
        .p52_halted(p52_halted), .p52_tohost(p52_tohost),
        .p53_halted(p53_halted), .p53_tohost(p53_tohost),
        .p54_halted(p54_halted), .p54_tohost(p54_tohost),
        .p55_halted(p55_halted), .p55_tohost(p55_tohost),
        .p56_halted(p56_halted), .p56_tohost(p56_tohost),
        .p57_halted(p57_halted), .p57_tohost(p57_tohost),
        .p58_halted(p58_halted), .p58_tohost(p58_tohost),
        .p59_halted(p59_halted), .p59_tohost(p59_tohost),
        .p60_halted(p60_halted), .p60_tohost(p60_tohost),
        .p61_halted(p61_halted), .p61_tohost(p61_tohost),
        .p62_halted(p62_halted), .p62_tohost(p62_tohost),
        .p63_halted(p63_halted), .p63_tohost(p63_tohost),
        .p64_halted(p64_halted), .p64_tohost(p64_tohost),
        .p65_halted(p65_halted), .p65_tohost(p65_tohost),
        .p66_halted(p66_halted), .p66_tohost(p66_tohost),
        .p67_halted(p67_halted), .p67_tohost(p67_tohost),
        .p68_halted(p68_halted), .p68_tohost(p68_tohost),
        .p69_halted(p69_halted), .p69_tohost(p69_tohost),
        .p70_halted(p70_halted), .p70_tohost(p70_tohost),
        .p71_halted(p71_halted), .p71_tohost(p71_tohost),
        .p72_halted(p72_halted), .p72_tohost(p72_tohost),
        .p73_halted(p73_halted), .p73_tohost(p73_tohost),
        .p74_halted(p74_halted), .p74_tohost(p74_tohost),
        .p75_halted(p75_halted), .p75_tohost(p75_tohost),
        .p76_halted(p76_halted), .p76_tohost(p76_tohost),
        .p77_halted(p77_halted), .p77_tohost(p77_tohost),
        .p78_halted(p78_halted), .p78_tohost(p78_tohost),
        .p79_halted(p79_halted), .p79_tohost(p79_tohost),
        .p80_halted(p80_halted), .p80_tohost(p80_tohost),
        .p81_halted(p81_halted), .p81_tohost(p81_tohost),
        .p82_halted(p82_halted), .p82_tohost(p82_tohost),
        .p83_halted(p83_halted), .p83_tohost(p83_tohost),
        .p84_halted(p84_halted), .p84_tohost(p84_tohost),
        .p85_halted(p85_halted), .p85_tohost(p85_tohost),
        .p86_halted(p86_halted), .p86_tohost(p86_tohost),
        .p87_halted(p87_halted), .p87_tohost(p87_tohost),
        .p88_halted(p88_halted), .p88_tohost(p88_tohost),
        .p89_halted(p89_halted), .p89_tohost(p89_tohost),
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
        .e35_halted(e35_halted), .e35_tohost(e35_tohost),
        .e36_halted(e36_halted), .e36_tohost(e36_tohost),
        .e37_halted(e37_halted), .e37_tohost(e37_tohost),
        .e38_halted(e38_halted), .e38_tohost(e38_tohost),
        .e39_halted(e39_halted), .e39_tohost(e39_tohost),
        .e40_halted(e40_halted), .e40_tohost(e40_tohost),
        .e41_halted(e41_halted), .e41_tohost(e41_tohost),
        .e42_halted(e42_halted), .e42_tohost(e42_tohost),
        .e43_halted(e43_halted), .e43_tohost(e43_tohost),
        .e44_halted(e44_halted), .e44_tohost(e44_tohost),
        .e45_halted(e45_halted), .e45_tohost(e45_tohost),
        .e46_halted(e46_halted), .e46_tohost(e46_tohost),
        .e47_halted(e47_halted), .e47_tohost(e47_tohost),
        .e48_halted(e48_halted), .e48_tohost(e48_tohost),
        .e49_halted(e49_halted), .e49_tohost(e49_tohost),
        .e50_halted(e50_halted), .e50_tohost(e50_tohost),
        .e51_halted(e51_halted), .e51_tohost(e51_tohost),
        .e52_halted(e52_halted), .e52_tohost(e52_tohost),
        .e53_halted(e53_halted), .e53_tohost(e53_tohost),
        .e54_halted(e54_halted), .e54_tohost(e54_tohost),
        .e55_halted(e55_halted), .e55_tohost(e55_tohost),
        .e56_halted(e56_halted), .e56_tohost(e56_tohost),
        .e57_halted(e57_halted), .e57_tohost(e57_tohost),
        .e58_halted(e58_halted), .e58_tohost(e58_tohost),
        .e59_halted(e59_halted), .e59_tohost(e59_tohost),
        .e60_halted(e60_halted), .e60_tohost(e60_tohost),
        .e61_halted(e61_halted), .e61_tohost(e61_tohost),
        .e62_halted(e62_halted), .e62_tohost(e62_tohost),
        .e63_halted(e63_halted), .e63_tohost(e63_tohost),
        .e64_halted(e64_halted), .e64_tohost(e64_tohost),
        .e65_halted(e65_halted), .e65_tohost(e65_tohost),
        .e66_halted(e66_halted), .e66_tohost(e66_tohost),
        .e67_halted(e67_halted), .e67_tohost(e67_tohost),
        .e68_halted(e68_halted), .e68_tohost(e68_tohost),
        .e69_halted(e69_halted), .e69_tohost(e69_tohost),
        .e70_halted(e70_halted), .e70_tohost(e70_tohost),
        .e71_halted(e71_halted), .e71_tohost(e71_tohost),
        .e72_halted(e72_halted), .e72_tohost(e72_tohost),
        .e73_halted(e73_halted), .e73_tohost(e73_tohost),
        .e74_halted(e74_halted), .e74_tohost(e74_tohost),
        .e75_halted(e75_halted), .e75_tohost(e75_tohost),
        .e76_halted(e76_halted), .e76_tohost(e76_tohost),
        .e77_halted(e77_halted), .e77_tohost(e77_tohost),
        .e78_halted(e78_halted), .e78_tohost(e78_tohost),
        .e79_halted(e79_halted), .e79_tohost(e79_tohost),
        .e80_halted(e80_halted), .e80_tohost(e80_tohost),
        .e81_halted(e81_halted), .e81_tohost(e81_tohost),
        .e82_halted(e82_halted), .e82_tohost(e82_tohost),
        .e83_halted(e83_halted), .e83_tohost(e83_tohost),
        .e84_halted(e84_halted), .e84_tohost(e84_tohost),
        .e85_halted(e85_halted), .e85_tohost(e85_tohost),
        .e86_halted(e86_halted), .e86_tohost(e86_tohost),
        .e87_halted(e87_halted), .e87_tohost(e87_tohost),
        .e88_halted(e88_halted), .e88_tohost(e88_tohost),
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
        $dumpfile("tb_soc.vcd");
        $dumpvars(0, tb_soc);

        if (!$value$plusargs("EXPECT_P0_TOHOST=%d", expect_p0)) expect_p0 = 119;
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
        if (!$value$plusargs("EXPECT_P36_TOHOST=%d", expect_p36)) expect_p36 = 42;
        if (!$value$plusargs("EXPECT_P37_TOHOST=%d", expect_p37)) expect_p37 = 42;
        if (!$value$plusargs("EXPECT_P38_TOHOST=%d", expect_p38)) expect_p38 = 42;
        if (!$value$plusargs("EXPECT_P39_TOHOST=%d", expect_p39)) expect_p39 = 42;
        if (!$value$plusargs("EXPECT_P40_TOHOST=%d", expect_p40)) expect_p40 = 42;
        if (!$value$plusargs("EXPECT_P41_TOHOST=%d", expect_p41)) expect_p41 = 42;
        if (!$value$plusargs("EXPECT_P42_TOHOST=%d", expect_p42)) expect_p42 = 42;
        if (!$value$plusargs("EXPECT_P43_TOHOST=%d", expect_p43)) expect_p43 = 42;
        if (!$value$plusargs("EXPECT_P44_TOHOST=%d", expect_p44)) expect_p44 = 42;
        if (!$value$plusargs("EXPECT_P45_TOHOST=%d", expect_p45)) expect_p45 = 42;
        if (!$value$plusargs("EXPECT_P46_TOHOST=%d", expect_p46)) expect_p46 = 42;
        if (!$value$plusargs("EXPECT_P47_TOHOST=%d", expect_p47)) expect_p47 = 42;
        if (!$value$plusargs("EXPECT_P48_TOHOST=%d", expect_p48)) expect_p48 = 42;
        if (!$value$plusargs("EXPECT_P49_TOHOST=%d", expect_p49)) expect_p49 = 42;
        if (!$value$plusargs("EXPECT_P50_TOHOST=%d", expect_p50)) expect_p50 = 42;
        if (!$value$plusargs("EXPECT_P51_TOHOST=%d", expect_p51)) expect_p51 = 42;
        if (!$value$plusargs("EXPECT_P52_TOHOST=%d", expect_p52)) expect_p52 = 42;
        if (!$value$plusargs("EXPECT_P53_TOHOST=%d", expect_p53)) expect_p53 = 42;
        if (!$value$plusargs("EXPECT_P54_TOHOST=%d", expect_p54)) expect_p54 = 42;
        if (!$value$plusargs("EXPECT_P55_TOHOST=%d", expect_p55)) expect_p55 = 42;
        if (!$value$plusargs("EXPECT_P56_TOHOST=%d", expect_p56)) expect_p56 = 42;
        if (!$value$plusargs("EXPECT_P57_TOHOST=%d", expect_p57)) expect_p57 = 42;
        if (!$value$plusargs("EXPECT_P58_TOHOST=%d", expect_p58)) expect_p58 = 42;
        if (!$value$plusargs("EXPECT_P59_TOHOST=%d", expect_p59)) expect_p59 = 42;
        if (!$value$plusargs("EXPECT_P60_TOHOST=%d", expect_p60)) expect_p60 = 42;
        if (!$value$plusargs("EXPECT_P61_TOHOST=%d", expect_p61)) expect_p61 = 42;
        if (!$value$plusargs("EXPECT_P62_TOHOST=%d", expect_p62)) expect_p62 = 42;
        if (!$value$plusargs("EXPECT_P63_TOHOST=%d", expect_p63)) expect_p63 = 42;
        if (!$value$plusargs("EXPECT_P64_TOHOST=%d", expect_p64)) expect_p64 = 42;
        if (!$value$plusargs("EXPECT_P65_TOHOST=%d", expect_p65)) expect_p65 = 42;
        if (!$value$plusargs("EXPECT_P66_TOHOST=%d", expect_p66)) expect_p66 = 42;
        if (!$value$plusargs("EXPECT_P67_TOHOST=%d", expect_p67)) expect_p67 = 42;
        if (!$value$plusargs("EXPECT_P68_TOHOST=%d", expect_p68)) expect_p68 = 42;
        if (!$value$plusargs("EXPECT_P69_TOHOST=%d", expect_p69)) expect_p69 = 42;
        if (!$value$plusargs("EXPECT_P70_TOHOST=%d", expect_p70)) expect_p70 = 42;
        if (!$value$plusargs("EXPECT_P71_TOHOST=%d", expect_p71)) expect_p71 = 42;
        if (!$value$plusargs("EXPECT_P72_TOHOST=%d", expect_p72)) expect_p72 = 42;
        if (!$value$plusargs("EXPECT_P73_TOHOST=%d", expect_p73)) expect_p73 = 42;
        if (!$value$plusargs("EXPECT_P74_TOHOST=%d", expect_p74)) expect_p74 = 42;
        if (!$value$plusargs("EXPECT_P75_TOHOST=%d", expect_p75)) expect_p75 = 42;
        if (!$value$plusargs("EXPECT_P76_TOHOST=%d", expect_p76)) expect_p76 = 42;
        if (!$value$plusargs("EXPECT_P77_TOHOST=%d", expect_p77)) expect_p77 = 42;
        if (!$value$plusargs("EXPECT_P78_TOHOST=%d", expect_p78)) expect_p78 = 42;
        if (!$value$plusargs("EXPECT_P79_TOHOST=%d", expect_p79)) expect_p79 = 42;
        if (!$value$plusargs("EXPECT_P80_TOHOST=%d", expect_p80)) expect_p80 = 42;
        if (!$value$plusargs("EXPECT_P81_TOHOST=%d", expect_p81)) expect_p81 = 42;
        if (!$value$plusargs("EXPECT_P82_TOHOST=%d", expect_p82)) expect_p82 = 42;
        if (!$value$plusargs("EXPECT_P83_TOHOST=%d", expect_p83)) expect_p83 = 42;
        if (!$value$plusargs("EXPECT_P84_TOHOST=%d", expect_p84)) expect_p84 = 42;
        if (!$value$plusargs("EXPECT_P85_TOHOST=%d", expect_p85)) expect_p85 = 42;
        if (!$value$plusargs("EXPECT_P86_TOHOST=%d", expect_p86)) expect_p86 = 42;
        if (!$value$plusargs("EXPECT_P87_TOHOST=%d", expect_p87)) expect_p87 = 42;
        if (!$value$plusargs("EXPECT_P88_TOHOST=%d", expect_p88)) expect_p88 = 42;
        if (!$value$plusargs("EXPECT_P89_TOHOST=%d", expect_p89)) expect_p89 = 42;
        if (!$value$plusargs("EXPECT_E0_TOHOST=%d", expect_e0)) expect_e0 = 110;
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
        if (!$value$plusargs("EXPECT_E35_TOHOST=%d", expect_e35)) expect_e35 = 42;
        if (!$value$plusargs("EXPECT_E36_TOHOST=%d", expect_e36)) expect_e36 = 42;
        if (!$value$plusargs("EXPECT_E37_TOHOST=%d", expect_e37)) expect_e37 = 42;
        if (!$value$plusargs("EXPECT_E38_TOHOST=%d", expect_e38)) expect_e38 = 42;
        if (!$value$plusargs("EXPECT_E39_TOHOST=%d", expect_e39)) expect_e39 = 42;
        if (!$value$plusargs("EXPECT_E40_TOHOST=%d", expect_e40)) expect_e40 = 42;
        if (!$value$plusargs("EXPECT_E41_TOHOST=%d", expect_e41)) expect_e41 = 42;
        if (!$value$plusargs("EXPECT_E42_TOHOST=%d", expect_e42)) expect_e42 = 42;
        if (!$value$plusargs("EXPECT_E43_TOHOST=%d", expect_e43)) expect_e43 = 42;
        if (!$value$plusargs("EXPECT_E44_TOHOST=%d", expect_e44)) expect_e44 = 42;
        if (!$value$plusargs("EXPECT_E45_TOHOST=%d", expect_e45)) expect_e45 = 42;
        if (!$value$plusargs("EXPECT_E46_TOHOST=%d", expect_e46)) expect_e46 = 42;
        if (!$value$plusargs("EXPECT_E47_TOHOST=%d", expect_e47)) expect_e47 = 42;
        if (!$value$plusargs("EXPECT_E48_TOHOST=%d", expect_e48)) expect_e48 = 42;
        if (!$value$plusargs("EXPECT_E49_TOHOST=%d", expect_e49)) expect_e49 = 42;
        if (!$value$plusargs("EXPECT_E50_TOHOST=%d", expect_e50)) expect_e50 = 42;
        if (!$value$plusargs("EXPECT_E51_TOHOST=%d", expect_e51)) expect_e51 = 42;
        if (!$value$plusargs("EXPECT_E52_TOHOST=%d", expect_e52)) expect_e52 = 42;
        if (!$value$plusargs("EXPECT_E53_TOHOST=%d", expect_e53)) expect_e53 = 42;
        if (!$value$plusargs("EXPECT_E54_TOHOST=%d", expect_e54)) expect_e54 = 42;
        if (!$value$plusargs("EXPECT_E55_TOHOST=%d", expect_e55)) expect_e55 = 42;
        if (!$value$plusargs("EXPECT_E56_TOHOST=%d", expect_e56)) expect_e56 = 42;
        if (!$value$plusargs("EXPECT_E57_TOHOST=%d", expect_e57)) expect_e57 = 42;
        if (!$value$plusargs("EXPECT_E58_TOHOST=%d", expect_e58)) expect_e58 = 42;
        if (!$value$plusargs("EXPECT_E59_TOHOST=%d", expect_e59)) expect_e59 = 42;
        if (!$value$plusargs("EXPECT_E60_TOHOST=%d", expect_e60)) expect_e60 = 42;
        if (!$value$plusargs("EXPECT_E61_TOHOST=%d", expect_e61)) expect_e61 = 42;
        if (!$value$plusargs("EXPECT_E62_TOHOST=%d", expect_e62)) expect_e62 = 42;
        if (!$value$plusargs("EXPECT_E63_TOHOST=%d", expect_e63)) expect_e63 = 42;
        if (!$value$plusargs("EXPECT_E64_TOHOST=%d", expect_e64)) expect_e64 = 42;
        if (!$value$plusargs("EXPECT_E65_TOHOST=%d", expect_e65)) expect_e65 = 42;
        if (!$value$plusargs("EXPECT_E66_TOHOST=%d", expect_e66)) expect_e66 = 42;
        if (!$value$plusargs("EXPECT_E67_TOHOST=%d", expect_e67)) expect_e67 = 42;
        if (!$value$plusargs("EXPECT_E68_TOHOST=%d", expect_e68)) expect_e68 = 42;
        if (!$value$plusargs("EXPECT_E69_TOHOST=%d", expect_e69)) expect_e69 = 42;
        if (!$value$plusargs("EXPECT_E70_TOHOST=%d", expect_e70)) expect_e70 = 42;
        if (!$value$plusargs("EXPECT_E71_TOHOST=%d", expect_e71)) expect_e71 = 42;
        if (!$value$plusargs("EXPECT_E72_TOHOST=%d", expect_e72)) expect_e72 = 42;
        if (!$value$plusargs("EXPECT_E73_TOHOST=%d", expect_e73)) expect_e73 = 42;
        if (!$value$plusargs("EXPECT_E74_TOHOST=%d", expect_e74)) expect_e74 = 42;
        if (!$value$plusargs("EXPECT_E75_TOHOST=%d", expect_e75)) expect_e75 = 42;
        if (!$value$plusargs("EXPECT_E76_TOHOST=%d", expect_e76)) expect_e76 = 42;
        if (!$value$plusargs("EXPECT_E77_TOHOST=%d", expect_e77)) expect_e77 = 42;
        if (!$value$plusargs("EXPECT_E78_TOHOST=%d", expect_e78)) expect_e78 = 42;
        if (!$value$plusargs("EXPECT_E79_TOHOST=%d", expect_e79)) expect_e79 = 42;
        if (!$value$plusargs("EXPECT_E80_TOHOST=%d", expect_e80)) expect_e80 = 42;
        if (!$value$plusargs("EXPECT_E81_TOHOST=%d", expect_e81)) expect_e81 = 42;
        if (!$value$plusargs("EXPECT_E82_TOHOST=%d", expect_e82)) expect_e82 = 42;
        if (!$value$plusargs("EXPECT_E83_TOHOST=%d", expect_e83)) expect_e83 = 42;
        if (!$value$plusargs("EXPECT_E84_TOHOST=%d", expect_e84)) expect_e84 = 42;
        if (!$value$plusargs("EXPECT_E85_TOHOST=%d", expect_e85)) expect_e85 = 42;
        if (!$value$plusargs("EXPECT_E86_TOHOST=%d", expect_e86)) expect_e86 = 42;
        if (!$value$plusargs("EXPECT_E87_TOHOST=%d", expect_e87)) expect_e87 = 42;
        if (!$value$plusargs("EXPECT_E88_TOHOST=%d", expect_e88)) expect_e88 = 42;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 300;

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
            $display("FAIL: not all 179 cores halted within %0d cycles (p0=%b p1=%b p2=%b p3=%b p4=%b p5=%b p6=%b p7=%b p8=%b p9=%b p10=%b p11=%b p12=%b p13=%b p14=%b p15=%b p16=%b p17=%b p18=%b p19=%b p20=%b p21=%b p22=%b p23=%b p24=%b p25=%b p26=%b p27=%b p28=%b p29=%b p30=%b p31=%b p32=%b p33=%b p34=%b p35=%b p36=%b p37=%b p38=%b p39=%b p40=%b p41=%b p42=%b p43=%b p44=%b p45=%b p46=%b p47=%b p48=%b p49=%b p50=%b p51=%b p52=%b p53=%b p54=%b p55=%b p56=%b p57=%b p58=%b p59=%b p60=%b p61=%b p62=%b p63=%b p64=%b p65=%b p66=%b p67=%b p68=%b p69=%b p70=%b p71=%b p72=%b p73=%b p74=%b p75=%b p76=%b p77=%b p78=%b p79=%b p80=%b p81=%b p82=%b p83=%b p84=%b p85=%b p86=%b p87=%b p88=%b p89=%b e0=%b e1=%b e2=%b e3=%b e4=%b e5=%b e6=%b e7=%b e8=%b e9=%b e10=%b e11=%b e12=%b e13=%b e14=%b e15=%b e16=%b e17=%b e18=%b e19=%b e20=%b e21=%b e22=%b e23=%b e24=%b e25=%b e26=%b e27=%b e28=%b e29=%b e30=%b e31=%b e32=%b e33=%b e34=%b e35=%b e36=%b e37=%b e38=%b e39=%b e40=%b e41=%b e42=%b e43=%b e44=%b e45=%b e46=%b e47=%b e48=%b e49=%b e50=%b e51=%b e52=%b e53=%b e54=%b e55=%b e56=%b e57=%b e58=%b e59=%b e60=%b e61=%b e62=%b e63=%b e64=%b e65=%b e66=%b e67=%b e68=%b e69=%b e70=%b e71=%b e72=%b e73=%b e74=%b e75=%b e76=%b e77=%b e78=%b e79=%b e80=%b e81=%b e82=%b e83=%b e84=%b e85=%b e86=%b e87=%b e88=%b)",
                      max_cycles, p0_halted, p1_halted, p2_halted, p3_halted, p4_halted, p5_halted, p6_halted, p7_halted, p8_halted, p9_halted, p10_halted, p11_halted, p12_halted, p13_halted, p14_halted, p15_halted, p16_halted, p17_halted, p18_halted, p19_halted, p20_halted, p21_halted, p22_halted, p23_halted, p24_halted, p25_halted, p26_halted, p27_halted, p28_halted, p29_halted, p30_halted, p31_halted, p32_halted, p33_halted, p34_halted, p35_halted, p36_halted, p37_halted, p38_halted, p39_halted, p40_halted, p41_halted, p42_halted, p43_halted, p44_halted, p45_halted, p46_halted, p47_halted, p48_halted, p49_halted, p50_halted, p51_halted, p52_halted, p53_halted, p54_halted, p55_halted, p56_halted, p57_halted, p58_halted, p59_halted, p60_halted, p61_halted, p62_halted, p63_halted, p64_halted, p65_halted, p66_halted, p67_halted, p68_halted, p69_halted, p70_halted, p71_halted, p72_halted, p73_halted, p74_halted, p75_halted, p76_halted, p77_halted, p78_halted, p79_halted, p80_halted, p81_halted, p82_halted, p83_halted, p84_halted, p85_halted, p86_halted, p87_halted, p88_halted, p89_halted, e0_halted, e1_halted, e2_halted, e3_halted, e4_halted, e5_halted, e6_halted, e7_halted, e8_halted, e9_halted, e10_halted, e11_halted, e12_halted, e13_halted, e14_halted, e15_halted, e16_halted, e17_halted, e18_halted, e19_halted, e20_halted, e21_halted, e22_halted, e23_halted, e24_halted, e25_halted, e26_halted, e27_halted, e28_halted, e29_halted, e30_halted, e31_halted, e32_halted, e33_halted, e34_halted, e35_halted, e36_halted, e37_halted, e38_halted, e39_halted, e40_halted, e41_halted, e42_halted, e43_halted, e44_halted, e45_halted, e46_halted, e47_halted, e48_halted, e49_halted, e50_halted, e51_halted, e52_halted, e53_halted, e54_halted, e55_halted, e56_halted, e57_halted, e58_halted, e59_halted, e60_halted, e61_halted, e62_halted, e63_halted, e64_halted, e65_halted, e66_halted, e67_halted, e68_halted, e69_halted, e70_halted, e71_halted, e72_halted, e73_halted, e74_halted, e75_halted, e76_halted, e77_halted, e78_halted, e79_halted, e80_halted, e81_halted, e82_halted, e83_halted, e84_halted, e85_halted, e86_halted, e87_halted, e88_halted);
        end else begin
            $display("All 179 cores halted after %0d cycles.", cycle_count);
            check_core(p0_tohost, expect_p0, "p0-core (pipelined)");
            check_core(p1_tohost, expect_p1, "p1-core (pipelined)");
            check_core(p2_tohost, expect_p2, "p2-core (pipelined)");
            check_core(p3_tohost, expect_p3, "p3-core (pipelined)");
            check_core(p4_tohost, expect_p4, "p4-core (pipelined)");
            check_core(p5_tohost, expect_p5, "p5-core (pipelined)");
            check_core(p6_tohost, expect_p6, "p6-core (pipelined)");
            check_core(p7_tohost, expect_p7, "p7-core (pipelined)");
            check_core(p8_tohost, expect_p8, "p8-core (pipelined)");
            check_core(p9_tohost, expect_p9, "p9-core (pipelined)");
            check_core(p10_tohost, expect_p10, "p10-core (pipelined)");
            check_core(p11_tohost, expect_p11, "p11-core (pipelined)");
            check_core(p12_tohost, expect_p12, "p12-core (pipelined)");
            check_core(p13_tohost, expect_p13, "p13-core (pipelined)");
            check_core(p14_tohost, expect_p14, "p14-core (pipelined)");
            check_core(p15_tohost, expect_p15, "p15-core (pipelined)");
            check_core(p16_tohost, expect_p16, "p16-core (pipelined)");
            check_core(p17_tohost, expect_p17, "p17-core (pipelined)");
            check_core(p18_tohost, expect_p18, "p18-core (pipelined)");
            check_core(p19_tohost, expect_p19, "p19-core (pipelined)");
            check_core(p20_tohost, expect_p20, "p20-core (pipelined)");
            check_core(p21_tohost, expect_p21, "p21-core (pipelined)");
            check_core(p22_tohost, expect_p22, "p22-core (pipelined)");
            check_core(p23_tohost, expect_p23, "p23-core (pipelined)");
            check_core(p24_tohost, expect_p24, "p24-core (pipelined)");
            check_core(p25_tohost, expect_p25, "p25-core (pipelined)");
            check_core(p26_tohost, expect_p26, "p26-core (pipelined)");
            check_core(p27_tohost, expect_p27, "p27-core (pipelined)");
            check_core(p28_tohost, expect_p28, "p28-core (pipelined)");
            check_core(p29_tohost, expect_p29, "p29-core (pipelined)");
            check_core(p30_tohost, expect_p30, "p30-core (pipelined)");
            check_core(p31_tohost, expect_p31, "p31-core (pipelined)");
            check_core(p32_tohost, expect_p32, "p32-core (pipelined)");
            check_core(p33_tohost, expect_p33, "p33-core (pipelined)");
            check_core(p34_tohost, expect_p34, "p34-core (pipelined)");
            check_core(p35_tohost, expect_p35, "p35-core (pipelined)");
            check_core(p36_tohost, expect_p36, "p36-core (pipelined)");
            check_core(p37_tohost, expect_p37, "p37-core (pipelined)");
            check_core(p38_tohost, expect_p38, "p38-core (pipelined)");
            check_core(p39_tohost, expect_p39, "p39-core (pipelined)");
            check_core(p40_tohost, expect_p40, "p40-core (pipelined)");
            check_core(p41_tohost, expect_p41, "p41-core (pipelined)");
            check_core(p42_tohost, expect_p42, "p42-core (pipelined)");
            check_core(p43_tohost, expect_p43, "p43-core (pipelined)");
            check_core(p44_tohost, expect_p44, "p44-core (pipelined)");
            check_core(p45_tohost, expect_p45, "p45-core (pipelined)");
            check_core(p46_tohost, expect_p46, "p46-core (pipelined)");
            check_core(p47_tohost, expect_p47, "p47-core (pipelined)");
            check_core(p48_tohost, expect_p48, "p48-core (pipelined)");
            check_core(p49_tohost, expect_p49, "p49-core (pipelined)");
            check_core(p50_tohost, expect_p50, "p50-core (pipelined)");
            check_core(p51_tohost, expect_p51, "p51-core (pipelined)");
            check_core(p52_tohost, expect_p52, "p52-core (pipelined)");
            check_core(p53_tohost, expect_p53, "p53-core (pipelined)");
            check_core(p54_tohost, expect_p54, "p54-core (pipelined)");
            check_core(p55_tohost, expect_p55, "p55-core (pipelined)");
            check_core(p56_tohost, expect_p56, "p56-core (pipelined)");
            check_core(p57_tohost, expect_p57, "p57-core (pipelined)");
            check_core(p58_tohost, expect_p58, "p58-core (pipelined)");
            check_core(p59_tohost, expect_p59, "p59-core (pipelined)");
            check_core(p60_tohost, expect_p60, "p60-core (pipelined)");
            check_core(p61_tohost, expect_p61, "p61-core (pipelined)");
            check_core(p62_tohost, expect_p62, "p62-core (pipelined)");
            check_core(p63_tohost, expect_p63, "p63-core (pipelined)");
            check_core(p64_tohost, expect_p64, "p64-core (pipelined)");
            check_core(p65_tohost, expect_p65, "p65-core (pipelined)");
            check_core(p66_tohost, expect_p66, "p66-core (pipelined)");
            check_core(p67_tohost, expect_p67, "p67-core (pipelined)");
            check_core(p68_tohost, expect_p68, "p68-core (pipelined)");
            check_core(p69_tohost, expect_p69, "p69-core (pipelined)");
            check_core(p70_tohost, expect_p70, "p70-core (pipelined)");
            check_core(p71_tohost, expect_p71, "p71-core (pipelined)");
            check_core(p72_tohost, expect_p72, "p72-core (pipelined)");
            check_core(p73_tohost, expect_p73, "p73-core (pipelined)");
            check_core(p74_tohost, expect_p74, "p74-core (pipelined)");
            check_core(p75_tohost, expect_p75, "p75-core (pipelined)");
            check_core(p76_tohost, expect_p76, "p76-core (pipelined)");
            check_core(p77_tohost, expect_p77, "p77-core (pipelined)");
            check_core(p78_tohost, expect_p78, "p78-core (pipelined)");
            check_core(p79_tohost, expect_p79, "p79-core (pipelined)");
            check_core(p80_tohost, expect_p80, "p80-core (pipelined)");
            check_core(p81_tohost, expect_p81, "p81-core (pipelined)");
            check_core(p82_tohost, expect_p82, "p82-core (pipelined)");
            check_core(p83_tohost, expect_p83, "p83-core (pipelined)");
            check_core(p84_tohost, expect_p84, "p84-core (pipelined)");
            check_core(p85_tohost, expect_p85, "p85-core (pipelined)");
            check_core(p86_tohost, expect_p86, "p86-core (pipelined)");
            check_core(p87_tohost, expect_p87, "p87-core (pipelined)");
            check_core(p88_tohost, expect_p88, "p88-core (pipelined)");
            check_core(p89_tohost, expect_p89, "p89-core (pipelined)");
            check_core(e0_tohost, expect_e0, "e0-core (single-cycle)");
            check_core(e1_tohost, expect_e1, "e1-core (single-cycle)");
            check_core(e2_tohost, expect_e2, "e2-core (single-cycle)");
            check_core(e3_tohost, expect_e3, "e3-core (single-cycle)");
            check_core(e4_tohost, expect_e4, "e4-core (single-cycle)");
            check_core(e5_tohost, expect_e5, "e5-core (single-cycle)");
            check_core(e6_tohost, expect_e6, "e6-core (single-cycle)");
            check_core(e7_tohost, expect_e7, "e7-core (single-cycle)");
            check_core(e8_tohost, expect_e8, "e8-core (single-cycle)");
            check_core(e9_tohost, expect_e9, "e9-core (single-cycle)");
            check_core(e10_tohost, expect_e10, "e10-core (single-cycle)");
            check_core(e11_tohost, expect_e11, "e11-core (single-cycle)");
            check_core(e12_tohost, expect_e12, "e12-core (single-cycle)");
            check_core(e13_tohost, expect_e13, "e13-core (single-cycle)");
            check_core(e14_tohost, expect_e14, "e14-core (single-cycle)");
            check_core(e15_tohost, expect_e15, "e15-core (single-cycle)");
            check_core(e16_tohost, expect_e16, "e16-core (single-cycle)");
            check_core(e17_tohost, expect_e17, "e17-core (single-cycle)");
            check_core(e18_tohost, expect_e18, "e18-core (single-cycle)");
            check_core(e19_tohost, expect_e19, "e19-core (single-cycle)");
            check_core(e20_tohost, expect_e20, "e20-core (single-cycle)");
            check_core(e21_tohost, expect_e21, "e21-core (single-cycle)");
            check_core(e22_tohost, expect_e22, "e22-core (single-cycle)");
            check_core(e23_tohost, expect_e23, "e23-core (single-cycle)");
            check_core(e24_tohost, expect_e24, "e24-core (single-cycle)");
            check_core(e25_tohost, expect_e25, "e25-core (single-cycle)");
            check_core(e26_tohost, expect_e26, "e26-core (single-cycle)");
            check_core(e27_tohost, expect_e27, "e27-core (single-cycle)");
            check_core(e28_tohost, expect_e28, "e28-core (single-cycle)");
            check_core(e29_tohost, expect_e29, "e29-core (single-cycle)");
            check_core(e30_tohost, expect_e30, "e30-core (single-cycle)");
            check_core(e31_tohost, expect_e31, "e31-core (single-cycle)");
            check_core(e32_tohost, expect_e32, "e32-core (single-cycle)");
            check_core(e33_tohost, expect_e33, "e33-core (single-cycle)");
            check_core(e34_tohost, expect_e34, "e34-core (single-cycle)");
            check_core(e35_tohost, expect_e35, "e35-core (single-cycle)");
            check_core(e36_tohost, expect_e36, "e36-core (single-cycle)");
            check_core(e37_tohost, expect_e37, "e37-core (single-cycle)");
            check_core(e38_tohost, expect_e38, "e38-core (single-cycle)");
            check_core(e39_tohost, expect_e39, "e39-core (single-cycle)");
            check_core(e40_tohost, expect_e40, "e40-core (single-cycle)");
            check_core(e41_tohost, expect_e41, "e41-core (single-cycle)");
            check_core(e42_tohost, expect_e42, "e42-core (single-cycle)");
            check_core(e43_tohost, expect_e43, "e43-core (single-cycle)");
            check_core(e44_tohost, expect_e44, "e44-core (single-cycle)");
            check_core(e45_tohost, expect_e45, "e45-core (single-cycle)");
            check_core(e46_tohost, expect_e46, "e46-core (single-cycle)");
            check_core(e47_tohost, expect_e47, "e47-core (single-cycle)");
            check_core(e48_tohost, expect_e48, "e48-core (single-cycle)");
            check_core(e49_tohost, expect_e49, "e49-core (single-cycle)");
            check_core(e50_tohost, expect_e50, "e50-core (single-cycle)");
            check_core(e51_tohost, expect_e51, "e51-core (single-cycle)");
            check_core(e52_tohost, expect_e52, "e52-core (single-cycle)");
            check_core(e53_tohost, expect_e53, "e53-core (single-cycle)");
            check_core(e54_tohost, expect_e54, "e54-core (single-cycle)");
            check_core(e55_tohost, expect_e55, "e55-core (single-cycle)");
            check_core(e56_tohost, expect_e56, "e56-core (single-cycle)");
            check_core(e57_tohost, expect_e57, "e57-core (single-cycle)");
            check_core(e58_tohost, expect_e58, "e58-core (single-cycle)");
            check_core(e59_tohost, expect_e59, "e59-core (single-cycle)");
            check_core(e60_tohost, expect_e60, "e60-core (single-cycle)");
            check_core(e61_tohost, expect_e61, "e61-core (single-cycle)");
            check_core(e62_tohost, expect_e62, "e62-core (single-cycle)");
            check_core(e63_tohost, expect_e63, "e63-core (single-cycle)");
            check_core(e64_tohost, expect_e64, "e64-core (single-cycle)");
            check_core(e65_tohost, expect_e65, "e65-core (single-cycle)");
            check_core(e66_tohost, expect_e66, "e66-core (single-cycle)");
            check_core(e67_tohost, expect_e67, "e67-core (single-cycle)");
            check_core(e68_tohost, expect_e68, "e68-core (single-cycle)");
            check_core(e69_tohost, expect_e69, "e69-core (single-cycle)");
            check_core(e70_tohost, expect_e70, "e70-core (single-cycle)");
            check_core(e71_tohost, expect_e71, "e71-core (single-cycle)");
            check_core(e72_tohost, expect_e72, "e72-core (single-cycle)");
            check_core(e73_tohost, expect_e73, "e73-core (single-cycle)");
            check_core(e74_tohost, expect_e74, "e74-core (single-cycle)");
            check_core(e75_tohost, expect_e75, "e75-core (single-cycle)");
            check_core(e76_tohost, expect_e76, "e76-core (single-cycle)");
            check_core(e77_tohost, expect_e77, "e77-core (single-cycle)");
            check_core(e78_tohost, expect_e78, "e78-core (single-cycle)");
            check_core(e79_tohost, expect_e79, "e79-core (single-cycle)");
            check_core(e80_tohost, expect_e80, "e80-core (single-cycle)");
            check_core(e81_tohost, expect_e81, "e81-core (single-cycle)");
            check_core(e82_tohost, expect_e82, "e82-core (single-cycle)");
            check_core(e83_tohost, expect_e83, "e83-core (single-cycle)");
            check_core(e84_tohost, expect_e84, "e84-core (single-cycle)");
            check_core(e85_tohost, expect_e85, "e85-core (single-cycle)");
            check_core(e86_tohost, expect_e86, "e86-core (single-cycle)");
            check_core(e87_tohost, expect_e87, "e87-core (single-cycle)");
            check_core(e88_tohost, expect_e88, "e88-core (single-cycle)");
            if (!any_fail) $display("PASS: all 179 cores matched their expected values");
        end

        $finish;
    end
endmodule
