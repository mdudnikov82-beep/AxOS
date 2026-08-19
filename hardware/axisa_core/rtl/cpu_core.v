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
// 2 read + 1 write ports per bank - the global worst case is GLUON's
// rs1_bank==rs2_bank==rd_bank case (2R+1W to one bank), and STORE's
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
    parameter PT_INDEX_BITS = 4
) (
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
        .clk(clk), .addr(pc), .stall(mem_stall), .instr(instr_fetched)
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

    wire [1:0]  write_bank;
    wire [2:0]  write_addr;
    wire        reg_write, illegal;

    control_unit cu (
        .instr(instr),
        .bank(bank), .alu_funct(alu_funct), .branch_funct(branch_funct),
        .rd_addr(rd_addr), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .imm(imm),
        .alu_src_imm(alu_src_imm),
        .is_branch(is_branch), .is_halt(is_halt), .tohost_reg(tohost_reg),
        .is_gluon(is_gluon), .gluon_funct(gluon_funct),
        .gluon_rs1_bank(gluon_rs1_bank), .gluon_rs1_reg(gluon_rs1_reg),
        .gluon_rs2_bank(gluon_rs2_bank), .gluon_rs2_reg(gluon_rs2_reg),
        .is_baryon(is_baryon), .baryon_rr(baryon_rr), .baryon_gg(baryon_gg), .baryon_bb(baryon_bb),
        .is_meson(is_meson), .meson_funct(meson_funct),
        .meson_q1_bank(meson_q1_bank), .meson_q1_reg(meson_q1_reg),
        .meson_q2_bank(meson_q2_bank), .meson_q2_reg(meson_q2_reg),
        .is_load(is_load), .is_store(is_store), .mem_nd_ns(mem_nd_ns),
        .mem_base_bank(mem_base_bank), .mem_base_reg(mem_base_reg), .mem_imm(mem_imm),
        .is_jal(is_jal), .jal_imm(jal_imm),
        .is_rft(is_rft), .is_syscall(is_syscall), .is_mvsr(is_mvsr),
        .mvsr_dir(mvsr_dir), .mvsr_selreg(mvsr_selreg), .mvsr_nreg(mvsr_nreg),
        .is_ptb(is_ptb), .ptb_dir(ptb_dir), .ptb_nreg(ptb_nreg),
        .write_bank(write_bank), .write_addr(write_addr),
        .reg_write(reg_write), .illegal(illegal)
    );

    // ==================== Per-bank read-address routing ====================
    reg [2:0] r_addr_a, r_addr_b;
    reg [2:0] g_addr_a, g_addr_b;
    reg [2:0] b_addr_a, b_addr_b;
    reg [2:0] n_addr_a, n_addr_b;

    always @(*) begin
        r_addr_a = 3'b0; r_addr_b = 3'b0;
        if (is_gluon) begin
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
    end

    // ==================== Register banks ====================
    wire [31:0] r_porta_data, r_portb_data;
    wire [31:0] g_porta_data, g_portb_data;
    wire [31:0] b_porta_data, b_portb_data;
    wire [31:0] n_porta_data, n_portb_data;

    wire [31:0] write_data;

    // Gated ONCE here, not repeated at all four sites - a stalled
    // LOAD/STORE only ever targets N anyway (only N is load/store-
    // writable, per docs/ISA.md's confinement rule), but a single
    // shared gate can't drift the way 4 independently-written copies
    // of "&& !mem_stall" could (confirmed by design review before
    // this was written).
    wire gated_reg_write = reg_write && !mem_stall && !squash_r;
    wire r_write_en = gated_reg_write && (write_bank == BANK_R);
    wire g_write_en = gated_reg_write && (write_bank == BANK_G);
    wire b_write_en = gated_reg_write && (write_bank == BANK_B);
    wire n_write_en = gated_reg_write && (write_bank == BANK_N);

    regbank #(.HARDWIRE_REG0(0)) r_bank (
        .clk(clk), .rs1_addr(r_addr_a), .rs2_addr(r_addr_b),
        .rs1_data(r_porta_data), .rs2_data(r_portb_data),
        .rd_addr(write_addr), .rd_data(write_data), .reg_write(r_write_en)
    );
    regbank #(.HARDWIRE_REG0(0)) g_bank (
        .clk(clk), .rs1_addr(g_addr_a), .rs2_addr(g_addr_b),
        .rs1_data(g_porta_data), .rs2_data(g_portb_data),
        .rd_addr(write_addr), .rd_data(write_data), .reg_write(g_write_en)
    );
    regbank #(.HARDWIRE_REG0(0)) b_bank (
        .clk(clk), .rs1_addr(b_addr_a), .rs2_addr(b_addr_b),
        .rs1_data(b_porta_data), .rs2_data(b_portb_data),
        .rd_addr(write_addr), .rd_data(write_data), .reg_write(b_write_en)
    );
    regbank #(.HARDWIRE_REG0(1)) n_bank (
        .clk(clk), .rs1_addr(n_addr_a), .rs2_addr(n_addr_b),
        .rs1_data(n_porta_data), .rs2_data(n_portb_data),
        .rd_addr(write_addr), .rd_data(write_data), .reg_write(n_write_en)
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
    wire [31:0] gluon_rs2_data = (gluon_rs2_bank == BANK_R) ? r_portb_data :
                                  (gluon_rs2_bank == BANK_G) ? g_portb_data :
                                  (gluon_rs2_bank == BANK_B) ? b_portb_data : n_portb_data;

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
    // 8 gluons, one fixed XOR constant each (docs/ISA.md) - deliberately
    // the simplest real per-gluon-distinct operation for v0.1.
    wire [31:0] gluon_const = (gluon_funct == 3'd0) ? 32'h00000000 :
                               (gluon_funct == 3'd1) ? 32'h00000001 :
                               (gluon_funct == 3'd2) ? 32'h00000002 :
                               (gluon_funct == 3'd3) ? 32'h00000004 :
                               (gluon_funct == 3'd4) ? 32'h00000008 :
                               (gluon_funct == 3'd5) ? 32'h00000010 :
                               (gluon_funct == 3'd6) ? 32'h00000020 :
                                                        32'h00000040; // funct==7
    wire [31:0] gluon_result = gluon_rs1_data ^ gluon_rs2_data ^ gluon_const;

    // ==================== BARYON / MESON ====================
    wire [31:0] baryon_result = baryon_rr_data + baryon_gg_data + baryon_bb_data;
    wire [31:0] meson_result  = meson_q1_data - meson_q2_data;

    // ==================== Data memory (LOAD/STORE) ====================
    wire [31:0] mem_addr  = mem_base_data + mem_imm;

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
    wire ptb_changed = is_ptb && ptb_dir && !mem_stall && !any_trap;
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

    // Walker's own PTE fetch takes priority (its read must land on
    // data_mem's shared port); otherwise a translated user-mode access
    // uses the MMU's resolved physical address; everything else (kernel
    // mode, or the shared-bus/UART tiers whose real transfer happens
    // elsewhere and whose private-array read here is simply discarded
    // below) passes the raw address through unchanged - identical to
    // rv32i_core/rtl/cpu_core.v's own dmem_addr muxing.
    wire [31:0] dmem_addr_final = mmu_walk_active ? mmu_walk_addr :
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
        .wdata(store_value),
        // !mmu_walk_active blocks a STORE's write from landing during
        // the walker's own PTE-fetch cycle; !mmu_stall additionally
        // blocks it during S_FILL (mmu.v's walk_active has already
        // dropped there, but `paddr` isn't valid yet either - a stalled
        // pending STORE's we must not fire against that stale address,
        // exactly the subtlety rv32i_core/rtl/mmu.v's own module header
        // documents as a real historical bug there).
        .we(is_store && !is_shared_access && !is_uart_addr && !mmu_walk_active && !mmu_stall),
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

    reg [31:0] epc_r;
    reg [2:0]  cause_r;
    reg        mode_r, saved_mode_r;
    reg        ie_r, saved_ie_r;

    // RFT/MVSR are runtime-privileged (mode-dependent), so this check
    // lives HERE, not in control_unit.v - keeps that module a pure
    // function of `instr` alone (confirmed by design review: no other
    // module needs to know the CPU's runtime state just to decode).
    wire priv_violation = (is_rft || is_mvsr || is_ptb) && (mode_r == MODE_USER);
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
    wire sync_trap = illegal || is_syscall || priv_violation || mmu_fault;

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
    wire any_trap  = sync_trap || (irq_taken && !is_load && !is_store);

    wire [2:0] next_cause = illegal        ? CAUSE_ILLEGAL :
                             is_syscall     ? CAUSE_SYSCALL :
                             priv_violation ? CAUSE_PRIV :
                             mmu_fault      ? CAUSE_PAGE_FAULT :
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
                         is_load   ? effective_dmem_rdata :
                         is_jal    ? (pc_r + 32'd4) :
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
                                                           pc_plus4;

    // Any of these committing means instr_mem already latched a now-
    // abandoned next-sequential fetch at the same edge - the following
    // cycle must squash (see squash_r's declaration above).
    wire is_redirect = any_trap || is_rft || (is_branch && branch_taken) || is_jal;

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
        end else if (!halted_r && !mem_stall) begin
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
endmodule
