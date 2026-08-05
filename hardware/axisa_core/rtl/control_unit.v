// Pure combinational instruction decode for AxISA (see docs/ISA.md) -
// milestone 1 subset only: ALUR, ALUI, BRANCH, HALT. GLUON/BARYON/
// MESON/LOAD/STORE/JAL are decoded as `illegal` for now (milestone 2).
//
// ALUR and ALUI share identical bit positions for opcode/bank/funct/
// rd/rs1 (bits 31 down to 15) by design - only what follows bit 15
// differs (rs2 vs imm). BRANCH has its own layout (3-bit funct, not
// 4-bit) since it only needs 6 comparison codes, not ALUR's 10 ops.
`timescale 1ns/1ps

module control_unit (
    input  wire [31:0] instr,

    output reg  [1:0]  bank,       // which register bank ALUR/ALUI/BRANCH operate on
    output reg  [3:0]  alu_funct,  // ALUR/ALUI's ALU op select (see alu.v)
    output reg  [2:0]  branch_funct,
    output reg  [2:0]  rd_addr,
    output reg  [2:0]  rs1_addr,
    output reg  [2:0]  rs2_addr,
    output reg  [31:0] imm,        // sign-extended per format, ALUR's own rs2 case leaves this unused
    output reg          reg_write, // write rd_addr in `bank` this cycle
    output reg          alu_src_imm, // ALU's B input is `imm`, not rs2_data (ALUI)
    output reg          is_branch,
    output reg          is_halt,
    output reg  [2:0]  tohost_reg,
    output reg          illegal
);
    localparam OP_ALUR   = 5'b00000;
    localparam OP_ALUI   = 5'b00001;
    localparam OP_BRANCH = 5'b00111;
    localparam OP_HALT   = 5'b01001;

    wire [4:0] opcode = instr[31:27];

    always @(*) begin
        bank         = instr[26:25];
        alu_funct    = instr[24:21];
        branch_funct = 3'b0;
        rd_addr      = instr[20:18];
        rs1_addr     = instr[17:15];
        rs2_addr     = instr[14:12];
        imm          = 32'b0;
        reg_write    = 1'b0;
        alu_src_imm  = 1'b0;
        is_branch    = 1'b0;
        is_halt      = 1'b0;
        tohost_reg   = 3'b0;
        illegal      = 1'b0;

        case (opcode)
            OP_ALUR: begin
                reg_write = 1'b1;
            end

            OP_ALUI: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                imm         = {{17{instr[14]}}, instr[14:0]}; // sign-extend 15-bit imm, uniform per docs/ISA.md
            end

            OP_BRANCH: begin
                branch_funct = instr[24:22];
                rs1_addr     = instr[21:19];
                rs2_addr     = instr[18:16];
                imm          = {{16{instr[15]}}, instr[15:0]}; // sign-extend 16-bit branch offset
                is_branch    = 1'b1;
            end

            OP_HALT: begin
                tohost_reg = instr[26:24];
                is_halt    = 1'b1;
            end

            default: begin
                illegal = 1'b1;
            end
        endcase
    end
endmodule
