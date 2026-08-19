// Top-level single-cycle RV32I core: wires alu.v/regfile.v/imm_gen.v/
// control_unit.v/instr_mem.v/data_mem.v into the classic single-cycle
// datapath. Every instruction fetches, decodes, executes, accesses
// memory, and writes back all within one clock edge - no pipeline, no
// hazards to detect.
`timescale 1ns/1ps

module cpu_core #(
    parameter INSTR_MEM_WORDS = 1024,
    parameter INSTR_INIT_FILE = "",
    parameter DATA_MEM_BYTES  = 4096,
    parameter SHARED_MEM_BASE  = 32'h0000_2000,
    parameter SHARED_MEM_BYTES = 256,
    // Virtual memory (mmu.v) - see [[project_mmu]]. MMU_ENABLE=0 (the
    // default) makes mmu.v a pure wire-through, so every existing
    // program/testbench that never set up a page table keeps working
    // with ZERO behavior change - this is a strictly additive, opt-in
    // feature, not a replacement for direct physical addressing.
    parameter MMU_ENABLE      = 0,
    parameter MMU_TLB_ENTRIES = 4,
    parameter PAGE_TABLE_BASE = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        reset,
    output wire         halted,       // latched true the cycle after ECALL fires - see below
    output wire [31:0]  tohost_value, // x10/a0 at the moment ECALL fired; valid once halted==1
    // Distinct from `halted` deliberately (see mmu.v's header comment) -
    // a page fault also sets halted_r (so anything just polling `halted`
    // to end simulation still works), but a testbench must check
    // `!page_fault` before trusting tohost_value means anything.
    output wire         page_fault,

    // Shared-bus master port (see shared_bus.v) - a memory op whose
    // address falls in [SHARED_MEM_BASE, SHARED_MEM_BASE+SHARED_MEM_BYTES)
    // goes out on this port instead of the private data_mem below, and
    // must wait for bus_grant before its result/side-effect is real.
    output wire        bus_req,
    output wire [31:0] bus_addr,
    output wire [31:0] bus_write_data,
    output wire        bus_mem_write,
    output wire [1:0]  bus_mem_size,
    output wire        bus_mem_unsigned,
    input  wire        bus_grant,
    input  wire [31:0] bus_read_data
);
    reg [31:0] pc;
    // Trails `pc` by exactly one cycle, unconditionally within the
    // same gate as pc's own update - always matches whatever address
    // instr_mem's own SYNC_READ=1 internal register just latched, so
    // (pc_r, instr) stay a self-consistent pair regardless of what
    // else the core is doing (stalled, just reset, just redirected).
    // "Address of the instruction currently being decoded" (AUIPC,
    // branch/JAL targets, JAL/JALR's link-register value) - use pc_r.
    // "Address to fetch next" (instr_mem's own .addr port, pc_plus4's
    // fallthrough) - stays raw pc. See AxISA's sibling cpu_core.v for
    // the two real bugs found live while building this exact redesign
    // there (this file needs neither fix: RV32I's opcode 0 already
    // decodes as `illegal` with every other output at its all-zero
    // default - a genuinely inert NOP - and this core has no trap/EPC
    // concept at all, so there's no analogous "commit against a
    // meaningless pc_r" risk to guard against).
    reg  [31:0] pc_r;
    // 1 through reset and for exactly one cycle after any committed
    // redirect (taken branch, JAL, JALR) - a registered fetch has
    // already latched the now-abandoned next-sequential address at the
    // exact edge a redirect is decided, and cannot un-fetch it.
    reg         squash_r;
    reg        halted_r;
    assign halted = halted_r;

    wire [31:0] instr_fetched;
    wire [31:0] instr = squash_r ? 32'b0 : instr_fetched;
    wire [6:0]  opcode = instr[6:0];
    wire [2:0]  funct3 = instr[14:12];
    wire [6:0]  funct7 = instr[31:25];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [4:0]  rd     = instr[11:7];

    localparam OP_SYSTEM = 7'b1110011;

    wire [31:0] imm;
    wire [31:0] rs1_data, rs2_data;
    wire [31:0] x10_debug;
    reg  [31:0] rd_data;

    wire reg_write, mem_read, mem_write, mem_to_reg, alu_src, branch, jump, jalr, auipc, lui, mem_unsigned, illegal, is_sfence;
    wire [3:0]  alu_op;
    wire [1:0]  mem_size;

    // Minimal RV32F (see fp_regfile.v/fp_addsub.v/fp_mul.v/fp_div.v/fp_sqrt.v).
    localparam FP_MUL  = 3'b010;
    localparam FP_DIV  = 3'b011;
    localparam FP_SQRT = 3'b100;

    wire        fp_reg_write, is_fp_mem;
    wire [2:0]  fp_op;
    wire [31:0] fp_rs1_data, fp_rs2_data;
    reg  [31:0] fp_rd_data;

    wire [31:0] alu_a = auipc ? pc_r : (lui ? 32'b0 : rs1_data);
    wire [31:0] alu_b = alu_src ? imm : rs2_data;
    wire [31:0] alu_result;
    wire        alu_zero;

    wire [31:0] mem_read_data;

    // Address decode: is THIS cycle's memory op (if any) targeting the
    // shared region instead of this core's own private data_mem?
    wire is_shared_access = (mem_read || mem_write) &&
        (alu_result >= SHARED_MEM_BASE) && (alu_result < SHARED_MEM_BASE + SHARED_MEM_BYTES);

    // shared_bus's own memory is a small, separately-indexed array
    // (0..SHARED_MEM_BYTES-1) - the global address must be re-based to
    // that local window before crossing the bus, the same way a real
    // memory-mapped peripheral's own internal offset differs from its
    // address in the CPU's global map.
    // FSW's store data comes from fp_regfile's rs2, not the integer
    // regfile's - this single mux feeds BOTH store-data sites below
    // (the private data_mem AND the shared bus each have their own
    // write_data wire today, so this needs to reach both, not just
    // one - flagged specifically by this feature's design review).
    wire [31:0] store_data = is_fp_mem ? fp_rs2_data : rs2_data;

    assign bus_req          = is_shared_access;
    assign bus_addr          = alu_result - SHARED_MEM_BASE;
    assign bus_write_data    = store_data;
    assign bus_mem_write     = mem_write;
    assign bus_mem_size      = mem_size;
    assign bus_mem_unsigned  = mem_unsigned;

    // Losing arbitration for a shared access stalls this core for a
    // cycle - the private-memory path never stalls (nothing else in
    // this design can ever contend for it), so this is the ONLY wait
    // state a single-cycle core ever needs.
    wire mem_stall = is_shared_access && !bus_grant;

    // Virtual memory (mmu.v): translates NON-shared data accesses only
    // - the shared-bus window above is decoded on the raw (virtual)
    // address first, exactly as before the MMU existed, and is treated
    // as a permanently-unpaged reserved VA range (like a fixed MMIO
    // hole), never looked up in the TLB or walked. This makes
    // mem_stall (shared-bus arbitration) and mmu_stall (page-table
    // walk) mutually exclusive by construction - no instruction is
    // ever both - confirmed sound by design review before this was
    // built (see [[project_mmu]]).
    wire mmu_is_access = (mem_read || mem_write) && !is_shared_access;
    wire [31:0] mmu_paddr;
    wire        mmu_stall;
    wire        mmu_walk_active;
    wire [31:0] mmu_walk_addr;

    // The walker issues its own PTE reads through this SAME data_mem
    // instance the LSU already uses (data_mem's read is combinational,
    // so mem_read_data below reflects EITHER the LSU's own translated
    // read OR the walker's current PTE fetch, depending on which
    // address dmem_addr is currently presenting - never both at once,
    // since the core is fully frozen for the walk's whole duration).
    // Forcing dmem_write to 0 during a walk is required, not
    // defensive: without it, a stalled pending STORE's mem_write
    // staying asserted would silently write that store's data into
    // whatever physical address the walker happens to be reading that
    // cycle - corrupting the live page table. A design review caught
    // this exact hazard before any RTL was written.
    wire [31:0] dmem_addr  = mmu_walk_active ? mmu_walk_addr : mmu_paddr;
    // !mmu_walk_active alone is NOT enough - walk_active is only true
    // during S_L1/S_L0 (see mmu.v), but a store can also present
    // dmem_write=1 on the S_IDLE miss-detection cycle and the S_FILL
    // cycle, neither of which is walk_active. On both of those cycles
    // hit_ppn is still 0 (no valid TLB entry yet), so mmu_paddr resolves
    // to a bogus physical address (page 0, at the faulting vaddr's own
    // page offset) - without also gating on !mmu_stall, a first-touch
    // store hitting a TLB miss silently corrupts whatever real data
    // lives at that bogus address (physical page 0, dangerously close to
    // where PAGE_TABLE_BASE defaults) in addition to eventually landing
    // correctly at the real translated address once the walk finishes.
    // Found live: a `sw` to a fresh VA reliably clobbered physical
    // 0x0000 even though the SAME instruction's final translated write
    // still (coincidentally) succeeded at the real destination.
    wire        dmem_write = mem_write && !is_shared_access && !mmu_walk_active && !mmu_stall;
    // A PTE is always a full 32-bit word regardless of what the stalled
    // instruction's own access width happens to be (e.g. a byte load
    // hitting a TLB miss) - data_mem.v's read mux depends on mem_size,
    // so leaving it as the LSU's own mem_size during a walk would hand
    // the walker a sign/zero-extended BYTE or HALF of the PTE instead
    // of the real 32-bit value. Found live: an `lb` triggering a walk
    // produced a garbage translation instead of a fault or the correct
    // result, because the byte-narrowed "PTE" still had its valid bit
    // sometimes set by chance.
    wire [1:0]  dmem_mem_size = mmu_walk_active ? 2'b10 : mem_size;

    // SFENCE.VMA never itself triggers mem_stall/mmu_stall (it does no
    // memory access), so in this single-cycle core it always executes
    // in exactly the one cycle it's fetched - a plain combinational
    // pulse is correct and sufficient (no held/redundant-pulse hazard
    // exists here the way it does in the pipelined core).
    wire tlb_flush = is_sfence;

    mmu #(
        .MMU_ENABLE(MMU_ENABLE), .TLB_ENTRIES(MMU_TLB_ENTRIES), .DATA_MEM_BYTES(DATA_MEM_BYTES)
    ) mmu_inst (
        .clk(clk), .reset(reset),
        .vaddr(alu_result), .is_access(mmu_is_access), .is_write(mem_write),
        .page_table_base(PAGE_TABLE_BASE), .tlb_flush(tlb_flush),
        .paddr(mmu_paddr), .mmu_stall(mmu_stall), .page_fault(page_fault), .fault_vaddr(),
        .walk_active(mmu_walk_active), .walk_addr(mmu_walk_addr), .walk_read_data(mem_read_data)
    );

    wire [31:0] effective_mem_read_data = is_shared_access ? bus_read_data : mem_read_data;

    // A private-memory LOAD needs one extra cycle once its final
    // address is stable (un-translated dmem_addr, or mmu_paddr the
    // cycle mmu_stall first drops) - data_mem's SYNC_READ=1 registered
    // capture (below) makes the data valid one cycle after the address
    // is issued, not the same cycle. `!mmu_walk_active && !mmu_stall`
    // matches this exact file's own established dmem_write gating
    // (see its comment above: S_IDLE-miss and S_FILL cycles also need
    // excluding, not just walk_active).
    wire dmem_read_needed = mem_read && !is_shared_access;
    wire dmem_load_stall  = dmem_read_needed && !mmu_walk_active && !mmu_stall && !dmem_read_valid_r;

    // Gated only on !halted_r, deliberately NOT nested inside any
    // pc_stall-gated always block - it must update WHILE pc_stall is
    // already 1 (that's the transition it drives), or it would
    // deadlock at dmem_load_stall=1 forever.
    reg dmem_read_valid_r;
    always @(posedge clk or posedge reset) begin
        if (reset) dmem_read_valid_r <= 1'b0;
        else if (!halted_r) dmem_read_valid_r <= dmem_load_stall;
    end

    // OR of every condition that freezes pc below - instr_mem's own
    // internal SYNC_READ register needs this SAME signal (not just a
    // frozen `addr`, which arrives one cycle too late for it - see
    // instr_mem.v's own header comment for the real bug this fixes).
    wire pc_stall = mem_stall || fpu_div_stall || fpu_sqrt_stall || mmu_stall || dmem_load_stall;

    instr_mem #(.MEM_WORDS(INSTR_MEM_WORDS), .INIT_FILE(INSTR_INIT_FILE), .SYNC_READ(1)) imem (
        .clk(clk), .addr(pc), .stall(pc_stall), .instr(instr_fetched)
    );

    // A losing cycle must not commit a register write - the same
    // instruction (same rd/rd_data inputs) simply retries next cycle.
    wire regfile_write_en = reg_write && !mem_stall && !mmu_stall && !dmem_load_stall;

    regfile rf (
        .clk(clk), .rs1_addr(rs1), .rs2_addr(rs2),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .rd_addr(rd), .rd_data(rd_data), .reg_write(regfile_write_en),
        .x10_debug(x10_debug)
    );

    imm_gen ig (.instr(instr), .imm(imm));

    control_unit cu (
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .mem_to_reg(mem_to_reg), .alu_src(alu_src), .branch(branch),
        .jump(jump), .jalr(jalr), .auipc(auipc), .lui(lui),
        .alu_op(alu_op), .mem_size(mem_size), .mem_unsigned(mem_unsigned),
        .illegal(illegal),
        .fp_reg_write(fp_reg_write), .is_fp_mem(is_fp_mem), .fp_op(fp_op),
        .is_sfence(is_sfence)
    );

    alu ax (.a(alu_a), .b(alu_b), .alu_op(alu_op), .result(alu_result), .zero(alu_zero));

    // A shared-range write must never hit the private memory (it's out
    // of that address's own valid range anyway, but the decode belongs
    // here at the bus level, not left to the memory to silently no-op).
    // addr/mem_write are muxed above to give the MMU's walker exclusive
    // control of this port while it's active.
    data_mem #(.MEM_BYTES(DATA_MEM_BYTES), .SYNC_READ(1)) dmem (
        .clk(clk), .addr(dmem_addr), .write_data(store_data),
        .mem_write(dmem_write), .mem_size(dmem_mem_size), .mem_unsigned(mem_unsigned),
        .read_data(mem_read_data)
    );

    // Minimal RV32F datapath: FLW/FSW's address still comes from the
    // INTEGER regfile via rs1/alu_result above, completely unchanged -
    // only the DATA side (fp_regfile's rs1/rs2/rd) is new here.
    // FADD.S/FSUB.S/FMUL.S touch fp_regfile exclusively; the integer
    // regfile and ALU are never involved for those (control_unit.v
    // already keeps the integer regfile's reg_write=0 for every
    // RV32F instruction, since rd's 5-bit number aliases between the
    // two register files).
    wire [31:0] fpu_addsub_result, fpu_mul_result, fpu_div_result, fpu_sqrt_result;

    // FDIV.S is a genuine multi-cycle operation (see fp_div.v) - a new
    // functional-unit-latency stall, distinct from mem_stall (shared-
    // bus arbitration wait). start pulses exactly once (the cycle
    // fpu_div_busy is still 0, before the unit's own registered state
    // takes over) and does not re-fire while busy holds this same
    // still-decoded instruction in place.
    wire is_fdiv_instr = fp_reg_write && !is_fp_mem && (fp_op == FP_DIV);
    wire fpu_div_busy, fpu_div_done;
    wire fpu_div_start = is_fdiv_instr && !fpu_div_busy;
    wire fpu_div_stall = is_fdiv_instr && !fpu_div_done;

    // FSQRT.S mirrors FDIV.S exactly - a second, independent multi-cycle
    // functional unit. Only one of the two can ever be "the current
    // instruction" at a time (fp_op selects exactly one), so there's no
    // need for the two units' busy/stall signals to know about each
    // other beyond being OR'd together wherever something needs "is ANY
    // multi-cycle FP op still in flight".
    wire is_fsqrt_instr = fp_reg_write && !is_fp_mem && (fp_op == FP_SQRT);
    wire fpu_sqrt_busy, fpu_sqrt_done;
    wire fpu_sqrt_start = is_fsqrt_instr && !fpu_sqrt_busy;
    wire fpu_sqrt_stall = is_fsqrt_instr && !fpu_sqrt_done;

    // Same !mem_stall gating as the integer regfile's write enable -
    // a stalled FLW (targeting the shared-bus region) must not commit
    // garbage into fp_regfile on a losing arbitration cycle, the exact
    // bug class mem_stall already exists to prevent on the integer side.
    // fpu_div_stall/fpu_sqrt_stall get the identical treatment: a
    // division or sqrt result only commits on the one cycle it's
    // actually done.
    wire fp_regfile_write_en = fp_reg_write && !mem_stall && !fpu_div_stall && !fpu_sqrt_stall && !mmu_stall && !dmem_load_stall;

    fp_regfile fprf (
        .clk(clk), .rs1_addr(rs1), .rs2_addr(rs2),
        .rs1_data(fp_rs1_data), .rs2_data(fp_rs2_data),
        .rd_addr(rd), .rd_data(fp_rd_data), .reg_write(fp_regfile_write_en)
    );

    fp_addsub fpas (
        .a(fp_rs1_data), .b(fp_rs2_data), .op_sub(fp_op[0]),
        .result(fpu_addsub_result)
    );

    fp_mul fpmul (
        .a(fp_rs1_data), .b(fp_rs2_data),
        .result(fpu_mul_result)
    );

    fp_div fpdiv (
        .clk(clk), .reset(reset), .start(fpu_div_start),
        .a(fp_rs1_data), .b(fp_rs2_data),
        .busy(fpu_div_busy), .done(fpu_div_done), .result(fpu_div_result)
    );

    // FSQRT.S is architecturally ONE-OPERAND - only rs1's data is wired
    // in, unlike every other FPU unit here (fp_fwd_rs2 is genuinely
    // unused for this op, not "computed but harmlessly discarded" the
    // way the other units' cross-op operands are).
    fp_sqrt fpsqrt (
        .clk(clk), .reset(reset), .start(fpu_sqrt_start),
        .a(fp_rs1_data),
        .busy(fpu_sqrt_busy), .done(fpu_sqrt_done), .result(fpu_sqrt_result)
    );

    // FLW's write-back is the loaded memory data; FADD.S/FSUB.S write
    // fp_addsub's result (op_sub selects which); FMUL.S writes
    // fp_mul's; FDIV.S writes fp_div's; FSQRT.S writes fp_sqrt's (each
    // an explicit branch - falling through to the addsub default here
    // would silently compute the wrong operation instead, the same
    // "silent wrong branch" bug class already documented in
    // control_unit.v's own LUI comment) - a dedicated mux kept
    // independent of the integer path's mem_to_reg mux, per this
    // feature's design review.
    always @(*) begin
        if (is_fp_mem)             fp_rd_data = effective_mem_read_data;
        else if (fp_op == FP_MUL)  fp_rd_data = fpu_mul_result;
        else if (fp_op == FP_DIV)  fp_rd_data = fpu_div_result;
        else if (fp_op == FP_SQRT) fp_rd_data = fpu_sqrt_result;
        else                        fp_rd_data = fpu_addsub_result;
    end

    // Branch comparison - funct3 selects which relation BEQ/BNE/BLT/
    // BGE/BLTU/BGEU tests, independent of the ALU (which is busy
    // computing rs1+imm for load/store addressing on other opcodes;
    // reusing it here would need an extra mux for no real benefit in
    // a single-cycle design where rs1_data/rs2_data are already free).
    reg branch_taken;
    always @(*) begin
        case (funct3)
            3'b000:  branch_taken = (rs1_data == rs2_data);                    // BEQ
            3'b001:  branch_taken = (rs1_data != rs2_data);                    // BNE
            3'b100:  branch_taken = ($signed(rs1_data) <  $signed(rs2_data)); // BLT
            3'b101:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data)); // BGE
            3'b110:  branch_taken = (rs1_data <  rs2_data);                   // BLTU
            3'b111:  branch_taken = (rs1_data >= rs2_data);                   // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    wire [31:0] pc_plus4      = pc + 32'd4;
    wire [31:0] pc_r_plus4    = pc_r + 32'd4;
    wire [31:0] branch_target = pc_r + imm;
    wire [31:0] jal_target    = pc_r + imm;
    // JALR clears the LSB per spec (target must be even) - it's not
    // an alignment nicety, it's how the encoding tells JALR targets
    // apart from a plain register-relative call with an odd base.
    wire [31:0] jalr_target   = (rs1_data + imm) & 32'hFFFFFFFE;

    wire [31:0] next_pc =
        jump                    ? jal_target    :
        jalr                    ? jalr_target   :
        (branch && branch_taken) ? branch_target :
        pc_plus4;

    // Any of these committing means instr_mem already latched a now-
    // abandoned next-sequential fetch at the same edge - the following
    // cycle must squash (see squash_r's declaration above).
    wire is_redirect = jump || jalr || (branch && branch_taken);

    always @(*) begin
        if (jump || jalr)     rd_data = pc_r_plus4;    // link register gets the return address
        else if (mem_to_reg)  rd_data = effective_mem_read_data;
        else                  rd_data = alu_result;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc       <= 32'b0;
            pc_r     <= 32'b0;
            halted_r <= 1'b0;
            squash_r <= 1'b1; // warm-up bubble - instr_mem/pc_r not primed yet
        end else if (!halted_r && !pc_stall) begin
            // pc_r must advance in exact lockstep with this whole
            // block (only when a new instruction is genuinely being
            // decided), not on its own free-running clock - see
            // instr_mem.v's header comment for the real bug this
            // avoids (a stalled decode silently drifting to show the
            // next, not-yet-relevant instruction).
            pc_r     <= pc;
            squash_r <= squash_r ? 1'b0 : is_redirect;
            pc <= squash_r ? pc_plus4 : next_pc;
            // SFENCE.VMA also decodes as OP_SYSTEM but must NOT halt the
            // core - is_sfence excludes it here (mmu_inst below is what
            // actually consumes it, via tlb_flush).
            // No explicit "&& !squash_r" needed here (unlike AxISA's
            // sibling cpu_core.v): opcode 0 (the masked-instr value
            // during squash) decodes as `illegal`, never OP_SYSTEM, so
            // this condition is already provably unreachable mid-squash.
            if (opcode == OP_SYSTEM && !is_sfence) halted_r <= 1'b1;
        end else if (!halted_r && page_fault) begin
            // Sticky mmu.v fault state never clears on its own (by
            // design - see mmu.v) - freeze this core's own halted_r too
            // so anything just polling `halted` to end simulation
            // still works, per the module-header contract.
            halted_r <= 1'b1;
        end
    end

    assign tohost_value = x10_debug;
endmodule
