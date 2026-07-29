// Top-level single-cycle RV32I core: wires alu.v/regfile.v/imm_gen.v/
// control_unit.v/instr_mem.v/data_mem.v into the classic single-cycle
// datapath. Every instruction fetches, decodes, executes, accesses
// memory, and writes back all within one clock edge - no pipeline, no
// hazards to detect.
`timescale 1ns/1ps

module cpu_core #(
    parameter INSTR_MEM_WORDS = 1024,
    parameter INSTR_INIT_FILE = "",
    parameter DATA_MEM_BYTES  = 4096
) (
    input  wire        clk,
    input  wire        reset,
    output wire         halted,       // latched true the cycle after ECALL fires - see below
    output wire [31:0]  tohost_value  // x10/a0 at the moment ECALL fired; valid once halted==1
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

    wire [31:0] alu_a = auipc ? pc : (lui ? 32'b0 : rs1_data);
    wire [31:0] alu_b = alu_src ? imm : rs2_data;
    wire [31:0] alu_result;
    wire        alu_zero;

    wire [31:0] mem_read_data;

    instr_mem #(.MEM_WORDS(INSTR_MEM_WORDS), .INIT_FILE(INSTR_INIT_FILE)) imem (
        .addr(pc), .instr(instr)
    );

    regfile rf (
        .clk(clk), .rs1_addr(rs1), .rs2_addr(rs2),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .rd_addr(rd), .rd_data(rd_data), .reg_write(reg_write),
        .x10_debug(x10_debug)
    );

    imm_gen ig (.instr(instr), .imm(imm));

    control_unit cu (
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .mem_to_reg(mem_to_reg), .alu_src(alu_src), .branch(branch),
        .jump(jump), .jalr(jalr), .auipc(auipc), .lui(lui),
        .alu_op(alu_op), .mem_size(mem_size), .mem_unsigned(mem_unsigned),
        .illegal(illegal)
    );

    alu ax (.a(alu_a), .b(alu_b), .alu_op(alu_op), .result(alu_result), .zero(alu_zero));

    data_mem #(.MEM_BYTES(DATA_MEM_BYTES)) dmem (
        .clk(clk), .addr(alu_result), .write_data(rs2_data),
        .mem_write(mem_write), .mem_size(mem_size), .mem_unsigned(mem_unsigned),
        .read_data(mem_read_data)
    );

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
        else if (mem_to_reg)  rd_data = mem_read_data;
        else                  rd_data = alu_result;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc       <= 32'b0;
            halted_r <= 1'b0;
        end else if (!halted_r) begin
            pc <= next_pc;
            if (opcode == OP_SYSTEM) halted_r <= 1'b1;
        end
    end

    assign tohost_value = x10_debug;
endmodule
