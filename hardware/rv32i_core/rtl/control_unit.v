// Pure combinational instruction decode: opcode/funct3/funct7 (bits
// 6:0, 14:12, 31:25 of the instruction) -> every control signal the
// rest of the single-cycle datapath needs. No state, no memory - this
// module IS the decode stage.
`timescale 1ns/1ps

module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,

    output reg        reg_write,   // write ALU/mem/pc+4 result back to rd
    output reg        mem_read,    // this is a load
    output reg        mem_write,   // this is a store
    output reg        mem_to_reg,  // rd <= memory data, not ALU result
    output reg        alu_src,     // ALU's B input is the immediate, not rs2
    output reg        branch,      // this is a conditional branch
    output reg        jump,        // this is JAL (unconditional, PC-relative)
    output reg        jalr,        // this is JALR (unconditional, register-relative)
    output reg        auipc,       // ALU's A input is PC, not rs1
    output reg        lui,         // ALU's A input is 0, not rs1 - LUI's instr[19:15] bits are
                                    // part of its immediate, NOT a real rs1 field (U-type has no
                                    // rs1 at all); feeding them to the regfile as rs1_addr and
                                    // adding whatever garbage register that reads as would corrupt
                                    // every LUI result - caught while wiring up cpu_core.v, before
                                    // it ever ran, by re-checking U-type's actual bit layout.
    output reg [3:0]  alu_op,
    output reg [1:0]  mem_size,    // 00=byte 01=half 10=word
    output reg        mem_unsigned,// zero-extend (LBU/LHU) instead of sign-extend
    output reg        illegal,     // opcode not recognized - see cpu_core.v's own handling

    // Minimal RV32F (see fp_regfile.v/fp_addsub.v/fp_mul.v): FLW/FSW +
    // FADD.S/FSUB.S/FMUL.S only. fp_reg_write means this instruction's
    // RESULT targets fp_regfile, not the integer regfile (FLW and the
    // 3 arithmetic ops). is_fp_mem means only FLW/FSW - address
    // computation reuses mem_read/mem_write/alu_src/alu_op=ADD above
    // completely unchanged; this just tells cpu_core.v which SIDE
    // (a load's rd, or a store's rs2) is the FP register instead of
    // the integer one. fp_op selects which FPU unit's result a
    // FADD.S/FSUB.S/FMUL.S instruction writes back.
    output reg        fp_reg_write,
    output reg        is_fp_mem,
    output reg [2:0]  fp_op,       // 000=add 001=sub 010=mul 011=div

    // TLB invalidation (see mmu.v): SFENCE.VMA's REAL RISC-V encoding is
    // opcode=OP_SYSTEM, funct7=0000001, funct3=000 (rs1/rs2 ignored here -
    // full flush only, no selective ASID/vaddr flush, matching this
    // project's already-simplified MMU). ECALL/EBREAK are funct7=0000000
    // - is_sfence deliberately does NOT overlap them, so cpu_core.v/
    // cpu_core_pipelined.v can tell "halt for tohost" apart from "flush
    // the TLB" even though both share OP_SYSTEM.
    output reg        is_sfence
);
    localparam OP_LOAD    = 7'b0000011;
    localparam OP_IMM     = 7'b0010011;
    localparam OP_JALR    = 7'b1100111;
    localparam OP_STORE   = 7'b0100011;
    localparam OP_BRANCH  = 7'b1100011;
    localparam OP_LUI     = 7'b0110111;
    localparam OP_AUIPC   = 7'b0010111;
    localparam OP_JAL     = 7'b1101111;
    localparam OP_REG     = 7'b0110011;
    localparam OP_FENCE   = 7'b0001111;
    localparam OP_SYSTEM  = 7'b1110011;
    localparam OP_LOAD_FP  = 7'b0000111;
    localparam OP_STORE_FP = 7'b0100111;
    localparam OP_FP       = 7'b1010011;

    localparam FP_ADD  = 3'b000;
    localparam FP_SUB  = 3'b001;
    localparam FP_MUL  = 3'b010;
    localparam FP_DIV  = 3'b011;
    localparam FP_SQRT = 3'b100;

    // ALU op encoding shared with alu.v.
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_SLL  = 4'b0010;
    localparam ALU_SLT  = 4'b0011;
    localparam ALU_SLTU = 4'b0100;
    localparam ALU_XOR  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_OR   = 4'b1000;
    localparam ALU_AND  = 4'b1001;

    // funct3-driven ALU selection shared by OP_IMM and OP_REG - the
    // only difference between them is whether SUB/SRA are possible
    // (only OP_REG's SUB/ADD share funct3=000 and need funct7 bit 30
    // to disambiguate; OP_IMM's funct3=000 is always ADDI).
    function [3:0] alu_op_for_funct3;
        input [2:0] f3;
        input       is_sub_or_sra; // funct7[5] (bit 30 of instr) when opcode==OP_REG, or SRAI's funct7 bit for OP_IMM
        begin
            case (f3)
                3'b000:  alu_op_for_funct3 = is_sub_or_sra ? ALU_SUB : ALU_ADD;
                3'b001:  alu_op_for_funct3 = ALU_SLL;
                3'b010:  alu_op_for_funct3 = ALU_SLT;
                3'b011:  alu_op_for_funct3 = ALU_SLTU;
                3'b100:  alu_op_for_funct3 = ALU_XOR;
                3'b101:  alu_op_for_funct3 = is_sub_or_sra ? ALU_SRA : ALU_SRL;
                3'b110:  alu_op_for_funct3 = ALU_OR;
                3'b111:  alu_op_for_funct3 = ALU_AND;
                default: alu_op_for_funct3 = ALU_ADD;
            endcase
        end
    endfunction

    always @(*) begin
        // Defaults - every non-taken path below starts here, so each
        // case only needs to set what actually differs.
        reg_write    = 1'b0;
        mem_read     = 1'b0;
        mem_write    = 1'b0;
        mem_to_reg   = 1'b0;
        alu_src      = 1'b0;
        branch       = 1'b0;
        jump         = 1'b0;
        jalr         = 1'b0;
        auipc        = 1'b0;
        lui          = 1'b0;
        alu_op       = ALU_ADD;
        mem_size     = 2'b10;
        mem_unsigned = 1'b0;
        illegal      = 1'b0;
        fp_reg_write = 1'b0;
        is_fp_mem    = 1'b0;
        fp_op        = FP_ADD;
        is_sfence    = 1'b0;

        case (opcode)
            OP_REG: begin
                reg_write = 1'b1;
                alu_op    = alu_op_for_funct3(funct3, funct7[5]);
            end

            OP_IMM: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                // SRAI is the only OP_IMM case where funct7 matters
                // (SLLI/SRLI/SRAI's shift amount lives in imm[4:0];
                // imm[11:5] doubles as funct7 for exactly this reason).
                alu_op    = alu_op_for_funct3(funct3, (funct3 == 3'b101) && funct7[5]);
            end

            OP_LOAD: begin
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                alu_src    = 1'b1;      // address = rs1 + imm
                alu_op     = ALU_ADD;
                mem_size   = (funct3[1:0] == 2'b00) ? 2'b00 :
                             (funct3[1:0] == 2'b01) ? 2'b01 : 2'b10;
                mem_unsigned = funct3[2];  // LBU/LHU have funct3[2]=1
            end

            OP_STORE: begin
                mem_write = 1'b1;
                alu_src   = 1'b1;       // address = rs1 + imm
                alu_op    = ALU_ADD;
                mem_size  = (funct3 == 3'b000) ? 2'b00 :
                            (funct3 == 3'b001) ? 2'b01 : 2'b10;
            end

            OP_LOAD_FP: begin
                // Same address computation as OP_LOAD (rs1+imm, an
                // INTEGER register base) - only the destination is
                // different (fp_regfile, not the integer regfile).
                // reg_write stays 0 deliberately: rd's 5-bit number
                // aliases between the two register files, so leaving
                // the integer regfile's write enable off is required
                // correctness here, not just unnecessary caution.
                fp_reg_write = 1'b1;
                is_fp_mem    = 1'b1;
                mem_read     = 1'b1;
                alu_src      = 1'b1;
                alu_op       = ALU_ADD;
                mem_size     = 2'b10; // FLW is always a full word
            end

            OP_STORE_FP: begin
                // Same address computation as OP_STORE - only the
                // store DATA source differs (fp_regfile's rs2, not the
                // integer regfile's).
                is_fp_mem = 1'b1;
                mem_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
                mem_size  = 2'b10; // FSW is always a full word
            end

            OP_FP: begin
                // FADD.S/FSUB.S/FMUL.S - rs1/rs2/rd are ALL fp_regfile
                // registers, no integer regfile or ALU involvement at
                // all. funct7[6:2] is the real RV32F "funct5" operation
                // field (funct7[1:0] is the format field, 00=single -
                // ignored here since this project only implements
                // single precision).
                case (funct7[6:2])
                    5'b00000: begin fp_op = FP_ADD;  fp_reg_write = 1'b1; end // FADD.S
                    5'b00001: begin fp_op = FP_SUB;  fp_reg_write = 1'b1; end // FSUB.S
                    5'b00010: begin fp_op = FP_MUL;  fp_reg_write = 1'b1; end // FMUL.S
                    5'b00011: begin fp_op = FP_DIV;  fp_reg_write = 1'b1; end // FDIV.S
                    // FSQRT.S - architecturally ONE-OPERAND (rs2's field
                    // is a reserved sub-opcode selector in the real
                    // encoding, not a real second register); cpu_core.v/
                    // cpu_core_pipelined.v's fp_sqrt instantiation only
                    // ever wires up rs1's data, matching this.
                    5'b01011: begin fp_op = FP_SQRT; fp_reg_write = 1'b1; end // FSQRT.S
                    // unimplemented RV32F op: fp_reg_write stays 0 (its
                    // default), deliberately NOT set here, so an
                    // unrecognized op can never sneak a garbage FP
                    // register write through - same principle as the
                    // top-level default case below for entirely unknown
                    // opcodes.
                    default:  illegal = 1'b1;
                endcase
            end

            OP_BRANCH: begin
                branch = 1'b1;
                // funct3 selects the comparison the same way alu_op
                // does for SLT/SLTU - cpu_core.v derives the branch
                // decision from a compare, not directly from alu_op,
                // so this just needs SUB-style equality/relational
                // info; see cpu_core.v for exactly how funct3 is used.
            end

            OP_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                lui       = 1'b1;
                alu_op    = ALU_ADD;   // rd = 0 + imm (imm already shifted by imm_gen)
            end

            OP_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                auipc     = 1'b1;      // rd = PC + imm
                alu_op    = ALU_ADD;
            end

            OP_JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
            end

            OP_JALR: begin
                reg_write = 1'b1;
                jalr      = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;   // target = rs1 + imm (LSB cleared in cpu_core.v)
            end

            OP_FENCE: begin
                // No-op: single-hart, non-pipelined, no cache - there
                // is nothing for FENCE to actually order.
            end

            OP_SYSTEM: begin
                // ECALL/EBREAK (funct7=0000000) - repurposed as the
                // testbench tohost convention (see cpu_core.v/tb_cpu.v),
                // not real trap handling; no datapath signals needed
                // here, cpu_core.v watches (opcode==OP_SYSTEM) directly
                // to latch a0. SFENCE.VMA (funct7=0000001, funct3=000)
                // is the one OP_SYSTEM encoding that means something
                // else entirely (flush the TLB) - see is_sfence's own
                // comment above.
                is_sfence = (funct7 == 7'b0000001) && (funct3 == 3'b000);
            end

            default: begin
                illegal = 1'b1;
            end
        endcase
    end
endmodule
