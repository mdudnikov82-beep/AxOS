// 32 x 32-bit floating-point register file (f0-f31). Same shape as
// regfile.v (two async read ports, one sync write port) but WITHOUT
// regfile.v's x0-is-always-zero rule: f0 is an ordinary, freely
// writable register in RV32F - there is no hardwired-zero FP register.
`timescale 1ns/1ps

module fp_regfile (
    input  wire        clk,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        reg_write
);
    reg [31:0] regs [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1) regs[i] = 32'b0;
    end

    // Deliberately no same-cycle write-through bypass here either -
    // see regfile.v's own comment for why that caused a real
    // combinational-loop hang the first time it was tried.
    assign rs1_data = regs[rs1_addr];
    assign rs2_data = regs[rs2_addr];

    always @(posedge clk) begin
        if (reg_write) begin
            regs[rd_addr] <= rd_data;
        end
    end
endmodule
