// Minimal heterogeneous SoC: one P-core (cpu_core_pipelined, the
// 5-stage pipeline - performance) and one E-core (cpu_core, the
// single-cycle design - efficiency) side by side, each with its own
// private instruction/data memory. No shared bus or interconnect yet:
// the point of this module is only to prove two genuinely different
// cores run at the same time, on the same clock, executing different
// programs - the real building block a bigger multi-core SoC would
// scale up from.
`timescale 1ns/1ps

module soc_top #(
    parameter P_INSTR_HEX     = "",
    parameter E_INSTR_HEX     = "",
    parameter INSTR_MEM_WORDS = 1024,
    parameter DATA_MEM_BYTES  = 8192
) (
    input  wire        clk,
    input  wire        reset,
    output wire        p_halted,
    output wire [31:0]  p_tohost,
    output wire        e_halted,
    output wire [31:0]  e_tohost,
    output wire        both_halted
);
    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS),
        .INSTR_INIT_FILE(P_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES)
    ) p_core (
        .clk(clk), .reset(reset),
        .halted(p_halted), .tohost_value(p_tohost)
    );

    cpu_core #(
        .INSTR_MEM_WORDS(INSTR_MEM_WORDS),
        .INSTR_INIT_FILE(E_INSTR_HEX),
        .DATA_MEM_BYTES(DATA_MEM_BYTES)
    ) e_core (
        .clk(clk), .reset(reset),
        .halted(e_halted), .tohost_value(e_tohost)
    );

    assign both_halted = p_halted && e_halted;
endmodule
