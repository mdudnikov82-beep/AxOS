// 32 x 32-bit register file. x0 is hardwired to zero (writes to it are
// silently dropped, reads always return 0) - the one RISC-V-specific
// rule this module has to get right. Two async (combinational) read
// ports + one synchronous write port: the standard single-cycle shape
// - an instruction's source operands must be valid the same cycle its
// own decode happens, but the write (for the PREVIOUS instruction,
// in this single-cycle design actually the write for THIS instruction
// happens at the end of the same cycle) only needs to land on the
// clock edge.
`timescale 1ns/1ps

module regfile (
    input  wire        clk,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        reg_write,

    // Dedicated monitor port for x10/a0 - the CPU's ECALL/tohost test
    // convention (see cpu_core.v) needs a0's value at the moment of
    // ECALL, but ECALL's own encoding carries no real rs1 (its
    // instr[19:15] bits are always zero), so there's no way to get it
    // through the two ordinary read ports without also decoding a
    // second, unrelated register read for a fake "rs1". A third,
    // always-on read path is simpler and doesn't touch the real
    // datapath at all.
    output wire [31:0] x10_debug
);
    reg [31:0] regs [0:31];
    integer i;

    assign x10_debug = regs[10];

    initial begin
        for (i = 0; i < 32; i = i + 1) regs[i] = 32'b0;
    end

    assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 : regs[rs2_addr];

    always @(posedge clk) begin
        if (reg_write && rd_addr != 5'd0) begin
            regs[rd_addr] <= rd_data;
        end
    end
endmodule
