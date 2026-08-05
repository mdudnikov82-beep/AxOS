// 8 x 32-bit register bank - one instance each for AxISA's R/G/B/N
// banks (see docs/ISA.md). Two async (combinational) read ports + one
// synchronous write port, same single-cycle shape as rv32i_core's own
// regfile.v, which this is deliberately modeled on. HARDWIRE_REG0
// enables the N-bank-only "n0 is the vacuum, always zero" rule
// (mirrors RISC-V x0); R/G/B instances leave it disabled, since
// docs/ISA.md is explicit that r0/g0/b0 are ordinary registers.
//
// NOT a write-through bypass, deliberately - same real bug this
// project already found once in rv32i_core/rtl/regfile.v (see that
// file's own comment): a single instruction routinely has its own
// rd equal to one of its own sources in the SAME bank (e.g. an ALUR
// add-into-itself), so a same-cycle write-to-read bypass would feed
// the ALU's about-to-be-computed output back into its own input - a
// genuine combinational loop, not just a stale-data bug. This module
// only ever does a plain combinational read of the storage array.
`timescale 1ns/1ps

module regbank #(
    parameter HARDWIRE_REG0 = 0
) (
    input  wire        clk,
    input  wire [2:0]  rs1_addr,
    input  wire [2:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    input  wire [2:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        reg_write
);
    reg [31:0] regs [0:7];
    integer i;

    initial begin
        for (i = 0; i < 8; i = i + 1) regs[i] = 32'b0;
    end

    generate
        if (HARDWIRE_REG0) begin: hardwired
            assign rs1_data = (rs1_addr == 3'd0) ? 32'b0 : regs[rs1_addr];
            assign rs2_data = (rs2_addr == 3'd0) ? 32'b0 : regs[rs2_addr];
        end else begin: plain
            assign rs1_data = regs[rs1_addr];
            assign rs2_data = regs[rs2_addr];
        end
    endgenerate

    always @(posedge clk) begin
        if (reg_write && !(HARDWIRE_REG0 && rd_addr == 3'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end
endmodule
