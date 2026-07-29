// Detects the one RAW hazard forward_unit.v can't fix: a LOAD sitting
// in EX (its result isn't real until MEM finishes, one cycle later)
// whose destination register is needed by the instruction right
// behind it, currently in ID. Forwarding can't produce data that
// doesn't exist yet - the only fix is a one-cycle stall: freeze PC and
// IF/ID, and turn the load-use instruction's own ID/EX slot into a
// bubble so it doesn't spuriously execute a half-decoded instruction
// while stalled.
`timescale 1ns/1ps

module hazard_unit (
    input  wire       id_ex_mem_read,
    input  wire [4:0] id_ex_rd,
    input  wire [4:0] if_id_rs1,
    input  wire [4:0] if_id_rs2,

    output wire       stall   // 1: freeze PC/IF-ID, bubble ID/EX
);
    assign stall = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                   ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));
endmodule
