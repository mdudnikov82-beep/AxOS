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
    parameter SHARED_MEM_BYTES = 256
) (
    input  wire        clk,
    input  wire        reset,
    output wire         halted,       // latched true the cycle after ECALL fires - see below
    output wire [31:0]  tohost_value, // x10/a0 at the moment ECALL fired; valid once halted==1

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
    reg        halted_r;
    assign halted = halted_r;

    wire [31:0] instr;
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

    wire reg_write, mem_read, mem_write, mem_to_reg, alu_src, branch, jump, jalr, auipc, lui, mem_unsigned, illegal;
    wire [3:0]  alu_op;
    wire [1:0]  mem_size;

    // Minimal RV32F (see fp_regfile.v/fp_addsub.v/fp_mul.v/fp_div.v).
    localparam FP_MUL = 3'b010;
    localparam FP_DIV = 3'b011;

    wire        fp_reg_write, is_fp_mem;
    wire [2:0]  fp_op;
    wire [31:0] fp_rs1_data, fp_rs2_data;
    reg  [31:0] fp_rd_data;

    wire [31:0] alu_a = auipc ? pc : (lui ? 32'b0 : rs1_data);
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

    wire [31:0] effective_mem_read_data = is_shared_access ? bus_read_data : mem_read_data;

    instr_mem #(.MEM_WORDS(INSTR_MEM_WORDS), .INIT_FILE(INSTR_INIT_FILE)) imem (
        .addr(pc), .instr(instr)
    );

    // A losing cycle must not commit a register write - the same
    // instruction (same rd/rd_data inputs) simply retries next cycle.
    wire regfile_write_en = reg_write && !mem_stall;

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
        .fp_reg_write(fp_reg_write), .is_fp_mem(is_fp_mem), .fp_op(fp_op)
    );

    alu ax (.a(alu_a), .b(alu_b), .alu_op(alu_op), .result(alu_result), .zero(alu_zero));

    // A shared-range write must never hit the private memory (it's out
    // of that address's own valid range anyway, but the decode belongs
    // here at the bus level, not left to the memory to silently no-op).
    data_mem #(.MEM_BYTES(DATA_MEM_BYTES)) dmem (
        .clk(clk), .addr(alu_result), .write_data(store_data),
        .mem_write(mem_write && !is_shared_access), .mem_size(mem_size), .mem_unsigned(mem_unsigned),
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
    wire [31:0] fpu_addsub_result, fpu_mul_result, fpu_div_result;

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

    // Same !mem_stall gating as the integer regfile's write enable -
    // a stalled FLW (targeting the shared-bus region) must not commit
    // garbage into fp_regfile on a losing arbitration cycle, the exact
    // bug class mem_stall already exists to prevent on the integer side.
    // fpu_div_stall gets the identical treatment: a division result
    // only commits on the one cycle it's actually done.
    wire fp_regfile_write_en = fp_reg_write && !mem_stall && !fpu_div_stall;

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

    // FLW's write-back is the loaded memory data; FADD.S/FSUB.S write
    // fp_addsub's result (op_sub selects which); FMUL.S writes
    // fp_mul's; FDIV.S writes fp_div's (an explicit branch - falling
    // through to the addsub default here would silently compute the
    // wrong operation instead of dividing, the same "silent wrong
    // branch" bug class already documented in control_unit.v's own
    // LUI comment) - a dedicated mux kept independent of the integer
    // path's mem_to_reg mux, per this feature's design review.
    always @(*) begin
        if (is_fp_mem)           fp_rd_data = effective_mem_read_data;
        else if (fp_op == FP_MUL) fp_rd_data = fpu_mul_result;
        else if (fp_op == FP_DIV) fp_rd_data = fpu_div_result;
        else                       fp_rd_data = fpu_addsub_result;
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
    wire [31:0] branch_target = pc + imm;
    wire [31:0] jal_target    = pc + imm;
    // JALR clears the LSB per spec (target must be even) - it's not
    // an alignment nicety, it's how the encoding tells JALR targets
    // apart from a plain register-relative call with an odd base.
    wire [31:0] jalr_target   = (rs1_data + imm) & 32'hFFFFFFFE;

    wire [31:0] next_pc =
        jump                    ? jal_target    :
        jalr                    ? jalr_target   :
        (branch && branch_taken) ? branch_target :
        pc_plus4;

    always @(*) begin
        if (jump || jalr)     rd_data = pc_plus4;      // link register gets the return address
        else if (mem_to_reg)  rd_data = effective_mem_read_data;
        else                  rd_data = alu_result;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc       <= 32'b0;
            halted_r <= 1'b0;
        end else if (!halted_r && !mem_stall && !fpu_div_stall) begin
            pc <= next_pc;
            if (opcode == OP_SYSTEM) halted_r <= 1'b1;
        end
    end

    assign tohost_value = x10_debug;
endmodule
