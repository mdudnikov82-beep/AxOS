// Pure combinational instruction decode for AxISA (see docs/ISA.md) -
// milestone 2: full ALUR/ALUI/BRANCH/HALT (milestone 1) plus GLUON/
// BARYON/MESON/LOAD/STORE/JAL. Plus RFT/SYSCALL/MVSR (traps/privilege
// modes) - this module stays a PURE function of `instr` alone even for
// the privilege check (mode-dependent trap decisions are made in
// cpu_core.v instead, deliberately, so no other module ever needs to
// know the CPU's runtime state just to decode an instruction).
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
    output reg  [2:0]  baryon_funct, // v2.0: 000=SUM 001=MAJ 010=EPS 011=QN (docs/ISA.md)

    // MESON
    output reg          is_meson,
    output reg  [1:0]  meson_funct, // v2.0: 00=DIFF 01=SINGLET 10=QN (docs/ISA.md); 11 reserved
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

    // RFT / SYSCALL / MVSR (traps + privilege) - see docs/ISA.md's
    // "Traps" section. is_rft/is_mvsr are PRIVILEGED (cpu_core.v traps
    // them with cause=PRIV_VIOLATION if mode==user, since that check
    // needs runtime state this module deliberately doesn't have).
    output reg          is_rft,
    output reg          is_syscall,
    output reg          is_mvsr,
    output reg          mvsr_dir,     // 0=read (special->N), 1=write (N->special)
    output reg  [1:0]  mvsr_selreg,  // 00=EPC 01=CAUSE 10=SAVED_MODE 11=SAVED_IE
    output reg  [2:0]  mvsr_nreg,    // bare N-bank index, same shape as LOAD's nd/STORE's ns

    // PTB (page table base) - split out from MVSR because mvsr_selreg's
    // 2-bit field is already fully populated (see docs/ISA.md's Traps
    // section - all 4 encodings assigned) - a brand-new privileged
    // opcode, same read/write shape as MVSR but with only one register.
    output reg          is_ptb,
    output reg          ptb_dir,      // 0=read (PTB->N), 1=write (N->PTB)
    output reg  [2:0]  ptb_nreg,

    // QHAD / QCNOT - classical quantum-circuit-simulator extension (see
    // docs/ISA.md's QHAD/QCNOT sections). Both only ever touch the R
    // bank; the actual register addresses are resolved HERE from a
    // small selector field (like BARYON's implicit rr/gg/bb), not
    // instruction-encoded directly. reg_write is intentionally left 0
    // for both - the write path is entirely the new multi-cycle
    // q-sequencer FSM in cpu_core.v, not the normal single-cycle write
    // path this module drives for every other opcode.
    output reg          is_qhad,
    output reg          qhad_qubit,   // which qubit the Hadamard acts on
    output reg          qhad_half,    // which of the 2 independent amplitude-pairs for that qubit
    output reg          is_qcnot,
    output reg          qcnot_ctrl,   // which qubit is the control (the other is the target)
    output reg  [2:0]  q_reg_i,      // "Re" address of amplitude alpha (Im = q_reg_i+1)
    output reg  [2:0]  q_reg_j,      // "Re" address of amplitude beta  (Im = q_reg_j+1)

    // QMEASURE - third member of the same extension. Unlike QHAD, it
    // has no `half`-equivalent bit: measuring a qubit inherently sums
    // over BOTH amplitudes sharing that qubit's value, so `qmeasure_
    // qubit` alone fully determines both outcome groups (see docs/
    // ISA.md's QMEASURE section for the pairing table). `qmeasure_nd`
    // is a bare N-bank index (same shape as LOAD's nd/HALT's
    // tohost_reg) - the 1-bit outcome is written there by the
    // qm-sequencer's own independent N-write path, not through the
    // normal write_data/write_bank broadcast (reg_write stays 0 here
    // too, same reasoning as QHAD/QCNOT).
    // STRING (v2.0 step 4, asymptotic freedom): the color flux tube
    // between two same-color quarks. Reads through the ordinary
    // bank/rs1_addr/rs2_addr path; cpu_core.v's string sequencer adds
    // the distance-dependent stall cycles.
    output reg          is_string,

    // SU3MUL (v2.0 step 5): U*psi, U = 3x3 complex SU(3) matrix in
    // memory at N[su3_ns], psi = color vector in R/G/B[su3_src..+1].
    // cpu_core.v's su-sequencer owns every read/write - reg_write stays 0.
    // MTAG (v2.1 step 1): memory tagging. funct 00 IRG nd, ns (random
    // pointer tag), 01 STG ns (set the granule's tag), 10 LDG nd, ns
    // (read the granule's tag into a pointer), 11 reserved.
    // JALR (v2.1 step 2): indirect jump-and-link - nd = PC+4,
    // PC = (N[jalr_ns] + imm) with the low 2 bits cleared. The return
    // half of a function call; reuses jal_imm for its offset.
    // REGGE (v2.1 step 3): Regge trajectories of the rotating string.
    // funct 00 SPIN.M / 01 SPIN.B: J = a0 + a'*M^2 (meson / baryon);
    // 10 MASS.M / 11 MASS.B: M = sqrt((J - a0) / a'). N-bank binary32.
    output reg          is_regge,
    output reg  [1:0]  regge_funct,
    output reg  [2:0]  regge_ns,

    output reg          is_jalr,
    output reg  [2:0]  jalr_ns,

    output reg          is_mtag,
    output reg  [1:0]  mtag_funct,
    output reg  [2:0]  mtag_ns,

    // PLAQ (v2.2): lattice-QCD plaquette, (1/3) Re Tr(U1 U2 U3^dag U4^dag)
    // of 4 link matrices at N[su3_ns]. Runs on the su-sequencer; the
    // N[nd] write goes through the normal path on its terminal cycle.
    output reg          is_plaq,
    // LINKMUL (v2.3 step 1): C = A' * B', 3x3 complex matrices in memory at
    // N[nc], N[na], N[nb]; A' = A or A^dag, B' = B or B^dag.
    output reg          is_linkmul,
    // REUNIT (v2.3 step 2): pull the 3x3 complex matrix at N[ru_ns] back
    // onto SU(3), in place (microcoded - see tools/reunit_ucode.py)
    output reg          is_reunit,
    // SWEEP (v2.3 step 3): the average plaquette of a whole periodic L x L
    // lattice at N[su3_ns] into N[nd]; sw_l1 = L - 1
    output reg          is_sweep,
    output reg  [1:0]  sw_l1,
    output reg  [2:0]  ru_ns,
    output reg          lm_daga, lm_dagb,
    output reg  [2:0]  lm_na, lm_nb, lm_nc,
    // METRO (v2.2 step 2): the Metropolis step. dS = beta*(P_old - P_new);
    // funct 0 ACCEPT: nd = (r < exp(-dS)), 1 WEIGHT: nd = min(1, exp(-dS)).
    output reg          is_metro,
    output reg          metro_weight,
    output reg  [2:0]  metro_na, metro_nb, metro_nbeta,
    output reg          is_su3mul,
    output reg  [2:0]  su3_ns,
    output reg  [2:0]  su3_dst,
    output reg  [2:0]  su3_src,

    output reg          is_qmeasure,
    output reg          qmeasure_qubit,
    output reg  [2:0]  qmeasure_nd,
    output reg  [2:0]  qm_reg_a0,    // "Re" address of outcome-0 amplitude A (Im = qm_reg_a0+1)
    output reg  [2:0]  qm_reg_a1,    // "Re" address of outcome-0 amplitude B (Im = qm_reg_a1+1)
    output reg  [2:0]  qm_reg_b0,    // "Re" address of outcome-1 amplitude A (Im = qm_reg_b0+1)
    output reg  [2:0]  qm_reg_b1,    // "Re" address of outcome-1 amplitude B (Im = qm_reg_b1+1)

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
    localparam OP_RFT    = 5'b01010;
    localparam OP_SYSCALL = 5'b01011;
    localparam OP_MVSR   = 5'b01100;
    localparam OP_PTB    = 5'b01101;
    localparam OP_QHAD   = 5'b01110;
    localparam OP_QCNOT  = 5'b01111;
    localparam OP_QMEASURE = 5'b10000;
    localparam OP_STRING   = 5'b10001;
    localparam OP_SU3MUL   = 5'b10010;
    localparam OP_MTAG     = 5'b10011;
    localparam OP_JALR     = 5'b10100;
    localparam OP_REGGE    = 5'b10101;
    localparam OP_PLAQ     = 5'b10110;
    localparam OP_METRO    = 5'b10111;
    localparam OP_LINKMUL  = 5'b11000;
    localparam OP_REUNIT   = 5'b11001;
    localparam OP_SWEEP    = 5'b11010;

    localparam BANK_R = 2'b00;
    localparam BANK_G = 2'b01;
    localparam BANK_B = 2'b10;
    localparam BANK_N = 2'b11;

    // GLUON funct: the 8 gluons (docs/ISA.md). GL_XY = color X, anticolor Y.
    localparam GL_RG = 3'd0;
    localparam GL_GR = 3'd1;
    localparam GL_RB = 3'd2;
    localparam GL_BR = 3'd3;
    localparam GL_GB = 3'd4;
    localparam GL_BG = 3'd5;
    localparam GL_L3 = 3'd6;
    localparam GL_L8 = 3'd7;

    wire [4:0] opcode = instr[31:27];

    reg [1:0] gl_need_bank; // GLUON: the only source bank that can absorb this gluon

    always @(*) begin
        gl_need_bank   = 2'b0;
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
        baryon_funct   = 3'b0;

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

        is_rft         = 1'b0;
        is_syscall     = 1'b0;
        is_mvsr        = 1'b0;
        mvsr_dir       = 1'b0;
        mvsr_selreg    = 2'b0;
        mvsr_nreg      = 3'b0;

        is_ptb         = 1'b0;
        ptb_dir        = 1'b0;
        ptb_nreg       = 3'b0;

        is_qhad        = 1'b0;
        qhad_qubit     = 1'b0;
        qhad_half      = 1'b0;
        is_qcnot       = 1'b0;
        qcnot_ctrl     = 1'b0;
        q_reg_i        = 3'b0;
        q_reg_j        = 3'b0;

        is_string      = 1'b0;
        is_regge       = 1'b0;
        regge_funct    = 2'b0;
        regge_ns       = 3'b0;
        is_jalr        = 1'b0;
        jalr_ns        = 3'b0;
        is_mtag        = 1'b0;
        mtag_funct     = 2'b0;
        mtag_ns        = 3'b0;
        is_plaq        = 1'b0;
        is_linkmul     = 1'b0;
        is_reunit      = 1'b0;
        is_sweep       = 1'b0;
        sw_l1          = 2'b0;
        ru_ns          = 3'b0;
        lm_daga        = 1'b0;
        lm_dagb        = 1'b0;
        lm_na          = 3'b0;
        lm_nb          = 3'b0;
        lm_nc          = 3'b0;
        is_metro       = 1'b0;
        metro_weight   = 1'b0;
        metro_na       = 3'b0;
        metro_nb       = 3'b0;
        metro_nbeta    = 3'b0;
        is_su3mul      = 1'b0;
        su3_ns         = 3'b0;
        su3_dst        = 3'b0;
        su3_src        = 3'b0;
        is_qmeasure    = 1'b0;
        qmeasure_qubit = 1'b0;
        qmeasure_nd    = 3'b0;
        qm_reg_a0      = 3'b0;
        qm_reg_a1      = 3'b0;
        qm_reg_b0      = 3'b0;
        qm_reg_b1      = 3'b0;

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
                // v2.0 real gluons (docs/ISA.md): one source quark, one
                // destination. rs2 mirrors rs1 so cpu_core.v's existing
                // per-bank read-port muxing needs no new case.
                is_gluon       = 1'b1;
                gluon_funct    = instr[26:24];
                write_addr     = instr[23:21];
                gluon_rs1_bank = instr[20:19];
                gluon_rs1_reg  = instr[18:16];
                gluon_rs2_bank = instr[20:19];
                gluon_rs2_reg  = instr[18:16];
                // Off-diagonal gluon c1-anti(c2): only a quark of color c2
                // can absorb it, and it comes out as color c1. Diagonal
                // gluons (lambda3/lambda8) keep the quark's color.
                case (instr[26:24])
                    GL_RG:   begin gl_need_bank = BANK_G; write_bank = BANK_R; end
                    GL_GR:   begin gl_need_bank = BANK_R; write_bank = BANK_G; end
                    GL_RB:   begin gl_need_bank = BANK_B; write_bank = BANK_R; end
                    GL_BR:   begin gl_need_bank = BANK_R; write_bank = BANK_B; end
                    GL_GB:   begin gl_need_bank = BANK_B; write_bank = BANK_G; end
                    GL_BG:   begin gl_need_bank = BANK_G; write_bank = BANK_B; end
                    default: begin gl_need_bank = instr[20:19]; write_bank = instr[20:19]; end // L3/L8
                endcase
                // Gluons couple only to color charge: an N-bank (colorless)
                // source, or a quark of the wrong color, is illegal.
                if (instr[20:19] == BANK_N || instr[20:19] != gl_need_bank)
                    illegal = 1'b1;
                else
                    reg_write = 1'b1;
            end

            OP_BARYON: begin
                is_baryon = 1'b1;
                baryon_funct = instr[26:24]; // 000 SUM, 001 MAJ, 010 EPS, 011 QN; 100-111 reserved
                write_bank = BANK_N;
                write_addr = instr[23:21];
                baryon_rr  = instr[20:18];
                baryon_gg  = instr[17:15];
                baryon_bb  = instr[14:12];
                if (instr[26:24] > 3'b011) begin
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
                // SINGLET/QN: a quark and an antiquark of the SAME color
                // are the only colorless pair - red + anti-green is a
                // color octet (a gluon's charge), and N holds no color at
                // all. (QN's flavor checks are data-dependent - cpu_core.v.)
                if (meson_funct == 2'b11 ||
                    (meson_funct != 2'b00 && (instr[21:20] != instr[16:15] || instr[21:20] == BANK_N))) begin
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

            OP_RFT: begin
                is_rft = 1'b1; // privilege check + trap-entry mechanics live in cpu_core.v
            end

            OP_SYSCALL: begin
                is_syscall = 1'b1; // never privileged - the user->kernel door
            end

            OP_MVSR: begin
                is_mvsr     = 1'b1;
                mvsr_dir    = instr[26];
                mvsr_selreg = instr[25:24];
                mvsr_nreg   = instr[23:21];
                if (!mvsr_dir) begin // read: special -> N (write: N -> special, no bank write)
                    write_bank = BANK_N;
                    write_addr = mvsr_nreg;
                    reg_write  = 1'b1;
                end
            end

            OP_PTB: begin
                is_ptb   = 1'b1; // privileged - cpu_core.v traps with CAUSE_PRIV if mode==user
                ptb_dir  = instr[26];
                ptb_nreg = instr[25:23];
                if (!ptb_dir) begin // read: PTB -> N (write: N -> PTB, no bank write)
                    write_bank = BANK_N;
                    write_addr = ptb_nreg;
                    reg_write  = 1'b1;
                end
            end

            OP_QHAD: begin
                // Amplitude layout (R bank): amp0=(r0,r1) amp1=(r2,r3)
                // amp2=(r4,r5) amp3=(r6,r7), amplitude index = {q1,q0}.
                // qhad_qubit selects WHICH qubit's Hadamard butterfly
                // (q0 pairs differ only in bit0, q1 pairs differ only
                // in bit1); qhad_half selects which of the 2
                // independent pairs for that qubit. Both bits are
                // always meaningful (all 4 encodings used) - no
                // illegal case, same style as GLUON's fully-populated
                // funct field.
                is_qhad    = 1'b1;
                qhad_qubit = instr[26];
                qhad_half  = instr[25];
                case ({qhad_qubit, qhad_half})
                    2'b00: begin q_reg_i = 3'd0; q_reg_j = 3'd2; end // qubit0,half0: amp0<->amp1
                    2'b01: begin q_reg_i = 3'd4; q_reg_j = 3'd6; end // qubit0,half1: amp2<->amp3
                    2'b10: begin q_reg_i = 3'd0; q_reg_j = 3'd4; end // qubit1,half0: amp0<->amp2
                    2'b11: begin q_reg_i = 3'd2; q_reg_j = 3'd6; end // qubit1,half1: amp1<->amp3
                endcase
                // no reg_write - the q-sequencer FSM in cpu_core.v owns R-bank writes for this opcode
            end

            OP_QCNOT: begin
                // A real CNOT's control=0 branch is identity (nothing
                // to represent), so with 2 qubits there are only 2
                // real (control,target) assignments - both encodings
                // meaningful, no illegal case.
                is_qcnot   = 1'b1;
                qcnot_ctrl = instr[26];
                if (!qcnot_ctrl) begin
                    q_reg_i = 3'd2; q_reg_j = 3'd6; // control=q0: swap amp1<->amp3
                end else begin
                    q_reg_i = 3'd4; q_reg_j = 3'd6; // control=q1: swap amp2<->amp3
                end
                // no reg_write - the q-sequencer FSM in cpu_core.v owns R-bank writes for this opcode
            end

            OP_STRING: begin
                // opcode[31:27] nd[26:24] bank[23:22] qa[21:19] qb[18:16]
                // One bank field for both ends: a flux tube only joins a
                // color and its own anticolor, so mismatched colors are
                // not even encodable. N (colorless) has no string.
                is_string  = 1'b1;
                bank       = instr[23:22];
                rs1_addr   = instr[21:19];
                rs2_addr   = instr[18:16];
                write_bank = BANK_N;
                write_addr = instr[26:24];
                if (instr[23:22] == BANK_N)
                    illegal = 1'b1;
                else
                    reg_write = 1'b1;
            end

            OP_REGGE: begin
                // opcode[31:27] funct[26:25] nd[24:22] ns[21:19]; all four
                // funct codes are defined. cpu_core.v's rg-sequencer stalls
                // until the result is ready; the write itself goes through
                // the normal path on its terminal cycle.
                is_regge    = 1'b1;
                regge_funct = instr[26:25];
                regge_ns    = instr[21:19];
                write_bank  = BANK_N;
                write_addr  = instr[24:22];
                reg_write   = 1'b1;
            end

            OP_JALR: begin
                // opcode[31:27] nd[26:24] ns[23:21] imm[20:0]
                is_jalr    = 1'b1;
                jalr_ns    = instr[23:21];
                jal_imm    = {{11{instr[20]}}, instr[20:0]};
                write_bank = BANK_N;
                write_addr = instr[26:24];
                reg_write  = 1'b1;
            end

            OP_MTAG: begin
                // opcode[31:27] funct[26:25] nd[24:22] ns[21:19] - pointers
                // live in N (only N touches memory)
                is_mtag    = 1'b1;
                mtag_funct = instr[26:25];
                mtag_ns    = instr[21:19];
                write_bank = BANK_N;
                write_addr = instr[24:22];
                if (instr[26:25] == 2'b11)
                    illegal = 1'b1;
                else if (instr[26:25] != 2'b01)
                    reg_write = 1'b1; // IRG/LDG write nd; STG writes tag memory only
            end

            OP_SU3MUL: begin
                // opcode[31:27] ns[26:24] dst[23:21] src[20:18]. Each color
                // component is a register PAIR (Re = idx, Im = idx+1), so
                // idx 7 has no Im partner -> ILLEGAL.
                is_su3mul = 1'b1;
                su3_ns    = instr[26:24];
                su3_dst   = instr[23:21];
                su3_src   = instr[20:18];
                if (instr[23:21] == 3'd7 || instr[20:18] == 3'd7)
                    illegal = 1'b1;
            end

            OP_SWEEP: begin
                // opcode[31:27] nd[26:24] ns[23:21] L-1[20:19]. Runs PLAQ's
                // sequencer over every site; N[nd] written on its terminal cycle.
                is_sweep   = 1'b1;
                sw_l1      = instr[20:19];
                su3_ns     = instr[23:21];
                write_bank = BANK_N;
                write_addr = instr[26:24];
                reg_write  = 1'b1;
            end

            OP_REUNIT: begin
                // opcode[31:27] ns[26:24]; the rx-sequencer owns every
                // read and write, reg_write stays 0
                is_reunit = 1'b1;
                ru_ns     = instr[26:24];
            end

            OP_LINKMUL: begin
                // opcode[31:27] dagA[26] dagB[25] nc[24:22] na[21:19] nb[18:16].
                // The su-sequencer owns every read and write; reg_write stays 0.
                is_linkmul = 1'b1;
                lm_daga    = instr[26];
                lm_dagb    = instr[25];
                lm_nc      = instr[24:22];
                lm_na      = instr[21:19];
                lm_nb      = instr[18:16];
            end

            OP_METRO: begin
                // opcode[31:27] funct[26] nd[25:23] na[22:20] nb[19:17]
                // nbeta[16:14]; all N-bank binary32. cpu_core.v's
                // mx-sequencer stalls; nd is written on its terminal cycle.
                is_metro     = 1'b1;
                metro_weight = instr[26];
                metro_na     = instr[22:20];
                metro_nb     = instr[19:17];
                metro_nbeta  = instr[16:14];
                write_bank   = BANK_N;
                write_addr   = instr[25:23];
                reg_write    = 1'b1;
            end

            OP_PLAQ: begin
                // opcode[31:27] nd[26:24] ns[23:21]. Gauge-invariant, so the
                // result is colorless: binary32 in N[nd].
                is_plaq    = 1'b1;
                su3_ns     = instr[23:21];
                write_bank = BANK_N;
                write_addr = instr[26:24];
                reg_write  = 1'b1;
            end

            OP_QMEASURE: begin
                // Measuring qubit `qmeasure_qubit` inherently sums a
                // probability over BOTH amplitudes sharing that
                // qubit's value - unlike QHAD, there is no free
                // "which pair" choice to disambiguate, so 1 bit fully
                // determines both outcome groups. Both encodings
                // meaningful, no illegal case (same style as QHAD/
                // QCNOT's fully-populated selector fields).
                is_qmeasure    = 1'b1;
                qmeasure_qubit = instr[26];
                qmeasure_nd    = instr[25:23];
                case (qmeasure_qubit)
                    1'b0: begin // measuring q0: outcome-0={amp0,amp2}, outcome-1={amp1,amp3}
                        qm_reg_a0 = 3'd0; qm_reg_a1 = 3'd4;
                        qm_reg_b0 = 3'd2; qm_reg_b1 = 3'd6;
                    end
                    1'b1: begin // measuring q1: outcome-0={amp0,amp1}, outcome-1={amp2,amp3}
                        qm_reg_a0 = 3'd0; qm_reg_a1 = 3'd2;
                        qm_reg_b0 = 3'd4; qm_reg_b1 = 3'd6;
                    end
                endcase
                // no reg_write - the qm-sequencer FSM in cpu_core.v owns both the
                // R-bank writes (collapsed amplitudes) and the N-bank write (outcome)
            end

            default: begin
                illegal = 1'b1;
            end
        endcase
    end
endmodule
