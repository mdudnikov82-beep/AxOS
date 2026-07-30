// EX-stage operand forwarding for the FP register file (fp_regfile.v).
// Structurally identical to forward_unit.v, but DELIBERATELY WITHOUT
// its "!= 5'd0" exclusions: forward_unit.v skips forwarding into x0
// because x0 is hardwired zero in the INTEGER regfile - fp_regfile.v
// has no such rule at all, f0 is an ordinary, freely-writable
// register in RV32F, so f0 must forward exactly like any other
// register number.
//
// Safe to reuse the SAME id_ex_rs1/id_ex_rs2/ex_mem_rd/mem_wb_rd
// register-NUMBER fields the integer forward_unit also uses: a given
// EX/MEM or MEM/WB "slot" is one instruction, and control_unit.v
// guarantees reg_write/fp_reg_write are mutually exclusive for it, so
// a numeric rd coincidence between the two register files can never
// make both forwarding units fire for the same producer.
//
// forward_a/forward_b encoding (same as forward_unit.v):
//   2'b00 - no hazard, use the ID/EX-stage fp_regfile-read value as-is
//   2'b10 - forward from EX/MEM (the more recent write - higher priority)
//   2'b01 - forward from MEM/WB
`timescale 1ns/1ps

module fp_forward_unit (
    input  wire [4:0] id_ex_rs1,
    input  wire [4:0] id_ex_rs2,

    input  wire [4:0] ex_mem_rd,
    input  wire       ex_mem_reg_write,

    input  wire [4:0] mem_wb_rd,
    input  wire       mem_wb_reg_write,

    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b
);
    always @(*) begin
        if (ex_mem_reg_write && ex_mem_rd == id_ex_rs1)
            forward_a = 2'b10;
        else if (mem_wb_reg_write && mem_wb_rd == id_ex_rs1)
            forward_a = 2'b01;
        else
            forward_a = 2'b00;

        if (ex_mem_reg_write && ex_mem_rd == id_ex_rs2)
            forward_b = 2'b10;
        else if (mem_wb_reg_write && mem_wb_rd == id_ex_rs2)
            forward_b = 2'b01;
        else
            forward_b = 2'b00;
    end
endmodule
