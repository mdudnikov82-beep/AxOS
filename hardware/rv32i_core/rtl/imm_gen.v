// Extracts and sign-extends the immediate for whichever instruction
// format `instr`'s opcode indicates. Format is determined purely from
// opcode[6:0] - this is a combinational lookup, no state.
//
// RV32I immediate layouts (all sign-extended from their own top bit):
//   I-type: imm[11:0]  = instr[31:20]
//   S-type: imm[11:0]  = instr[31:25] , instr[11:7]
//   B-type: imm[12:1]  = instr[31],instr[7],instr[30:25],instr[11:8], imm[0]=0
//   U-type: imm[31:12] = instr[31:12], imm[11:0]=0
//   J-type: imm[20:1]  = instr[31],instr[19:12],instr[20],instr[30:21], imm[0]=0
`timescale 1ns/1ps

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;

    wire [6:0] opcode = instr[6:0];

    always @(*) begin
        case (opcode)
            OP_LOAD, OP_IMM, OP_JALR:
                imm = {{20{instr[31]}}, instr[31:20]};
            OP_STORE:
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            OP_BRANCH:
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            OP_LUI, OP_AUIPC:
                imm = {instr[31:12], 12'b0};
            OP_JAL:
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default:
                imm = 32'b0;
        endcase
    end
endmodule
