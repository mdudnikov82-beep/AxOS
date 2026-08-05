// Pure combinational instruction decode for AxISA (see docs/ISA.md) -
// milestone 2: full ALUR/ALUI/BRANCH/HALT (milestone 1) plus GLUON/
// BARYON/MESON/LOAD/STORE/JAL.
//
// Every field is assigned ONLY inside its own opcode's case arm (a
// design-review requirement before this was written): several classes
// reuse the same bit RANGE for genuinely different fields (e.g. bits
// [26:25] are ALUR/ALUI/BRANCH's `bank`, but also the top 2 bits of
// GLUON's funct and exactly MESON's funct) - hoisting a shared default
// above the case, the way milestone 1 did for its own 4 classes, would
// silently misdecode those bits for classes that don't share that
// meaning. Only LOAD/STORE/JAL/HALT genuinely share one field's bit
// position ([26:24], an N-bank register index each calls nd/ns/nd/
// tohost_reg) - factored into one shared `mem_nd_ns`/`jal_nd`-style
// extraction is still done per-arm below, not hoisted, to keep every
// class's decode self-contained and avoid ambiguity if that agreement
// ever changes for one class but not another.
//
// `write_bank`/`write_addr` resolve WHERE a result is written (any
// bank for ALUR/ALUI/GLUON, always N for BARYON/MESON/LOAD/JAL) -
// cpu_core.v broadcasts these to all 4 banks' write ports exactly like
// milestone 1 did, gated by the same per-bank `write_en = reg_write &&
// (write_bank==X)` demux, just with `write_bank` now a real per-class
// mux instead of always being milestone 1's shared `bank` field.
// `write_data` itself (ALU result / GLUON combine / BARYON sum / MESON
// diff / loaded word / PC+4) is NOT decided here - it depends on
// computed values (ALU output, memory read data) this module doesn't
// have, so cpu_core.v muxes it.
`timescale 1ns/1ps

module control_unit (
    input  wire [31:0] instr,

    output reg  [1:0]  bank,       // ALUR/ALUI/BRANCH's shared operand bank
    output reg  [3:0]  alu_funct,
    output reg  [2:0]  branch_funct,
    output reg  [2:0]  rd_addr,
    output reg  [2:0]  rs1_addr,
    output reg  [2:0]  rs2_addr,
    output reg  [31:0] imm,
    output reg          alu_src_imm,
    output reg          is_branch,
    output reg          is_halt,
    output reg  [2:0]  tohost_reg,

    // GLUON
    output reg          is_gluon,
    output reg  [2:0]  gluon_funct,
    output reg  [1:0]  gluon_rs1_bank,
    output reg  [2:0]  gluon_rs1_reg,
    output reg  [1:0]  gluon_rs2_bank,
    output reg  [2:0]  gluon_rs2_reg,

    // BARYON (rr/gg/bb banks are implicit - always R/G/B, per docs/ISA.md)
    output reg          is_baryon,
    output reg  [2:0]  baryon_rr,
    output reg  [2:0]  baryon_gg,
    output reg  [2:0]  baryon_bb,

    // MESON
    output reg          is_meson,
    output reg  [1:0]  meson_funct, // only funct[0] is used (funct=00 is the sole v0.1 rule); kept 2 bits to match docs/ISA.md's field width
    output reg  [1:0]  meson_q1_bank,
    output reg  [2:0]  meson_q1_reg,
    output reg  [1:0]  meson_q2_bank,
    output reg  [2:0]  meson_q2_reg,

    // LOAD/STORE
    output reg          is_load,
    output reg          is_store,
    output reg  [2:0]  mem_nd_ns,   // LOAD's nd / STORE's ns - same bit position, always N
    output reg  [1:0]  mem_base_bank,
    output reg  [2:0]  mem_base_reg,
    output reg  [31:0] mem_imm,     // sign-extended 19-bit byte offset

    // JAL
    output reg          is_jal,
    output reg  [31:0] jal_imm,     // sign-extended 24-bit PC-relative offset

    // Resolved write target (valid whenever reg_write=1)
    output reg  [1:0]  write_bank,
    output reg  [2:0]  write_addr,

    output reg          reg_write,
    output reg          illegal
);
    localparam OP_ALUR   = 5'b00000;
    localparam OP_ALUI   = 5'b00001;
    localparam OP_GLUON  = 5'b00010;
    localparam OP_BARYON = 5'b00011;
    localparam OP_MESON  = 5'b00100;
    localparam OP_LOAD   = 5'b00101;
    localparam OP_STORE  = 5'b00110;
    localparam OP_BRANCH = 5'b00111;
    localparam OP_JAL    = 5'b01000;
    localparam OP_HALT   = 5'b01001;

    localparam BANK_N = 2'b11;

    wire [4:0] opcode = instr[31:27];

    always @(*) begin
        bank           = 2'b0;
        alu_funct      = 4'b0;
        branch_funct   = 3'b0;
        rd_addr        = 3'b0;
        rs1_addr       = 3'b0;
        rs2_addr       = 3'b0;
        imm            = 32'b0;
        alu_src_imm    = 1'b0;
        is_branch      = 1'b0;
        is_halt        = 1'b0;
        tohost_reg     = 3'b0;

        is_gluon       = 1'b0;
        gluon_funct    = 3'b0;
        gluon_rs1_bank = 2'b0;
        gluon_rs1_reg  = 3'b0;
        gluon_rs2_bank = 2'b0;
        gluon_rs2_reg  = 3'b0;

        is_baryon      = 1'b0;
        baryon_rr      = 3'b0;
        baryon_gg      = 3'b0;
        baryon_bb      = 3'b0;

        is_meson       = 1'b0;
        meson_funct    = 2'b0;
        meson_q1_bank  = 2'b0;
        meson_q1_reg   = 3'b0;
        meson_q2_bank  = 2'b0;
        meson_q2_reg   = 3'b0;

        is_load        = 1'b0;
        is_store       = 1'b0;
        mem_nd_ns      = 3'b0;
        mem_base_bank  = 2'b0;
        mem_base_reg   = 3'b0;
        mem_imm        = 32'b0;

        is_jal         = 1'b0;
        jal_imm        = 32'b0;

        write_bank     = 2'b0;
        write_addr     = 3'b0;

        reg_write      = 1'b0;
        illegal        = 1'b0;

        case (opcode)
            OP_ALUR: begin
                bank      = instr[26:25];
                alu_funct = instr[24:21];
                rd_addr   = instr[20:18];
                rs1_addr  = instr[17:15];
                rs2_addr  = instr[14:12];
                if (alu_funct >= 4'b1010) begin
                    illegal = 1'b1; // reserved ALU funct - see alu.v
                end else begin
                    reg_write  = 1'b1;
                    write_bank = bank;
                    write_addr = rd_addr;
                end
            end

            OP_ALUI: begin
                bank        = instr[26:25];
                alu_funct   = instr[24:21];
                rd_addr     = instr[20:18];
                rs1_addr    = instr[17:15];
                alu_src_imm = 1'b1;
                imm         = {{17{instr[14]}}, instr[14:0]};
                if (alu_funct >= 4'b1010) begin
                    illegal = 1'b1;
                end else begin
                    reg_write  = 1'b1;
                    write_bank = bank;
                    write_addr = rd_addr;
                end
            end

            OP_GLUON: begin
                is_gluon       = 1'b1;
                gluon_funct    = instr[26:24];
                write_bank     = instr[23:22];
                write_addr     = instr[21:19];
                gluon_rs1_bank = instr[18:17];
                gluon_rs1_reg  = instr[16:14];
                gluon_rs2_bank = instr[13:12];
                gluon_rs2_reg  = instr[11:9];
                reg_write      = 1'b1; // all 8 funct codes are defined (docs/ISA.md) - no reserved case
            end

            OP_BARYON: begin
                is_baryon = 1'b1;
                // funct = instr[26:24], only funct=000 is defined in v0.1
                write_bank = BANK_N;
                write_addr = instr[23:21];
                baryon_rr  = instr[20:18];
                baryon_gg  = instr[17:15];
                baryon_bb  = instr[14:12];
                if (instr[26:24] != 3'b000) begin
                    illegal = 1'b1;
                end else begin
                    reg_write = 1'b1;
                end
            end

            OP_MESON: begin
                is_meson      = 1'b1;
                meson_funct   = instr[26:25];
                write_bank    = BANK_N;
                write_addr    = instr[24:22];
                meson_q1_bank = instr[21:20];
                meson_q1_reg  = instr[19:17];
                meson_q2_bank = instr[16:15];
                meson_q2_reg  = instr[14:12];
                if (meson_funct != 2'b00) begin
                    illegal = 1'b1;
                end else begin
                    reg_write = 1'b1;
                end
            end

            OP_LOAD: begin
                is_load       = 1'b1;
                mem_nd_ns     = instr[26:24];
                mem_base_bank = instr[23:22];
                mem_base_reg  = instr[21:19];
                mem_imm       = {{13{instr[18]}}, instr[18:0]};
                write_bank    = BANK_N;
                write_addr    = mem_nd_ns;
                reg_write     = 1'b1;
            end

            OP_STORE: begin
                is_store      = 1'b1;
                mem_nd_ns     = instr[26:24];
                mem_base_bank = instr[23:22];
                mem_base_reg  = instr[21:19];
                mem_imm       = {{13{instr[18]}}, instr[18:0]};
                // no reg_write - STORE never writes a register
            end

            OP_BRANCH: begin
                bank         = instr[26:25];
                branch_funct = instr[24:22];
                rs1_addr     = instr[21:19];
                rs2_addr     = instr[18:16];
                imm          = {{16{instr[15]}}, instr[15:0]};
                is_branch    = 1'b1;
            end

            OP_JAL: begin
                is_jal     = 1'b1;
                write_bank = BANK_N;
                write_addr = instr[26:24];
                jal_imm    = {{8{instr[23]}}, instr[23:0]};
                reg_write  = 1'b1;
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
