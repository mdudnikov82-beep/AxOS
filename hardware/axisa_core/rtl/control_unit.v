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
    // HOP (v2.3 step 4): nearest-neighbour links. funct 00 SEND (N[reg]
    // -> neighbour), 01 RECV (neighbour -> N[reg]), 10 SENDL / 11 RECVL (an
    // 18-word link from / to memory at N[reg]); dir 0 +x, 1 -x, 2 +y, 3 -y
    output reg          is_hop,
    output reg  [1:0]  hop_funct,
    output reg  [1:0]  hop_dir,
    output reg  [2:0]  hop_reg,
    // CIM (v2.4): compute-in-memory block, rtl/cim.v. funct 0 PUT 1 GET
    // 2 ADD 3 FINDEQ 4 FINDLT 5 FIRST 6 SUM 7 SUMF; ns = index, nt = value
    output reg          is_cim,
    output reg  [2:0]  cim_funct,
    output reg  [2:0]  cim_ns,
    output reg  [2:0]  cim_nt,
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

    // Register-file read addresses, as far as the instruction alone
    // decides them (cpu_core overlays the multi-cycle sequencers' own
    // addresses on top). Decoded here so that the decode register holds
    // them ready - the long `if (is_x) addr = ...` priority chain used to
    // sit on the core's critical path between the decode register and
    // the register-file read. rd_n_late: one of the N-bank readers that
    // outrank the SU3 sequencer (MTAG, JALR, REGGE, METRO, LINKMUL,
    // REUNIT, HOP, CIM) - see cpu_core's n_addr routing.
    output reg  [2:0]  rd_r_a, rd_r_b, rd_g_a, rd_g_b, rd_b_a, rd_b_b, rd_n_a, rd_n_b,
    output reg          rd_n_late,

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
    localparam OP_HOP      = 5'b11011;
    localparam OP_CIM      = 5'b11100;

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
        is_hop         = 1'b0;
        hop_funct      = 2'b0;
        hop_dir        = 2'b0;
        hop_reg        = 3'b0;
        is_cim         = 1'b0;
        cim_funct      = 3'b0;
        cim_ns         = 3'b0;
        cim_nt         = 3'b0;
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

            OP_CIM: begin
                // opcode[31:27] funct[26:24] nd[23:21] ns[20:18] nt[17:15];
                // all eight funct codes are defined. PUT and ADD write only
                // the CIM block; the rest write N[nd] (SUM/SUMF on their
                // terminal cycle - cpu_core.v gates the write with cim_stall).
                is_cim     = 1'b1;
                cim_funct  = instr[26:24];
                cim_ns     = instr[20:18];
                cim_nt     = instr[17:15];
                write_bank = BANK_N;
                write_addr = instr[23:21];
                reg_write  = (instr[26:24] != 3'd0) && (instr[26:24] != 3'd2);
            end

            OP_HOP: begin
                // opcode[31:27] funct[26:25] dir[24:23] reg[22:20]
                is_hop     = 1'b1;
                hop_funct  = instr[26:25];
                hop_dir    = instr[24:23];
                hop_reg    = instr[22:20];
                write_bank = BANK_N;
                write_addr = instr[22:20];
                reg_write  = (instr[26:25] == 2'b01); // only RECV writes a register
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

    // ==================== Register-file read addresses ====================
    // Moved here from cpu_core.v unchanged (the instruction-only part of
    // its per-bank routing). Every input is one of this module's own
    // outputs above, so this is still a pure function of `instr`.
    always @(*) begin
        rd_r_a = 3'b0; rd_r_b = 3'b0; rd_g_a = 3'b0; rd_g_b = 3'b0;
        rd_b_a = 3'b0; rd_b_b = 3'b0; rd_n_a = 3'b0; rd_n_b = 3'b0;
        // R, G, B: the same shape, bank by bank
        if (is_gluon) begin
            case ({gluon_rs1_bank == BANK_R, gluon_rs2_bank == BANK_R})
                2'b11: begin rd_r_a = gluon_rs1_reg; rd_r_b = gluon_rs2_reg; end
                2'b10: begin rd_r_a = gluon_rs1_reg; rd_r_b = gluon_rs1_reg; end
                2'b01: begin rd_r_a = gluon_rs2_reg; rd_r_b = gluon_rs2_reg; end
                default: ;
            endcase
            case ({gluon_rs1_bank == BANK_G, gluon_rs2_bank == BANK_G})
                2'b11: begin rd_g_a = gluon_rs1_reg; rd_g_b = gluon_rs2_reg; end
                2'b10: begin rd_g_a = gluon_rs1_reg; rd_g_b = gluon_rs1_reg; end
                2'b01: begin rd_g_a = gluon_rs2_reg; rd_g_b = gluon_rs2_reg; end
                default: ;
            endcase
            case ({gluon_rs1_bank == BANK_B, gluon_rs2_bank == BANK_B})
                2'b11: begin rd_b_a = gluon_rs1_reg; rd_b_b = gluon_rs2_reg; end
                2'b10: begin rd_b_a = gluon_rs1_reg; rd_b_b = gluon_rs1_reg; end
                2'b01: begin rd_b_a = gluon_rs2_reg; rd_b_b = gluon_rs2_reg; end
                default: ;
            endcase
        end else if (is_baryon) begin
            rd_r_a = baryon_rr; rd_r_b = baryon_rr;
            rd_g_a = baryon_gg; rd_g_b = baryon_gg;
            rd_b_a = baryon_bb; rd_b_b = baryon_bb;
        end else if (is_meson) begin
            case ({meson_q1_bank == BANK_R, meson_q2_bank == BANK_R})
                2'b11: begin rd_r_a = meson_q1_reg; rd_r_b = meson_q2_reg; end
                2'b10: begin rd_r_a = meson_q1_reg; rd_r_b = meson_q1_reg; end
                2'b01: begin rd_r_a = meson_q2_reg; rd_r_b = meson_q2_reg; end
                default: ;
            endcase
            case ({meson_q1_bank == BANK_G, meson_q2_bank == BANK_G})
                2'b11: begin rd_g_a = meson_q1_reg; rd_g_b = meson_q2_reg; end
                2'b10: begin rd_g_a = meson_q1_reg; rd_g_b = meson_q1_reg; end
                2'b01: begin rd_g_a = meson_q2_reg; rd_g_b = meson_q2_reg; end
                default: ;
            endcase
            case ({meson_q1_bank == BANK_B, meson_q2_bank == BANK_B})
                2'b11: begin rd_b_a = meson_q1_reg; rd_b_b = meson_q2_reg; end
                2'b10: begin rd_b_a = meson_q1_reg; rd_b_b = meson_q1_reg; end
                2'b01: begin rd_b_a = meson_q2_reg; rd_b_b = meson_q2_reg; end
                default: ;
            endcase
        end else if (is_load || is_store) begin
            if (mem_base_bank == BANK_R) begin rd_r_a = mem_base_reg; rd_r_b = mem_base_reg; end
            if (mem_base_bank == BANK_G) begin rd_g_a = mem_base_reg; rd_g_b = mem_base_reg; end
            if (mem_base_bank == BANK_B) begin rd_b_a = mem_base_reg; rd_b_b = mem_base_reg; end
        end else if (!is_halt && !is_jal && !is_rft && !is_syscall && !is_mvsr && !is_ptb) begin // ALUR/ALUI/BRANCH (and illegal/default, harmlessly)
            if (bank == BANK_R) begin rd_r_a = rs1_addr; rd_r_b = rs2_addr; end
            if (bank == BANK_G) begin rd_g_a = rs1_addr; rd_g_b = rs2_addr; end
            if (bank == BANK_B) begin rd_b_a = rs1_addr; rd_b_b = rs2_addr; end
        end

        // N - the only bank with STORE's double read and HALT's tohost
        // read; BARYON never reads N (it only writes nd)
        if (is_gluon) begin
            case ({gluon_rs1_bank == BANK_N, gluon_rs2_bank == BANK_N})
                2'b11: begin rd_n_a = gluon_rs1_reg; rd_n_b = gluon_rs2_reg; end
                2'b10: begin rd_n_a = gluon_rs1_reg; rd_n_b = gluon_rs1_reg; end
                2'b01: begin rd_n_a = gluon_rs2_reg; rd_n_b = gluon_rs2_reg; end
                default: ;
            endcase
        end else if (is_meson) begin
            case ({meson_q1_bank == BANK_N, meson_q2_bank == BANK_N})
                2'b11: begin rd_n_a = meson_q1_reg; rd_n_b = meson_q2_reg; end
                2'b10: begin rd_n_a = meson_q1_reg; rd_n_b = meson_q1_reg; end
                2'b01: begin rd_n_a = meson_q2_reg; rd_n_b = meson_q2_reg; end
                default: ;
            endcase
        end else if (is_load) begin
            if (mem_base_bank == BANK_N) begin rd_n_a = mem_base_reg; rd_n_b = mem_base_reg; end
        end else if (is_store) begin
            rd_n_a = mem_nd_ns; // the value to store - ALWAYS read from N
            rd_n_b = (mem_base_bank == BANK_N) ? mem_base_reg : mem_nd_ns;
        end else if (is_halt) begin
            rd_n_a = tohost_reg; rd_n_b = tohost_reg;
        end else if (is_mvsr) begin
            // dir=1 (N -> special) reads the value to capture
            if (mvsr_dir) begin rd_n_a = mvsr_nreg; rd_n_b = mvsr_nreg; end
        end else if (is_ptb) begin
            if (ptb_dir) begin rd_n_a = ptb_nreg; rd_n_b = ptb_nreg; end
        end else if (!is_jal && !is_rft && !is_syscall) begin // ALUR/ALUI/BRANCH
            if (bank == BANK_N) begin rd_n_a = rs1_addr; rd_n_b = rs2_addr; end
        end
        // (cpu_core puts the SU3 sequencer's matrix base here when none
        // of the readers below is active)
        rd_n_late = is_mtag || is_jalr || is_regge || is_metro || is_linkmul || is_reunit || is_hop || is_cim;
        if (is_mtag)    begin rd_n_a = mtag_ns;  rd_n_b = mtag_ns;  end // MTAG: its pointer
        if (is_jalr)    begin rd_n_a = jalr_ns;  rd_n_b = jalr_ns;  end // JALR: the target base
        if (is_regge)   begin rd_n_a = regge_ns; rd_n_b = regge_ns; end // REGGE: mass / spin
        if (is_metro)   begin rd_n_a = metro_na; rd_n_b = metro_nb; end // METRO: P_old / P_new (cpu_core swaps in beta on MX_SUB)
        if (is_linkmul) begin rd_n_a = lm_na;    rd_n_b = lm_nb;    end // LINKMUL: matrix bases A, B
        if (is_reunit)  begin rd_n_a = ru_ns;    rd_n_b = ru_ns;    end // REUNIT: the matrix base
        if (is_hop)     begin rd_n_a = hop_reg;  rd_n_b = hop_reg;  end // HOP: the word / link base
        if (is_cim)     begin rd_n_a = cim_ns;   rd_n_b = cim_nt;   end // CIM: index on A, value on B
    end
endmodule

// ===== control_unit_stage: GENERATED by tools/gen_decode_stage.py - do not edit by hand =====
//
// 109 control_unit outputs, 321 bits. REGISTERED=1: control_unit
// decodes `instr` (the instruction memory's combinational read of the
// next pc) and the outputs are registered - updated when `en`
// (!cpu_stall), forced to decode(0) by `kill` (the next cycle is a
// squash bubble) and by reset. REGISTERED=0: the old structure,
// control_unit on (squash ? 0 : instr) with `instr` already registered
// by the instruction memory (SYNC_READ=1 - for FPGA block RAM).
module control_unit_stage #(parameter REGISTERED = 1) (
    input  wire        clk, reset, en, kill, squash,
    input  wire [31:0] instr,
    output wire [1:0] bank,
    output wire [3:0] alu_funct,
    output wire [2:0] branch_funct,
    output wire [2:0] rd_addr,
    output wire [2:0] rs1_addr,
    output wire [2:0] rs2_addr,
    output wire [31:0] imm,
    output wire [0:0] alu_src_imm,
    output wire [0:0] is_branch,
    output wire [0:0] is_halt,
    output wire [2:0] tohost_reg,
    output wire [0:0] is_gluon,
    output wire [2:0] gluon_funct,
    output wire [1:0] gluon_rs1_bank,
    output wire [2:0] gluon_rs1_reg,
    output wire [1:0] gluon_rs2_bank,
    output wire [2:0] gluon_rs2_reg,
    output wire [0:0] is_baryon,
    output wire [2:0] baryon_rr,
    output wire [2:0] baryon_gg,
    output wire [2:0] baryon_bb,
    output wire [2:0] baryon_funct,
    output wire [0:0] is_meson,
    output wire [1:0] meson_funct,
    output wire [1:0] meson_q1_bank,
    output wire [2:0] meson_q1_reg,
    output wire [1:0] meson_q2_bank,
    output wire [2:0] meson_q2_reg,
    output wire [0:0] is_load,
    output wire [0:0] is_store,
    output wire [2:0] mem_nd_ns,
    output wire [1:0] mem_base_bank,
    output wire [2:0] mem_base_reg,
    output wire [31:0] mem_imm,
    output wire [0:0] is_jal,
    output wire [31:0] jal_imm,
    output wire [0:0] is_rft,
    output wire [0:0] is_syscall,
    output wire [0:0] is_mvsr,
    output wire [0:0] mvsr_dir,
    output wire [1:0] mvsr_selreg,
    output wire [2:0] mvsr_nreg,
    output wire [0:0] is_ptb,
    output wire [0:0] ptb_dir,
    output wire [2:0] ptb_nreg,
    output wire [0:0] is_qhad,
    output wire [0:0] qhad_qubit,
    output wire [0:0] qhad_half,
    output wire [0:0] is_qcnot,
    output wire [0:0] qcnot_ctrl,
    output wire [2:0] q_reg_i,
    output wire [2:0] q_reg_j,
    output wire [0:0] is_string,
    output wire [0:0] is_regge,
    output wire [1:0] regge_funct,
    output wire [2:0] regge_ns,
    output wire [0:0] is_jalr,
    output wire [2:0] jalr_ns,
    output wire [0:0] is_mtag,
    output wire [1:0] mtag_funct,
    output wire [2:0] mtag_ns,
    output wire [0:0] is_plaq,
    output wire [0:0] is_linkmul,
    output wire [0:0] is_reunit,
    output wire [0:0] is_sweep,
    output wire [0:0] is_hop,
    output wire [1:0] hop_funct,
    output wire [1:0] hop_dir,
    output wire [2:0] hop_reg,
    output wire [0:0] is_cim,
    output wire [2:0] cim_funct,
    output wire [2:0] cim_ns,
    output wire [2:0] cim_nt,
    output wire [1:0] sw_l1,
    output wire [2:0] ru_ns,
    output wire [0:0] lm_daga,
    output wire [0:0] lm_dagb,
    output wire [2:0] lm_na,
    output wire [2:0] lm_nb,
    output wire [2:0] lm_nc,
    output wire [0:0] is_metro,
    output wire [0:0] metro_weight,
    output wire [2:0] metro_na,
    output wire [2:0] metro_nb,
    output wire [2:0] metro_nbeta,
    output wire [0:0] is_su3mul,
    output wire [2:0] su3_ns,
    output wire [2:0] su3_dst,
    output wire [2:0] su3_src,
    output wire [0:0] is_qmeasure,
    output wire [0:0] qmeasure_qubit,
    output wire [2:0] qmeasure_nd,
    output wire [2:0] qm_reg_a0,
    output wire [2:0] qm_reg_a1,
    output wire [2:0] qm_reg_b0,
    output wire [2:0] qm_reg_b1,
    output wire [1:0] write_bank,
    output wire [2:0] write_addr,
    output wire [2:0] rd_r_a,
    output wire [2:0] rd_r_b,
    output wire [2:0] rd_g_a,
    output wire [2:0] rd_g_b,
    output wire [2:0] rd_b_a,
    output wire [2:0] rd_b_b,
    output wire [2:0] rd_n_a,
    output wire [2:0] rd_n_b,
    output wire [0:0] rd_n_late,
    output wire [0:0] reg_write,
    output wire [0:0] illegal
);
    generate if (REGISTERED) begin: g_reg
        wire [1:0] d_bank;
        reg  [1:0] q_bank;
        wire [3:0] d_alu_funct;
        reg  [3:0] q_alu_funct;
        wire [2:0] d_branch_funct;
        reg  [2:0] q_branch_funct;
        wire [2:0] d_rd_addr;
        reg  [2:0] q_rd_addr;
        wire [2:0] d_rs1_addr;
        reg  [2:0] q_rs1_addr;
        wire [2:0] d_rs2_addr;
        reg  [2:0] q_rs2_addr;
        wire [31:0] d_imm;
        reg  [31:0] q_imm;
        wire [0:0] d_alu_src_imm;
        reg  [0:0] q_alu_src_imm;
        wire [0:0] d_is_branch;
        reg  [0:0] q_is_branch;
        wire [0:0] d_is_halt;
        reg  [0:0] q_is_halt;
        wire [2:0] d_tohost_reg;
        reg  [2:0] q_tohost_reg;
        wire [0:0] d_is_gluon;
        reg  [0:0] q_is_gluon;
        wire [2:0] d_gluon_funct;
        reg  [2:0] q_gluon_funct;
        wire [1:0] d_gluon_rs1_bank;
        reg  [1:0] q_gluon_rs1_bank;
        wire [2:0] d_gluon_rs1_reg;
        reg  [2:0] q_gluon_rs1_reg;
        wire [1:0] d_gluon_rs2_bank;
        reg  [1:0] q_gluon_rs2_bank;
        wire [2:0] d_gluon_rs2_reg;
        reg  [2:0] q_gluon_rs2_reg;
        wire [0:0] d_is_baryon;
        reg  [0:0] q_is_baryon;
        wire [2:0] d_baryon_rr;
        reg  [2:0] q_baryon_rr;
        wire [2:0] d_baryon_gg;
        reg  [2:0] q_baryon_gg;
        wire [2:0] d_baryon_bb;
        reg  [2:0] q_baryon_bb;
        wire [2:0] d_baryon_funct;
        reg  [2:0] q_baryon_funct;
        wire [0:0] d_is_meson;
        reg  [0:0] q_is_meson;
        wire [1:0] d_meson_funct;
        reg  [1:0] q_meson_funct;
        wire [1:0] d_meson_q1_bank;
        reg  [1:0] q_meson_q1_bank;
        wire [2:0] d_meson_q1_reg;
        reg  [2:0] q_meson_q1_reg;
        wire [1:0] d_meson_q2_bank;
        reg  [1:0] q_meson_q2_bank;
        wire [2:0] d_meson_q2_reg;
        reg  [2:0] q_meson_q2_reg;
        wire [0:0] d_is_load;
        reg  [0:0] q_is_load;
        wire [0:0] d_is_store;
        reg  [0:0] q_is_store;
        wire [2:0] d_mem_nd_ns;
        reg  [2:0] q_mem_nd_ns;
        wire [1:0] d_mem_base_bank;
        reg  [1:0] q_mem_base_bank;
        wire [2:0] d_mem_base_reg;
        reg  [2:0] q_mem_base_reg;
        wire [31:0] d_mem_imm;
        reg  [31:0] q_mem_imm;
        wire [0:0] d_is_jal;
        reg  [0:0] q_is_jal;
        wire [31:0] d_jal_imm;
        reg  [31:0] q_jal_imm;
        wire [0:0] d_is_rft;
        reg  [0:0] q_is_rft;
        wire [0:0] d_is_syscall;
        reg  [0:0] q_is_syscall;
        wire [0:0] d_is_mvsr;
        reg  [0:0] q_is_mvsr;
        wire [0:0] d_mvsr_dir;
        reg  [0:0] q_mvsr_dir;
        wire [1:0] d_mvsr_selreg;
        reg  [1:0] q_mvsr_selreg;
        wire [2:0] d_mvsr_nreg;
        reg  [2:0] q_mvsr_nreg;
        wire [0:0] d_is_ptb;
        reg  [0:0] q_is_ptb;
        wire [0:0] d_ptb_dir;
        reg  [0:0] q_ptb_dir;
        wire [2:0] d_ptb_nreg;
        reg  [2:0] q_ptb_nreg;
        wire [0:0] d_is_qhad;
        reg  [0:0] q_is_qhad;
        wire [0:0] d_qhad_qubit;
        reg  [0:0] q_qhad_qubit;
        wire [0:0] d_qhad_half;
        reg  [0:0] q_qhad_half;
        wire [0:0] d_is_qcnot;
        reg  [0:0] q_is_qcnot;
        wire [0:0] d_qcnot_ctrl;
        reg  [0:0] q_qcnot_ctrl;
        wire [2:0] d_q_reg_i;
        reg  [2:0] q_q_reg_i;
        wire [2:0] d_q_reg_j;
        reg  [2:0] q_q_reg_j;
        wire [0:0] d_is_string;
        reg  [0:0] q_is_string;
        wire [0:0] d_is_regge;
        reg  [0:0] q_is_regge;
        wire [1:0] d_regge_funct;
        reg  [1:0] q_regge_funct;
        wire [2:0] d_regge_ns;
        reg  [2:0] q_regge_ns;
        wire [0:0] d_is_jalr;
        reg  [0:0] q_is_jalr;
        wire [2:0] d_jalr_ns;
        reg  [2:0] q_jalr_ns;
        wire [0:0] d_is_mtag;
        reg  [0:0] q_is_mtag;
        wire [1:0] d_mtag_funct;
        reg  [1:0] q_mtag_funct;
        wire [2:0] d_mtag_ns;
        reg  [2:0] q_mtag_ns;
        wire [0:0] d_is_plaq;
        reg  [0:0] q_is_plaq;
        wire [0:0] d_is_linkmul;
        reg  [0:0] q_is_linkmul;
        wire [0:0] d_is_reunit;
        reg  [0:0] q_is_reunit;
        wire [0:0] d_is_sweep;
        reg  [0:0] q_is_sweep;
        wire [0:0] d_is_hop;
        reg  [0:0] q_is_hop;
        wire [1:0] d_hop_funct;
        reg  [1:0] q_hop_funct;
        wire [1:0] d_hop_dir;
        reg  [1:0] q_hop_dir;
        wire [2:0] d_hop_reg;
        reg  [2:0] q_hop_reg;
        wire [0:0] d_is_cim;
        reg  [0:0] q_is_cim;
        wire [2:0] d_cim_funct;
        reg  [2:0] q_cim_funct;
        wire [2:0] d_cim_ns;
        reg  [2:0] q_cim_ns;
        wire [2:0] d_cim_nt;
        reg  [2:0] q_cim_nt;
        wire [1:0] d_sw_l1;
        reg  [1:0] q_sw_l1;
        wire [2:0] d_ru_ns;
        reg  [2:0] q_ru_ns;
        wire [0:0] d_lm_daga;
        reg  [0:0] q_lm_daga;
        wire [0:0] d_lm_dagb;
        reg  [0:0] q_lm_dagb;
        wire [2:0] d_lm_na;
        reg  [2:0] q_lm_na;
        wire [2:0] d_lm_nb;
        reg  [2:0] q_lm_nb;
        wire [2:0] d_lm_nc;
        reg  [2:0] q_lm_nc;
        wire [0:0] d_is_metro;
        reg  [0:0] q_is_metro;
        wire [0:0] d_metro_weight;
        reg  [0:0] q_metro_weight;
        wire [2:0] d_metro_na;
        reg  [2:0] q_metro_na;
        wire [2:0] d_metro_nb;
        reg  [2:0] q_metro_nb;
        wire [2:0] d_metro_nbeta;
        reg  [2:0] q_metro_nbeta;
        wire [0:0] d_is_su3mul;
        reg  [0:0] q_is_su3mul;
        wire [2:0] d_su3_ns;
        reg  [2:0] q_su3_ns;
        wire [2:0] d_su3_dst;
        reg  [2:0] q_su3_dst;
        wire [2:0] d_su3_src;
        reg  [2:0] q_su3_src;
        wire [0:0] d_is_qmeasure;
        reg  [0:0] q_is_qmeasure;
        wire [0:0] d_qmeasure_qubit;
        reg  [0:0] q_qmeasure_qubit;
        wire [2:0] d_qmeasure_nd;
        reg  [2:0] q_qmeasure_nd;
        wire [2:0] d_qm_reg_a0;
        reg  [2:0] q_qm_reg_a0;
        wire [2:0] d_qm_reg_a1;
        reg  [2:0] q_qm_reg_a1;
        wire [2:0] d_qm_reg_b0;
        reg  [2:0] q_qm_reg_b0;
        wire [2:0] d_qm_reg_b1;
        reg  [2:0] q_qm_reg_b1;
        wire [1:0] d_write_bank;
        reg  [1:0] q_write_bank;
        wire [2:0] d_write_addr;
        reg  [2:0] q_write_addr;
        wire [2:0] d_rd_r_a;
        reg  [2:0] q_rd_r_a;
        wire [2:0] d_rd_r_b;
        reg  [2:0] q_rd_r_b;
        wire [2:0] d_rd_g_a;
        reg  [2:0] q_rd_g_a;
        wire [2:0] d_rd_g_b;
        reg  [2:0] q_rd_g_b;
        wire [2:0] d_rd_b_a;
        reg  [2:0] q_rd_b_a;
        wire [2:0] d_rd_b_b;
        reg  [2:0] q_rd_b_b;
        wire [2:0] d_rd_n_a;
        reg  [2:0] q_rd_n_a;
        wire [2:0] d_rd_n_b;
        reg  [2:0] q_rd_n_b;
        wire [0:0] d_rd_n_late;
        reg  [0:0] q_rd_n_late;
        wire [0:0] d_reg_write;
        reg  [0:0] q_reg_write;
        wire [0:0] d_illegal;
        reg  [0:0] q_illegal;
        control_unit u (.instr(instr), .bank(d_bank), .alu_funct(d_alu_funct), .branch_funct(d_branch_funct), .rd_addr(d_rd_addr), .rs1_addr(d_rs1_addr), .rs2_addr(d_rs2_addr), .imm(d_imm), .alu_src_imm(d_alu_src_imm), .is_branch(d_is_branch), .is_halt(d_is_halt), .tohost_reg(d_tohost_reg), .is_gluon(d_is_gluon), .gluon_funct(d_gluon_funct), .gluon_rs1_bank(d_gluon_rs1_bank), .gluon_rs1_reg(d_gluon_rs1_reg), .gluon_rs2_bank(d_gluon_rs2_bank), .gluon_rs2_reg(d_gluon_rs2_reg), .is_baryon(d_is_baryon), .baryon_rr(d_baryon_rr), .baryon_gg(d_baryon_gg), .baryon_bb(d_baryon_bb), .baryon_funct(d_baryon_funct), .is_meson(d_is_meson), .meson_funct(d_meson_funct), .meson_q1_bank(d_meson_q1_bank), .meson_q1_reg(d_meson_q1_reg), .meson_q2_bank(d_meson_q2_bank), .meson_q2_reg(d_meson_q2_reg), .is_load(d_is_load), .is_store(d_is_store), .mem_nd_ns(d_mem_nd_ns), .mem_base_bank(d_mem_base_bank), .mem_base_reg(d_mem_base_reg), .mem_imm(d_mem_imm), .is_jal(d_is_jal), .jal_imm(d_jal_imm), .is_rft(d_is_rft), .is_syscall(d_is_syscall), .is_mvsr(d_is_mvsr), .mvsr_dir(d_mvsr_dir), .mvsr_selreg(d_mvsr_selreg), .mvsr_nreg(d_mvsr_nreg), .is_ptb(d_is_ptb), .ptb_dir(d_ptb_dir), .ptb_nreg(d_ptb_nreg), .is_qhad(d_is_qhad), .qhad_qubit(d_qhad_qubit), .qhad_half(d_qhad_half), .is_qcnot(d_is_qcnot), .qcnot_ctrl(d_qcnot_ctrl), .q_reg_i(d_q_reg_i), .q_reg_j(d_q_reg_j), .is_string(d_is_string), .is_regge(d_is_regge), .regge_funct(d_regge_funct), .regge_ns(d_regge_ns), .is_jalr(d_is_jalr), .jalr_ns(d_jalr_ns), .is_mtag(d_is_mtag), .mtag_funct(d_mtag_funct), .mtag_ns(d_mtag_ns), .is_plaq(d_is_plaq), .is_linkmul(d_is_linkmul), .is_reunit(d_is_reunit), .is_sweep(d_is_sweep), .is_hop(d_is_hop), .hop_funct(d_hop_funct), .hop_dir(d_hop_dir), .hop_reg(d_hop_reg), .is_cim(d_is_cim), .cim_funct(d_cim_funct), .cim_ns(d_cim_ns), .cim_nt(d_cim_nt), .sw_l1(d_sw_l1), .ru_ns(d_ru_ns), .lm_daga(d_lm_daga), .lm_dagb(d_lm_dagb), .lm_na(d_lm_na), .lm_nb(d_lm_nb), .lm_nc(d_lm_nc), .is_metro(d_is_metro), .metro_weight(d_metro_weight), .metro_na(d_metro_na), .metro_nb(d_metro_nb), .metro_nbeta(d_metro_nbeta), .is_su3mul(d_is_su3mul), .su3_ns(d_su3_ns), .su3_dst(d_su3_dst), .su3_src(d_su3_src), .is_qmeasure(d_is_qmeasure), .qmeasure_qubit(d_qmeasure_qubit), .qmeasure_nd(d_qmeasure_nd), .qm_reg_a0(d_qm_reg_a0), .qm_reg_a1(d_qm_reg_a1), .qm_reg_b0(d_qm_reg_b0), .qm_reg_b1(d_qm_reg_b1), .write_bank(d_write_bank), .write_addr(d_write_addr), .rd_r_a(d_rd_r_a), .rd_r_b(d_rd_r_b), .rd_g_a(d_rd_g_a), .rd_g_b(d_rd_g_b), .rd_b_a(d_rd_b_a), .rd_b_b(d_rd_b_b), .rd_n_a(d_rd_n_a), .rd_n_b(d_rd_n_b), .rd_n_late(d_rd_n_late), .reg_write(d_reg_write), .illegal(d_illegal));
        always @(posedge clk or posedge reset) begin
            if (reset) begin
                q_bank <= 2'b00;
                q_alu_funct <= 4'b0000;
                q_branch_funct <= 3'b000;
                q_rd_addr <= 3'b000;
                q_rs1_addr <= 3'b000;
                q_rs2_addr <= 3'b000;
                q_imm <= 32'b00000000000000000000000000000000;
                q_alu_src_imm <= 1'b0;
                q_is_branch <= 1'b0;
                q_is_halt <= 1'b0;
                q_tohost_reg <= 3'b000;
                q_is_gluon <= 1'b0;
                q_gluon_funct <= 3'b000;
                q_gluon_rs1_bank <= 2'b00;
                q_gluon_rs1_reg <= 3'b000;
                q_gluon_rs2_bank <= 2'b00;
                q_gluon_rs2_reg <= 3'b000;
                q_is_baryon <= 1'b0;
                q_baryon_rr <= 3'b000;
                q_baryon_gg <= 3'b000;
                q_baryon_bb <= 3'b000;
                q_baryon_funct <= 3'b000;
                q_is_meson <= 1'b0;
                q_meson_funct <= 2'b00;
                q_meson_q1_bank <= 2'b00;
                q_meson_q1_reg <= 3'b000;
                q_meson_q2_bank <= 2'b00;
                q_meson_q2_reg <= 3'b000;
                q_is_load <= 1'b0;
                q_is_store <= 1'b0;
                q_mem_nd_ns <= 3'b000;
                q_mem_base_bank <= 2'b00;
                q_mem_base_reg <= 3'b000;
                q_mem_imm <= 32'b00000000000000000000000000000000;
                q_is_jal <= 1'b0;
                q_jal_imm <= 32'b00000000000000000000000000000000;
                q_is_rft <= 1'b0;
                q_is_syscall <= 1'b0;
                q_is_mvsr <= 1'b0;
                q_mvsr_dir <= 1'b0;
                q_mvsr_selreg <= 2'b00;
                q_mvsr_nreg <= 3'b000;
                q_is_ptb <= 1'b0;
                q_ptb_dir <= 1'b0;
                q_ptb_nreg <= 3'b000;
                q_is_qhad <= 1'b0;
                q_qhad_qubit <= 1'b0;
                q_qhad_half <= 1'b0;
                q_is_qcnot <= 1'b0;
                q_qcnot_ctrl <= 1'b0;
                q_q_reg_i <= 3'b000;
                q_q_reg_j <= 3'b000;
                q_is_string <= 1'b0;
                q_is_regge <= 1'b0;
                q_regge_funct <= 2'b00;
                q_regge_ns <= 3'b000;
                q_is_jalr <= 1'b0;
                q_jalr_ns <= 3'b000;
                q_is_mtag <= 1'b0;
                q_mtag_funct <= 2'b00;
                q_mtag_ns <= 3'b000;
                q_is_plaq <= 1'b0;
                q_is_linkmul <= 1'b0;
                q_is_reunit <= 1'b0;
                q_is_sweep <= 1'b0;
                q_is_hop <= 1'b0;
                q_hop_funct <= 2'b00;
                q_hop_dir <= 2'b00;
                q_hop_reg <= 3'b000;
                q_is_cim <= 1'b0;
                q_cim_funct <= 3'b000;
                q_cim_ns <= 3'b000;
                q_cim_nt <= 3'b000;
                q_sw_l1 <= 2'b00;
                q_ru_ns <= 3'b000;
                q_lm_daga <= 1'b0;
                q_lm_dagb <= 1'b0;
                q_lm_na <= 3'b000;
                q_lm_nb <= 3'b000;
                q_lm_nc <= 3'b000;
                q_is_metro <= 1'b0;
                q_metro_weight <= 1'b0;
                q_metro_na <= 3'b000;
                q_metro_nb <= 3'b000;
                q_metro_nbeta <= 3'b000;
                q_is_su3mul <= 1'b0;
                q_su3_ns <= 3'b000;
                q_su3_dst <= 3'b000;
                q_su3_src <= 3'b000;
                q_is_qmeasure <= 1'b0;
                q_qmeasure_qubit <= 1'b0;
                q_qmeasure_nd <= 3'b000;
                q_qm_reg_a0 <= 3'b000;
                q_qm_reg_a1 <= 3'b000;
                q_qm_reg_b0 <= 3'b000;
                q_qm_reg_b1 <= 3'b000;
                q_write_bank <= 2'b00;
                q_write_addr <= 3'b000;
                q_rd_r_a <= 3'b000;
                q_rd_r_b <= 3'b000;
                q_rd_g_a <= 3'b000;
                q_rd_g_b <= 3'b000;
                q_rd_b_a <= 3'b000;
                q_rd_b_b <= 3'b000;
                q_rd_n_a <= 3'b000;
                q_rd_n_b <= 3'b000;
                q_rd_n_late <= 1'b0;
                q_reg_write <= 1'b1;
                q_illegal <= 1'b0;
            end else if (en) begin
                if (kill) begin
                    q_bank <= 2'b00;
                    q_alu_funct <= 4'b0000;
                    q_branch_funct <= 3'b000;
                    q_rd_addr <= 3'b000;
                    q_rs1_addr <= 3'b000;
                    q_rs2_addr <= 3'b000;
                    q_imm <= 32'b00000000000000000000000000000000;
                    q_alu_src_imm <= 1'b0;
                    q_is_branch <= 1'b0;
                    q_is_halt <= 1'b0;
                    q_tohost_reg <= 3'b000;
                    q_is_gluon <= 1'b0;
                    q_gluon_funct <= 3'b000;
                    q_gluon_rs1_bank <= 2'b00;
                    q_gluon_rs1_reg <= 3'b000;
                    q_gluon_rs2_bank <= 2'b00;
                    q_gluon_rs2_reg <= 3'b000;
                    q_is_baryon <= 1'b0;
                    q_baryon_rr <= 3'b000;
                    q_baryon_gg <= 3'b000;
                    q_baryon_bb <= 3'b000;
                    q_baryon_funct <= 3'b000;
                    q_is_meson <= 1'b0;
                    q_meson_funct <= 2'b00;
                    q_meson_q1_bank <= 2'b00;
                    q_meson_q1_reg <= 3'b000;
                    q_meson_q2_bank <= 2'b00;
                    q_meson_q2_reg <= 3'b000;
                    q_is_load <= 1'b0;
                    q_is_store <= 1'b0;
                    q_mem_nd_ns <= 3'b000;
                    q_mem_base_bank <= 2'b00;
                    q_mem_base_reg <= 3'b000;
                    q_mem_imm <= 32'b00000000000000000000000000000000;
                    q_is_jal <= 1'b0;
                    q_jal_imm <= 32'b00000000000000000000000000000000;
                    q_is_rft <= 1'b0;
                    q_is_syscall <= 1'b0;
                    q_is_mvsr <= 1'b0;
                    q_mvsr_dir <= 1'b0;
                    q_mvsr_selreg <= 2'b00;
                    q_mvsr_nreg <= 3'b000;
                    q_is_ptb <= 1'b0;
                    q_ptb_dir <= 1'b0;
                    q_ptb_nreg <= 3'b000;
                    q_is_qhad <= 1'b0;
                    q_qhad_qubit <= 1'b0;
                    q_qhad_half <= 1'b0;
                    q_is_qcnot <= 1'b0;
                    q_qcnot_ctrl <= 1'b0;
                    q_q_reg_i <= 3'b000;
                    q_q_reg_j <= 3'b000;
                    q_is_string <= 1'b0;
                    q_is_regge <= 1'b0;
                    q_regge_funct <= 2'b00;
                    q_regge_ns <= 3'b000;
                    q_is_jalr <= 1'b0;
                    q_jalr_ns <= 3'b000;
                    q_is_mtag <= 1'b0;
                    q_mtag_funct <= 2'b00;
                    q_mtag_ns <= 3'b000;
                    q_is_plaq <= 1'b0;
                    q_is_linkmul <= 1'b0;
                    q_is_reunit <= 1'b0;
                    q_is_sweep <= 1'b0;
                    q_is_hop <= 1'b0;
                    q_hop_funct <= 2'b00;
                    q_hop_dir <= 2'b00;
                    q_hop_reg <= 3'b000;
                    q_is_cim <= 1'b0;
                    q_cim_funct <= 3'b000;
                    q_cim_ns <= 3'b000;
                    q_cim_nt <= 3'b000;
                    q_sw_l1 <= 2'b00;
                    q_ru_ns <= 3'b000;
                    q_lm_daga <= 1'b0;
                    q_lm_dagb <= 1'b0;
                    q_lm_na <= 3'b000;
                    q_lm_nb <= 3'b000;
                    q_lm_nc <= 3'b000;
                    q_is_metro <= 1'b0;
                    q_metro_weight <= 1'b0;
                    q_metro_na <= 3'b000;
                    q_metro_nb <= 3'b000;
                    q_metro_nbeta <= 3'b000;
                    q_is_su3mul <= 1'b0;
                    q_su3_ns <= 3'b000;
                    q_su3_dst <= 3'b000;
                    q_su3_src <= 3'b000;
                    q_is_qmeasure <= 1'b0;
                    q_qmeasure_qubit <= 1'b0;
                    q_qmeasure_nd <= 3'b000;
                    q_qm_reg_a0 <= 3'b000;
                    q_qm_reg_a1 <= 3'b000;
                    q_qm_reg_b0 <= 3'b000;
                    q_qm_reg_b1 <= 3'b000;
                    q_write_bank <= 2'b00;
                    q_write_addr <= 3'b000;
                    q_rd_r_a <= 3'b000;
                    q_rd_r_b <= 3'b000;
                    q_rd_g_a <= 3'b000;
                    q_rd_g_b <= 3'b000;
                    q_rd_b_a <= 3'b000;
                    q_rd_b_b <= 3'b000;
                    q_rd_n_a <= 3'b000;
                    q_rd_n_b <= 3'b000;
                    q_rd_n_late <= 1'b0;
                    q_reg_write <= 1'b1;
                    q_illegal <= 1'b0;
                end else begin
                    q_bank <= d_bank;
                    q_alu_funct <= d_alu_funct;
                    q_branch_funct <= d_branch_funct;
                    q_rd_addr <= d_rd_addr;
                    q_rs1_addr <= d_rs1_addr;
                    q_rs2_addr <= d_rs2_addr;
                    q_imm <= d_imm;
                    q_alu_src_imm <= d_alu_src_imm;
                    q_is_branch <= d_is_branch;
                    q_is_halt <= d_is_halt;
                    q_tohost_reg <= d_tohost_reg;
                    q_is_gluon <= d_is_gluon;
                    q_gluon_funct <= d_gluon_funct;
                    q_gluon_rs1_bank <= d_gluon_rs1_bank;
                    q_gluon_rs1_reg <= d_gluon_rs1_reg;
                    q_gluon_rs2_bank <= d_gluon_rs2_bank;
                    q_gluon_rs2_reg <= d_gluon_rs2_reg;
                    q_is_baryon <= d_is_baryon;
                    q_baryon_rr <= d_baryon_rr;
                    q_baryon_gg <= d_baryon_gg;
                    q_baryon_bb <= d_baryon_bb;
                    q_baryon_funct <= d_baryon_funct;
                    q_is_meson <= d_is_meson;
                    q_meson_funct <= d_meson_funct;
                    q_meson_q1_bank <= d_meson_q1_bank;
                    q_meson_q1_reg <= d_meson_q1_reg;
                    q_meson_q2_bank <= d_meson_q2_bank;
                    q_meson_q2_reg <= d_meson_q2_reg;
                    q_is_load <= d_is_load;
                    q_is_store <= d_is_store;
                    q_mem_nd_ns <= d_mem_nd_ns;
                    q_mem_base_bank <= d_mem_base_bank;
                    q_mem_base_reg <= d_mem_base_reg;
                    q_mem_imm <= d_mem_imm;
                    q_is_jal <= d_is_jal;
                    q_jal_imm <= d_jal_imm;
                    q_is_rft <= d_is_rft;
                    q_is_syscall <= d_is_syscall;
                    q_is_mvsr <= d_is_mvsr;
                    q_mvsr_dir <= d_mvsr_dir;
                    q_mvsr_selreg <= d_mvsr_selreg;
                    q_mvsr_nreg <= d_mvsr_nreg;
                    q_is_ptb <= d_is_ptb;
                    q_ptb_dir <= d_ptb_dir;
                    q_ptb_nreg <= d_ptb_nreg;
                    q_is_qhad <= d_is_qhad;
                    q_qhad_qubit <= d_qhad_qubit;
                    q_qhad_half <= d_qhad_half;
                    q_is_qcnot <= d_is_qcnot;
                    q_qcnot_ctrl <= d_qcnot_ctrl;
                    q_q_reg_i <= d_q_reg_i;
                    q_q_reg_j <= d_q_reg_j;
                    q_is_string <= d_is_string;
                    q_is_regge <= d_is_regge;
                    q_regge_funct <= d_regge_funct;
                    q_regge_ns <= d_regge_ns;
                    q_is_jalr <= d_is_jalr;
                    q_jalr_ns <= d_jalr_ns;
                    q_is_mtag <= d_is_mtag;
                    q_mtag_funct <= d_mtag_funct;
                    q_mtag_ns <= d_mtag_ns;
                    q_is_plaq <= d_is_plaq;
                    q_is_linkmul <= d_is_linkmul;
                    q_is_reunit <= d_is_reunit;
                    q_is_sweep <= d_is_sweep;
                    q_is_hop <= d_is_hop;
                    q_hop_funct <= d_hop_funct;
                    q_hop_dir <= d_hop_dir;
                    q_hop_reg <= d_hop_reg;
                    q_is_cim <= d_is_cim;
                    q_cim_funct <= d_cim_funct;
                    q_cim_ns <= d_cim_ns;
                    q_cim_nt <= d_cim_nt;
                    q_sw_l1 <= d_sw_l1;
                    q_ru_ns <= d_ru_ns;
                    q_lm_daga <= d_lm_daga;
                    q_lm_dagb <= d_lm_dagb;
                    q_lm_na <= d_lm_na;
                    q_lm_nb <= d_lm_nb;
                    q_lm_nc <= d_lm_nc;
                    q_is_metro <= d_is_metro;
                    q_metro_weight <= d_metro_weight;
                    q_metro_na <= d_metro_na;
                    q_metro_nb <= d_metro_nb;
                    q_metro_nbeta <= d_metro_nbeta;
                    q_is_su3mul <= d_is_su3mul;
                    q_su3_ns <= d_su3_ns;
                    q_su3_dst <= d_su3_dst;
                    q_su3_src <= d_su3_src;
                    q_is_qmeasure <= d_is_qmeasure;
                    q_qmeasure_qubit <= d_qmeasure_qubit;
                    q_qmeasure_nd <= d_qmeasure_nd;
                    q_qm_reg_a0 <= d_qm_reg_a0;
                    q_qm_reg_a1 <= d_qm_reg_a1;
                    q_qm_reg_b0 <= d_qm_reg_b0;
                    q_qm_reg_b1 <= d_qm_reg_b1;
                    q_write_bank <= d_write_bank;
                    q_write_addr <= d_write_addr;
                    q_rd_r_a <= d_rd_r_a;
                    q_rd_r_b <= d_rd_r_b;
                    q_rd_g_a <= d_rd_g_a;
                    q_rd_g_b <= d_rd_g_b;
                    q_rd_b_a <= d_rd_b_a;
                    q_rd_b_b <= d_rd_b_b;
                    q_rd_n_a <= d_rd_n_a;
                    q_rd_n_b <= d_rd_n_b;
                    q_rd_n_late <= d_rd_n_late;
                    q_reg_write <= d_reg_write;
                    q_illegal <= d_illegal;
                end
            end
        end
        assign bank = q_bank;
        assign alu_funct = q_alu_funct;
        assign branch_funct = q_branch_funct;
        assign rd_addr = q_rd_addr;
        assign rs1_addr = q_rs1_addr;
        assign rs2_addr = q_rs2_addr;
        assign imm = q_imm;
        assign alu_src_imm = q_alu_src_imm;
        assign is_branch = q_is_branch;
        assign is_halt = q_is_halt;
        assign tohost_reg = q_tohost_reg;
        assign is_gluon = q_is_gluon;
        assign gluon_funct = q_gluon_funct;
        assign gluon_rs1_bank = q_gluon_rs1_bank;
        assign gluon_rs1_reg = q_gluon_rs1_reg;
        assign gluon_rs2_bank = q_gluon_rs2_bank;
        assign gluon_rs2_reg = q_gluon_rs2_reg;
        assign is_baryon = q_is_baryon;
        assign baryon_rr = q_baryon_rr;
        assign baryon_gg = q_baryon_gg;
        assign baryon_bb = q_baryon_bb;
        assign baryon_funct = q_baryon_funct;
        assign is_meson = q_is_meson;
        assign meson_funct = q_meson_funct;
        assign meson_q1_bank = q_meson_q1_bank;
        assign meson_q1_reg = q_meson_q1_reg;
        assign meson_q2_bank = q_meson_q2_bank;
        assign meson_q2_reg = q_meson_q2_reg;
        assign is_load = q_is_load;
        assign is_store = q_is_store;
        assign mem_nd_ns = q_mem_nd_ns;
        assign mem_base_bank = q_mem_base_bank;
        assign mem_base_reg = q_mem_base_reg;
        assign mem_imm = q_mem_imm;
        assign is_jal = q_is_jal;
        assign jal_imm = q_jal_imm;
        assign is_rft = q_is_rft;
        assign is_syscall = q_is_syscall;
        assign is_mvsr = q_is_mvsr;
        assign mvsr_dir = q_mvsr_dir;
        assign mvsr_selreg = q_mvsr_selreg;
        assign mvsr_nreg = q_mvsr_nreg;
        assign is_ptb = q_is_ptb;
        assign ptb_dir = q_ptb_dir;
        assign ptb_nreg = q_ptb_nreg;
        assign is_qhad = q_is_qhad;
        assign qhad_qubit = q_qhad_qubit;
        assign qhad_half = q_qhad_half;
        assign is_qcnot = q_is_qcnot;
        assign qcnot_ctrl = q_qcnot_ctrl;
        assign q_reg_i = q_q_reg_i;
        assign q_reg_j = q_q_reg_j;
        assign is_string = q_is_string;
        assign is_regge = q_is_regge;
        assign regge_funct = q_regge_funct;
        assign regge_ns = q_regge_ns;
        assign is_jalr = q_is_jalr;
        assign jalr_ns = q_jalr_ns;
        assign is_mtag = q_is_mtag;
        assign mtag_funct = q_mtag_funct;
        assign mtag_ns = q_mtag_ns;
        assign is_plaq = q_is_plaq;
        assign is_linkmul = q_is_linkmul;
        assign is_reunit = q_is_reunit;
        assign is_sweep = q_is_sweep;
        assign is_hop = q_is_hop;
        assign hop_funct = q_hop_funct;
        assign hop_dir = q_hop_dir;
        assign hop_reg = q_hop_reg;
        assign is_cim = q_is_cim;
        assign cim_funct = q_cim_funct;
        assign cim_ns = q_cim_ns;
        assign cim_nt = q_cim_nt;
        assign sw_l1 = q_sw_l1;
        assign ru_ns = q_ru_ns;
        assign lm_daga = q_lm_daga;
        assign lm_dagb = q_lm_dagb;
        assign lm_na = q_lm_na;
        assign lm_nb = q_lm_nb;
        assign lm_nc = q_lm_nc;
        assign is_metro = q_is_metro;
        assign metro_weight = q_metro_weight;
        assign metro_na = q_metro_na;
        assign metro_nb = q_metro_nb;
        assign metro_nbeta = q_metro_nbeta;
        assign is_su3mul = q_is_su3mul;
        assign su3_ns = q_su3_ns;
        assign su3_dst = q_su3_dst;
        assign su3_src = q_su3_src;
        assign is_qmeasure = q_is_qmeasure;
        assign qmeasure_qubit = q_qmeasure_qubit;
        assign qmeasure_nd = q_qmeasure_nd;
        assign qm_reg_a0 = q_qm_reg_a0;
        assign qm_reg_a1 = q_qm_reg_a1;
        assign qm_reg_b0 = q_qm_reg_b0;
        assign qm_reg_b1 = q_qm_reg_b1;
        assign write_bank = q_write_bank;
        assign write_addr = q_write_addr;
        assign rd_r_a = q_rd_r_a;
        assign rd_r_b = q_rd_r_b;
        assign rd_g_a = q_rd_g_a;
        assign rd_g_b = q_rd_g_b;
        assign rd_b_a = q_rd_b_a;
        assign rd_b_b = q_rd_b_b;
        assign rd_n_a = q_rd_n_a;
        assign rd_n_b = q_rd_n_b;
        assign rd_n_late = q_rd_n_late;
        assign reg_write = q_reg_write;
        assign illegal = q_illegal;
`ifndef SYNTHESIS
`ifndef VERILATOR
        // the constants above must still be decode(0) - simulation only:
        // OpenLane lints with Verilator, which rejects the #delay below
        wire [1:0] z_bank;
        wire [3:0] z_alu_funct;
        wire [2:0] z_branch_funct;
        wire [2:0] z_rd_addr;
        wire [2:0] z_rs1_addr;
        wire [2:0] z_rs2_addr;
        wire [31:0] z_imm;
        wire [0:0] z_alu_src_imm;
        wire [0:0] z_is_branch;
        wire [0:0] z_is_halt;
        wire [2:0] z_tohost_reg;
        wire [0:0] z_is_gluon;
        wire [2:0] z_gluon_funct;
        wire [1:0] z_gluon_rs1_bank;
        wire [2:0] z_gluon_rs1_reg;
        wire [1:0] z_gluon_rs2_bank;
        wire [2:0] z_gluon_rs2_reg;
        wire [0:0] z_is_baryon;
        wire [2:0] z_baryon_rr;
        wire [2:0] z_baryon_gg;
        wire [2:0] z_baryon_bb;
        wire [2:0] z_baryon_funct;
        wire [0:0] z_is_meson;
        wire [1:0] z_meson_funct;
        wire [1:0] z_meson_q1_bank;
        wire [2:0] z_meson_q1_reg;
        wire [1:0] z_meson_q2_bank;
        wire [2:0] z_meson_q2_reg;
        wire [0:0] z_is_load;
        wire [0:0] z_is_store;
        wire [2:0] z_mem_nd_ns;
        wire [1:0] z_mem_base_bank;
        wire [2:0] z_mem_base_reg;
        wire [31:0] z_mem_imm;
        wire [0:0] z_is_jal;
        wire [31:0] z_jal_imm;
        wire [0:0] z_is_rft;
        wire [0:0] z_is_syscall;
        wire [0:0] z_is_mvsr;
        wire [0:0] z_mvsr_dir;
        wire [1:0] z_mvsr_selreg;
        wire [2:0] z_mvsr_nreg;
        wire [0:0] z_is_ptb;
        wire [0:0] z_ptb_dir;
        wire [2:0] z_ptb_nreg;
        wire [0:0] z_is_qhad;
        wire [0:0] z_qhad_qubit;
        wire [0:0] z_qhad_half;
        wire [0:0] z_is_qcnot;
        wire [0:0] z_qcnot_ctrl;
        wire [2:0] z_q_reg_i;
        wire [2:0] z_q_reg_j;
        wire [0:0] z_is_string;
        wire [0:0] z_is_regge;
        wire [1:0] z_regge_funct;
        wire [2:0] z_regge_ns;
        wire [0:0] z_is_jalr;
        wire [2:0] z_jalr_ns;
        wire [0:0] z_is_mtag;
        wire [1:0] z_mtag_funct;
        wire [2:0] z_mtag_ns;
        wire [0:0] z_is_plaq;
        wire [0:0] z_is_linkmul;
        wire [0:0] z_is_reunit;
        wire [0:0] z_is_sweep;
        wire [0:0] z_is_hop;
        wire [1:0] z_hop_funct;
        wire [1:0] z_hop_dir;
        wire [2:0] z_hop_reg;
        wire [0:0] z_is_cim;
        wire [2:0] z_cim_funct;
        wire [2:0] z_cim_ns;
        wire [2:0] z_cim_nt;
        wire [1:0] z_sw_l1;
        wire [2:0] z_ru_ns;
        wire [0:0] z_lm_daga;
        wire [0:0] z_lm_dagb;
        wire [2:0] z_lm_na;
        wire [2:0] z_lm_nb;
        wire [2:0] z_lm_nc;
        wire [0:0] z_is_metro;
        wire [0:0] z_metro_weight;
        wire [2:0] z_metro_na;
        wire [2:0] z_metro_nb;
        wire [2:0] z_metro_nbeta;
        wire [0:0] z_is_su3mul;
        wire [2:0] z_su3_ns;
        wire [2:0] z_su3_dst;
        wire [2:0] z_su3_src;
        wire [0:0] z_is_qmeasure;
        wire [0:0] z_qmeasure_qubit;
        wire [2:0] z_qmeasure_nd;
        wire [2:0] z_qm_reg_a0;
        wire [2:0] z_qm_reg_a1;
        wire [2:0] z_qm_reg_b0;
        wire [2:0] z_qm_reg_b1;
        wire [1:0] z_write_bank;
        wire [2:0] z_write_addr;
        wire [2:0] z_rd_r_a;
        wire [2:0] z_rd_r_b;
        wire [2:0] z_rd_g_a;
        wire [2:0] z_rd_g_b;
        wire [2:0] z_rd_b_a;
        wire [2:0] z_rd_b_b;
        wire [2:0] z_rd_n_a;
        wire [2:0] z_rd_n_b;
        wire [0:0] z_rd_n_late;
        wire [0:0] z_reg_write;
        wire [0:0] z_illegal;
        control_unit z (.instr(32'b0), .bank(z_bank), .alu_funct(z_alu_funct), .branch_funct(z_branch_funct), .rd_addr(z_rd_addr), .rs1_addr(z_rs1_addr), .rs2_addr(z_rs2_addr), .imm(z_imm), .alu_src_imm(z_alu_src_imm), .is_branch(z_is_branch), .is_halt(z_is_halt), .tohost_reg(z_tohost_reg), .is_gluon(z_is_gluon), .gluon_funct(z_gluon_funct), .gluon_rs1_bank(z_gluon_rs1_bank), .gluon_rs1_reg(z_gluon_rs1_reg), .gluon_rs2_bank(z_gluon_rs2_bank), .gluon_rs2_reg(z_gluon_rs2_reg), .is_baryon(z_is_baryon), .baryon_rr(z_baryon_rr), .baryon_gg(z_baryon_gg), .baryon_bb(z_baryon_bb), .baryon_funct(z_baryon_funct), .is_meson(z_is_meson), .meson_funct(z_meson_funct), .meson_q1_bank(z_meson_q1_bank), .meson_q1_reg(z_meson_q1_reg), .meson_q2_bank(z_meson_q2_bank), .meson_q2_reg(z_meson_q2_reg), .is_load(z_is_load), .is_store(z_is_store), .mem_nd_ns(z_mem_nd_ns), .mem_base_bank(z_mem_base_bank), .mem_base_reg(z_mem_base_reg), .mem_imm(z_mem_imm), .is_jal(z_is_jal), .jal_imm(z_jal_imm), .is_rft(z_is_rft), .is_syscall(z_is_syscall), .is_mvsr(z_is_mvsr), .mvsr_dir(z_mvsr_dir), .mvsr_selreg(z_mvsr_selreg), .mvsr_nreg(z_mvsr_nreg), .is_ptb(z_is_ptb), .ptb_dir(z_ptb_dir), .ptb_nreg(z_ptb_nreg), .is_qhad(z_is_qhad), .qhad_qubit(z_qhad_qubit), .qhad_half(z_qhad_half), .is_qcnot(z_is_qcnot), .qcnot_ctrl(z_qcnot_ctrl), .q_reg_i(z_q_reg_i), .q_reg_j(z_q_reg_j), .is_string(z_is_string), .is_regge(z_is_regge), .regge_funct(z_regge_funct), .regge_ns(z_regge_ns), .is_jalr(z_is_jalr), .jalr_ns(z_jalr_ns), .is_mtag(z_is_mtag), .mtag_funct(z_mtag_funct), .mtag_ns(z_mtag_ns), .is_plaq(z_is_plaq), .is_linkmul(z_is_linkmul), .is_reunit(z_is_reunit), .is_sweep(z_is_sweep), .is_hop(z_is_hop), .hop_funct(z_hop_funct), .hop_dir(z_hop_dir), .hop_reg(z_hop_reg), .is_cim(z_is_cim), .cim_funct(z_cim_funct), .cim_ns(z_cim_ns), .cim_nt(z_cim_nt), .sw_l1(z_sw_l1), .ru_ns(z_ru_ns), .lm_daga(z_lm_daga), .lm_dagb(z_lm_dagb), .lm_na(z_lm_na), .lm_nb(z_lm_nb), .lm_nc(z_lm_nc), .is_metro(z_is_metro), .metro_weight(z_metro_weight), .metro_na(z_metro_na), .metro_nb(z_metro_nb), .metro_nbeta(z_metro_nbeta), .is_su3mul(z_is_su3mul), .su3_ns(z_su3_ns), .su3_dst(z_su3_dst), .su3_src(z_su3_src), .is_qmeasure(z_is_qmeasure), .qmeasure_qubit(z_qmeasure_qubit), .qmeasure_nd(z_qmeasure_nd), .qm_reg_a0(z_qm_reg_a0), .qm_reg_a1(z_qm_reg_a1), .qm_reg_b0(z_qm_reg_b0), .qm_reg_b1(z_qm_reg_b1), .write_bank(z_write_bank), .write_addr(z_write_addr), .rd_r_a(z_rd_r_a), .rd_r_b(z_rd_r_b), .rd_g_a(z_rd_g_a), .rd_g_b(z_rd_g_b), .rd_b_a(z_rd_b_a), .rd_b_b(z_rd_b_b), .rd_n_a(z_rd_n_a), .rd_n_b(z_rd_n_b), .rd_n_late(z_rd_n_late), .reg_write(z_reg_write), .illegal(z_illegal));
        initial begin #0.001;
            if ({z_bank, z_alu_funct, z_branch_funct, z_rd_addr, z_rs1_addr, z_rs2_addr, z_imm, z_alu_src_imm, z_is_branch, z_is_halt, z_tohost_reg, z_is_gluon, z_gluon_funct, z_gluon_rs1_bank, z_gluon_rs1_reg, z_gluon_rs2_bank, z_gluon_rs2_reg, z_is_baryon, z_baryon_rr, z_baryon_gg, z_baryon_bb, z_baryon_funct, z_is_meson, z_meson_funct, z_meson_q1_bank, z_meson_q1_reg, z_meson_q2_bank, z_meson_q2_reg, z_is_load, z_is_store, z_mem_nd_ns, z_mem_base_bank, z_mem_base_reg, z_mem_imm, z_is_jal, z_jal_imm, z_is_rft, z_is_syscall, z_is_mvsr, z_mvsr_dir, z_mvsr_selreg, z_mvsr_nreg, z_is_ptb, z_ptb_dir, z_ptb_nreg, z_is_qhad, z_qhad_qubit, z_qhad_half, z_is_qcnot, z_qcnot_ctrl, z_q_reg_i, z_q_reg_j, z_is_string, z_is_regge, z_regge_funct, z_regge_ns, z_is_jalr, z_jalr_ns, z_is_mtag, z_mtag_funct, z_mtag_ns, z_is_plaq, z_is_linkmul, z_is_reunit, z_is_sweep, z_is_hop, z_hop_funct, z_hop_dir, z_hop_reg, z_is_cim, z_cim_funct, z_cim_ns, z_cim_nt, z_sw_l1, z_ru_ns, z_lm_daga, z_lm_dagb, z_lm_na, z_lm_nb, z_lm_nc, z_is_metro, z_metro_weight, z_metro_na, z_metro_nb, z_metro_nbeta, z_is_su3mul, z_su3_ns, z_su3_dst, z_su3_src, z_is_qmeasure, z_qmeasure_qubit, z_qmeasure_nd, z_qm_reg_a0, z_qm_reg_a1, z_qm_reg_b0, z_qm_reg_b1, z_write_bank, z_write_addr, z_rd_r_a, z_rd_r_b, z_rd_g_a, z_rd_g_b, z_rd_b_a, z_rd_b_b, z_rd_n_a, z_rd_n_b, z_rd_n_late, z_reg_write, z_illegal} !== {2'b00, 4'b0000, 3'b000, 3'b000, 3'b000, 3'b000, 32'b00000000000000000000000000000000, 1'b0, 1'b0, 1'b0, 3'b000, 1'b0, 3'b000, 2'b00, 3'b000, 2'b00, 3'b000, 1'b0, 3'b000, 3'b000, 3'b000, 3'b000, 1'b0, 2'b00, 2'b00, 3'b000, 2'b00, 3'b000, 1'b0, 1'b0, 3'b000, 2'b00, 3'b000, 32'b00000000000000000000000000000000, 1'b0, 32'b00000000000000000000000000000000, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 3'b000, 1'b0, 1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'b000, 3'b000, 1'b0, 1'b0, 2'b00, 3'b000, 1'b0, 3'b000, 1'b0, 2'b00, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 3'b000, 1'b0, 3'b000, 3'b000, 3'b000, 2'b00, 3'b000, 1'b0, 1'b0, 3'b000, 3'b000, 3'b000, 1'b0, 1'b0, 3'b000, 3'b000, 3'b000, 1'b0, 3'b000, 3'b000, 3'b000, 1'b0, 1'b0, 3'b000, 3'b000, 3'b000, 3'b000, 3'b000, 2'b00, 3'b000, 3'b000, 3'b000, 3'b000, 3'b000, 3'b000, 3'b000, 3'b000, 3'b000, 1'b0, 1'b1, 1'b0}) begin
                $display("FATAL: control_unit_stage is stale - re-run tools/gen_decode_stage.py");
                $finish;
            end
        end
`endif
`endif
    end else begin: g_comb
        control_unit u (.instr(squash ? 32'b0 : instr), .bank(bank), .alu_funct(alu_funct), .branch_funct(branch_funct), .rd_addr(rd_addr), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .imm(imm), .alu_src_imm(alu_src_imm), .is_branch(is_branch), .is_halt(is_halt), .tohost_reg(tohost_reg), .is_gluon(is_gluon), .gluon_funct(gluon_funct), .gluon_rs1_bank(gluon_rs1_bank), .gluon_rs1_reg(gluon_rs1_reg), .gluon_rs2_bank(gluon_rs2_bank), .gluon_rs2_reg(gluon_rs2_reg), .is_baryon(is_baryon), .baryon_rr(baryon_rr), .baryon_gg(baryon_gg), .baryon_bb(baryon_bb), .baryon_funct(baryon_funct), .is_meson(is_meson), .meson_funct(meson_funct), .meson_q1_bank(meson_q1_bank), .meson_q1_reg(meson_q1_reg), .meson_q2_bank(meson_q2_bank), .meson_q2_reg(meson_q2_reg), .is_load(is_load), .is_store(is_store), .mem_nd_ns(mem_nd_ns), .mem_base_bank(mem_base_bank), .mem_base_reg(mem_base_reg), .mem_imm(mem_imm), .is_jal(is_jal), .jal_imm(jal_imm), .is_rft(is_rft), .is_syscall(is_syscall), .is_mvsr(is_mvsr), .mvsr_dir(mvsr_dir), .mvsr_selreg(mvsr_selreg), .mvsr_nreg(mvsr_nreg), .is_ptb(is_ptb), .ptb_dir(ptb_dir), .ptb_nreg(ptb_nreg), .is_qhad(is_qhad), .qhad_qubit(qhad_qubit), .qhad_half(qhad_half), .is_qcnot(is_qcnot), .qcnot_ctrl(qcnot_ctrl), .q_reg_i(q_reg_i), .q_reg_j(q_reg_j), .is_string(is_string), .is_regge(is_regge), .regge_funct(regge_funct), .regge_ns(regge_ns), .is_jalr(is_jalr), .jalr_ns(jalr_ns), .is_mtag(is_mtag), .mtag_funct(mtag_funct), .mtag_ns(mtag_ns), .is_plaq(is_plaq), .is_linkmul(is_linkmul), .is_reunit(is_reunit), .is_sweep(is_sweep), .is_hop(is_hop), .hop_funct(hop_funct), .hop_dir(hop_dir), .hop_reg(hop_reg), .is_cim(is_cim), .cim_funct(cim_funct), .cim_ns(cim_ns), .cim_nt(cim_nt), .sw_l1(sw_l1), .ru_ns(ru_ns), .lm_daga(lm_daga), .lm_dagb(lm_dagb), .lm_na(lm_na), .lm_nb(lm_nb), .lm_nc(lm_nc), .is_metro(is_metro), .metro_weight(metro_weight), .metro_na(metro_na), .metro_nb(metro_nb), .metro_nbeta(metro_nbeta), .is_su3mul(is_su3mul), .su3_ns(su3_ns), .su3_dst(su3_dst), .su3_src(su3_src), .is_qmeasure(is_qmeasure), .qmeasure_qubit(qmeasure_qubit), .qmeasure_nd(qmeasure_nd), .qm_reg_a0(qm_reg_a0), .qm_reg_a1(qm_reg_a1), .qm_reg_b0(qm_reg_b0), .qm_reg_b1(qm_reg_b1), .write_bank(write_bank), .write_addr(write_addr), .rd_r_a(rd_r_a), .rd_r_b(rd_r_b), .rd_g_a(rd_g_a), .rd_g_b(rd_g_b), .rd_b_a(rd_b_a), .rd_b_b(rd_b_b), .rd_n_a(rd_n_a), .rd_n_b(rd_n_b), .rd_n_late(rd_n_late), .reg_write(reg_write), .illegal(illegal));
    end endgenerate
endmodule
