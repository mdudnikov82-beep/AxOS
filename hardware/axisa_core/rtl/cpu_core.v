// AxISA single-cycle core - milestone 2 (see docs/ISA.md): adds GLUON/
// BARYON/MESON/LOAD/STORE/JAL on top of milestone 1's ALUR/ALUI/
// BRANCH/HALT.
//
// Milestone 1 broadcast ONE shared rs1_addr/rs2_addr pair to all 4
// banks, since ALUR/ALUI/BRANCH only ever touch one bank at a time.
// That doesn't generalize: GLUON/MESON take independent bank+register
// tags per operand (possibly 2 or 3 DIFFERENT banks in one cycle, or
// the SAME bank twice - docs/ISA.md explicitly allows rs1_bank==
// rs2_bank), BARYON always reads R+G+B simultaneously (fixed, not
// data-selected), and STORE reads N twice at once when base_bank==N
// (the value being stored, `ns`, plus the address register, `base_reg`
// - two DIFFERENT N addresses in the same cycle).
//
// Design (confirmed correct by a design review before this was
// written, worked through every instruction's worst case): each bank
// gets its OWN 2-port read-address mux (r_addr_a/r_addr_b etc. below),
// decided per-opcode. This was proven to never exceed the existing
// 2 read + 1 write ports per bank - the global worst case was v0.1
// GLUON's rs1_bank==rs2_bank==rd_bank case (2R+1W to one bank; v2.0's
// real gluons read just one register, driven as rs1==rs2), and STORE's
// base_bank==N case is 2R+0W to N (ties, doesn't exceed, the read
// side). Every mux branch below is gated on its own is_* flag from
// control_unit.v, never inferred by "which bits happen to match" -
// several classes reuse the SAME bit range for unrelated fields (see
// control_unit.v's own header comment), so cross-class bit reuse must
// never leak into datapath routing either.
`timescale 1ns/1ps

module cpu_core #(
    parameter INSTR_MEM_WORDS = 1024,
    parameter INSTR_INIT_FILE = "",
    // Bumped 1024->2048 (design review, before adding the UART below):
    // the private array must stay big enough to keep UART_TX_ADDR's
    // word index safely IN-RANGE, so a stray LOAD from it hits the
    // explicit read-mux tier below (defined as reading 0) rather than
    // an out-of-range array index (Icarus returns X for that, which
    // would silently poison whatever register the LOAD targets).
    parameter DATA_MEM_WORDS  = 2048,
    // Shared-bus master port (see rtl/router.v/noc_core_adapter.v,
    // ported byte-for-byte from rv32i_core - the NoC only ever speaks
    // this generic bus_req/addr/write_data/mem_write/mem_size/
    // mem_unsigned/grant/read_data protocol, with zero ISA-specific
    // assumptions, so it needed no changes to serve AxISA). A LOAD/
    // STORE whose address falls in [SHARED_MEM_BASE,
    // SHARED_MEM_BASE+SHARED_MEM_BYTES) goes out on this port instead
    // of the private data_mem below, mirroring rv32i_core/rtl/
    // cpu_core.v's own is_shared_access/mem_stall pattern exactly.
    parameter SHARED_MEM_BASE  = 32'h0000_2000,
    parameter SHARED_MEM_BYTES = 256,
    // Minimal UART-like console (design review before this was
    // written - AxISA's first real peripheral of any kind). Picked
    // deliberately inside the dead gap between the private memory's
    // old top (0xFFF) and SHARED_MEM_BASE (0x2000), so this can never
    // collide with either existing decoded range. TX needs no
    // persisted state (a fire-and-forget one-cycle pulse); RX DOES
    // need state that persists across many polling cycles, which is
    // why it's driven from OUTSIDE this module (uart_rx_data_in/
    // uart_rx_ready_in) rather than a register in here - mirrors the
    // existing precedent of keeping all real memory state for the
    // shared-bus path outside cpu_core.v too (in shared_mem_backing.v).
    parameter UART_TX_ADDR       = 32'h0000_1000,
    parameter UART_RX_DATA_ADDR  = 32'h0000_1004,
    parameter UART_RX_READY_ADDR = 32'h0000_1008,
    // Traps + privilege modes (design review before this was written -
    // see docs/ISA.md's "Traps" section for the full design). A FIXED
    // address, not a configurable vector register, for v0.1 - there is
    // only ever one thing that would want to reprogram it.
    parameter TRAP_VECTOR_ADDR = 32'h0000_0200,
    // Virtual memory (design review before this was written - see
    // docs/ISA.md's "Virtual memory" section). Default OFF (bypass,
    // rtl/mmu.v's own MMU_ENABLE=0 path: paddr=vaddr, zero added
    // latency) so every existing test that never sets up a page table
    // keeps its exact prior behavior with zero risk - mirrors
    // rv32i_core/rtl/mmu.v's own precedent exactly. Only a test that
    // deliberately wants to exercise translation passes MMU_ENABLE=1.
    parameter MMU_ENABLE    = 0,
    // v2.1: MTE-style memory tagging (docs/ISA.md "Memory tagging").
    // 0 removes the tag memory and every tag check (LDG reads tag 0,
    // STG does nothing) - for area-constrained builds.
    parameter MTE_ENABLE    = 1,
    parameter PT_INDEX_BITS = 4
) (
    // v2.1 program-load port into instr_mem (see instr_mem.v) - real
    // chips (and the ASIC wrapper) load their program from outside.
    // Simulation testbenches leave it unconnected.
    input  wire        imem_load_we,
    input  wire [31:0] imem_load_addr,
    input  wire [31:0] imem_load_data,
    input  wire        clk,
    input  wire        reset,
    output wire         halted,
    output wire [31:0]  tohost_value,

    // External interrupt request - asynchronous to the current
    // instruction, masked by `ie_r`, latched (see irq_pending below)
    // so a brief pulse is never missed even if it arrives mid-stall.
    input  wire        irq_in,

    output wire        bus_req,
    output wire [31:0] bus_addr,
    output wire [31:0] bus_write_data,
    output wire        bus_mem_write,
    output wire [1:0]  bus_mem_size,
    output wire        bus_mem_unsigned,
    input  wire        bus_grant,
    input  wire [31:0] bus_read_data,

    // UART TX: one-cycle pulse per STORE to UART_TX_ADDR - a testbench
    // (or eventually real hardware) watches this to actually emit the
    // character.
    output wire        uart_tx_valid,
    output wire [7:0]  uart_tx_data,

    // UART RX: whatever the testbench is CURRENTLY presenting, read
    // purely combinationally on LOAD - no internal latch here. Ready-
    // clear is software-explicit (a STORE to UART_RX_READY_ADDR, value
    // ignored), not hardware auto-clear-on-read: a LOAD from
    // UART_RX_DATA_ADDR must stay a pure, repeatable, side-effect-free
    // read like every other LOAD in this ISA - auto-clear would make
    // it the one address where re-issuing the same instruction twice
    // silently loses a byte with no assembly-visible signal that
    // anything unusual happened. uart_rx_ack tells the testbench
    // "software just consumed this, you may advance."
    input  wire [7:0]  uart_rx_data_in,
    input  wire        uart_rx_ready_in,
    output wire        uart_rx_ack
);
    localparam BANK_R = 2'b00;
    localparam BANK_G = 2'b01;
    localparam BANK_B = 2'b10;
    localparam BANK_N = 2'b11;

    reg  [31:0] pc;
    // Trails `pc` by exactly one cycle, unconditionally - always
    // matches whatever address instr_mem's own SYNC_READ=1 internal
    // register just latched, so (pc_r, instr) stay a self-consistent
    // pair regardless of what else the core is doing (stalled, just
    // reset, just redirected). "Address of the instruction currently
    // being decoded" (branch/JAL targets, EPC on trap) - use pc_r.
    // "Address to fetch next" (instr_mem's own .addr port, pc_plus4's
    // fallthrough) - stays raw pc.
    reg  [31:0] pc_r;
    // 1 through reset and for exactly one cycle after ANY committed
    // redirect (taken branch, JAL, trap, RFT) - a registered fetch has
    // already latched the now-abandoned next-sequential address at the
    // exact edge a redirect is decided, and cannot un-fetch it, so the
    // cycle immediately after must not let that wrong-path/warm-up
    // instr commit anything. `instr` itself is masked to 0 below, but
    // that alone is NOT sufficient here (unlike RV32I): AxISA opcode 0
    // is OP_ALUR with alu_funct 0 (not reserved) - a real, committing
    // instruction that writes R-bank register 0 - so gated_reg_write
    // ALSO needs an explicit !squash_r term, and any_trap needs
    // squash_r checked first (a pending IRQ alone can satisfy
    // any_trap's `!is_load && !is_store` guard even mid-squash, which
    // would otherwise commit epc_r from a meaningless pc_r) - see the
    // main pc/trap-state always block below.
    reg         squash_r;
    reg         halted_r;
    assign halted = halted_r;

    wire [31:0] instr_fetched;
    instr_mem #(.MEM_WORDS(INSTR_MEM_WORDS), .INIT_FILE(INSTR_INIT_FILE), .SYNC_READ(1)) imem (
        .clk(clk), .addr(pc), .stall(cpu_stall),
        .load_we(imem_load_we), .load_addr(imem_load_addr), .load_data(imem_load_data),
        .instr(instr_fetched)
    );
    wire [31:0] instr = squash_r ? 32'b0 : instr_fetched;

    wire [1:0]  bank;
    wire [3:0]  alu_funct;
    wire [2:0]  branch_funct;
    wire [2:0]  rd_addr, rs1_addr, rs2_addr;
    wire [31:0] imm;
    wire        alu_src_imm, is_branch, is_halt;
    wire [2:0]  tohost_reg;

    wire        is_gluon;
    wire [2:0]  gluon_funct;
    wire [1:0]  gluon_rs1_bank;
    wire [2:0]  gluon_rs1_reg;
    wire [1:0]  gluon_rs2_bank;
    wire [2:0]  gluon_rs2_reg;

    wire        is_baryon;
    wire [2:0]  baryon_rr, baryon_gg, baryon_bb;
    wire [2:0]  baryon_funct;

    wire        is_meson;
    wire [1:0]  meson_funct;
    wire [1:0]  meson_q1_bank;
    wire [2:0]  meson_q1_reg;
    wire [1:0]  meson_q2_bank;
    wire [2:0]  meson_q2_reg;

    wire        is_load, is_store;
    wire [2:0]  mem_nd_ns;
    wire [1:0]  mem_base_bank;
    wire [2:0]  mem_base_reg;
    wire [31:0] mem_imm;

    wire        is_jal;
    wire [31:0] jal_imm;

    wire        is_rft, is_syscall, is_mvsr;
    wire        mvsr_dir;
    wire [1:0]  mvsr_selreg;
    wire [2:0]  mvsr_nreg;

    wire        is_ptb;
    wire        ptb_dir;
    wire [2:0]  ptb_nreg;

    wire        is_qhad, qhad_qubit, qhad_half;
    wire        is_qcnot, qcnot_ctrl;
    wire [2:0]  q_reg_i, q_reg_j;

    wire        is_string;
    wire        is_regge;
    wire [1:0]  regge_funct;
    wire [2:0]  regge_ns;
    wire        rg_active, rg_stall; // v2.1 step 3 rg-sequencer (see the REGGE section)
    wire        is_jalr;
    wire [2:0]  jalr_ns;
    wire        is_mtag;
    wire [1:0]  mtag_funct;
    wire [2:0]  mtag_ns;
    wire        is_su3mul;
    wire        is_plaq;      // v2.2: lattice plaquette, on the su-sequencer
    wire        fa_wait;      // v2.2: a sequencer waits for the two-stage adder
    wire        is_metro, metro_weight;
    wire        is_linkmul, lm_daga, lm_dagb;
    wire        is_reunit;
    wire        is_sweep;
    wire [1:0]  sw_l1;
    wire [2:0]  ru_ns;
    wire        rx_active, rx_stall; // v2.3 step 2 rx-sequencer (see the REUNIT section)
    wire [2:0]  lm_na, lm_nb, lm_nc;
    wire [2:0]  metro_na, metro_nb, metro_nbeta;
    wire        mx_active, mx_stall; // v2.2 step 2 mx-sequencer (see the METRO section)
    wire [2:0]  su3_ns, su3_dst, su3_src;
    wire        su3_active, su3_stall, su3_bad; // v2.0 step 5 su-sequencer (see the SU3MUL section)
    wire        is_qmeasure, qmeasure_qubit;
    wire [2:0]  qmeasure_nd;
    wire [2:0]  qm_reg_a0, qm_reg_a1, qm_reg_b0, qm_reg_b1;

    wire [1:0]  write_bank;
    wire [2:0]  write_addr;
    wire        reg_write, illegal;
    wire        data_illegal; // v2.0: ILLEGAL that depends on register VALUES (QN flavors, SU3MUL/STG/LDG address)
    wire        tag_fault;    // v2.1: MTE tag mismatch on LOAD/STORE
    wire        str_stall;  // v2.0 step 4: STRING's distance-dependent stall

    control_unit cu (
        .instr(instr),
        .bank(bank), .alu_funct(alu_funct), .branch_funct(branch_funct),
        .rd_addr(rd_addr), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .imm(imm),
        .alu_src_imm(alu_src_imm),
        .is_branch(is_branch), .is_halt(is_halt), .tohost_reg(tohost_reg),
        .is_gluon(is_gluon), .gluon_funct(gluon_funct),
        .gluon_rs1_bank(gluon_rs1_bank), .gluon_rs1_reg(gluon_rs1_reg),
        .gluon_rs2_bank(gluon_rs2_bank), .gluon_rs2_reg(gluon_rs2_reg),
        .is_baryon(is_baryon), .baryon_rr(baryon_rr), .baryon_gg(baryon_gg), .baryon_bb(baryon_bb), .baryon_funct(baryon_funct),
        .is_meson(is_meson), .meson_funct(meson_funct),
        .meson_q1_bank(meson_q1_bank), .meson_q1_reg(meson_q1_reg),
        .meson_q2_bank(meson_q2_bank), .meson_q2_reg(meson_q2_reg),
        .is_load(is_load), .is_store(is_store), .mem_nd_ns(mem_nd_ns),
        .mem_base_bank(mem_base_bank), .mem_base_reg(mem_base_reg), .mem_imm(mem_imm),
        .is_jal(is_jal), .jal_imm(jal_imm),
        .is_rft(is_rft), .is_syscall(is_syscall), .is_mvsr(is_mvsr),
        .mvsr_dir(mvsr_dir), .mvsr_selreg(mvsr_selreg), .mvsr_nreg(mvsr_nreg),
        .is_ptb(is_ptb), .ptb_dir(ptb_dir), .ptb_nreg(ptb_nreg),
        .is_qhad(is_qhad), .qhad_qubit(qhad_qubit), .qhad_half(qhad_half),
        .is_qcnot(is_qcnot), .qcnot_ctrl(qcnot_ctrl),
        .q_reg_i(q_reg_i), .q_reg_j(q_reg_j),
        .is_string(is_string),
        .is_regge(is_regge), .regge_funct(regge_funct), .regge_ns(regge_ns),
        .is_jalr(is_jalr), .jalr_ns(jalr_ns),
        .is_mtag(is_mtag), .mtag_funct(mtag_funct), .mtag_ns(mtag_ns),
        .is_plaq(is_plaq), .is_reunit(is_reunit), .ru_ns(ru_ns), .is_sweep(is_sweep), .sw_l1(sw_l1), .is_linkmul(is_linkmul), .lm_daga(lm_daga), .lm_dagb(lm_dagb),
        .lm_na(lm_na), .lm_nb(lm_nb), .lm_nc(lm_nc), .is_metro(is_metro), .metro_weight(metro_weight),
        .metro_na(metro_na), .metro_nb(metro_nb), .metro_nbeta(metro_nbeta),
        .is_su3mul(is_su3mul), .su3_ns(su3_ns), .su3_dst(su3_dst), .su3_src(su3_src),
        .is_qmeasure(is_qmeasure), .qmeasure_qubit(qmeasure_qubit), .qmeasure_nd(qmeasure_nd),
        .qm_reg_a0(qm_reg_a0), .qm_reg_a1(qm_reg_a1), .qm_reg_b0(qm_reg_b0), .qm_reg_b1(qm_reg_b1),
        .write_bank(write_bank), .write_addr(write_addr),
        .reg_write(reg_write), .illegal(illegal)
    );

    // ==================== Per-bank read-address routing ====================
    reg [2:0] r_addr_a, r_addr_b;
    reg [2:0] g_addr_a, g_addr_b;
    reg [2:0] b_addr_a, b_addr_b;
    reg [2:0] n_addr_a, n_addr_b;
    reg [2:0] n_addr_c; // v2.3: N's third read port (LINKMUL's C)

    always @(*) begin
        r_addr_a = 3'b0; r_addr_b = 3'b0;
        if (q_active) begin
            // The q-sequencer FSM (below) owns R-bank read routing for
            // its whole multi-cycle sequence - top priority, since
            // is_qhad/is_qcnot's own `bank` field defaults to 0 (=
            // BANK_R), which would otherwise incorrectly fall through
            // to the ALUR/ALUI/BRANCH catch-all below and read
            // rs1_addr/rs2_addr (also 0-default garbage) instead.
            if (q_state_r == Q_S1) begin
                r_addr_a = q_reg_j; r_addr_b = q_reg_j + 3'd1;
            end else if (q_state_r == Q_IDLE) begin // decode cycle
                r_addr_a = q_reg_i; r_addr_b = q_reg_i + 3'd1;
            end
            // Q_S2/Q_S3/Q_S4: no read needed, defaults above stand.
        end else if (qm_active) begin
            // The qm-sequencer FSM (below) owns R-bank read routing for
            // its whole 96-cycle sequence - same top-priority reasoning
            // as q_active above (is_qmeasure's own `bank` field also
            // defaults to 0=BANK_R).
            if (qm_state_r == QM_IDLE) begin
                r_addr_a = qm_reg_a0; r_addr_b = qm_reg_a0 + 3'd1;
            end else if (qm_state_r == QM_S1) begin
                r_addr_a = qm_reg_a1; r_addr_b = qm_reg_a1 + 3'd1;
            end else if (qm_state_r == QM_S2) begin
                r_addr_a = qm_reg_b0; r_addr_b = qm_reg_b0 + 3'd1;
            end else if (qm_state_r == QM_S3) begin
                r_addr_a = qm_reg_b1; r_addr_b = qm_reg_b1 + 3'd1;
            end
            // QM_S4 onward: no further reads needed, defaults stand.
        end else if (is_gluon) begin
            case ({gluon_rs1_bank == BANK_R, gluon_rs2_bank == BANK_R})
                2'b11: begin r_addr_a = gluon_rs1_reg; r_addr_b = gluon_rs2_reg; end
                2'b10: begin r_addr_a = gluon_rs1_reg; r_addr_b = gluon_rs1_reg; end
                2'b01: begin r_addr_a = gluon_rs2_reg; r_addr_b = gluon_rs2_reg; end
                default: ;
            endcase
        end else if (is_baryon) begin
            r_addr_a = baryon_rr; r_addr_b = baryon_rr;
        end else if (is_meson) begin
            case ({meson_q1_bank == BANK_R, meson_q2_bank == BANK_R})
                2'b11: begin r_addr_a = meson_q1_reg; r_addr_b = meson_q2_reg; end
                2'b10: begin r_addr_a = meson_q1_reg; r_addr_b = meson_q1_reg; end
                2'b01: begin r_addr_a = meson_q2_reg; r_addr_b = meson_q2_reg; end
                default: ;
            endcase
        end else if (is_load || is_store) begin
            if (mem_base_bank == BANK_R) begin r_addr_a = mem_base_reg; r_addr_b = mem_base_reg; end
        end else if (!is_halt && !is_jal && !is_rft && !is_syscall && !is_mvsr && !is_ptb) begin // ALUR/ALUI/BRANCH (and illegal/default, harmlessly)
            if (bank == BANK_R) begin r_addr_a = rs1_addr; r_addr_b = rs2_addr; end
        end
        // SU3MUL owns every R/G/B read while it runs: color j's psi pair
        if (su3_active) begin r_addr_a = su3_src; r_addr_b = su3_src + 3'd1; end
    end

    always @(*) begin
        g_addr_a = 3'b0; g_addr_b = 3'b0;
        if (is_gluon) begin
            case ({gluon_rs1_bank == BANK_G, gluon_rs2_bank == BANK_G})
                2'b11: begin g_addr_a = gluon_rs1_reg; g_addr_b = gluon_rs2_reg; end
                2'b10: begin g_addr_a = gluon_rs1_reg; g_addr_b = gluon_rs1_reg; end
                2'b01: begin g_addr_a = gluon_rs2_reg; g_addr_b = gluon_rs2_reg; end
                default: ;
            endcase
        end else if (is_baryon) begin
            g_addr_a = baryon_gg; g_addr_b = baryon_gg;
        end else if (is_meson) begin
            case ({meson_q1_bank == BANK_G, meson_q2_bank == BANK_G})
                2'b11: begin g_addr_a = meson_q1_reg; g_addr_b = meson_q2_reg; end
                2'b10: begin g_addr_a = meson_q1_reg; g_addr_b = meson_q1_reg; end
                2'b01: begin g_addr_a = meson_q2_reg; g_addr_b = meson_q2_reg; end
                default: ;
            endcase
        end else if (is_load || is_store) begin
            if (mem_base_bank == BANK_G) begin g_addr_a = mem_base_reg; g_addr_b = mem_base_reg; end
        end else if (!is_halt && !is_jal && !is_rft && !is_syscall && !is_mvsr && !is_ptb) begin
            if (bank == BANK_G) begin g_addr_a = rs1_addr; g_addr_b = rs2_addr; end
        end
        // SU3MUL owns every R/G/B read while it runs: color j's psi pair
        if (su3_active) begin g_addr_a = su3_src; g_addr_b = su3_src + 3'd1; end
    end

    always @(*) begin
        b_addr_a = 3'b0; b_addr_b = 3'b0;
        if (is_gluon) begin
            case ({gluon_rs1_bank == BANK_B, gluon_rs2_bank == BANK_B})
                2'b11: begin b_addr_a = gluon_rs1_reg; b_addr_b = gluon_rs2_reg; end
                2'b10: begin b_addr_a = gluon_rs1_reg; b_addr_b = gluon_rs1_reg; end
                2'b01: begin b_addr_a = gluon_rs2_reg; b_addr_b = gluon_rs2_reg; end
                default: ;
            endcase
        end else if (is_baryon) begin
            b_addr_a = baryon_bb; b_addr_b = baryon_bb;
        end else if (is_meson) begin
            case ({meson_q1_bank == BANK_B, meson_q2_bank == BANK_B})
                2'b11: begin b_addr_a = meson_q1_reg; b_addr_b = meson_q2_reg; end
                2'b10: begin b_addr_a = meson_q1_reg; b_addr_b = meson_q1_reg; end
                2'b01: begin b_addr_a = meson_q2_reg; b_addr_b = meson_q2_reg; end
                default: ;
            endcase
        end else if (is_load || is_store) begin
            if (mem_base_bank == BANK_B) begin b_addr_a = mem_base_reg; b_addr_b = mem_base_reg; end
        end else if (!is_halt && !is_jal && !is_rft && !is_syscall && !is_mvsr && !is_ptb) begin
            if (bank == BANK_B) begin b_addr_a = rs1_addr; b_addr_b = rs2_addr; end
        end
        // SU3MUL owns every R/G/B read while it runs: color j's psi pair
        if (su3_active) begin b_addr_a = su3_src; b_addr_b = su3_src + 3'd1; end
    end

    // N is the only bank with STORE's real double-read (ns + base_reg,
    // when base_bank==N) and HALT's tohost read - BARYON never reads N
    // at all (it only writes nd), so it's deliberately absent below.
    always @(*) begin
        n_addr_a = 3'b0; n_addr_b = 3'b0;
        if (is_gluon) begin
            case ({gluon_rs1_bank == BANK_N, gluon_rs2_bank == BANK_N})
                2'b11: begin n_addr_a = gluon_rs1_reg; n_addr_b = gluon_rs2_reg; end
                2'b10: begin n_addr_a = gluon_rs1_reg; n_addr_b = gluon_rs1_reg; end
                2'b01: begin n_addr_a = gluon_rs2_reg; n_addr_b = gluon_rs2_reg; end
                default: ;
            endcase
        end else if (is_meson) begin
            case ({meson_q1_bank == BANK_N, meson_q2_bank == BANK_N})
                2'b11: begin n_addr_a = meson_q1_reg; n_addr_b = meson_q2_reg; end
                2'b10: begin n_addr_a = meson_q1_reg; n_addr_b = meson_q1_reg; end
                2'b01: begin n_addr_a = meson_q2_reg; n_addr_b = meson_q2_reg; end
                default: ;
            endcase
        end else if (is_load) begin
            if (mem_base_bank == BANK_N) begin n_addr_a = mem_base_reg; n_addr_b = mem_base_reg; end
        end else if (is_store) begin
            n_addr_a = mem_nd_ns; // the value to store - ALWAYS read from N
            n_addr_b = (mem_base_bank == BANK_N) ? mem_base_reg : mem_nd_ns;
        end else if (is_halt) begin
            n_addr_a = tohost_reg; n_addr_b = tohost_reg;
        end else if (is_mvsr) begin
            // dir=1 (write, N->special): read mvsr_nreg's value to
            // capture into the target special register (see the
            // trap-entry always block below). dir=0 (read, special->N):
            // no N read needed at all - the result is written via the
            // normal write_data/write_bank broadcast, same as LOAD.
            if (mvsr_dir) begin n_addr_a = mvsr_nreg; n_addr_b = mvsr_nreg; end
        end else if (is_ptb) begin
            // Same shape as MVSR's write direction just above: dir=1
            // (write, N->PTB) needs ptb_nreg's value read to capture
            // into ptb_r (trap-entry always block below); dir=0 (read,
            // PTB->N) needs no N read at all - control_unit.v already
            // routed that case via the normal write_data/write_bank
            // broadcast, same as MVSR's own read direction.
            if (ptb_dir) begin n_addr_a = ptb_nreg; n_addr_b = ptb_nreg; end
        end else if (!is_jal && !is_rft && !is_syscall) begin // ALUR/ALUI/BRANCH (BARYON has no N read - falls through harmlessly, bank stays 0!=BANK_N)
            if (bank == BANK_N) begin n_addr_a = rs1_addr; n_addr_b = rs2_addr; end
        end
        // SU3MUL: the matrix base address (only N touches memory)
        if (su3_active) begin n_addr_a = su3_ns; n_addr_b = su3_ns; end
        // MTAG: its pointer operand
        if (is_mtag) begin n_addr_a = mtag_ns; n_addr_b = mtag_ns; end
        // JALR: the target base (read before nd is written - no bypass, so nd == ns works)
        if (is_jalr) begin n_addr_a = jalr_ns; n_addr_b = jalr_ns; end
        // REGGE: the mass / spin operand
        if (is_regge) begin n_addr_a = regge_ns; n_addr_b = regge_ns; end
        // METRO: P_old / P_new on the decode cycle, beta on the next
        if (is_metro) begin n_addr_a = (mx_state_r == MX_SUB) ? metro_nbeta : metro_na; n_addr_b = metro_nb; end
        // LINKMUL: all three matrix bases on the decode cycle (port C is its own)
        n_addr_c = lm_nc;
        if (is_linkmul) begin n_addr_a = lm_na; n_addr_b = lm_nb; end
        // REUNIT: the matrix base
        if (is_reunit) begin n_addr_a = ru_ns; n_addr_b = ru_ns; end
    end

    // ==================== Register banks ====================
    wire [31:0] r_porta_data, r_portb_data;
    wire [31:0] g_porta_data, g_portb_data;
    wire [31:0] b_porta_data, b_portb_data;
    wire [31:0] n_porta_data, n_portb_data, n_portc_data;

    wire [31:0] write_data;

    // Gated ONCE here, not repeated at all four sites - a stalled
    // LOAD/STORE only ever targets N anyway (only N is load/store-
    // writable, per docs/ISA.md's confinement rule), but a single
    // shared gate can't drift the way 4 independently-written copies
    // of "&& !mem_stall" could (confirmed by design review before
    // this was written).
    // !any_trap: an instruction that takes a trap must not commit -
    // epc_r points AT it, so RFT re-executes it. Sync traps already had
    // reg_write=0, but an external IRQ landing on an ordinary
    // instruction used to let its write through as well, so after RFT
    // it ran twice (found by tb_trap_irq_string.v's n6 check, v2.0).
    // !su3_stall: PLAQ writes N[nd] only on its terminal cycle (SU3MUL
    // has reg_write = 0 and its own write path). Without it nd would get
    // 533 intermediate writes nobody can observe (the core is stalled and
    // the last one is right) - a mutation test confirmed that, so this
    // gate saves register-file switching rather than fixing a result.
    wire gated_reg_write = reg_write && !mem_stall && !squash_r && !data_illegal && !str_stall && !rg_stall && !su3_stall && !mx_stall && !any_trap;
    wire r_write_en = gated_reg_write && (write_bank == BANK_R);
    wire g_write_en = gated_reg_write && (write_bank == BANK_G);
    wire b_write_en = gated_reg_write && (write_bank == BANK_B);
    wire n_write_en = gated_reg_write && (write_bank == BANK_N);

    // R-bank's write port is the ONE place QHAD/QCNOT's q-sequencer
    // (see the "QHAD / QCNOT" section below) needs its own independent
    // write path, separate from the normal write_data/write_addr
    // broadcast: it must write on cycles the sequencer is still busy
    // (q_stall=1), which gated_reg_write's own "&& !mem_stall"-style
    // term would otherwise suppress. Safe to just OR q_write_en in and
    // mux the address/data per-bank ONLY for R: control_unit.v leaves
    // reg_write=0 for both new opcodes, so gated_reg_write's own
    // R-bank term is always 0 whenever q_write_en could be 1 - the two
    // paths never race.
    // QMEASURE's qm-sequencer needs the identical independent-write
    // treatment, extended here (mutually exclusive with q_write_en by
    // construction, same reasoning as fpaddsub_in_a/b's own mux above).
    // SU3MUL's write-back phase is a third independent writer, into all
    // three color banks (one register per cycle) - same exclusivity.
    wire [2:0]  r_write_addr_final = q_write_en ? q_write_addr :
                                      qm_write_en ? qm_write_addr :
                                      su_wr_r ? su_wr_addr : write_addr;
    wire [31:0] r_write_data_final = q_write_en ? q_write_data :
                                      qm_write_en ? qm_write_data :
                                      su_wr_r ? su_wr_data : write_data;
    wire        r_write_en_final   = r_write_en || q_write_en || qm_write_en || su_wr_r;
    wire [2:0]  g_write_addr_final = su_wr_g ? su_wr_addr : write_addr;
    wire [31:0] g_write_data_final = su_wr_g ? su_wr_data : write_data;
    wire        g_write_en_final   = g_write_en || su_wr_g;
    wire [2:0]  b_write_addr_final = su_wr_b ? su_wr_addr : write_addr;
    wire [31:0] b_write_data_final = su_wr_b ? su_wr_data : write_data;
    wire        b_write_en_final   = b_write_en || su_wr_b;

    regbank #(.HARDWIRE_REG0(0)) r_bank (
        .clk(clk), .rs1_addr(r_addr_a), .rs2_addr(r_addr_b),
        .rs1_data(r_porta_data), .rs2_data(r_portb_data),
        .rd_addr(r_write_addr_final), .rd_data(r_write_data_final), .reg_write(r_write_en_final)
    );
    regbank #(.HARDWIRE_REG0(0)) g_bank (
        .clk(clk), .rs1_addr(g_addr_a), .rs2_addr(g_addr_b),
        .rs1_data(g_porta_data), .rs2_data(g_portb_data),
        .rd_addr(g_write_addr_final), .rd_data(g_write_data_final), .reg_write(g_write_en_final)
    );
    regbank #(.HARDWIRE_REG0(0)) b_bank (
        .clk(clk), .rs1_addr(b_addr_a), .rs2_addr(b_addr_b),
        .rs1_data(b_porta_data), .rs2_data(b_portb_data),
        .rd_addr(b_write_addr_final), .rd_data(b_write_data_final), .reg_write(b_write_en_final)
    );
    // N-bank's own independent write path (QMEASURE's outcome bit) -
    // see q_n_write_en/addr/data's own declaration in the QMEASURE
    // section above for why the normal write path can't be reused here.
    wire [2:0]  n_write_addr_final = q_n_write_en ? q_n_write_addr : write_addr;
    wire [31:0] n_write_data_final = q_n_write_en ? q_n_write_data : write_data;
    wire        n_write_en_final   = n_write_en || q_n_write_en;

    regbank #(.HARDWIRE_REG0(1)) n_bank (
        .clk(clk), .rs1_addr(n_addr_a), .rs2_addr(n_addr_b),
        .rs1_data(n_porta_data), .rs2_data(n_portb_data),
        .rs3_addr(n_addr_c), .rs3_data(n_portc_data),
        .rd_addr(n_write_addr_final), .rd_data(n_write_data_final), .reg_write(n_write_en_final)
    );

    // ALUR/ALUI/BRANCH operand select (bank's own port A/B - rs1/rs2 of `bank`)
    wire [31:0] sel_rs1_data = (bank == BANK_R) ? r_porta_data :
                                (bank == BANK_G) ? g_porta_data :
                                (bank == BANK_B) ? b_porta_data : n_porta_data;
    wire [31:0] sel_rs2_data = (bank == BANK_R) ? r_portb_data :
                                (bank == BANK_G) ? g_portb_data :
                                (bank == BANK_B) ? b_portb_data : n_portb_data;

    // GLUON operand select - rs1 is always on its bank's port A, rs2 is
    // always on its bank's port B (true even in the same-bank case, see
    // the routing muxes above: match1 always drives addr_a, match2
    // always drives addr_b).
    wire [31:0] gluon_rs1_data = (gluon_rs1_bank == BANK_R) ? r_porta_data :
                                  (gluon_rs1_bank == BANK_G) ? g_porta_data :
                                  (gluon_rs1_bank == BANK_B) ? b_porta_data : n_porta_data;

    wire [31:0] meson_q1_data = (meson_q1_bank == BANK_R) ? r_porta_data :
                                 (meson_q1_bank == BANK_G) ? g_porta_data :
                                 (meson_q1_bank == BANK_B) ? b_porta_data : n_porta_data;
    wire [31:0] meson_q2_data = (meson_q2_bank == BANK_R) ? r_portb_data :
                                 (meson_q2_bank == BANK_G) ? g_portb_data :
                                 (meson_q2_bank == BANK_B) ? b_portb_data : n_portb_data;

    wire [31:0] baryon_rr_data = r_porta_data;
    wire [31:0] baryon_gg_data = g_porta_data;
    wire [31:0] baryon_bb_data = b_porta_data;

    // STORE's value-to-store (`ns`) is always N's port A; the base
    // address register is port A of whichever non-N bank matched, or
    // N's port B specifically when base_bank==N (the STORE-only
    // double-read case - see the N read-routing mux above). LOAD never
    // hits that double-read (no `ns` to compete with), so it always
    // uses port A even when base_bank==N.
    wire [31:0] mem_base_data = (mem_base_bank == BANK_R) ? r_porta_data :
                                 (mem_base_bank == BANK_G) ? g_porta_data :
                                 (mem_base_bank == BANK_B) ? b_porta_data :
                                 (is_store ? n_portb_data : n_porta_data);
    wire [31:0] store_value = n_porta_data;

    // Latched, NOT a live combinational read - see cpu_core.v's git
    // history / project memory for why (halted_r registers one cycle
    // after is_halt is first seen; a live read would track the extra
    // past-the-end-of-program fetch's decode instead of HALT's actual
    // operand by the time anything outside checks it).
    reg [31:0] tohost_r;
    assign tohost_value = tohost_r;

    // ==================== ALU (ALUR/ALUI) ====================
    wire [31:0] alu_b = alu_src_imm ? imm : sel_rs2_data;
    wire [31:0] alu_result;
    alu ax (.a(sel_rs1_data), .b(alu_b), .funct(alu_funct), .result(alu_result));

    // ==================== GLUON ====================
    // v2.0 real gluons (docs/ISA.md). The 6 off-diagonal gluons only
    // change the quark's color (control_unit.v picks the destination
    // bank) - the value itself passes through. The 2 diagonal ones scale
    // it by their Gell-Mann eigenvalue for the quark's color:
    //   lambda3 = diag( 1, -1,  0)   lambda8 = diag( 1, 1, -2) (x sqrt(3), integer form)
    // Both are traceless, so a red+green+blue triple with equal values
    // always sums to 0 afterwards - the color-singlet invariant.
    wire [31:0] gluon_v = gluon_rs1_data;
    wire [31:0] gluon_l3 = (gluon_rs1_bank == BANK_R) ? gluon_v :
                           (gluon_rs1_bank == BANK_G) ? -gluon_v : 32'd0;
    wire [31:0] gluon_l8 = (gluon_rs1_bank == BANK_B) ? -(gluon_v << 1) : gluon_v;
    wire [31:0] gluon_result = (gluon_funct == 3'd6) ? gluon_l3 :
                               (gluon_funct == 3'd7) ? gluon_l8 : gluon_v;

    // ==================== BARYON / MESON ====================
    // v2.0 (docs/ISA.md): SUM; MAJ = bitwise majority ("color vote", the
    // same function as SHA-256's Maj); EPS = Levi-Civita symbol of the
    // three values' order: sgn(r-g)*sgn(g-b)*sgn(b-r), +1 for r<g<b
    // cyclically, -1 anti-cyclically, 0 if any two are equal - totally
    // antisymmetric, like a real baryon's color wavefunction eps_ijk.
    wire signed [31:0] b_r = baryon_rr_data, b_g = baryon_gg_data, b_b = baryon_bb_data;
    wire eps_any_eq = (b_r == b_g) || (b_g == b_b) || (b_b == b_r);
    // sgn product is negative iff an odd number of the 3 differences
    // are negative (none is zero once eps_any_eq is ruled out)
    wire eps_neg = (b_r < b_g) ^ (b_g < b_b) ^ (b_b < b_r);
    wire [31:0] baryon_eps = eps_any_eq ? 32'd0 : (eps_neg ? 32'hFFFFFFFF : 32'd1);
    wire [31:0] baryon_maj = (baryon_rr_data & baryon_gg_data) | (baryon_gg_data & baryon_bb_data) |
                             (baryon_rr_data & baryon_bb_data);
    // ---- v2.0 step 3: flavor quantum numbers (docs/ISA.md) ----
    // A quark register holds a flavor code u=1 d=2 s=3 c=4 b=5 t=6; an
    // antiquark holds the negated code (ANTI). QN packs the hadron's
    // quantum numbers into 4-bit signed fields:
    //   [3:0] Q  [7:4] B  [11:8] S  [15:12] C  [19:16] B'  [23:20] T(=0)  [27:24] 2*I3
    // The top quark decays (~5e-25 s) before it can hadronize, so a QN
    // with a top/antitop traps ILLEGAL and T is always 0 - kept as a
    // field so the layout covers all six flavors' quantum numbers.
    // fl_field(f, k) = one quantum number of one quark (k: 0=3*Q 1=S
    // 2=C 3=B' 5=2*I3), sign-flipped for an antiquark.
    function [3:0] fl_field;
        input [31:0] f;
        input [2:0]  k;
        reg   [2:0]  a;
        reg   [3:0]  v;
        begin
            a = f[31] ? (~f[2:0] + 3'd1) : f[2:0]; // |f| - only meaningful once fl_valid(f)
            case (k)
                3'd0:    v = (a == 3'd1 || a == 3'd4 || a == 3'd6) ? 4'd2 : 4'hF; // u,c,t +2/3 - d,s,b -1/3
                3'd1:    v = (a == 3'd3) ? 4'hF : 4'd0;                         // s: S = -1
                3'd2:    v = (a == 3'd4) ? 4'd1 : 4'd0;                         // c: C = +1
                3'd3:    v = (a == 3'd5) ? 4'hF : 4'd0;                         // b: B' = -1
                3'd4:    v = 4'd0;                                              // T: top never hadronizes
                default: v = (a == 3'd1) ? 4'd1 : (a == 3'd2) ? 4'hF : 4'd0;    // u: +1, d: -1 (2*I3)
            endcase
            fl_field = f[31] ? (~v + 4'd1) : v;
        end
    endfunction
    function fl_valid; // a quark/antiquark that can be bound into a hadron: u d s c b, not t
        input [31:0] f;
        fl_valid = ($signed(f) >= 1 && $signed(f) <= 5) || ($signed(f) >= -5 && $signed(f) <= -1);
    endfunction
    // charge: the 3*Q sum of a real hadron is always a multiple of 3
    function [3:0] div3;
        input [3:0] x;
        div3 = (x == 4'd6) ? 4'd2 : (x == 4'd3) ? 4'd1 : (x == 4'hD) ? 4'hF : (x == 4'hA) ? 4'hE : 4'd0;
    endfunction

    wire bq_all_quark = !baryon_rr_data[31] && !baryon_gg_data[31] && !baryon_bb_data[31];
    wire bq_all_anti  =  baryon_rr_data[31] &&  baryon_gg_data[31] &&  baryon_bb_data[31];
    wire baryon_qn_ok = fl_valid(baryon_rr_data) && fl_valid(baryon_gg_data) && fl_valid(baryon_bb_data) &&
                        (bq_all_quark || bq_all_anti); // qqq or anti-qqq only
    wire [3:0] bqf [0:5];
    genvar gk;
    generate for (gk = 0; gk < 6; gk = gk + 1) begin : g_bqn
        assign bqf[gk] = fl_field(baryon_rr_data, gk) + fl_field(baryon_gg_data, gk) + fl_field(baryon_bb_data, gk);
    end endgenerate
    wire [31:0] baryon_qn = {4'd0, bqf[5], bqf[4], bqf[3], bqf[2], bqf[1],
                             bq_all_anti ? 4'hF : 4'd1, div3(bqf[0])};

    wire [31:0] baryon_result = (baryon_funct == 3'b001) ? baryon_maj :
                                (baryon_funct == 3'b010) ? baryon_eps :
                                (baryon_funct == 3'b011) ? baryon_qn :
                                baryon_rr_data + baryon_gg_data + baryon_bb_data;
    // DIFF = q1 - q2 (v0.1, any banks); SINGLET = q + qbar, where q2
    // already holds the antiquark (charge-conjugated, i.e. negated) -
    // so SINGLET(q, ANTI(x)) == DIFF(q, x). control_unit.v enforces
    // SINGLET's same-color rule.
    // QN: one quark + one antiquark (either order), same color (checked
    // in control_unit.v). Baryon number is 0 by construction.
    wire meson_qn_ok = fl_valid(meson_q1_data) && fl_valid(meson_q2_data) &&
                       (meson_q1_data[31] != meson_q2_data[31]);
    wire [3:0] mqf [0:5];
    generate for (gk = 0; gk < 6; gk = gk + 1) begin : g_mqn
        assign mqf[gk] = fl_field(meson_q1_data, gk) + fl_field(meson_q2_data, gk);
    end endgenerate
    wire [31:0] meson_qn = {4'd0, mqf[5], mqf[4], mqf[3], mqf[2], mqf[1], 4'd0, div3(mqf[0])};

    wire [31:0] meson_result  = (meson_funct == 2'b01) ? meson_q1_data + meson_q2_data :
                                (meson_funct == 2'b10) ? meson_qn :
                                                         meson_q1_data - meson_q2_data;

    assign data_illegal = (is_baryon && baryon_funct == 3'b011 && !baryon_qn_ok) ||
                          (is_meson  && meson_funct  == 2'b10  && !meson_qn_ok) ||
                          su3_bad || mtag_bad || rx_bad;

    // ==================== STRING (v2.0 step 4: asymptotic freedom) ====================
    // d = |qa - qb|, the two quarks' positions as signed integers (33-bit
    // difference, so |d| always fits 32 bits unsigned). The interaction
    // takes 1 + E cycles, E = number of significant bits of d: weak and
    // fast at short distance, slower as the coupling grows - a log-scale
    // stand-in for the running coupling alpha_s. At d >= 2^16 the
    // string breaks into new quark-antiquark pairs instead of stretching,
    // so E saturates at 16 (17 cycles max). The result packs
    // {pairs created = d >> 16, length of the last segment = d & 0xFFFF},
    // which with a 2^16 break energy is bit-for-bit d itself.
    wire signed [32:0] str_diff = {sel_rs1_data[31], sel_rs1_data} - {sel_rs2_data[31], sel_rs2_data};
    wire        [31:0] str_d    = str_diff[32] ? (~str_diff[31:0] + 32'd1) : str_diff[31:0];
    function [4:0] str_bits; // significant bits of d, saturated at 16 (string breaking)
        input [31:0] d;
        integer i;
        begin
            str_bits = 5'd0;
            for (i = 0; i < 16; i = i + 1)
                if (d[i]) str_bits = i + 1;
            if (d[31:16] != 16'd0) str_bits = 5'd16;
        end
    endfunction
    wire [4:0] str_extra = str_bits(str_d);
    wire       str_go    = is_string && reg_write; // a legal STRING (illegal ones trap immediately)

    // Same "gated only on !halted_r, not inside !cpu_stall" shape as
    // q_state_r below, for the same deadlock reason. str_left_r counts
    // the stall cycles still to go after this one.
    reg       str_busy_r;
    reg [4:0] str_left_r;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            str_busy_r <= 1'b0;
            str_left_r <= 5'd0;
        end else if (!halted_r) begin
            if (!str_busy_r) begin
                if (str_go && str_extra != 5'd0) begin
                    str_busy_r <= 1'b1;
                    str_left_r <= str_extra - 5'd1;
                end
            end else if (str_left_r != 5'd0) begin
                str_left_r <= str_left_r - 5'd1;
            end else begin
                str_busy_r <= 1'b0; // terminal cycle: the write commits, pc moves on
            end
        end
    end
    assign str_stall = str_go && (str_busy_r ? (str_left_r != 5'd0) : (str_extra != 5'd0));

    // ==================== QHAD / QCNOT (classical quantum-circuit-
    // simulator extension - design review before this was written; see
    // docs/ISA.md's QHAD/QCNOT sections) ====================
    // AxISA's register banks have exactly 2 read + 1 write port PER
    // BANK, and only one write port total system-wide (write_data/
    // write_addr, broadcast to all 4 banks above) - neither QHAD nor
    // QCNOT can complete in one cycle (each touches 4 R-bank
    // registers). This is the first multi-cycle instruction sequencer
    // in this core - proven minimal at 5 cycles (4 writes, 1/cycle,
    // plus a mandatory write-free first read cycle so nothing is
    // clobbered before it's read).
    //
    //
    // v2.2: QHAD now takes 7 cycles, so the FPU only ever sees flip-flops
    // (12 with the two-stage FPU: S2..S6 each wait a cycle, see fa_wait).
    // Its sum used to feed fp_mul in the same cycle (addsub -> mul ->
    // write); that mux path existed for EVERY fp_mul user, so static
    // timing charged SU3MUL/QMEASURE/REGGE/METRO's products with a full
    // fp_addsub too - the core's critical path. And S1 added beta straight
    // off the R-bank read port (decode -> register file -> fp_addsub).
    // Now: IDLE latches alpha, S1 latches beta, S2..S5 add/subtract into
    // q_s_r, S3..S6 multiply it by 1/sqrt(2) and write. QCNOT (no
    // arithmetic) keeps its 5 cycles and its S1..S4 writes.
    localparam Q_IDLE = 3'd0, Q_S1 = 3'd1, Q_S2 = 3'd2, Q_S3 = 3'd3, Q_S4 = 3'd4, Q_S5 = 3'd5, Q_S6 = 3'd6;
    reg [2:0] q_state_r;

    // Gated only on !halted_r, deliberately NOT nested inside a
    // !cpu_stall-gated block - it must update WHILE q_stall (derived
    // from q_state_r itself) is already high, or it would deadlock,
    // exactly the same reasoning dmem_read_valid_r's own comment above
    // documents for the identical shape of problem.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            q_state_r <= Q_IDLE;
        end else if (!halted_r && !fa_wait) begin
            case (q_state_r)
                Q_IDLE:  q_state_r <= (is_qhad || is_qcnot) ? Q_S1 : Q_IDLE;
                Q_S1:    q_state_r <= Q_S2;
                Q_S2:    q_state_r <= Q_S3;
                Q_S3:    q_state_r <= Q_S4;
                Q_S4:    q_state_r <= is_qhad ? Q_S5 : Q_IDLE;
                Q_S5:    q_state_r <= Q_S6;
                Q_S6:    q_state_r <= Q_IDLE;
                default: q_state_r <= Q_IDLE;
            endcase
        end
    end

    // q_active covers the whole 5-cycle sequence (decode cycle through
    // the terminal write); q_stall covers only the cycles the rest of
    // the CPU must stay frozen (everything except the terminal cycle,
    // which commits its write on the same edge cpu_stall drops - the
    // same "stall clears the cycle the operation is done" shape
    // mem_stall's own sub-terms already use).
    wire q_active = (q_state_r != Q_IDLE) || is_qhad || is_qcnot;
    wire q_stall  = (q_state_r == Q_S1) || (q_state_r == Q_S2) || (q_state_r == Q_S3) ||
                     (q_state_r == Q_S4 && is_qhad) || (q_state_r == Q_S5) ||
                     (q_state_r == Q_IDLE && (is_qhad || is_qcnot));

    // Scratch amplitude holding registers: T0/T1 = alpha's Re/Im
    // (latched from the decode-cycle read), T2/T3 = beta's Re/Im
    // (latched from the S1-cycle read). Same update-timing reasoning
    // as q_state_r above.
    // q_s_r: QHAD's registered sum/difference, multiplied by 1/sqrt(2)
    // in the NEXT state (S2's sum is written in S3, ..., S5's in S6).
    reg [31:0] q_t0, q_t1, q_t2, q_t3, q_s_r;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            q_t0 <= 32'b0; q_t1 <= 32'b0; q_t2 <= 32'b0; q_t3 <= 32'b0; q_s_r <= 32'b0;
        end else if (!halted_r && !fa_wait) begin
            if (q_state_r >= Q_S2 && q_state_r <= Q_S5) q_s_r <= q_addsub_result;
            if (q_state_r == Q_IDLE && (is_qhad || is_qcnot)) begin
                q_t0 <= r_porta_data; // alpha Re
                q_t1 <= r_portb_data; // alpha Im
            end else if (q_state_r == Q_S1) begin
                q_t2 <= r_porta_data; // beta Re
                q_t3 <= r_portb_data; // beta Im
            end
        end
    end

    // QHAD's shared arithmetic: new_alpha=(alpha+beta)*k,
    // new_beta=(alpha-beta)*k, k=1/sqrt(2). One fp_addsub/fp_mul pair,
    // muxed per-step: S2..S5 add/subtract into q_s_r, S3..S6 multiply it
    // by 1/sqrt(2) and write (see Q_S5 above). QCNOT bypasses both
    // entirely (pure register move).
    localparam [31:0] Q_INV_SQRT2 = 32'h3F3504F3; // IEEE-754 binary32 for 1/sqrt(2)

    // S2: a.re + b.re   S3: a.im + b.im   S4: a.re - b.re   S5: a.im - b.im
    wire [31:0] q_add_a = (q_state_r == Q_S2 || q_state_r == Q_S4) ? q_t0 : q_t1;
    wire [31:0] q_add_b = (q_state_r == Q_S2) ? q_t2 : (q_state_r == Q_S3) ? q_t3 :
                           (q_state_r == Q_S4) ? q_t2 : q_t3;
    wire        q_add_sub = (q_state_r == Q_S4) || (q_state_r == Q_S5); // SUB for beta's new value, ADD for alpha's

    // Shared fp_addsub/fp_mul instances are ALSO used by the QMEASURE
    // qm-sequencer below (see that section) - QHAD/QCNOT's own q_active
    // and QMEASURE's own qm_active are mutually exclusive (only one
    // instruction is ever in flight at a time in this single-cycle
    // core), so muxing by qm_active here is safe and keeps "one shared
    // add/mul pair, isolated from ALUR/etc." true across the whole
    // family instead of instantiating a second, redundant pair.
    // SU3MUL's su-sequencer shares the same pair (mutually exclusive too).
    wire [31:0] fpaddsub_in_a = rx_active ? rx_x : mx_active ? mx_add_a : rg_active ? rg_add_a : su3_active ? su_add_a : qm_active ? qm_add_a : q_add_a;
    wire [31:0] fpaddsub_in_b = rx_active ? rx_y : mx_active ? mx_add_b : rg_active ? rg_add_b : su3_active ? su_add_b : qm_active ? qm_add_b : q_add_b;
    wire        fpaddsub_in_sub = rx_active ? (rx_op == RX_OP_SUB) : mx_active ? mx_add_sub : rg_active ? rg_add_sub : su3_active ? su_add_sub : qm_active ? qm_add_sub : q_add_sub;

    // v2.2: two pipeline stages (fp_addsub2.v) - the result for this
    // cycle's inputs appears next cycle; see fa_wait at the end of the file.
    wire [31:0] q_addsub_result;
    fp_addsub2 q_fpaddsub (.clk(clk), .reset(reset), .a(fpaddsub_in_a), .b(fpaddsub_in_b),
                           .op_sub(fpaddsub_in_sub), .result(q_addsub_result));

    // QHAD always chains fp_mul's input from fp_addsub's own result
    // (scaling the sum/difference by 1/sqrt(2)); QMEASURE needs fp_mul
    // used INDEPENDENTLY (squaring components, then later scaling a
    // survivor component by qm_scale) - see the qm_mul_a/qm_mul_b mux
    // in the QMEASURE section below.
    wire [31:0] fpmul_in_a = rx_active ? rx_x : mx_active ? mx_mul_a : rg_active ? rg_mul_a : su3_active ? su_mul_a : qm_active ? qm_mul_a : q_s_r;
    wire [31:0] fpmul_in_b = rx_active ? rx_y : mx_active ? mx_mul_b : rg_active ? rg_mul_b : su3_active ? su_mul_b : qm_active ? qm_mul_b : Q_INV_SQRT2;

    // v2.2: two pipeline stages (fp_mul2.v), like the adder - see fa_wait.
    wire [31:0] q_mul_result;
    fp_mul2 q_fpmul (.clk(clk), .reset(reset), .a(fpmul_in_a), .b(fpmul_in_b), .result(q_mul_result));

    // ==================== SU3MUL (v2.0 step 5: lattice QCD) ====================
    // psi' = U * psi. U: 3x3 complex matrix, 18 binary32 words row-major
    // at N[ns] (element (i,j): Re at base+8*(3i+j), Im at +4). psi: color
    // j's component is the register pair (Re, Im) = bank j [src, src+1],
    // with bank 0/1/2 = R/G/B. psi' goes to [dst, dst+1] of each bank.
    //
    // Exact, documented rounding order (docs/ISA.md) so a reference
    // model can match it bit for bit: for each term, with u = a+bi and
    // psi_j = c+di,
    //   tRe = fl(fl(a*c) - fl(b*d))    tIm = fl(fl(a*d) + fl(b*c))
    //   acc = fl(acc + t), acc starting at +0.0, j = 0, 1, 2.
    // Every product is registered (su_p1_r/su_p2_r) before it is added,
    // so fp_mul never feeds fp_addsub in the same cycle: QHAD chains
    // them the OTHER way (addsub -> mul), and a mux-selected path in
    // both directions would be a structural combinational loop.
    //
    // Per term: LRE (fetch Re) LIM (fetch Im, latch a) A (latch b,
    // p1=a*c) B (p2=b*d) C (tRe=p1-p2, p1=a*d) D (p2=b*c, accRe+=tRe)
    // E (tIm=p1+p2) F (accIm+=tIm; row done after j=2). 9 terms x 8 +
    // decode + 6 write-back cycles W0..W5 = 79 cycles - 133 since v2.2:
    // A, B, C, D, E and F each wait a cycle for the two-stage FPU (fa_wait).
    // LIM also latches psi_j (su_cr/su_dr) so the multiplier never reads
    // a register bank directly. W5 is the
    // terminal cycle (stall drops, pc moves on).
    //
    // PLAQ (v2.2) runs on the same sequencer and the same per-term states.
    // The plaquette of one lattice square is P = (1/3) Re Tr(U1 U2 U3^dag U4^dag)
    // with U1 = U_mu(x), U2 = U_nu(x+mu), U3 = U_mu(x+nu), U4 = U_nu(x): 4
    // matrices back to back at N[ns] (U_m at base + 72*(m-1)). No 3x3
    // product is ever stored: Tr M = sum_k (M e_k)_k, and M e_k is three
    // matrix*vector products, so the only extra state is one color vector.
    // For k = 0, 1, 2:
    //   ph 0: v = U4^dag e_k = conj(row k of U4)  (LRE LIM A per element)
    //   ph 1: v = U3^dag v   (element (i,j) = conj(U3[j][i]))
    //   ph 2: v = U2 v
    //   ph 3: tr += Re (U1 v)_k   (row k only; accRe starts at tr)
    // conj(a+bi) = a-bi is a sign flip of the loaded Im word, so the term
    // rounding is exactly SU3MUL's. Then PM: tr = fl(tr * fl(1/3)), and PW
    // writes N[nd] through the normal path. 1 + 3*(9 + 126 + 126 + 42) + 3
    // = 913 cycles (14 per term with the two-stage FPU; PM waits too).
    localparam SU_IDLE = 5'd0, SU_LRE = 5'd1, SU_LIM = 5'd2, SU_A = 5'd3, SU_B = 5'd4,
               SU_C = 5'd5, SU_D = 5'd6, SU_E = 5'd7, SU_F = 5'd8,
               SU_W0 = 5'd9, SU_W1 = 5'd10, SU_W2 = 5'd11, SU_W3 = 5'd12, SU_W4 = 5'd13, SU_W5 = 5'd14,
               SU_PM = 5'd15, SU_PW = 5'd16, SU_MW = 5'd17;
    localparam [31:0] PL_THIRD = 32'h3EAAAAAB; // fl(1/3)
    reg [4:0]  su_state_r;
    reg [1:0]  su_i_r, su_j_r;
    reg [31:0] su_base_r, su_a_r, su_b_r, su_p1_r, su_p2_r, su_tre_r, su_tim_r, su_accre_r, su_accim_r;
    reg [31:0] su_ore0_r, su_oim0_r, su_ore1_r, su_oim1_r, su_ore2_r, su_oim2_r;
    reg        su_pl_r;            // running a PLAQ, not an SU3MUL
    reg [1:0]  su_ph_r, su_kk_r;   // PLAQ phase and trace index k
    reg [31:0] su_vre0_r, su_vim0_r, su_vre1_r, su_vim1_r, su_vre2_r, su_vim2_r; // PLAQ's vector v
    reg [31:0] su_tr_r;            // PLAQ's running trace, then the result
    reg [31:0] su_cr, su_dr;       // psi_j latched in LIM: the FPU never reads a register bank directly
    // LINKMUL (v2.3): C = A' B' column by column - v = column j of B'
    // (PLAQ's "ph 0" loads), then A' v (a "ph 1" mat-vec). All 9 results go
    // to su_res first and are written to C at the end (MW, one word per
    // cycle), so C may be A or B or overlap them: every read comes first.
    reg        su_lm_r;
    // SWEEP (v2.3 step 3): PLAQ over every site (x, y) of a periodic L x L
    // lattice, one trace accumulated across all sites. Link U_mu(x, y) is at
    // base + 72 * (2 * (y L + x) + mu); the square at (x, y) is
    // U1 = U_0(x, y), U2 = U_1(x+1, y), U3 = U_0(x, y+1), U4 = U_1(x, y).
    reg        su_sw_r;
    reg [1:0]  su_sx, su_sy, su_l1;
    reg [31:0] su_bb_r, su_cb_r;   // B and C bases (A is su_base_r)
    reg [31:0] su_res [0:17];      // C row-major: word 2(3i+j) = Re, +1 = Im
    reg [4:0]  su_w_r;
    integer    su_ri;

    // Matrices must be word-aligned and lie entirely below the UART/MMIO
    // window - SU3MUL/PLAQ read physical memory directly (kernel-only).
    wire lm_bad_a = (n_porta_data[1:0] != 2'b00) || (n_porta_data > UART_TX_ADDR - 32'd72);
    wire lm_bad_b = (n_portb_data[1:0] != 2'b00) || (n_portb_data > UART_TX_ADDR - 32'd72);
    wire lm_bad_c = (n_portc_data[1:0] != 2'b00) || (n_portc_data > UART_TX_ADDR - 32'd72);
    // SWEEP's lattice: 2 L^2 links of 72 bytes = 144 L^2 bytes
    wire [31:0] sw_bytes = (sw_l1 == 2'd0) ? 32'd144 : (sw_l1 == 2'd1) ? 32'd576 :
                           (sw_l1 == 2'd2) ? 32'd1296 : 32'd2304;
    assign su3_bad = (su_state_r == SU_IDLE) && (
                     (is_sweep && ((n_porta_data[1:0] != 2'b00) || (n_porta_data > UART_TX_ADDR - sw_bytes))) ||
                     ((is_su3mul || is_plaq) &&
                      ((n_porta_data[1:0] != 2'b00) ||
                       (n_porta_data > UART_TX_ADDR - (is_plaq ? 32'd288 : 32'd72)))) ||
                     (is_linkmul && (lm_bad_a || lm_bad_b || lm_bad_c)));
    wire su3_go = (is_su3mul || is_plaq || is_linkmul || is_sweep) && (su_state_r == SU_IDLE) && !sync_trap;

    assign su3_active = (su_state_r != SU_IDLE) || is_su3mul || is_plaq || is_linkmul || is_sweep;
    wire   su_last_mw = (su_state_r == SU_MW) && (su_w_r == 5'd17);
    assign su3_stall  = (su_state_r == SU_IDLE) ? su3_go :
                        (su_state_r != SU_W5 && su_state_r != SU_PW && !su_last_mw);

    // which matrix element this term uses: SU3MUL U[i][j]; PLAQ per phase
    // LINKMUL: ph 0 loads B'[k][j] (k = su_j_r, column j = su_kk_r), ph 1
    // multiplies by A'[i][k] (i = su_i_r); a dagger swaps row/col + conj.
    wire [1:0]  lm_row = (su_ph_r == 2'd0) ? (lm_dagb ? su_kk_r : su_j_r) : (lm_daga ? su_j_r : su_i_r);
    wire [1:0]  lm_col = (su_ph_r == 2'd0) ? (lm_dagb ? su_j_r : su_kk_r) : (lm_daga ? su_i_r : su_j_r);
    wire [1:0]  su_row = su_lm_r ? lm_row :
                         !su_pl_r ? su_i_r : (su_ph_r == 2'd1) ? su_j_r : (su_ph_r == 2'd2) ? su_i_r : su_kk_r;
    wire [1:0]  su_col = su_lm_r ? lm_col : (su_pl_r && su_ph_r == 2'd1) ? su_i_r : su_j_r;
    wire [1:0]  su_mat = su_pl_r ? 2'd3 - su_ph_r : 2'd0;  // ph 0..3 -> U4, U3, U2, U1
    wire        su_conj = su_lm_r ? ((su_ph_r == 2'd0) ? lm_dagb : lm_daga) :
                          su_pl_r && !su_ph_r[1];           // PLAQ ph 0, 1: daggered links
    wire [31:0] su_mbase = (su_lm_r && su_ph_r == 2'd0) ? su_bb_r : su_base_r;
    wire [3:0]  su_k       = {2'b00, su_row} * 4'd3 + {2'b00, su_col};   // 3*row + col, 0..8
    // SU_A keeps the Im address up: with the two-stage FPU it can last two
    // cycles (fa_wait), and data_mem's synchronous read must still hold Im
    // in the second one, when su_b_r takes it.
    wire        su3_mem_rd = (su_state_r == SU_LRE) || (su_state_r == SU_LIM) || (su_state_r == SU_A);
    // SWEEP: the link this phase needs, with periodic wrap-around
    wire [1:0]  sw_x1   = (su_sx == su_l1) ? 2'd0 : su_sx + 2'd1;
    wire [1:0]  sw_y1   = (su_sy == su_l1) ? 2'd0 : su_sy + 2'd1;
    wire [1:0]  sw_x    = (su_mat == 2'd1) ? sw_x1 : su_sx;       // U2 sits at x+1
    wire [1:0]  sw_y    = (su_mat == 2'd2) ? sw_y1 : su_sy;       // U3 sits at y+1
    wire [3:0]  sw_site = sw_y * ({1'b0, su_l1} + 3'd1) + {2'b00, sw_x};
    wire [4:0]  sw_li   = {sw_site, su_mat[0]};                   // mu = 1 for U2, U4
    wire [31:0] sw_off  = {21'd0, sw_li, 6'b0} + {24'd0, sw_li, 3'b0}; // 72 * link index
    wire [31:0] su_moff = su_sw_r ? sw_off : {27'd0, su_mat, 3'b000} * 32'd9;
    wire [31:0] su3_addr   = su_mbase + su_moff + {25'd0, su_k, 3'b000} +
                             ((su_state_r == SU_LIM || su_state_r == SU_A) ? 32'd4 : 32'd0);
    wire [31:0] su_im_in   = {dmem_rdata[31] ^ su_conj, dmem_rdata[30:0]};

    // psi_j: SU3MUL reads it from the color banks, PLAQ from v
    wire [31:0] su_vre = (su_j_r == 2'd0) ? su_vre0_r : (su_j_r == 2'd1) ? su_vre1_r : su_vre2_r;
    wire [31:0] su_vim = (su_j_r == 2'd0) ? su_vim0_r : (su_j_r == 2'd1) ? su_vim1_r : su_vim2_r;
    wire [31:0] su_c = (su_pl_r || su_lm_r) ? su_vre :
                       (su_j_r == 2'd0) ? r_porta_data : (su_j_r == 2'd1) ? g_porta_data : b_porta_data; // psi_j Re
    wire [31:0] su_d = (su_pl_r || su_lm_r) ? su_vim :
                       (su_j_r == 2'd0) ? r_portb_data : (su_j_r == 2'd1) ? g_portb_data : b_portb_data; // psi_j Im

    wire [31:0] su_mul_a = (su_state_r == SU_PM) ? su_tr_r :
                           (su_state_r == SU_A || su_state_r == SU_C) ? su_a_r : su_b_r;
    // fl(1/3), or SWEEP's fl(1/(3 L^2)) for L = 1..4
    wire [31:0] su_scale = !su_sw_r ? PL_THIRD :
                           (su_l1 == 2'd0) ? 32'h3EAAAAAB : (su_l1 == 2'd1) ? 32'h3DAAAAAB :
                           (su_l1 == 2'd2) ? 32'h3D17B426 : 32'h3CAAAAAB;
    wire [31:0] su_mul_b = (su_state_r == SU_PM) ? su_scale :
                           (su_state_r == SU_A || su_state_r == SU_D) ? su_cr  : su_dr;
    wire [31:0] su_add_a = (su_state_r == SU_D) ? su_accre_r : (su_state_r == SU_F) ? su_accim_r : su_p1_r;
    wire [31:0] su_add_b = (su_state_r == SU_D) ? su_tre_r   : (su_state_r == SU_F) ? su_tim_r   : su_p2_r;
    wire        su_add_sub = (su_state_r == SU_C);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            su_state_r <= SU_IDLE;
            su_i_r <= 2'd0; su_j_r <= 2'd0;
            su_base_r <= 32'b0; su_a_r <= 32'b0; su_b_r <= 32'b0;
            su_p1_r <= 32'b0; su_p2_r <= 32'b0; su_tre_r <= 32'b0; su_tim_r <= 32'b0;
            su_accre_r <= 32'b0; su_accim_r <= 32'b0;
            su_ore0_r <= 32'b0; su_oim0_r <= 32'b0; su_ore1_r <= 32'b0;
            su_oim1_r <= 32'b0; su_ore2_r <= 32'b0; su_oim2_r <= 32'b0;
            su_pl_r <= 1'b0; su_ph_r <= 2'd0; su_kk_r <= 2'd0;
            su_vre0_r <= 32'b0; su_vim0_r <= 32'b0; su_vre1_r <= 32'b0;
            su_vim1_r <= 32'b0; su_vre2_r <= 32'b0; su_vim2_r <= 32'b0;
            su_tr_r <= 32'b0; su_cr <= 32'b0; su_dr <= 32'b0;
            su_sw_r <= 1'b0; su_sx <= 2'd0; su_sy <= 2'd0; su_l1 <= 2'd0;
            su_lm_r <= 1'b0; su_bb_r <= 32'b0; su_cb_r <= 32'b0; su_w_r <= 5'd0;
            for (su_ri = 0; su_ri < 18; su_ri = su_ri + 1) su_res[su_ri] <= 32'b0;
        end else if (!halted_r && !fa_wait) begin
            case (su_state_r)
                SU_IDLE: if (su3_go) begin
                    su_base_r  <= n_porta_data;
                    su_i_r     <= 2'd0; su_j_r <= 2'd0;
                    su_accre_r <= 32'b0; su_accim_r <= 32'b0; // +0.0
                    su_pl_r    <= is_plaq || is_sweep;
                    su_sw_r    <= is_sweep;
                    su_sx      <= 2'd0; su_sy <= 2'd0; su_l1 <= sw_l1;
                    su_lm_r    <= is_linkmul;
                    su_bb_r    <= n_portb_data;
                    su_cb_r    <= n_portc_data;
                    su_ph_r    <= 2'd0; su_kk_r <= 2'd0;
                    su_tr_r    <= 32'b0;
                    su_state_r <= SU_LRE;
                end
                SU_LRE: su_state_r <= SU_LIM;
                SU_LIM: begin su_a_r <= dmem_rdata; su_cr <= su_c; su_dr <= su_d; su_state_r <= SU_A; end
                SU_A: if ((su_pl_r || su_lm_r) && su_ph_r == 2'd0) begin
                    // PLAQ ph 0: v_j = conj(U4[k][j]); LINKMUL ph 0: v_j = B'[j][col]. No arithmetic
                    case (su_j_r)
                        2'd0:    begin su_vre0_r <= su_a_r; su_vim0_r <= su_im_in; end
                        2'd1:    begin su_vre1_r <= su_a_r; su_vim1_r <= su_im_in; end
                        default: begin su_vre2_r <= su_a_r; su_vim2_r <= su_im_in; end
                    endcase
                    if (su_j_r == 2'd2) begin
                        su_j_r  <= 2'd0;
                        su_ph_r <= 2'd1; su_i_r <= 2'd0;
                        su_accre_r <= 32'b0; su_accim_r <= 32'b0;
                    end else
                        su_j_r  <= su_j_r + 2'd1;
                    su_state_r <= SU_LRE;
                end else begin
                    su_b_r <= su_im_in; su_p1_r <= q_mul_result; su_state_r <= SU_B;
                end
                SU_B:   begin su_p2_r <= q_mul_result; su_state_r <= SU_C; end
                SU_C:   begin su_tre_r <= q_addsub_result; su_p1_r <= q_mul_result; su_state_r <= SU_D; end
                SU_D:   begin su_p2_r <= q_mul_result; su_accre_r <= q_addsub_result; su_state_r <= SU_E; end
                SU_E:   begin su_tim_r <= q_addsub_result; su_state_r <= SU_F; end
                SU_F: begin
                    if (su_j_r != 2'd2) begin
                        su_accim_r <= q_addsub_result;
                        su_j_r     <= su_j_r + 2'd1;
                        su_state_r <= SU_LRE;
                    end else if (su_lm_r) begin
                        // LINKMUL: C[i][col] done - into the result buffer
                        su_res[lm_ri]        <= su_accre_r;
                        su_res[lm_ri + 5'd1] <= q_addsub_result;
                        su_accre_r <= 32'b0; su_accim_r <= 32'b0;
                        su_j_r     <= 2'd0;
                        if (su_i_r == 2'd2) begin
                            su_i_r <= 2'd0;
                            if (su_kk_r == 2'd2) begin su_w_r <= 5'd0; su_state_r <= SU_MW; end
                            else begin su_kk_r <= su_kk_r + 2'd1; su_ph_r <= 2'd0; su_state_r <= SU_LRE; end
                        end else begin
                            su_i_r <= su_i_r + 2'd1; su_state_r <= SU_LRE;
                        end
                    end else if (su_pl_r && su_ph_r == 2'd3) begin
                        // PLAQ: (U1 v)_k done - the trace absorbs it
                        su_tr_r    <= su_accre_r;
                        su_accre_r <= 32'b0; su_accim_r <= 32'b0;
                        su_j_r     <= 2'd0;
                        su_ph_r    <= 2'd0;
                        su_kk_r    <= su_kk_r + 2'd1;
                        su_state_r <= (su_kk_r == 2'd2) ? SU_PM : SU_LRE;
                        if (su_kk_r == 2'd2 && su_sw_r && !(su_sx == su_l1 && su_sy == su_l1)) begin
                            // SWEEP: next site (x fastest), same running trace
                            su_kk_r    <= 2'd0;
                            su_sx      <= (su_sx == su_l1) ? 2'd0 : su_sx + 2'd1;
                            if (su_sx == su_l1) su_sy <= su_sy + 2'd1;
                            su_state_r <= SU_LRE;
                        end
                    end else begin // row i finished
                        case (su_i_r)
                            2'd0:    begin su_ore0_r <= su_accre_r; su_oim0_r <= q_addsub_result; end
                            2'd1:    begin su_ore1_r <= su_accre_r; su_oim1_r <= q_addsub_result; end
                            default: begin su_ore2_r <= su_accre_r; su_oim2_r <= q_addsub_result; end
                        endcase
                        su_accre_r <= 32'b0; su_accim_r <= 32'b0;
                        su_j_r     <= 2'd0;
                        su_i_r     <= su_i_r + 2'd1;
                        if (!su_pl_r)
                            su_state_r <= (su_i_r == 2'd2) ? SU_W0 : SU_LRE;
                        else begin
                            su_state_r <= SU_LRE;
                            if (su_i_r == 2'd2) begin // PLAQ ph 1/2: the new vector replaces v
                                su_vre0_r <= su_ore0_r; su_vim0_r <= su_oim0_r;
                                su_vre1_r <= su_ore1_r; su_vim1_r <= su_oim1_r;
                                su_vre2_r <= su_accre_r; su_vim2_r <= q_addsub_result;
                                su_i_r    <= 2'd0;
                                su_ph_r   <= su_ph_r + 2'd1;
                                if (su_ph_r == 2'd2) su_accre_r <= su_tr_r; // ph 3 accumulates onto tr
                            end
                        end
                    end
                end
                SU_PM:   begin su_tr_r <= q_mul_result; su_state_r <= SU_PW; end
                SU_PW:   su_state_r <= SU_IDLE; // N[nd] = su_tr_r commits, pc moves on
                SU_MW: if (su_w_r == 5'd17) su_state_r <= SU_IDLE; // last word written, pc moves on
                       else su_w_r <= su_w_r + 5'd1;
                SU_W5:   su_state_r <= SU_IDLE;
                default: su_state_r <= su_state_r + 5'd1; // W0..W4
            endcase
        end
    end

    // Write-back: W0/W1 = red (Re, Im), W2/W3 = green, W4/W5 = blue.
    // W0/W2/W4 have odd state codes (9/11/13) -> Re at dst; W1/W3/W5 -> Im at dst+1.
    wire [4:0]  lm_ri = ({3'b000, su_i_r} * 5'd3 + {3'b000, su_kk_r}) << 1; // C[i][col] Re index
    // LINKMUL's write-back: word w of C, one per cycle, straight into data_mem
    wire        su_mw      = (su_state_r == SU_MW);
    wire [31:0] su_mw_addr = su_cb_r + {25'd0, su_w_r, 2'b00};
    wire [31:0] su_mw_data = su_res[su_w_r];

    wire        su_wr_r = (su_state_r == SU_W0) || (su_state_r == SU_W1);
    wire        su_wr_g = (su_state_r == SU_W2) || (su_state_r == SU_W3);
    wire        su_wr_b = (su_state_r == SU_W4) || (su_state_r == SU_W5);
    wire [2:0]  su_wr_addr = su3_dst + {2'b00, ~su_state_r[0]};
    wire [31:0] su_wr_data = (su_state_r == SU_W0) ? su_ore0_r : (su_state_r == SU_W1) ? su_oim0_r :
                             (su_state_r == SU_W2) ? su_ore1_r : (su_state_r == SU_W3) ? su_oim1_r :
                             (su_state_r == SU_W4) ? su_ore2_r : su_oim2_r;

    // QCNOT's write value is a pure move: whatever this cycle's R-bank
    // read (S1) or a scratch flop (S2-S4) already holds - no
    // arithmetic involved.
    wire [31:0] q_qcnot_write_data = (q_state_r == Q_S1) ? r_porta_data :
                                      (q_state_r == Q_S2) ? q_t3 :
                                      (q_state_r == Q_S3) ? q_t0 :
                                                             q_t1; // Q_S4

    // QCNOT writes in S1..S4; QHAD two states later, S3..S6.
    wire [2:0]  q_wstep      = is_qhad ? q_state_r - 3'd2 : q_state_r; // 1..4 = i, i+1, j, j+1
    wire        q_write_en   = ((q_wstep == 3'd1) || (q_wstep == 3'd2) ||
                                 (q_wstep == 3'd3) || (q_wstep == 3'd4)) &&
                                !(is_qhad && fa_wait); // QHAD writes a product: only once it is out
    wire [2:0]  q_write_addr = (q_wstep == 3'd1) ? q_reg_i :
                                (q_wstep == 3'd2) ? (q_reg_i + 3'd1) :
                                (q_wstep == 3'd3) ? q_reg_j :
                                                     (q_reg_j + 3'd1); // 4
    wire [31:0] q_write_data = is_qcnot ? q_qcnot_write_data : q_mul_result;

    // ==================== QMEASURE (third member of the classical
    // quantum-circuit-simulator family - design review before this was
    // written; see docs/ISA.md's QMEASURE section) ====================
    // Measures one qubit: computes the outcome-0 probability P0 =
    // |A0|^2+|A1|^2 (A0/A1 = the two amplitudes sharing that qubit's
    // 0-value), draws a random float from a new free-running LFSR,
    // compares it against P0 to pick an outcome, then renormalizes the
    // 2 surviving amplitudes by 1/sqrt(P_survived) (needs fp_sqrt AND
    // fp_div, both new, ported from rv32i_core) while zeroing the 2
    // losing amplitudes - 8 R-bank writes total (4 scaled survivors +
    // 4 zeros), plus 1 N-bank write for the 1-bit outcome. A genuinely
    // new, PARALLEL FSM (qm_state_r), not folded into q_state_r above,
    // to avoid bloating every existing QHAD/QCNOT state comparison -
    // safe because is_qhad/is_qcnot/is_qmeasure are mutually exclusive
    // opcodes and only one instruction is ever in flight at a time, so
    // q_active/qm_active never overlap.
    localparam QM_IDLE=5'd0, QM_S1=5'd1, QM_S2=5'd2, QM_S3=5'd3, QM_S4=5'd4,
               QM_S5=5'd5, QM_S6=5'd6, QM_S7=5'd7, QM_S8=5'd8, QM_S9=5'd9,
               QM_SQRT=5'd10, QM_DIV=5'd11,
               QM_W0=5'd12, QM_W1=5'd13, QM_W2=5'd14, QM_W3=5'd15,
               QM_W4=5'd16, QM_W5=5'd17, QM_W6=5'd18, QM_W7=5'd19;
    reg [4:0] qm_state_r;

    // fp_sqrt/fp_div's own busy/done - declared here (used by the state
    // transition block below) even though the instances themselves are
    // declared further down, since Verilog wire references are order-
    // independent (same as this file's own existing mem_stall/
    // gated_reg_write forward-reference precedent).
    wire fp_sqrt_busy, fp_sqrt_done;
    wire fp_div_busy, fp_div_done;

    // Same "gated only on !halted_r, not nested in !cpu_stall" style as
    // q_state_r above - must transition while qm_stall (derived from
    // qm_state_r itself) is already high, or it would deadlock.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            qm_state_r <= QM_IDLE;
        end else if (!halted_r && !fa_wait) begin
            case (qm_state_r)
                QM_IDLE: qm_state_r <= is_qmeasure ? QM_S1 : QM_IDLE;
                QM_S1:   qm_state_r <= QM_S2;
                QM_S2:   qm_state_r <= QM_S3;
                QM_S3:   qm_state_r <= QM_S4;
                QM_S4:   qm_state_r <= QM_S5;
                QM_S5:   qm_state_r <= QM_S6;
                QM_S6:   qm_state_r <= QM_S7;
                QM_S7:   qm_state_r <= QM_S8;
                QM_S8:   qm_state_r <= QM_S9;
                QM_S9:   qm_state_r <= QM_SQRT;
                QM_SQRT: qm_state_r <= fp_sqrt_done ? QM_DIV : QM_SQRT;
                QM_DIV:  qm_state_r <= fp_div_done  ? QM_W0  : QM_DIV;
                QM_W0:   qm_state_r <= QM_W1;
                QM_W1:   qm_state_r <= QM_W2;
                QM_W2:   qm_state_r <= QM_W3;
                QM_W3:   qm_state_r <= QM_W4;
                QM_W4:   qm_state_r <= QM_W5;
                QM_W5:   qm_state_r <= QM_W6;
                QM_W6:   qm_state_r <= QM_W7;
                QM_W7:   qm_state_r <= QM_IDLE;
                default: qm_state_r <= QM_IDLE;
            endcase
        end
    end

    // qm_active spans decode through the terminal write (QM_W7
    // included); qm_stall excludes QM_W7 (its write commits the same
    // edge cpu_stall drops) - identical shape to q_active/q_stall above.
    wire qm_active = (qm_state_r != QM_IDLE) || is_qmeasure;
    wire qm_stall  = qm_active && (qm_state_r != QM_W7);

    // A new hardware random-number source - AxISA's first. Free-running
    // off clk/reset alone (see lfsr.v's own header for why it must NOT
    // be gated by cpu_stall/halted_r).
    wire [31:0] lfsr_q;
    lfsr32 qm_lfsr (.clk(clk), .reset(reset), .q(lfsr_q));
    // Top 23 raw bits as fraction, fixed exponent 127 -> [1.0,2.0);
    // QM_S8 below subtracts 1.0 via the shared fp_addsub to land in
    // [0, 1-2^-23], exact (no subnormal/precision edge case).
    wire [31:0] qm_rng_float = {1'b0, 8'b0111_1111, lfsr_q[31:9]};

    localparam [31:0] Q_ONE = 32'h3F800000; // IEEE-754 binary32 for 1.0

    // Scratch registers: t0-t7 hold the 4 amplitudes' Re/Im (A0,A1 =
    // outcome-0 group; B0,B1 = outcome-1 group) as they're read;
    // sq0-sq3 hold the 4 squared components; sum0/sum1 are running
    // accumulators toward P0; p0/p1 are the two outcome probabilities;
    // r is the drawn random value; p_survived/outcome_r are latched
    // once the compare (QM_S9) resolves; sqrtval/scale hold fp_sqrt's
    // and fp_div's results.
    reg [31:0] qm_t0, qm_t1, qm_t2, qm_t3, qm_t4, qm_t5, qm_t6, qm_t7;
    reg [31:0] qm_sq0, qm_sq1, qm_sq2, qm_sq3;
    reg [31:0] qm_sum0, qm_sum1;
    reg [31:0] qm_p0, qm_p1, qm_r;
    reg [31:0] qm_p_survived;
    reg        qm_outcome_r;
    reg [31:0] qm_sqrtval, qm_scale;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            qm_t0 <= 32'b0; qm_t1 <= 32'b0; qm_t2 <= 32'b0; qm_t3 <= 32'b0;
            qm_t4 <= 32'b0; qm_t5 <= 32'b0; qm_t6 <= 32'b0; qm_t7 <= 32'b0;
            qm_sq0 <= 32'b0; qm_sq1 <= 32'b0; qm_sq2 <= 32'b0; qm_sq3 <= 32'b0;
            qm_sum0 <= 32'b0; qm_sum1 <= 32'b0;
            qm_p0 <= 32'b0; qm_p1 <= 32'b0; qm_r <= 32'b0;
            qm_p_survived <= 32'b0; qm_outcome_r <= 1'b0;
            qm_sqrtval <= 32'b0; qm_scale <= 32'b0;
        end else if (!halted_r && !fa_wait) begin
            case (qm_state_r)
                QM_IDLE: if (is_qmeasure) begin
                    qm_t0 <= r_porta_data; qm_t1 <= r_portb_data; // A0
                end
                QM_S1: begin qm_t2 <= r_porta_data; qm_t3 <= r_portb_data; end // A1
                QM_S2: begin
                    qm_t4 <= r_porta_data; qm_t5 <= r_portb_data; // B0
                    qm_sq0 <= q_mul_result; // A0_re^2
                end
                QM_S3: begin
                    qm_t6 <= r_porta_data; qm_t7 <= r_portb_data; // B1
                    qm_sq1 <= q_mul_result; // A0_im^2
                end
                QM_S4: begin
                    qm_sq2  <= q_mul_result;    // A1_re^2
                    qm_sum0 <= q_addsub_result; // sq0+sq1
                end
                QM_S5: begin
                    qm_sq3  <= q_mul_result;    // A1_im^2
                    qm_sum1 <= q_addsub_result; // sum0+sq2
                end
                QM_S6: qm_p0 <= q_addsub_result; // sum1+sq3 = |A0|^2+|A1|^2
                QM_S7: qm_p1 <= q_addsub_result; // 1-P0
                QM_S8: qm_r  <= q_addsub_result; // rng_float-1.0, uniform [0,1)
                QM_S9: begin
                    // q_addsub_result here = r-P0 (see qm_add_a/b
                    // below). Sign bit set (negative) means r<P0 ->
                    // outcome=0 (the A group survives); otherwise
                    // outcome=1 (covers the r>=P0 tie correctly).
                    qm_outcome_r  <= q_addsub_result[31] ? 1'b0 : 1'b1;
                    qm_p_survived <= q_addsub_result[31] ? qm_p0 : qm_p1;
                end
                QM_SQRT: if (fp_sqrt_done) qm_sqrtval <= fp_sqrt_result;
                QM_DIV:  if (fp_div_done)  qm_scale   <= fp_div_result;
                default: ;
            endcase
        end
    end

    // Shared fp_addsub operand mux for QMEASURE's own states (see
    // fpaddsub_in_a/b/sub above, which select these whenever qm_active).
    wire [31:0] qm_add_a = (qm_state_r == QM_S4) ? qm_sq0 :
                            (qm_state_r == QM_S5) ? qm_sum0 :
                            (qm_state_r == QM_S6) ? qm_sum1 :
                            (qm_state_r == QM_S7) ? Q_ONE :
                            (qm_state_r == QM_S8) ? qm_rng_float :
                            (qm_state_r == QM_S9) ? qm_r :
                                                     32'b0;
    wire [31:0] qm_add_b = (qm_state_r == QM_S4) ? qm_sq1 :
                            (qm_state_r == QM_S5) ? qm_sq2 :
                            (qm_state_r == QM_S6) ? qm_sq3 :
                            (qm_state_r == QM_S7) ? qm_p0 :
                            (qm_state_r == QM_S8) ? Q_ONE :
                            (qm_state_r == QM_S9) ? qm_p0 :
                                                     32'b0;
    wire        qm_add_sub = (qm_state_r == QM_S7) || (qm_state_r == QM_S8) || (qm_state_r == QM_S9);

    // Survivor/loser register addresses and values - resolved directly
    // from qm_outcome_r once latched (QM_S9 onward); qm_reg_a0/a1/b0/b1
    // stay valid combinationally for the whole sequence since `instr`
    // is frozen throughout (same reasoning q_reg_i/q_reg_j already
    // rely on for QHAD/QCNOT).
    wire [2:0]  qm_surv_reg0 = qm_outcome_r ? qm_reg_b0 : qm_reg_a0;
    wire [2:0]  qm_surv_reg1 = qm_outcome_r ? qm_reg_b1 : qm_reg_a1;
    wire [2:0]  qm_lose_reg0 = qm_outcome_r ? qm_reg_a0 : qm_reg_b0;
    wire [2:0]  qm_lose_reg1 = qm_outcome_r ? qm_reg_a1 : qm_reg_b1;
    wire [31:0] qm_surv_val0 = qm_outcome_r ? qm_t4 : qm_t0;
    wire [31:0] qm_surv_val1 = qm_outcome_r ? qm_t5 : qm_t1;
    wire [31:0] qm_surv_val2 = qm_outcome_r ? qm_t6 : qm_t2;
    wire [31:0] qm_surv_val3 = qm_outcome_r ? qm_t7 : qm_t3;

    // Shared fp_mul operand mux for QMEASURE's own states: squares
    // (S2-S5) then survivor-component scaling (W0-W3).
    wire [31:0] qm_mul_a = (qm_state_r == QM_S2) ? qm_t0 :
                            (qm_state_r == QM_S3) ? qm_t1 :
                            (qm_state_r == QM_S4) ? qm_t2 :
                            (qm_state_r == QM_S5) ? qm_t3 :
                            (qm_state_r == QM_W0) ? qm_surv_val0 :
                            (qm_state_r == QM_W1) ? qm_surv_val1 :
                            (qm_state_r == QM_W2) ? qm_surv_val2 :
                            (qm_state_r == QM_W3) ? qm_surv_val3 :
                                                     32'b0;
    wire [31:0] qm_mul_b = (qm_state_r == QM_S2) ? qm_t0 :
                            (qm_state_r == QM_S3) ? qm_t1 :
                            (qm_state_r == QM_S4) ? qm_t2 :
                            (qm_state_r == QM_S5) ? qm_t3 :
                            ((qm_state_r == QM_W0) || (qm_state_r == QM_W1) ||
                             (qm_state_r == QM_W2) || (qm_state_r == QM_W3)) ? qm_scale :
                                                     32'b0;

    // fp_sqrt/fp_div: start pulses exactly once (the cycle busy is
    // still 0), same discipline as rv32i_core/rtl/cpu_core.v's own
    // fpu_div_start/fpu_sqrt_start.
    // REGGE's MASS path shares the same unit (mutually exclusive with QMEASURE).
    wire fp_sqrt_start = ((qm_state_r == QM_SQRT) || rg_sqrt_req || rx_sqrt_req) && !fp_sqrt_busy;
    wire [31:0] fp_sqrt_result;
    fp_sqrt qm_fpsqrt (
        .clk(clk), .reset(reset), .start(fp_sqrt_start), .a(rx_active ? rx_x : rg_active ? rg_p_r : qm_p_survived),
        .busy(fp_sqrt_busy), .done(fp_sqrt_done), .result(fp_sqrt_result)
    );

    wire fp_div_start = ((qm_state_r == QM_DIV) || rx_div_req) && !fp_div_busy;
    wire [31:0] fp_div_result;
    fp_div qm_fpdiv (
        .clk(clk), .reset(reset), .start(fp_div_start), .a(rx_active ? rx_x : Q_ONE), .b(rx_active ? rx_y : qm_sqrtval),
        .busy(fp_div_busy), .done(fp_div_done), .result(fp_div_result)
    );

    // R-bank writes: W0-W3 write the 2 surviving amplitudes' Re/Im,
    // each scaled by qm_scale (computed combinationally the same cycle
    // via the shared fp_mul, mirroring QHAD's own "compute->write same
    // cycle" style); W4-W7 zero the 2 losing amplitudes' Re/Im.
    wire qm_write_en = ((qm_state_r == QM_W0) || (qm_state_r == QM_W1) ||
                        (qm_state_r == QM_W2) || (qm_state_r == QM_W3) ||
                        (qm_state_r == QM_W4) || (qm_state_r == QM_W5) ||
                        (qm_state_r == QM_W6) || (qm_state_r == QM_W7)) && !fa_wait;
    wire [2:0] qm_write_addr = (qm_state_r == QM_W0) ? qm_surv_reg0 :
                                (qm_state_r == QM_W1) ? (qm_surv_reg0 + 3'd1) :
                                (qm_state_r == QM_W2) ? qm_surv_reg1 :
                                (qm_state_r == QM_W3) ? (qm_surv_reg1 + 3'd1) :
                                (qm_state_r == QM_W4) ? qm_lose_reg0 :
                                (qm_state_r == QM_W5) ? (qm_lose_reg0 + 3'd1) :
                                (qm_state_r == QM_W6) ? qm_lose_reg1 :
                                                         (qm_lose_reg1 + 3'd1); // QM_W7
    wire [31:0] qm_write_data = ((qm_state_r == QM_W0) || (qm_state_r == QM_W1) ||
                                  (qm_state_r == QM_W2) || (qm_state_r == QM_W3)) ? q_mul_result : 32'b0;

    // N-bank write: the 1-bit outcome, fired on the terminal cycle
    // alongside the last R-bank zero-write - a NEW, independent write
    // path for N (mirroring R's own q_write_en/addr/data mechanism),
    // since the normal opcode-decoded write path can't fire mid-
    // sequence (reg_write is a static decode of the frozen instr).
    wire        q_n_write_en   = (qm_state_r == QM_W7);
    wire [2:0]  q_n_write_addr = qmeasure_nd;
    wire [31:0] q_n_write_data = {31'b0, qm_outcome_r};

    // ==================== Data memory (LOAD/STORE) ====================
    // v2.1: bits [31:28] are the pointer's MTE tag, not address bits -
    // every decode below (shared/UART/MMU/dmem) sees the stripped
    // address, like ARM's top-byte-ignore. Untagged pointers (tag 0)
    // behave exactly as before.
    wire [31:0] mem_addr_tagged = mem_base_data + mem_imm;
    wire [3:0]  mem_ptr_tag     = mem_addr_tagged[31:28];
    wire [31:0] mem_addr        = {4'b0, mem_addr_tagged[27:0]};

    // Address-range decode - a dedicated adder that exists ONLY for
    // LOAD/STORE addressing (unlike rv32i_core's alu_result, which is
    // also busy computing ADD/SUB/etc. for every other instruction),
    // so there's no ambiguity to resolve here the way there could be
    // on a shared ALU output. mem_base_data (the address operand) is
    // explicitly bank-agnostic per docs/ISA.md ("base_reg may be from
    // ANY bank") - confinement only constrains which BANK LOAD/STORE
    // can touch (N), never which bank may compute an address, so this
    // decode has no interaction with the confinement rule at all.
    wire is_shared_access = (is_load || is_store) &&
        (mem_addr >= SHARED_MEM_BASE) && (mem_addr < SHARED_MEM_BASE + SHARED_MEM_BYTES);

    // UART decode (design review before this was written) - picked
    // deliberately inside the dead gap below SHARED_MEM_BASE, so this
    // can never be simultaneously true with is_shared_access; no
    // priority-encoding is needed between the two decodes.
    wire is_uart_tx        = is_store && (mem_addr == UART_TX_ADDR);
    wire is_uart_rx_data    = (mem_addr == UART_RX_DATA_ADDR);
    wire is_uart_rx_ready   = (mem_addr == UART_RX_READY_ADDR);
    wire is_uart_rx_clear   = is_store && is_uart_rx_ready;
    wire is_uart_addr       = (mem_addr == UART_TX_ADDR) || is_uart_rx_data || is_uart_rx_ready;

    assign uart_tx_valid = is_uart_tx;
    assign uart_tx_data  = store_value[7:0];
    assign uart_rx_ack   = is_uart_rx_clear;

    // ==================== Virtual memory (design review before this was
    // written - see rtl/mmu.v's own header comment and docs/ISA.md's
    // "Virtual memory" section) ====================
    // Only a user-mode private-data_mem LOAD/STORE ever gets translated
    // - kernel mode ALWAYS bypasses (avoids the bootstrap chicken-and-
    // egg problem of the kernel needing its own page table just to set
    // one up), and the shared-bus/UART tiers are already fully decoded
    // above on the RAW address, before this point, exactly like
    // rv32i_core/rtl/cpu_core.v's own equivalent scope decision.
    wire mmu_is_access = (is_load || is_store) && !is_shared_access &&
                          !is_uart_addr && (mode_r == MODE_USER);

    reg [31:0] ptb_r;
    // One-cycle pulse the exact cycle a PTB write instruction actually
    // retires (mirrors the trap-entry always block's own !mem_stall/
    // !any_trap gating below - a PTB write that instead traps for
    // privilege violation must NOT be treated as "PTB changed").
    wire ptb_changed = is_ptb && ptb_dir && !cpu_stall && !any_trap;
    wire [31:0] ptb_write_value = n_porta_data;

    wire [31:0] mmu_paddr;
    wire        mmu_stall;
    wire        mmu_fault;
    wire        mmu_walk_active;
    wire [31:0] mmu_walk_addr;

    mmu #(.MMU_ENABLE(MMU_ENABLE), .PT_INDEX_BITS(PT_INDEX_BITS), .DATA_MEM_WORDS(DATA_MEM_WORDS)) mmu_inst (
        .clk(clk), .reset(reset),
        .vaddr(mem_addr),
        .is_access(mmu_is_access),
        .is_write(is_store),
        .ptb(ptb_r),
        .ptb_changed(ptb_changed),
        .paddr(mmu_paddr),
        .mmu_stall(mmu_stall),
        .mmu_fault(mmu_fault),
        .walk_active(mmu_walk_active),
        .walk_addr(mmu_walk_addr),
        .walk_read_data(dmem_rdata)
    );

    // A private-memory LOAD needs one extra cycle once its final
    // address is stable and presented (whether that's the
    // un-translated mem_addr, or mmu_paddr the cycle mmu_stall first
    // drops) - data_mem's SYNC_READ=1 registered capture (below) makes
    // the data valid one cycle after the address is issued, not the
    // same cycle. !mmu_walk_active is REQUIRED here, not just
    // !mmu_stall - mmu_fault's own one-cycle pulse needs mem_stall to
    // read exactly 0 on the S_WALK_READ fault cycle, and that cycle
    // still has mmu_walk_active=1 even though mmu_stall has already
    // dropped to 0; without this exclusion, a LOAD that page-faults
    // would never trap (see mmu.v's own S_WALK_READ comment).
    wire dmem_read_needed = is_load && !is_shared_access && !is_uart_addr;
    wire dmem_load_stall  = dmem_read_needed && !mmu_walk_active && !mmu_stall && !dmem_read_valid_r;

    // Gated only on !halted_r, deliberately NOT nested inside the
    // !mem_stall-gated main always block below - it must update WHILE
    // mem_stall is already 1 (that's the transition it drives), so
    // gating it on !mem_stall would deadlock at dmem_load_stall=1
    // forever.
    reg dmem_read_valid_r;
    always @(posedge clk or posedge reset) begin
        if (reset) dmem_read_valid_r <= 1'b0;
        else if (!halted_r) dmem_read_valid_r <= dmem_load_stall;
    end

    // is_halt can never itself be true while mem_stall is true (HALT
    // is neither is_load nor is_store), so the tohost_r-latching logic
    // below needs no separate change for this new stall source - it's
    // already only ever reached once mem_stall has cleared.
    wire mem_stall = (is_shared_access && !bus_grant) || mmu_stall || dmem_load_stall;

    // cpu_stall = "freeze the whole CPU this cycle", the general form
    // mem_stall alone used to be. Kept as a SEPARATE wire rather than
    // folded into mem_stall's own definition: mem_stall must stay
    // purely about the memory/MMU/bus subsystem (QHAD/QCNOT/QMEASURE
    // never touch memory, so mem_stall's own components are provably
    // always 0 whenever q_stall/qm_stall is 1) - see the "QHAD / QCNOT"
    // and "QMEASURE" sections above for q_stall/qm_stall's definitions.
    wire cpu_stall = mem_stall || q_stall || qm_stall || str_stall || su3_stall || rg_stall || mx_stall || rx_stall || fa_wait;

    // Walker's own PTE fetch takes priority (its read must land on
    // data_mem's shared port); otherwise a translated user-mode access
    // uses the MMU's resolved physical address; everything else (kernel
    // mode, or the shared-bus/UART tiers whose real transfer happens
    // elsewhere and whose private-array read here is simply discarded
    // below) passes the raw address through unchanged - identical to
    // rv32i_core/rtl/cpu_core.v's own dmem_addr muxing.
    wire [31:0] dmem_addr_final = rx_mem         ? rx_addr :       // REUNIT load / store (kernel-only, physical)
                                   su3_mem_rd      ? su3_addr :      // SU3MUL matrix fetch (kernel-only, physical)
                                   su_mw           ? su_mw_addr :    // LINKMUL result write (kernel-only, physical)
                                   mmu_walk_active ? mmu_walk_addr :
                                   mmu_is_access   ? mmu_paddr    :
                                                      mem_addr;

    assign bus_req          = is_shared_access;
    assign bus_addr          = mem_addr - SHARED_MEM_BASE;
    assign bus_write_data    = store_value;
    assign bus_mem_write     = is_store;
    // AxISA is word-only (docs/ISA.md - no partial-word LOAD/STORE in
    // v0.1), so these are fixed, not decoded per-instruction: 2'b10 is
    // rv32i_core/rtl/data_mem.v's own documented "word" encoding
    // (confirmed by reading that module, not assumed) - driving it
    // constantly produces exactly full 4-byte reads/writes, never a
    // truncated/extended one. mem_unsigned is provably inconsequential
    // for word-sized accesses (that module's word path never
    // references it), tied to 0 for clarity only.
    assign bus_mem_size      = 2'b10;
    assign bus_mem_unsigned  = 1'b0;


    // ==================== REGGE (v2.1 step 3: string theory) ====================
    // Hadrons sharing quark content lie on straight Regge trajectories,
    // J = a0 + a' * M^2 - the observation the rotating relativistic
    // string (and so string theory) was invented to explain: a string of
    // tension sigma has a' = 1 / (2 pi sigma). a' = 0.9 GeV^-2 gives
    // sigma = 0.177 GeV^2, the lattice-QCD flux-tube tension.
    //   SPIN.M/SPIN.B: J = fl(a0 + fl(a' * fl(M * M)))          4 + 1 cycles
    //   MASS.M/MASS.B: M = sqrt(fl(fl(J - a0) * (1/a')))        fp_sqrt + 3
    // (.M = leading meson trajectory, rho/a2/rho3/a4: a0 = 0.5;
    //  .B = Delta baryon trajectory: a0 = 0.15.) J below a0 has no real
    // mass: fp_sqrt returns its canonical NaN, 0x7FC00000.
    localparam [31:0] RG_ALPHA    = 32'h3F666666; // 0.9f    a' (GeV^-2)
    localparam [31:0] RG_INVALPHA = 32'h3F8E38E4; // 1/0.9f  (rounded once)
    localparam [31:0] RG_A0_MESON = 32'h3F000000; // 0.5f
    localparam [31:0] RG_A0_BARYON = 32'h3E19999A; // 0.15f
    localparam RG_IDLE = 3'd0, RG_X = 3'd1, RG_Y = 3'd2, RG_Z = 3'd3, RG_SQ = 3'd4, RG_W = 3'd5;
    reg [2:0]  rg_state_r;
    reg [31:0] rg_x_r, rg_p_r;
    wire       rg_mass = regge_funct[1];
    wire [31:0] rg_a0  = regge_funct[0] ? RG_A0_BARYON : RG_A0_MESON;

    // SPIN:  X: p = x*x          Y: p = a'*p        Z: p = a0 + p     W: write
    // MASS:  X: p = x - a0       Y: p = p*(1/a')    SQ: p = sqrt(p)   W: write
    wire [31:0] rg_mul_a   = (rg_state_r == RG_X) ? rg_x_r : rg_p_r;
    wire [31:0] rg_mul_b   = (rg_state_r == RG_X) ? rg_x_r : (rg_mass ? RG_INVALPHA : RG_ALPHA);
    wire [31:0] rg_add_a   = rg_mass ? rg_x_r : rg_a0;
    wire [31:0] rg_add_b   = rg_mass ? rg_a0  : rg_p_r;
    wire        rg_add_sub = rg_mass;
    wire        rg_sqrt_req = (rg_state_r == RG_SQ);

    assign rg_active = (rg_state_r != RG_IDLE) || is_regge;
    wire   rg_go     = is_regge && (rg_state_r == RG_IDLE) && !sync_trap;
    assign rg_stall  = (rg_state_r == RG_IDLE) ? rg_go : (rg_state_r != RG_W);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rg_state_r <= RG_IDLE;
            rg_x_r <= 32'b0; rg_p_r <= 32'b0;
        end else if (!halted_r && !fa_wait) begin
            case (rg_state_r)
                RG_IDLE: if (rg_go) begin rg_x_r <= n_porta_data; rg_state_r <= RG_X; end
                RG_X: begin
                    rg_p_r     <= rg_mass ? q_addsub_result : q_mul_result;
                    rg_state_r <= RG_Y;
                end
                RG_Y: begin
                    rg_p_r     <= q_mul_result;
                    rg_state_r <= rg_mass ? RG_SQ : RG_Z;
                end
                RG_Z: begin rg_p_r <= q_addsub_result; rg_state_r <= RG_W; end
                RG_SQ: if (fp_sqrt_done) begin rg_p_r <= fp_sqrt_result; rg_state_r <= RG_W; end
                default: rg_state_r <= RG_IDLE; // RG_W: the write commits, pc moves on
            endcase
        end
    end

    // ==================== METRO (v2.2 step 2: the Metropolis step) ====================
    // dS = fl(beta * fl(P_old - P_new)) - the change of Wilson's action
    // S = beta * sum(1 - P) when one plaquette goes from P_old to P_new.
    // w = min(1, exp(-dS)) is the Boltzmann weight; ACCEPT draws r in
    // [0, 1) and answers r < w (1 = take the new link), WEIGHT returns w.
    //
    // exp(-x) for x > 0 as 2^-y, y = fl(x * log2 e): split y = n + t
    // (n integer, 0 <= t < 1, both exact - just bit slicing), 2^-t by a
    // degree-6 Horner polynomial on the shared fp_mul/fp_addsub, then
    // 2^-n by subtracting n from the exponent field. y >= 128 (w below
    // binary32's normal range) gives w = 0; the result never goes
    // subnormal (flushed, like the rest of the FPU).
    //
    // Every FPU operand comes from a flip-flop, never straight off the
    // register file (that path was the core's longest after QHAD's):
    // IDLE: latch Pold, Pnew   SUB: d = Pold - Pnew, latch beta
    // BETA: x = beta*d   Y: x <= 0 -> w = 1, else
    // y = x*log2e   SPLIT: n, t (or w = 0)   HM/HA x6: q = q*t + c_k
    // SC: w = q * 2^-n   R: r = fl(1.rand23 - 1) (ACCEPT only)   W: write.
    localparam MX_IDLE = 4'd0, MX_BETA = 4'd1, MX_Y = 4'd2, MX_SPLIT = 4'd3, MX_HM = 4'd4,
               MX_HA = 4'd5, MX_SC = 4'd6, MX_R = 4'd7, MX_W = 4'd8, MX_SUB = 4'd9;
    localparam [31:0] MX_ONE   = 32'h3F800000;
    localparam [31:0] MX_LOG2E = 32'h3FB8AA3B;   // fl(log2 e)
    reg [3:0]  mx_state_r;
    reg [2:0]  mx_k_r;
    reg [6:0]  mx_n_r;
    reg [31:0] mx_d_r, mx_x_r, mx_t_r, mx_q_r, mx_p_r, mx_w_r, mx_r_r;

    // 2^-t ~ c0 + c1 t + ... + c6 t^6 on [0, 1): relative error <= 1.8e-7
    // (fitted by tools/gen_metro_test.py, which also checks it)
    reg [31:0] mx_coef;
    always @(*) begin
        case (mx_k_r)
            3'd0:    mx_coef = 32'h3F800000;
            3'd1:    mx_coef = 32'hBF317216;
            3'd2:    mx_coef = 32'h3E75FD5C;
            3'd3:    mx_coef = 32'hBD634A03;
            3'd4:    mx_coef = 32'h3C1CF011;
            default: mx_coef = 32'hBAA70867; // c5 (c6 = 0x38E4607B seeds q)
        endcase
    end

    // y = n + t. For 1 <= y < 128 (biased exponent 127..133, s = e - 127):
    // n = the top s+1 bits of 1.m, and 1 + t = 1.(m << s) exactly.
    wire [7:0]  mx_ye  = mx_x_r[30:23];          // MX_SPLIT: mx_x_r holds y
    wire [2:0]  mx_s   = mx_ye[2:0] - 3'd7;      // e - 127 (= e + 1 mod 8)
    // Written as a case, not << / >>: Yosys's resource sharing would
    // otherwise merge these shifts with the ALU's barrel shifter (they
    // are never active together) and route METRO through the ALU's
    // decode -> register-file operand path - the longest path in the
    // core when it happened.
    reg [6:0]  mx_n;
    reg [22:0] mx_zm;
    always @(*) begin
        case (mx_s)
            3'd0:    begin mx_n = 7'd1;                      mx_zm = mx_x_r[22:0]; end
            3'd1:    begin mx_n = {6'd1, mx_x_r[22]};        mx_zm = {mx_x_r[21:0], 1'b0}; end
            3'd2:    begin mx_n = {5'd1, mx_x_r[22:21]};     mx_zm = {mx_x_r[20:0], 2'b0}; end
            3'd3:    begin mx_n = {4'd1, mx_x_r[22:20]};     mx_zm = {mx_x_r[19:0], 3'b0}; end
            3'd4:    begin mx_n = {3'd1, mx_x_r[22:19]};     mx_zm = {mx_x_r[18:0], 4'b0}; end
            3'd5:    begin mx_n = {2'd1, mx_x_r[22:18]};     mx_zm = {mx_x_r[17:0], 5'b0}; end
            default: begin mx_n = {1'b1, mx_x_r[22:17]};     mx_zm = {mx_x_r[16:0], 6'b0}; end
        endcase
    end
    wire [31:0] mx_z   = {1'b0, 8'd127, mx_zm};
    wire        mx_big = (mx_ye >= 8'd134);      // y >= 128
    wire        mx_y_lt1 = (mx_ye < 8'd127);

    wire        mx_x_le0 = mx_x_r[31] || (mx_x_r[30:0] == 31'b0);
    wire [7:0]  mx_qe    = mx_q_r[30:23];
    wire [31:0] mx_scaled = (mx_qe > {1'b0, mx_n_r}) ? {1'b0, mx_qe - {1'b0, mx_n_r}, mx_q_r[22:0]} : 32'b0;

    wire [31:0] mx_add_a = (mx_state_r == MX_SUB) ? mx_x_r :
                           (mx_state_r == MX_SPLIT) ? mx_z :
                           (mx_state_r == MX_R) ? {1'b0, 8'd127, lfsr_q[31:9]} : mx_p_r;
    wire [31:0] mx_add_b = (mx_state_r == MX_SUB) ? mx_d_r :
                           (mx_state_r == MX_HA) ? mx_coef : MX_ONE;
    wire        mx_add_sub = (mx_state_r != MX_HA);
    wire [31:0] mx_mul_a = (mx_state_r == MX_BETA) ? mx_t_r :
                           (mx_state_r == MX_Y) ? mx_x_r : mx_q_r;
    wire [31:0] mx_mul_b = (mx_state_r == MX_BETA) ? mx_d_r :
                           (mx_state_r == MX_Y) ? MX_LOG2E : mx_t_r;

    assign mx_active = (mx_state_r != MX_IDLE) || is_metro;
    wire   mx_go     = is_metro && (mx_state_r == MX_IDLE) && !sync_trap;
    assign mx_stall  = (mx_state_r == MX_IDLE) ? mx_go : (mx_state_r != MX_W);
    wire [3:0] mx_done_w = metro_weight ? MX_W : MX_R; // where a finished w goes
    wire [31:0] mx_result = metro_weight ? mx_w_r : {31'b0, (mx_r_r < mx_w_r)};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mx_state_r <= MX_IDLE;
            mx_k_r <= 3'd0; mx_n_r <= 7'd0;
            mx_d_r <= 32'b0; mx_x_r <= 32'b0; mx_t_r <= 32'b0; mx_q_r <= 32'b0;
            mx_p_r <= 32'b0; mx_w_r <= 32'b0; mx_r_r <= 32'b0;
        end else if (!halted_r && !fa_wait) begin
            case (mx_state_r)
                MX_IDLE: if (mx_go) begin
                    mx_x_r <= n_porta_data; mx_d_r <= n_portb_data; mx_state_r <= MX_SUB;
                end
                MX_SUB:  begin mx_d_r <= q_addsub_result; mx_t_r <= n_porta_data; mx_state_r <= MX_BETA; end
                MX_BETA: begin mx_x_r <= q_mul_result; mx_state_r <= MX_Y; end
                MX_Y: if (mx_x_le0) begin
                    mx_w_r <= MX_ONE; mx_state_r <= mx_done_w;  // dS <= 0: always accept
                end else begin
                    mx_x_r <= q_mul_result; mx_state_r <= MX_SPLIT; // now y
                end
                MX_SPLIT: if (mx_big) begin
                    mx_w_r <= 32'b0; mx_state_r <= mx_done_w;
                end else begin
                    mx_n_r <= mx_y_lt1 ? 7'd0 : mx_n;
                    mx_t_r <= mx_y_lt1 ? mx_x_r : q_addsub_result;
                    mx_q_r <= 32'h38E4607B; // c6
                    mx_k_r <= 3'd5;
                    mx_state_r <= MX_HM;
                end
                MX_HM: begin mx_p_r <= q_mul_result; mx_state_r <= MX_HA; end
                MX_HA: begin
                    mx_q_r <= q_addsub_result;
                    mx_k_r <= mx_k_r - 3'd1;
                    mx_state_r <= (mx_k_r == 3'd0) ? MX_SC : MX_HM;
                end
                MX_SC: begin mx_w_r <= mx_scaled; mx_state_r <= mx_done_w; end
                MX_R:  begin mx_r_r <= q_addsub_result; mx_state_r <= MX_W; end
                default: mx_state_r <= MX_IDLE; // MX_W: the write commits, pc moves on
            endcase
        end
    end

    // ==================== REUNIT (v2.3 step 2: back onto SU(3)) ====================
    // Rounding drifts a link off SU(3) after many products; every lattice
    // code pulls it back: normalize row 0 (u), Gram-Schmidt row 1 (v)
    // against it and normalize, and recompute row 2 as conj(u x v) so that
    // det = 1. That is 127 floating-point steps, so REUNIT is microcoded:
    // rtl/reunit_rom.v, GENERATED by tools/reunit_ucode.py, which the test
    // model also executes. 23 scratch registers hold the matrix (S0..S17)
    // and temporaries; micro-operand 31 reads 1.0.
    //   LD:  18 words in from N[ns] (synchronous read: address k, data k-1)
    //   RUN: one micro-op at a time - MUL/ADD/SUB on the shared two-stage
    //        FPU (fa_wait), SQRT/DIV on the shared fp_sqrt/fp_div
    //   ST:  18 words back; the last write is the terminal cycle
    localparam RX_IDLE = 3'd0, RX_LD = 3'd1, RX_RUN = 3'd2, RX_SQ = 3'd3, RX_DV = 3'd4, RX_ST = 3'd5;
    localparam [2:0] RX_OP_MUL = 3'd0, RX_OP_ADD = 3'd1, RX_OP_SUB = 3'd2, RX_OP_SQRT = 3'd3,
                     RX_OP_DIV = 3'd4, RX_OP_END = 3'd7;
    reg [2:0]  rx_state_r;
    reg [4:0]  rx_k;
    reg [7:0]  rx_pc;
    reg [31:0] rx_base;
    reg [31:0] rx_s [0:22];
    integer    rx_i;

    wire [17:0] rx_word;
    reunit_rom rx_rom (.addr(rx_pc), .word(rx_word));
    wire [2:0]  rx_op = rx_word[17:15];
    wire [4:0]  rx_d  = rx_word[14:10];
    wire [4:0]  rx_a  = rx_word[9:5];
    wire [4:0]  rx_b  = rx_word[4:0];
    wire [31:0] rx_x  = (rx_a == 5'd31) ? 32'h3F800000 : rx_s[rx_a];
    wire [31:0] rx_y  = (rx_b == 5'd31) ? 32'h3F800000 : rx_s[rx_b];

    wire rx_bad   = is_reunit && (rx_state_r == RX_IDLE) &&
                    ((n_porta_data[1:0] != 2'b00) || (n_porta_data > UART_TX_ADDR - 32'd72));
    wire rx_go    = is_reunit && (rx_state_r == RX_IDLE) && !sync_trap;
    assign rx_active = (rx_state_r != RX_IDLE) || is_reunit;
    wire rx_st    = (rx_state_r == RX_ST);
    assign rx_stall = (rx_state_r == RX_IDLE) ? rx_go : !(rx_st && rx_k == 5'd17);
    wire rx_sqrt_req = (rx_state_r == RX_SQ);
    wire rx_div_req  = (rx_state_r == RX_DV);
    wire rx_mem   = (rx_state_r == RX_LD && rx_k <= 5'd17) || rx_st;
    wire [31:0] rx_addr = rx_base + {25'd0, rx_k, 2'b00};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_state_r <= RX_IDLE; rx_k <= 5'd0; rx_pc <= 8'd0; rx_base <= 32'b0;
            for (rx_i = 0; rx_i < 23; rx_i = rx_i + 1) rx_s[rx_i] <= 32'b0;
        end else if (!halted_r && !fa_wait) begin
            case (rx_state_r)
                RX_IDLE: if (rx_go) begin rx_base <= n_porta_data; rx_k <= 5'd0; rx_state_r <= RX_LD; end
                RX_LD: begin
                    if (rx_k != 5'd0) rx_s[rx_k - 5'd1] <= dmem_rdata;
                    if (rx_k == 5'd18) begin rx_pc <= 8'd0; rx_state_r <= RX_RUN; end
                    else rx_k <= rx_k + 5'd1;
                end
                RX_RUN: case (rx_op)
                    RX_OP_MUL:  begin rx_s[rx_d] <= q_mul_result;    rx_pc <= rx_pc + 8'd1; end
                    RX_OP_ADD,
                    RX_OP_SUB:  begin rx_s[rx_d] <= q_addsub_result; rx_pc <= rx_pc + 8'd1; end
                    RX_OP_SQRT: rx_state_r <= RX_SQ;
                    RX_OP_DIV:  rx_state_r <= RX_DV;
                    default:    begin rx_k <= 5'd0; rx_state_r <= RX_ST; end // END
                endcase
                RX_SQ: if (fp_sqrt_done) begin rx_s[rx_d] <= fp_sqrt_result; rx_pc <= rx_pc + 8'd1; rx_state_r <= RX_RUN; end
                RX_DV: if (fp_div_done)  begin rx_s[rx_d] <= fp_div_result;  rx_pc <= rx_pc + 8'd1; rx_state_r <= RX_RUN; end
                default: if (rx_k == 5'd17) rx_state_r <= RX_IDLE; // RX_ST: last word written, pc moves on
                         else rx_k <= rx_k + 5'd1;
            endcase
        end
    end

    // ==================== Memory tagging (v2.1 step 1, MTE-style) ====================
    // One 4-bit allocation tag per 16-byte granule of the private data
    // memory. A LOAD/STORE to private memory must carry the same tag in
    // its pointer's top nibble, checked on the PHYSICAL granule in the
    // cycle the access commits; a mismatch is a precise TAG_FAULT
    // (CAUSE 5): no register write, no memory write. UART and the shared
    // NoC window are not tagged. Like ARM MTE this catches bugs
    // (overflow into the next allocation, use after free) with
    // probability 15/16 per random tag - it is not an isolation
    // boundary (the MMU is).
    localparam TAG_GRANULES = DATA_MEM_WORDS / 4;
    localparam TG_BITS      = $clog2(TAG_GRANULES);

    wire [3:0] mtag_ptr_tag = n_porta_data[31:28];
    wire [31:0] mtag_addr   = {4'b0, n_porta_data[27:0]};
    wire [TG_BITS-1:0] mtag_gidx = mtag_addr[TG_BITS+3:4];
    wire [TG_BITS-1:0] mem_gidx  = dmem_addr_final[TG_BITS+3:4];
    wire [3:0] mem_alloc_tag, mtag_alloc_tag;

    // STG/LDG name a granule by physical address: kernel-only, and the
    // address must be inside the tagged memory.
    wire mtag_bad = is_mtag && (mtag_funct != 2'b00) && (mtag_addr >= DATA_MEM_WORDS * 4);
    wire stg_commit = is_mtag && (mtag_funct == 2'b01) && !cpu_stall && !any_trap && !halted_r;

    generate
        if (MTE_ENABLE) begin: g_mte
            reg [3:0] tag_mem [0:TAG_GRANULES-1];
            integer ti;
            initial for (ti = 0; ti < TAG_GRANULES; ti = ti + 1) tag_mem[ti] = 4'd0;
            always @(posedge clk)
                if (stg_commit) tag_mem[mtag_gidx] <= mtag_ptr_tag;
            assign mem_alloc_tag  = tag_mem[mem_gidx];
            assign mtag_alloc_tag = tag_mem[mtag_gidx];
        end else begin: g_no_mte
            assign mem_alloc_tag  = 4'd0;
            assign mtag_alloc_tag = 4'd0;
        end
    endgenerate

    wire mte_checked = (is_load || is_store) && !is_shared_access && !is_uart_addr;
    assign tag_fault = (MTE_ENABLE != 0) && mte_checked && !mem_stall && !mmu_fault &&
                       (mem_ptr_tag != mem_alloc_tag);

    // IRG: a random NONZERO tag (0 means "untagged"); LDG: the granule's tag
    wire [3:0]  irg_tag     = (lfsr_q[3:0] == 4'd0) ? 4'd1 : lfsr_q[3:0];
    wire [31:0] mtag_result = (mtag_funct == 2'b00) ? {irg_tag, n_porta_data[27:0]} :
                                                      {mtag_alloc_tag, n_porta_data[27:0]};

    wire [31:0] dmem_rdata;
    // A shared-range or UART-range STORE must never ALSO land in the
    // private memory (it would otherwise silently alias into whatever
    // word this global address maps to in the private array's own
    // address space) - mirrors rv32i_core/rtl/cpu_core.v's identical
    // dmem_write gating, extended with the UART term (design review:
    // this is a package deal with the DATA_MEM_WORDS bump above - an
    // ungated STORE here would have been harmless only by accident,
    // while the array was too small to actually reach that address;
    // bumping the array without ALSO adding this gate would turn that
    // latent bug into a live one). The address input itself stays
    // unconditional; the resulting private read is simply discarded by
    // the read-data mux below whenever is_shared_access/is_uart_addr
    // is set.
    data_mem #(.MEM_WORDS(DATA_MEM_WORDS), .SYNC_READ(1)) dmem (
        .clk(clk), .addr(dmem_addr_final),
        .wdata(rx_st ? rx_s[rx_k] : su_mw ? su_mw_data : store_value),
        // !mmu_walk_active blocks a STORE's write from landing during
        // the walker's own PTE-fetch cycle; !mmu_stall additionally
        // blocks it during S_FILL (mmu.v's walk_active has already
        // dropped there, but `paddr` isn't valid yet either - a stalled
        // pending STORE's we must not fire against that stale address,
        // exactly the subtlety rv32i_core/rtl/mmu.v's own module header
        // documents as a real historical bug there).
        .we((is_store && !is_shared_access && !is_uart_addr && !mmu_walk_active && !mmu_stall && !tag_fault) || su_mw || rx_st),
        .rdata(dmem_rdata)
    );

    // A shared-range LOAD's real data comes back over the bus, not
    // from the private memory (which was never actually storing that
    // address) - mirrors rv32i_core/rtl/cpu_core.v's own
    // effective_mem_read_data mux exactly. UART_TX_ADDR is write-only
    // (a stray LOAD reads a DEFINED 0, per design review, rather than
    // relying on DATA_MEM_WORDS sizing alone); UART_RX_DATA_ADDR/
    // UART_RX_READY_ADDR read whatever the testbench is CURRENTLY
    // presenting, purely combinationally.
    wire [31:0] effective_dmem_rdata =
        is_shared_access  ? bus_read_data :
        is_uart_rx_data   ? {24'b0, uart_rx_data_in} :
        is_uart_rx_ready  ? {31'b0, uart_rx_ready_in} :
        (mem_addr == UART_TX_ADDR) ? 32'b0 :
                                       dmem_rdata;

    // ==================== Traps / privilege (design review before this
    // was written - see docs/ISA.md's "Traps" section) ====================
    localparam MODE_USER   = 1'b0;
    localparam MODE_KERNEL = 1'b1;
    localparam CAUSE_ILLEGAL = 3'b000;
    localparam CAUSE_SYSCALL = 3'b001;
    localparam CAUSE_IRQ     = 3'b010;
    localparam CAUSE_PRIV    = 3'b011;
    localparam CAUSE_PAGE_FAULT = 3'b100;
    localparam CAUSE_TAG_FAULT  = 3'b101; // v2.1 MTE

    reg [31:0] epc_r;
    reg [2:0]  cause_r;
    reg        mode_r, saved_mode_r;
    reg        ie_r, saved_ie_r;

    // RFT/MVSR are runtime-privileged (mode-dependent), so this check
    // lives HERE, not in control_unit.v - keeps that module a pure
    // function of `instr` alone (confirmed by design review: no other
    // module needs to know the CPU's runtime state just to decode).
    wire priv_violation = (is_rft || is_mvsr || is_ptb || is_su3mul || is_plaq || is_linkmul || is_reunit || is_sweep || (is_mtag && mtag_funct != 2'b00)) &&
                          (mode_r == MODE_USER); // SU3MUL/STG/LDG address physical memory directly
    // Exceptions are never maskable by ie_r (a real bug in kernel code
    // shouldn't be silently swallowed) - only the external-IRQ cause
    // below is gated by ie_r. A synchronous double-fault (the handler
    // itself trapping again before its own RFT) is an explicit,
    // documented v0.1 policy gap (see docs/ISA.md), not a silently-
    // assumed invariant. mmu_fault is likewise a precise, synchronous,
    // non-maskable exception - mutually exclusive with the other three
    // by construction (it can only ever coincide with is_load/is_store,
    // which illegal/is_syscall/priv_violation's own opcode classes
    // never are).
    wire sync_trap = illegal || data_illegal || is_syscall || priv_violation || mmu_fault || tag_fault;

    // Latched, not a live level - a brief irq_in pulse must never be
    // missed even if it arrives mid-mem_stall (see below), and clearing
    // only once the trap is actually TAKEN (not merely pending) means a
    // pulse that arrives while ie_r=0 correctly stays pending until
    // interrupts are re-enabled, rather than being silently dropped.
    reg irq_pending;
    wire irq_taken = irq_pending && ie_r && !sync_trap;
    // An external IRQ must never preempt a LOAD/STORE on the exact
    // cycle it completes - whether it just finished stalling, or never
    // stalled at all - because the underlying access has already
    // happened for real by then (a STORE's write already landed at
    // the real memory the instant bus_grant fires; an ordinary
    // private-memory access is likewise unstoppable once it reaches
    // this cycle). Taking the trap on that SAME cycle instead of
    // letting pc advance past it would make RFT re-execute (and for
    // STORE, double-commit) an instruction that already happened -
    // found live while working through this specific same-cycle race,
    // a case the general "nothing has committed yet while mem_stall
    // is still high" reasoning doesn't cover (it's true for every
    // cycle mem_stall stays high, but not for the one cycle it just
    // cleared). Deferring by exactly one cycle (irq_pending stays
    // latched) is safe and needs no special-casing for whether this
    // particular LOAD/STORE actually stalled at all.
    // QHAD/QCNOT's terminal cycle (q_state_r==Q_S6 / Q_S4, where q_stall
    // drops to 0 and the sequencer's own last write commits) has the
    // exact same same-cycle-completion race as a LOAD/STORE's own
    // mem_stall-clearing cycle (see the comment above irq_taken):
    // without excluding is_qhad/is_qcnot here too, an IRQ landing
    // exactly on that cycle would trap with epc_r pointing at the
    // QHAD/QCNOT instruction itself, and RFT would later re-execute
    // the WHOLE 5-cycle sequence from scratch - reading its own
    // already-mutated R-bank registers as if they were fresh inputs,
    // silently producing wrong amplitudes. Since is_qhad/is_qcnot stay
    // asserted for the full 5-cycle sequence (instr frozen throughout
    // by cpu_stall), this defers the IRQ across the entire sequence,
    // exactly mirroring the LOAD/STORE precedent. QMEASURE needs the
    // identical treatment, for an EXTRA reason beyond register
    // corruption: the LFSR keeps advancing every cycle regardless of
    // qm_stall, so an undeferred IRQ would make RFT re-execute
    // QMEASURE against a DIFFERENT random draw than the aborted
    // attempt, compounding the corruption with silent non-
    // reproducibility.
    // STRING (v2.0) gets the same deferral: its write commits on the
    // terminal cycle, so an IRQ there would make RFT redo it.
    wire any_trap  = sync_trap || (irq_taken && !is_load && !is_store && !is_qhad && !is_qcnot && !is_qmeasure && !is_string && !is_su3mul && !is_plaq && !is_linkmul && !is_reunit && !is_sweep && !is_regge && !is_metro);

    wire [2:0] next_cause = (illegal || data_illegal) ? CAUSE_ILLEGAL :
                             is_syscall     ? CAUSE_SYSCALL :
                             priv_violation ? CAUSE_PRIV :
                             mmu_fault      ? CAUSE_PAGE_FAULT :
                             tag_fault      ? CAUSE_TAG_FAULT :
                                              CAUSE_IRQ; // the only remaining way any_trap can be set

    // MVSR read direction (special -> N, via the normal write_data/
    // write_bank broadcast - control_unit.v already set write_bank=N/
    // write_addr=mvsr_nreg/reg_write=1 for this case, see its OP_MVSR
    // arm) and write direction (N -> special, captured into the new
    // registers above by the trap-entry always block below).
    wire [31:0] mvsr_read_data = (mvsr_selreg == 2'b00) ? epc_r :
                                  (mvsr_selreg == 2'b01) ? {29'b0, cause_r} :
                                  (mvsr_selreg == 2'b10) ? {31'b0, saved_mode_r} :
                                                            {31'b0, saved_ie_r}; // 2'b11 = SAVED_IE
    // Always N's port A when is_mvsr && mvsr_dir (write direction) -
    // see the N read-routing mux above.
    wire [31:0] mvsr_write_value = n_porta_data;

    // ==================== Write-data mux ====================
    assign write_data = is_gluon  ? gluon_result :
                         is_baryon ? baryon_result :
                         is_meson  ? meson_result :
                         is_string ? str_d :
                         is_mtag   ? mtag_result :
                         is_regge  ? rg_p_r :
                         (is_plaq || is_sweep) ? su_tr_r :
                         is_metro  ? mx_result :
                         is_load   ? effective_dmem_rdata :
                         (is_jal || is_jalr) ? (pc_r + 32'd4) :
                         (is_mvsr && !mvsr_dir) ? mvsr_read_data :
                         (is_ptb && !ptb_dir)   ? ptb_r :
                                     alu_result; // ALUR/ALUI

    // ==================== Branch ====================
    reg branch_taken;
    always @(*) begin
        case (branch_funct)
            3'b000:  branch_taken = (sel_rs1_data == sel_rs2_data);                     // BEQ
            3'b001:  branch_taken = (sel_rs1_data != sel_rs2_data);                     // BNE
            3'b010:  branch_taken = ($signed(sel_rs1_data) <  $signed(sel_rs2_data));   // BLT
            3'b011:  branch_taken = ($signed(sel_rs1_data) >= $signed(sel_rs2_data));   // BGE
            3'b100:  branch_taken = (sel_rs1_data <  sel_rs2_data);                     // BLTU
            3'b101:  branch_taken = (sel_rs1_data >= sel_rs2_data);                     // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] next_pc  = (is_branch && branch_taken) ? (pc_r + imm) :
                            is_jal                      ? (pc_r + jal_imm) :
                            is_jalr                     ? ((n_porta_data + jal_imm) & ~32'd3) :
                                                           pc_plus4;

    // Any of these committing means instr_mem already latched a now-
    // abandoned next-sequential fetch at the same edge - the following
    // cycle must squash (see squash_r's declaration above).
    wire is_redirect = any_trap || is_rft || (is_branch && branch_taken) || is_jal || is_jalr;

    // Latching (irq_in itself) is independent of mem_stall/halted_r - a
    // brief pulse must be caught even mid-stall. CLEARING is gated by
    // !halted_r to stay exactly consistent with the main trap block
    // below, which never acts on any_trap once halted - without this
    // gate, irq_pending could clear here even though the main block
    // never actually took the trap (a real, if minor, inconsistency
    // found while double-checking this against the main block's own
    // gating, not just assumed consistent).
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            irq_pending <= 1'b0;
        end else if (!halted_r && any_trap && irq_taken) begin
            irq_pending <= 1'b0; // consumed
        end else if (irq_in) begin
            irq_pending <= 1'b1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc           <= 32'b0;
            pc_r         <= 32'b0;
            halted_r     <= 1'b0;
            tohost_r     <= 32'b0;
            epc_r        <= 32'b0;
            cause_r      <= 3'b0;
            mode_r       <= MODE_KERNEL;
            saved_mode_r <= MODE_KERNEL;
            ie_r         <= 1'b0;
            saved_ie_r   <= 1'b0;
            ptb_r        <= 32'b0;
            squash_r     <= 1'b1; // warm-up bubble - instr_mem/pc_r not primed yet
        end else if (!halted_r && !cpu_stall) begin
            // pc_r must advance in EXACT lockstep with this whole block
            // (only when a new instruction is genuinely being retired/
            // decided), not on its own unconditional clock - a real bug
            // caught live (tb_trap_irq_stall.v: EPC landed one
            // instruction past the expected address) from an earlier
            // draft that gave pc_r its own free-running always block:
            // pc always races one instruction ahead of pc_r/instr
            // (prefetching), so while mem_stall holds pc frozen at
            // "the instruction AFTER the stalled one" (already
            // prefetched before the stall was even detected), an
            // unconditional pc_r would drift to match THAT frozen
            // value too, silently losing track of the actually-still-
            // stalled instruction's own real address for the entire
            // stall.
            pc_r <= pc;
            // squash_r's own 1->0 transition lives in THIS gate, not an
            // additional "&& !squash_r" on the outer condition above -
            // otherwise it could never clear once set.
            squash_r <= squash_r ? 1'b0 : is_redirect;
            if (squash_r) begin
                // Wrong-path/warm-up bubble: nothing else may commit.
                // In particular a pending external IRQ (irq_taken - see
                // any_trap's own definition, its guard doesn't actually
                // depend on this cycle's own decode) must be deferred
                // exactly one more cycle rather than taken against this
                // cycle's meaningless pc_r - mirrors the existing
                // mem_stall deferral below. Straight-line catch-up only.
                pc <= pc_plus4;
            end else if (any_trap) begin
                // Hardware-latched EPC, not a general register - see
                // docs/ISA.md's "Traps" section for why AxISA needs
                // this specific primitive instead of a general
                // indirect-jump instruction (it has neither, by
                // design). `pc_r` (the address of the instruction
                // `instr` actually reflects this cycle) is exactly
                // right for BOTH cases: for a synchronous trap it's the
                // trapping instruction's own address; for an external
                // IRQ it's the address of the NOT-yet-executed
                // instruction that got preempted - RFT jumps to
                // EXACTLY epc (no automatic +4), so a synchronous
                // handler must advance EPC itself (via MVSR) to skip
                // the trapping instruction, while an IRQ handler
                // correctly needs no adjustment at all.
                epc_r        <= pc_r;
                cause_r      <= next_cause;
                saved_mode_r <= mode_r;
                mode_r       <= MODE_KERNEL;
                saved_ie_r   <= ie_r;
                ie_r         <= 1'b0;
                pc           <= TRAP_VECTOR_ADDR;
            end else if (is_rft) begin
                mode_r <= saved_mode_r;
                ie_r   <= saved_ie_r;
                pc     <= epc_r;
            end else begin
                pc <= next_pc;
                if (is_halt) begin
                    halted_r <= 1'b1;
                    tohost_r <= n_porta_data;
                end
                if (is_mvsr && mvsr_dir) begin
                    case (mvsr_selreg)
                        2'b00: epc_r        <= mvsr_write_value;
                        2'b01: cause_r      <= mvsr_write_value[2:0];
                        2'b10: saved_mode_r <= mvsr_write_value[0];
                        2'b11: saved_ie_r   <= mvsr_write_value[0];
                    endcase
                end
                if (is_ptb && ptb_dir) begin
                    ptb_r <= ptb_write_value;
                end
            end
        end
    end
    // ==================== fa_wait: the two-stage FPU (v2.2) ====================
    // fp_addsub2's and fp_mul2's result for the inputs a sequencer presents
    // in cycle N appears in cycle N+1. Every sequencer state that CONSUMES
    // either result therefore runs twice: the first cycle (fa_ready_r = 0) only
    // fills the stage register while fa_wait freezes all sequencers, the
    // second takes the result and moves on. The adder's inputs come only
    // from sequencer flip-flops (and QMEASURE/METRO's free-running LFSR,
    // sampled in the first cycle - still a fair draw), so they hold still
    // across both cycles. fa_wait is part of cpu_stall: QHAD's terminal
    // cycle writes a product, so it must not let the CPU move on until the
    // product is out; the sequencers' own register writes are gated too.
    wire fa_use = (is_qhad && q_state_r >= Q_S2 && q_state_r <= Q_S5) ||
                  (qm_state_r >= QM_S4 && qm_state_r <= QM_S9) ||
                  (su_state_r == SU_C || su_state_r == SU_D || su_state_r == SU_E || su_state_r == SU_F) ||
                  (rg_state_r == RG_X && rg_mass) || (rg_state_r == RG_Z) ||
                  (mx_state_r == MX_SUB || mx_state_r == MX_SPLIT || mx_state_r == MX_HA || mx_state_r == MX_R) ||
                  // ... and the multiplier's
                  (is_qhad && q_state_r >= Q_S3) ||
                  (qm_state_r >= QM_S2 && qm_state_r <= QM_S5) ||
                  (qm_state_r >= QM_W0 && qm_state_r <= QM_W3) ||
                  ((su_state_r == SU_A && !((su_pl_r || su_lm_r) && su_ph_r == 2'd0)) || su_state_r == SU_B || su_state_r == SU_PM) ||
                  (rg_state_r == RG_X && !rg_mass) || (rg_state_r == RG_Y) ||
                  (mx_state_r == MX_BETA || mx_state_r == MX_Y || mx_state_r == MX_HM) ||
                  // REUNIT's add/sub/mul micro-ops
                  (rx_state_r == RX_RUN && rx_op <= RX_OP_SUB);
    reg  fa_ready_r;
    always @(posedge clk or posedge reset) begin
        if (reset)          fa_ready_r <= 1'b0;
        else if (!halted_r) fa_ready_r <= fa_use && !fa_ready_r;
    end
    assign fa_wait = fa_use && !fa_ready_r;

endmodule
