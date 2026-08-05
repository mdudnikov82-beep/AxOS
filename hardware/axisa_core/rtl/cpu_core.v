// AxISA single-cycle core - milestone 1 (see docs/ISA.md): ALUR, ALUI,
// BRANCH, HALT only. GLUON/BARYON/MESON/LOAD/STORE/JAL are milestone 2
// (need multi-bank simultaneous operand routing and a memory
// subsystem respectively - deliberately not attempted yet, matching
// this project's established practice of proving the smallest real
// slice first).
//
// Four independent 8-register banks (R/G/B/N - see regbank.v) instead
// of RV32I's one 32-register file. Every bank's read-address ports are
// ALWAYS driven (harmless - a regbank simply looks up whatever index
// it's given), and only the SELECTED bank's read-data output is
// actually consulted (via `sel_*_data` below) or write-enable actually
// asserted (via the per-bank `*_write_en` demux) - the bank selection
// itself is pure combinational muxing, no different in kind from a
// single-file design's own address decode, just spread across 4 small
// files instead of 1 big one (confirmed by design review before this
// was written: 2 read ports + 1 write port per bank is provably
// sufficient for every instruction in the spec).
`timescale 1ns/1ps

module cpu_core #(
    parameter INSTR_MEM_WORDS = 1024,
    parameter INSTR_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        reset,
    output wire         halted,
    output wire [31:0]  tohost_value
);
    reg  [31:0] pc;
    reg         halted_r;
    assign halted = halted_r;

    wire [31:0] instr;
    instr_mem #(.MEM_WORDS(INSTR_MEM_WORDS), .INIT_FILE(INSTR_INIT_FILE)) imem (
        .addr(pc), .instr(instr)
    );

    wire [1:0]  bank;
    wire [3:0]  alu_funct;
    wire [2:0]  branch_funct;
    wire [2:0]  rd_addr, rs1_addr, rs2_addr;
    wire [31:0] imm;
    wire        reg_write, alu_src_imm, is_branch, is_halt, illegal;
    wire [2:0]  tohost_reg;

    control_unit cu (
        .instr(instr),
        .bank(bank), .alu_funct(alu_funct), .branch_funct(branch_funct),
        .rd_addr(rd_addr), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .imm(imm),
        .reg_write(reg_write), .alu_src_imm(alu_src_imm),
        .is_branch(is_branch), .is_halt(is_halt), .tohost_reg(tohost_reg),
        .illegal(illegal)
    );

    // ==================== Register banks ====================
    wire [31:0] r_rs1_data, r_rs2_data;
    wire [31:0] g_rs1_data, g_rs2_data;
    wire [31:0] b_rs1_data, b_rs2_data;
    wire [31:0] n_rs1_data, n_rs2_data;

    wire [31:0] rd_data = alu_result; // ALUR/ALUI's only writers in milestone 1

    wire r_write_en = reg_write && (bank == 2'b00);
    wire g_write_en = reg_write && (bank == 2'b01);
    wire b_write_en = reg_write && (bank == 2'b10);
    wire n_write_en = reg_write && (bank == 2'b11);

    // HALT has no bank field (it's implicitly N-only, per docs/ISA.md's
    // confinement rule) - override N's own rs1_addr with tohost_reg
    // during HALT so its value shows up on n_rs1_data without needing
    // a dedicated 3rd read port the way rv32i_core's ECALL convention
    // needed (that workaround existed there only because ECALL's
    // encoding had no spare bits for a real register field; HALT's
    // does, see docs/ISA.md's HALT section).
    wire [2:0] n_rs1_addr = is_halt ? tohost_reg : rs1_addr;

    regbank #(.HARDWIRE_REG0(0)) r_bank (
        .clk(clk), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(r_rs1_data), .rs2_data(r_rs2_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .reg_write(r_write_en)
    );
    regbank #(.HARDWIRE_REG0(0)) g_bank (
        .clk(clk), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(g_rs1_data), .rs2_data(g_rs2_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .reg_write(g_write_en)
    );
    regbank #(.HARDWIRE_REG0(0)) b_bank (
        .clk(clk), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(b_rs1_data), .rs2_data(b_rs2_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .reg_write(b_write_en)
    );
    regbank #(.HARDWIRE_REG0(1)) n_bank (
        .clk(clk), .rs1_addr(n_rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(n_rs1_data), .rs2_data(n_rs2_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .reg_write(n_write_en)
    );

    wire [31:0] sel_rs1_data = (bank == 2'b00) ? r_rs1_data :
                                (bank == 2'b01) ? g_rs1_data :
                                (bank == 2'b10) ? b_rs1_data : n_rs1_data;
    wire [31:0] sel_rs2_data = (bank == 2'b00) ? r_rs2_data :
                                (bank == 2'b01) ? g_rs2_data :
                                (bank == 2'b10) ? b_rs2_data : n_rs2_data;

    // Latched, NOT a live combinational read of n_rs1_data - found live:
    // halted_r registers one cycle AFTER is_halt is first seen (PC/fetch
    // still advance that same edge, since the !halted_r gate below is
    // still checking the OLD, not-yet-updated value), so the core
    // fetches one more (past-the-end-of-program, undefined/'x') word
    // before halted_r truly latches. Left as a live combinational
    // read, tohost_value would track THAT garbage fetch's decode by the
    // time anything outside actually checks it, not the real HALT
    // instruction's value - reading 'x' instead of the real result.
    // Capturing tohost_r on the exact same edge halted_r itself latches
    // keeps it stable forever afterward, regardless of what the one
    // extra fetch cycle decodes to.
    reg [31:0] tohost_r;
    assign tohost_value = tohost_r;

    // ==================== ALU ====================
    wire [31:0] alu_b = alu_src_imm ? imm : sel_rs2_data;
    wire [31:0] alu_result;
    alu ax (.a(sel_rs1_data), .b(alu_b), .funct(alu_funct), .result(alu_result));

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
    wire [31:0] next_pc  = (is_branch && branch_taken) ? (pc + imm) : pc_plus4;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc       <= 32'b0;
            halted_r <= 1'b0;
            tohost_r <= 32'b0;
        end else if (!halted_r) begin
            pc <= next_pc;
            if (is_halt) begin
                halted_r <= 1'b1;
                tohost_r <= n_rs1_data;
            end
        end
    end
endmodule
