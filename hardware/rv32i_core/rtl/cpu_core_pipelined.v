// Classic 5-stage IF/ID/EX/MEM/WB pipelined RV32I core. Reuses the
// exact same alu.v/imm_gen.v/control_unit.v/instr_mem.v/data_mem.v as
// the single-cycle cpu_core.v (all already stage-agnostic), plus the
// new forward_unit.v/hazard_unit.v. Branches AND jumps both resolve
// in EX - a taken one flushes whatever's currently in IF/ID and ID/EX
// (the 2 instructions fetched behind it on the wrong-path assumption).
`timescale 1ns/1ps

module cpu_core_pipelined #(
    parameter INSTR_MEM_WORDS = 1024,
    parameter INSTR_INIT_FILE = "",
    parameter DATA_MEM_BYTES  = 8192,
    parameter SHARED_MEM_BASE  = 32'h0000_2000,
    parameter SHARED_MEM_BYTES = 256
) (
    input  wire        clk,
    input  wire        reset,
    output wire        halted,
    output wire [31:0] tohost_value,

    // Shared-bus master port (see shared_bus.v and cpu_core.v's matching
    // port) - driven from EX/MEM, since that's where a memory op
    // actually touches memory in this pipeline.
    output wire        bus_req,
    output wire [31:0] bus_addr,
    output wire [31:0] bus_write_data,
    output wire        bus_mem_write,
    output wire [1:0]  bus_mem_size,
    output wire        bus_mem_unsigned,
    input  wire        bus_grant,
    input  wire [31:0] bus_read_data
);
    localparam OP_SYSTEM = 7'b1110011;
    localparam WB_ALU  = 2'b00;
    localparam WB_MEM  = 2'b01;
    localparam WB_PC4  = 2'b10;

    reg halted_r;
    assign halted = halted_r;

    // ==================== IF stage ====================
    reg  [31:0] pc;
    wire [31:0] if_instr;
    wire [31:0] pc_plus4_if = pc + 32'd4;

    instr_mem #(.MEM_WORDS(INSTR_MEM_WORDS), .INIT_FILE(INSTR_INIT_FILE)) imem (
        .addr(pc), .instr(if_instr)
    );

    // ==================== IF/ID register ====================
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;

    wire [6:0] if_id_opcode = if_id_instr[6:0];
    wire [4:0] if_id_rs1    = if_id_instr[19:15];
    wire [4:0] if_id_rs2    = if_id_instr[24:20];

    // ==================== ID stage ====================
    wire [2:0] id_funct3 = if_id_instr[14:12];
    wire [6:0] id_funct7 = if_id_instr[31:25];
    wire [4:0] id_rd     = if_id_instr[11:7];
    wire [31:0] id_pc_plus4 = if_id_pc + 32'd4;

    wire [31:0] id_imm;
    imm_gen ig (.instr(if_id_instr), .imm(id_imm));

    wire id_reg_write, id_mem_read, id_mem_write, id_mem_to_reg, id_alu_src;
    wire id_branch, id_jump, id_jalr, id_auipc, id_lui, id_mem_unsigned, id_illegal;
    wire [3:0] id_alu_op;
    wire [1:0] id_mem_size;

    // Minimal RV32F (see fp_regfile.v/fp_addsub.v/fp_mul.v/cpu_core.v -
    // this ports the exact same 5-instruction subset already verified
    // on the single-cycle core: FLW/FSW + FADD.S/FSUB.S/FMUL.S).
    wire       id_fp_reg_write, id_is_fp_mem;
    wire [2:0] id_fp_op;

    control_unit cu (
        .opcode(if_id_opcode), .funct3(id_funct3), .funct7(id_funct7),
        .reg_write(id_reg_write), .mem_read(id_mem_read), .mem_write(id_mem_write),
        .mem_to_reg(id_mem_to_reg), .alu_src(id_alu_src), .branch(id_branch),
        .jump(id_jump), .jalr(id_jalr), .auipc(id_auipc), .lui(id_lui),
        .alu_op(id_alu_op), .mem_size(id_mem_size), .mem_unsigned(id_mem_unsigned),
        .illegal(id_illegal),
        .fp_reg_write(id_fp_reg_write), .is_fp_mem(id_is_fp_mem), .fp_op(id_fp_op)
    );

    wire [1:0] id_wb_sel = (id_jump || id_jalr) ? WB_PC4 : (id_mem_to_reg ? WB_MEM : WB_ALU);
    wire       id_is_system = (if_id_opcode == OP_SYSTEM);

    wire [31:0] x10_debug;

    // Regfile write port driven by WB stage (declared ahead of use).
    wire        wb_reg_write;
    wire [4:0]  wb_rd_addr;
    wire [31:0] wb_rd_data;

    wire [31:0] id_rs1_data_raw, id_rs2_data_raw;

    regfile rf (
        .clk(clk), .rs1_addr(if_id_rs1), .rs2_addr(if_id_rs2),
        .rs1_data(id_rs1_data_raw), .rs2_data(id_rs2_data_raw),
        .rd_addr(wb_rd_addr), .rd_data(wb_rd_data), .reg_write(wb_reg_write),
        .x10_debug(x10_debug)
    );

    // Distance-3 RAW hazard: MEM/WB retiring THIS cycle writes a
    // register that IF/ID's instruction (about to move into ID/EX)
    // also needs. forward_unit.v can't cover this (it forwards into EX
    // from EX/MEM/MEM/WB relative to ID/EX, one stage later than
    // this), and regfile.v's own combinational read can't see a
    // same-cycle write either. This mux is safe where a same-cycle
    // bypass INSIDE regfile.v was not: mem_wb_reg_write/mem_wb_rd/
    // wb_data_r are all REGISTERED values latched on an EARLIER clock
    // edge, so this can never loop back into its own output the way
    // the single-cycle core's `addi x1, x1, 5` did when the bypass
    // lived inside regfile.v itself (see that file's own comment - a
    // real combinational-loop hang was found live from that draft).
    wire [31:0] id_rs1_data = (mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == if_id_rs1) ? wb_data_r : id_rs1_data_raw;
    wire [31:0] id_rs2_data = (mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == if_id_rs2) ? wb_data_r : id_rs2_data_raw;

    // FP register file - read using the SAME if_id_rs1/if_id_rs2
    // fields RV32F reuses from the integer encoding. FLW/FSW's write
    // port is driven by the WB stage - mem_wb_fp_reg_write/fp_wb_data
    // are declared once down with the MEM/WB register and WB-stage mux
    // respectively; referencing them here needs no forward declaration
    // (same rule the existing mem_wb_reg_write/wb_data_r references
    // above already rely on).
    wire [31:0] fp_id_rs1_data_raw, fp_id_rs2_data_raw;

    fp_regfile fprf (
        .clk(clk), .rs1_addr(if_id_rs1), .rs2_addr(if_id_rs2),
        .rs1_data(fp_id_rs1_data_raw), .rs2_data(fp_id_rs2_data_raw),
        .rd_addr(mem_wb_rd), .rd_data(fp_wb_data), .reg_write(mem_wb_fp_reg_write)
    );

    // Same distance-3 RAW hazard bypass as the integer regfile above,
    // but WITHOUT its "!= 5'd0" exclusion: f0 is a real, ordinary
    // register (see fp_regfile.v), not a hardwired zero like x0. Uses
    // the RAW mem_wb_fp_reg_write/mem_wb_rd/fp_wb_data directly (NOT a
    // "_r"-style delayed alias) - see this feature's own design notes
    // for why building a delayed version here would silently break it.
    wire [31:0] fp_id_rs1_data = (mem_wb_fp_reg_write && mem_wb_rd == if_id_rs1) ? fp_wb_data : fp_id_rs1_data_raw;
    wire [31:0] fp_id_rs2_data = (mem_wb_fp_reg_write && mem_wb_rd == if_id_rs2) ? fp_wb_data : fp_id_rs2_data_raw;

    // ==================== Hazard detection (combinational, uses ID/EX + IF/ID) ====================
    reg        id_ex_mem_read_r;
    reg [4:0]  id_ex_rd_r;
    reg        id_ex_fp_reg_write_r;
    wire       stall;

    hazard_unit hz (
        .id_ex_mem_read(id_ex_mem_read_r), .id_ex_rd(id_ex_rd_r),
        .id_ex_fp_reg_write(id_ex_fp_reg_write_r),
        .if_id_rs1(if_id_rs1), .if_id_rs2(if_id_rs2),
        .stall(stall)
    );

    // ==================== ID/EX register ====================
    reg [31:0] id_ex_pc, id_ex_pc_plus4;
    reg [31:0] id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    reg [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    reg        id_ex_reg_write, id_ex_mem_read, id_ex_mem_write, id_ex_alu_src;
    reg        id_ex_branch, id_ex_jump, id_ex_jalr, id_ex_auipc, id_ex_lui;
    reg        id_ex_mem_unsigned, id_ex_is_system;
    reg [3:0]  id_ex_alu_op;
    reg [1:0]  id_ex_mem_size, id_ex_wb_sel;
    reg [2:0]  id_ex_funct3;

    // Minimal RV32F (see the ID-stage fp_regfile/control_unit wiring
    // above).
    reg        id_ex_fp_reg_write, id_ex_is_fp_mem;
    reg [2:0]  id_ex_fp_op;
    reg [31:0] id_ex_fp_rs1_data, id_ex_fp_rs2_data;

    // ==================== EX stage ====================
    // Forwarding compares ID/EX's own rs1/rs2 against EX/MEM's and
    // MEM/WB's destinations (declared ahead of use, driven by those
    // later pipeline registers below).
    reg [4:0]  ex_mem_rd_r;
    reg        ex_mem_reg_write_r;
    reg [4:0]  mem_wb_rd_r;
    reg        mem_wb_reg_write_r;
    wire [1:0] forward_a, forward_b;

    forward_unit fu (
        .id_ex_rs1(id_ex_rs1), .id_ex_rs2(id_ex_rs2),
        .ex_mem_rd(ex_mem_rd_r), .ex_mem_reg_write(ex_mem_reg_write_r),
        .mem_wb_rd(mem_wb_rd_r), .mem_wb_reg_write(mem_wb_reg_write_r),
        .forward_a(forward_a), .forward_b(forward_b)
    );

    // ex_mem_alu_result / mem_wb_wb_data_r are declared with the later
    // pipeline registers/WB-mux below - Verilog module-level wires/regs
    // don't need forward declaration by position, only used-before-
    // declared within the SAME always block would be a problem, and
    // none of these are.
    wire [31:0] fwd_rs1 = (forward_a == 2'b10) ? ex_mem_alu_result :
                          (forward_a == 2'b01) ? mem_wb_wb_data_r  : id_ex_rs1_data;
    wire [31:0] fwd_rs2 = (forward_b == 2'b10) ? ex_mem_alu_result :
                          (forward_b == 2'b01) ? mem_wb_wb_data_r  : id_ex_rs2_data;

    // FP forwarding - reuses id_ex_rs1/id_ex_rs2 (the SAME register-
    // NUMBER fields the integer forward_unit above already uses; safe
    // because ex_mem_fp_reg_write/mem_wb_fp_reg_write only ever fire
    // for an actual FP-destination instruction, and control_unit.v
    // guarantees reg_write/fp_reg_write are mutually exclusive per
    // instruction - see this feature's design notes). ex_mem_rd/
    // mem_wb_rd/ex_mem_fp_reg_write/mem_wb_fp_reg_write are referenced
    // directly (no "_r"-style alias) - confirmed unnecessary even for
    // the existing integer forward_unit above, not worth copying.
    wire [1:0] fp_forward_a, fp_forward_b;

    fp_forward_unit ffu (
        .id_ex_rs1(id_ex_rs1), .id_ex_rs2(id_ex_rs2),
        .ex_mem_rd(ex_mem_rd), .ex_mem_reg_write(ex_mem_fp_reg_write),
        .mem_wb_rd(mem_wb_rd), .mem_wb_reg_write(mem_wb_fp_reg_write),
        .forward_a(fp_forward_a), .forward_b(fp_forward_b)
    );

    // ex_mem_fpu_result is declared with the later EX/MEM register
    // below - same no-forward-declaration-needed rule as fwd_rs1/rs2
    // above.
    wire [31:0] fp_fwd_rs1 = (fp_forward_a == 2'b10) ? ex_mem_fpu_result :
                             (fp_forward_a == 2'b01) ? fp_wb_data       : id_ex_fp_rs1_data;
    wire [31:0] fp_fwd_rs2 = (fp_forward_b == 2'b10) ? ex_mem_fpu_result :
                             (fp_forward_b == 2'b01) ? fp_wb_data       : id_ex_fp_rs2_data;

    // fp_addsub/fp_mul both take fp_fwd_rs1/fp_fwd_rs2 unconditionally -
    // harmlessly computed-but-unused when the current instruction isn't
    // actually FADD.S/FSUB.S/FMUL.S, exactly like the integer ALU above
    // already computes something for every instruction regardless of
    // whether the result is ever consumed.
    wire [31:0] fpu_addsub_result, fpu_mul_result;

    fp_addsub fpas (
        .a(fp_fwd_rs1), .b(fp_fwd_rs2), .op_sub(id_ex_fp_op[0]),
        .result(fpu_addsub_result)
    );

    fp_mul fpmul (
        .a(fp_fwd_rs1), .b(fp_fwd_rs2),
        .result(fpu_mul_result)
    );

    // Only add/sub/mul are wired on this core (FDIV.S is E-core only
    // for now - see fp_div.v's own project notes) - an FDIV.S that
    // somehow reached this pipeline would silently fall through to
    // the addsub result rather than actually dividing, a known,
    // documented gap rather than real support.
    wire [31:0] ex_fpu_result = (id_ex_fp_op == 3'b010) ? fpu_mul_result : fpu_addsub_result;

    wire [31:0] ex_alu_a = id_ex_auipc ? id_ex_pc : (id_ex_lui ? 32'b0 : fwd_rs1);
    wire [31:0] ex_alu_b = id_ex_alu_src ? id_ex_imm : fwd_rs2;
    wire [31:0] ex_alu_result;
    wire        ex_alu_zero;

    alu ax (.a(ex_alu_a), .b(ex_alu_b), .alu_op(id_ex_alu_op), .result(ex_alu_result), .zero(ex_alu_zero));

    reg ex_branch_taken;
    always @(*) begin
        case (id_ex_funct3)
            3'b000:  ex_branch_taken = (fwd_rs1 == fwd_rs2);
            3'b001:  ex_branch_taken = (fwd_rs1 != fwd_rs2);
            3'b100:  ex_branch_taken = ($signed(fwd_rs1) <  $signed(fwd_rs2));
            3'b101:  ex_branch_taken = ($signed(fwd_rs1) >= $signed(fwd_rs2));
            3'b110:  ex_branch_taken = (fwd_rs1 <  fwd_rs2);
            3'b111:  ex_branch_taken = (fwd_rs1 >= fwd_rs2);
            default: ex_branch_taken = 1'b0;
        endcase
    end

    wire ex_taken = (id_ex_branch && ex_branch_taken) || id_ex_jump || id_ex_jalr;
    wire [31:0] ex_branch_target = id_ex_pc + id_ex_imm;
    wire [31:0] ex_jalr_target   = (fwd_rs1 + id_ex_imm) & 32'hFFFFFFFE;
    wire [31:0] ex_target        = id_ex_jalr ? ex_jalr_target : ex_branch_target;

    // ==================== EX/MEM register ====================
    reg [31:0] ex_mem_pc_plus4;
    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_store_data;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write, ex_mem_mem_unsigned;
    reg        ex_mem_is_system;
    reg [1:0]  ex_mem_mem_size, ex_mem_wb_sel;

    // Minimal RV32F.
    reg        ex_mem_fp_reg_write, ex_mem_is_fp_mem;
    reg [31:0] ex_mem_fpu_result;

    // Aliases so forward_unit's inputs (declared above, before this
    // register block) can reference this cycle's live EX/MEM contents.
    // (Verilog doesn't need textual reordering for this - these are
    // just plain continuous references to the regs declared here.)
    always @(*) begin
        ex_mem_rd_r        = ex_mem_rd;
        ex_mem_reg_write_r = ex_mem_reg_write;
    end

    // ==================== MEM stage ====================
    // Is the memory op CURRENTLY sitting in EX/MEM targeting the shared
    // region instead of this core's own private data_mem? A losing
    // arbitration here must hold EX/MEM (and everything ahead of it) in
    // place until granted - see the sequential blocks below.
    wire ex_mem_is_shared_access = (ex_mem_mem_read || ex_mem_mem_write) &&
        (ex_mem_alu_result >= SHARED_MEM_BASE) && (ex_mem_alu_result < SHARED_MEM_BASE + SHARED_MEM_BYTES);

    // Re-base to shared_bus's own local (0-based) address window - see
    // the matching comment in cpu_core.v.
    assign bus_req          = ex_mem_is_shared_access;
    assign bus_addr          = ex_mem_alu_result - SHARED_MEM_BASE;
    assign bus_write_data    = ex_mem_store_data;
    assign bus_mem_write     = ex_mem_mem_write;
    assign bus_mem_size      = ex_mem_mem_size;
    assign bus_mem_unsigned  = ex_mem_mem_unsigned;

    wire mem_stall = ex_mem_is_shared_access && !bus_grant;

    wire [31:0] mem_read_data;

    data_mem #(.MEM_BYTES(DATA_MEM_BYTES)) dmem (
        .clk(clk), .addr(ex_mem_alu_result), .write_data(ex_mem_store_data),
        .mem_write(ex_mem_mem_write && !ex_mem_is_shared_access), .mem_size(ex_mem_mem_size),
        .mem_unsigned(ex_mem_mem_unsigned), .read_data(mem_read_data)
    );

    wire [31:0] effective_mem_read_data = ex_mem_is_shared_access ? bus_read_data : mem_read_data;

    // ==================== MEM/WB register ====================
    reg [31:0] mem_wb_pc_plus4;
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_mem_data;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write, mem_wb_is_system;
    reg [1:0]  mem_wb_wb_sel;

    // Minimal RV32F.
    reg        mem_wb_fp_reg_write, mem_wb_is_fp_mem;
    reg [31:0] mem_wb_fpu_result;

    always @(*) begin
        mem_wb_rd_r        = mem_wb_rd;
        mem_wb_reg_write_r = mem_wb_reg_write;
    end

    // ==================== WB stage ====================
    reg [31:0] wb_data_r;
    always @(*) begin
        case (mem_wb_wb_sel)
            WB_MEM:  wb_data_r = mem_wb_mem_data;
            WB_PC4:  wb_data_r = mem_wb_pc_plus4;
            default: wb_data_r = mem_wb_alu_result;
        endcase
    end
    wire [31:0] mem_wb_wb_data_r = wb_data_r;

    assign wb_reg_write = mem_wb_reg_write;
    assign wb_rd_addr   = mem_wb_rd;
    assign wb_rd_data   = wb_data_r;

    // FLW's write-back value is the loaded memory data (mem_wb_mem_data,
    // the SAME register the integer WB_MEM case already uses - raw
    // bits don't care whether they're "integer" or "float"); FADD.S/
    // FSUB.S/FMUL.S write fp_addsub's/fp_mul's result instead. This
    // fp_regfile write is UNCONDITIONAL (no mem_stall gating) - the
    // design review confirmed correctness already comes entirely from
    // MEM/WB's hold-not-bubble behavior above (a held register just
    // re-writes the identical value every stalled cycle, harmless),
    // exactly matching the existing unconditional wb_reg_write above.
    wire [31:0] fp_wb_data = mem_wb_is_fp_mem ? mem_wb_mem_data : mem_wb_fpu_result;

    assign tohost_value = x10_debug;

    // ==================== Next-PC selection ====================
    wire [31:0] next_pc = ex_taken ? ex_target : pc_plus4_if;

    // ==================== Sequential updates ====================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc       <= 32'b0;
            halted_r <= 1'b0;
        end else if (!halted_r) begin
            if (!(stall || mem_stall)) pc <= next_pc;
            if (mem_wb_is_system) halted_r <= 1'b1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            if_id_pc    <= 32'b0;
            if_id_instr <= 32'b0;
        end else if (!halted_r) begin
            if (mem_stall) begin
                // Hold unconditionally - PC is frozen too (above), so
                // if_instr/pc wouldn't have changed anyway. A pending
                // ex_taken flush is simply deferred until mem_stall
                // clears (see the ID/EX block: whatever's driving
                // ex_taken is ALSO held frozen every cycle mem_stall
                // lasts, so nothing is lost by waiting).
            end else if (ex_taken) begin
                if_id_pc    <= 32'b0;
                if_id_instr <= 32'b0;
            end else if (!stall) begin
                if_id_pc    <= pc;
                if_id_instr <= if_instr;
            end
            // stall && !ex_taken: hold current if_id_* (no assignment)
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            id_ex_reg_write <= 1'b0; id_ex_mem_read <= 1'b0; id_ex_mem_write <= 1'b0;
            id_ex_alu_src <= 1'b0; id_ex_branch <= 1'b0; id_ex_jump <= 1'b0;
            id_ex_jalr <= 1'b0; id_ex_auipc <= 1'b0; id_ex_lui <= 1'b0;
            id_ex_mem_unsigned <= 1'b0; id_ex_is_system <= 1'b0;
            id_ex_alu_op <= 4'b0; id_ex_mem_size <= 2'b0; id_ex_wb_sel <= 2'b0;
            id_ex_funct3 <= 3'b0; id_ex_rd <= 5'b0; id_ex_rs1 <= 5'b0; id_ex_rs2 <= 5'b0;
            id_ex_pc <= 32'b0; id_ex_pc_plus4 <= 32'b0;
            id_ex_rs1_data <= 32'b0; id_ex_rs2_data <= 32'b0; id_ex_imm <= 32'b0;
            id_ex_mem_read_r <= 1'b0; id_ex_rd_r <= 5'b0;
            id_ex_fp_reg_write <= 1'b0; id_ex_is_fp_mem <= 1'b0; id_ex_fp_op <= 3'b0;
            id_ex_fp_rs1_data <= 32'b0; id_ex_fp_rs2_data <= 32'b0;
            id_ex_fp_reg_write_r <= 1'b0;
        end else if (!halted_r) begin
            if (mem_stall) begin
                // Hold entirely (not a bubble) - the instruction here is
                // itself waiting on the older memory op stuck in EX/MEM
                // (a structural resource conflict: EX/MEM physically
                // can't accept a new value this cycle), so it must stay
                // put rather than be silently discarded like a normal
                // hazard bubble would discard it.
            end else if (ex_taken || stall) begin
                // Bubble: either flushing a wrong-path instruction, or
                // holding back a load-use-hazardous one for one cycle.
                id_ex_reg_write <= 1'b0; id_ex_mem_read <= 1'b0; id_ex_mem_write <= 1'b0;
                id_ex_branch <= 1'b0; id_ex_jump <= 1'b0; id_ex_jalr <= 1'b0;
                id_ex_is_system <= 1'b0; id_ex_rd <= 5'b0;
                id_ex_fp_reg_write <= 1'b0; id_ex_is_fp_mem <= 1'b0;
            end else begin
                id_ex_reg_write     <= id_reg_write;
                id_ex_mem_read      <= id_mem_read;
                id_ex_mem_write     <= id_mem_write;
                id_ex_alu_src       <= id_alu_src;
                id_ex_branch        <= id_branch;
                id_ex_jump          <= id_jump;
                id_ex_jalr          <= id_jalr;
                id_ex_auipc         <= id_auipc;
                id_ex_lui           <= id_lui;
                id_ex_mem_unsigned  <= id_mem_unsigned;
                id_ex_is_system     <= id_is_system;
                id_ex_alu_op        <= id_alu_op;
                id_ex_mem_size      <= id_mem_size;
                id_ex_wb_sel        <= id_wb_sel;
                id_ex_funct3        <= id_funct3;
                id_ex_rd            <= id_rd;
                id_ex_rs1           <= if_id_rs1;
                id_ex_rs2           <= if_id_rs2;
                id_ex_pc            <= if_id_pc;
                id_ex_pc_plus4      <= id_pc_plus4;
                id_ex_rs1_data      <= id_rs1_data;
                id_ex_rs2_data      <= id_rs2_data;
                id_ex_imm           <= id_imm;
                id_ex_fp_reg_write  <= id_fp_reg_write;
                id_ex_is_fp_mem     <= id_is_fp_mem;
                id_ex_fp_op         <= id_fp_op;
                id_ex_fp_rs1_data   <= fp_id_rs1_data;
                id_ex_fp_rs2_data   <= fp_id_rs2_data;
            end
            // Hazard unit needs THIS cycle's about-to-be-latched values
            // available for NEXT cycle's stall check - mirror what's
            // being written above (hold under mem_stall since ID/EX
            // itself isn't changing; 0 for a bubble; real values
            // otherwise).
            if (mem_stall) begin
                // hold (no assignment)
            end else if (ex_taken || stall) begin
                id_ex_mem_read_r <= 1'b0;
                id_ex_rd_r       <= 5'b0;
                id_ex_fp_reg_write_r <= 1'b0;
            end else begin
                id_ex_mem_read_r <= id_mem_read;
                id_ex_rd_r       <= id_rd;
                id_ex_fp_reg_write_r <= id_fp_reg_write;
            end
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ex_mem_pc_plus4 <= 32'b0; ex_mem_alu_result <= 32'b0; ex_mem_store_data <= 32'b0;
            ex_mem_rd <= 5'b0; ex_mem_reg_write <= 1'b0; ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0; ex_mem_mem_unsigned <= 1'b0; ex_mem_is_system <= 1'b0;
            ex_mem_mem_size <= 2'b0; ex_mem_wb_sel <= 2'b0;
            ex_mem_fp_reg_write <= 1'b0; ex_mem_is_fp_mem <= 1'b0; ex_mem_fpu_result <= 32'b0;
        end else if (!halted_r) begin
            if (!mem_stall) begin
                ex_mem_pc_plus4     <= id_ex_pc_plus4;
                ex_mem_alu_result   <= ex_alu_result;
                // FSW's actual store data is FP (fp_fwd_rs2), not the
                // integer fwd_rs2 - id_ex_is_fp_mem&&id_ex_mem_write
                // uniquely identifies FSW among everything carried this
                // far (arithmetic ops never set mem_write, so this mux
                // can't misfire for them even though their own
                // ex_mem_store_data value is never actually consumed).
                ex_mem_store_data   <= (id_ex_is_fp_mem && id_ex_mem_write) ? fp_fwd_rs2 : fwd_rs2;
                ex_mem_rd           <= id_ex_rd;
                ex_mem_reg_write    <= id_ex_reg_write;
                ex_mem_mem_read     <= id_ex_mem_read;
                ex_mem_mem_write    <= id_ex_mem_write;
                ex_mem_mem_unsigned <= id_ex_mem_unsigned;
                ex_mem_is_system    <= id_ex_is_system;
                ex_mem_mem_size     <= id_ex_mem_size;
                ex_mem_wb_sel       <= id_ex_wb_sel;
                ex_mem_fp_reg_write <= id_ex_fp_reg_write;
                ex_mem_is_fp_mem    <= id_ex_is_fp_mem;
                ex_mem_fpu_result   <= ex_fpu_result;
            end
            // mem_stall: hold - the stuck access retries with the SAME
            // ex_mem_* values (address, size, etc.) next cycle.
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_wb_pc_plus4 <= 32'b0; mem_wb_alu_result <= 32'b0; mem_wb_mem_data <= 32'b0;
            mem_wb_rd <= 5'b0; mem_wb_reg_write <= 1'b0; mem_wb_is_system <= 1'b0;
            mem_wb_wb_sel <= 2'b0;
            mem_wb_fp_reg_write <= 1'b0; mem_wb_is_fp_mem <= 1'b0; mem_wb_fpu_result <= 32'b0;
        end else if (!halted_r) begin
            if (!mem_stall) begin
                mem_wb_pc_plus4   <= ex_mem_pc_plus4;
                mem_wb_alu_result <= ex_mem_alu_result;
                mem_wb_mem_data   <= effective_mem_read_data;
                mem_wb_rd         <= ex_mem_rd;
                mem_wb_reg_write  <= ex_mem_reg_write;
                mem_wb_is_system  <= ex_mem_is_system;
                mem_wb_wb_sel     <= ex_mem_wb_sel;
                mem_wb_fp_reg_write <= ex_mem_fp_reg_write;
                mem_wb_is_fp_mem    <= ex_mem_is_fp_mem;
                mem_wb_fpu_result   <= ex_mem_fpu_result;
            end
            // mem_stall: HOLD (not bubble) - EX/MEM is frozen too, so
            // nothing new is arriving here anyway. Holding (rather than
            // zeroing mem_wb_reg_write like a bubble would) keeps
            // forward_unit's MEM/WB source valid for however many
            // cycles the stall lasts - bubbling here was the bug an
            // earlier design review caught: it would silently flip
            // forward_a/forward_b back to "no forward" mid-stall,
            // corrupting fwd_rs1/fwd_rs2 for whatever instruction in
            // ID/EX is frozen waiting on that exact forwarded value.
        end
    end
endmodule
