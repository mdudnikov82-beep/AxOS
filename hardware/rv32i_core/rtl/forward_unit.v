// EX-stage operand forwarding: covers the distance-1 (previous
// instruction, result sitting in the EX/MEM pipeline register) and
// distance-2 (previous-previous instruction, result sitting in
// MEM/WB) RAW hazard cases. The distance-3 case (WB writing while ID
// reads the same cycle) is instead handled by regfile.v's own
// write-through bypass - simpler than routing a third forwarding path
// all the way back into ID.
//
// forward_a/forward_b encoding:
//   2'b00 - no hazard, use the ID/EX-stage regfile-read value as-is
//   2'b10 - forward from EX/MEM (the more recent write - higher priority)
//   2'b01 - forward from MEM/WB
`timescale 1ns/1ps

module forward_unit (
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
        // EX/MEM takes priority over MEM/WB when both would match -
        // it's the more recently written value (one instruction closer).
        if (ex_mem_reg_write && ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs1)
            forward_a = 2'b10;
        else if (mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_ex_rs1)
            forward_a = 2'b01;
        else
            forward_a = 2'b00;

        if (ex_mem_reg_write && ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs2)
            forward_b = 2'b10;
        else if (mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_ex_rs2)
            forward_b = 2'b01;
        else
            forward_b = 2'b00;
    end
endmodule
