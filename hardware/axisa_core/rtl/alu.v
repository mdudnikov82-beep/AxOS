// Combinational ALU for AxISA's single-cycle core. `funct` is consumed
// directly as specified in docs/ISA.md's ALUR/ALUI funct encoding - no
// translation layer, since this is a from-scratch ISA with no
// compatibility target to match.
`timescale 1ns/1ps

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  funct,
    output wire [31:0] result
);
    localparam FUNCT_ADD  = 4'b0000;
    localparam FUNCT_SUB  = 4'b0001;
    localparam FUNCT_AND  = 4'b0010;
    localparam FUNCT_OR   = 4'b0011;
    localparam FUNCT_XOR  = 4'b0100;
    localparam FUNCT_SLL  = 4'b0101;
    localparam FUNCT_SRL  = 4'b0110;
    localparam FUNCT_SRA  = 4'b0111;
    localparam FUNCT_SLT  = 4'b1000;
    localparam FUNCT_SLTU = 4'b1001;

    reg [31:0] result_r;
    assign result = result_r;

    always @(*) begin
        case (funct)
            FUNCT_ADD:  result_r = a + b;
            FUNCT_SUB:  result_r = a - b;
            FUNCT_AND:  result_r = a & b;
            FUNCT_OR:   result_r = a | b;
            FUNCT_XOR:  result_r = a ^ b;
            FUNCT_SLL:  result_r = a << b[4:0];
            FUNCT_SRL:  result_r = a >> b[4:0];
            FUNCT_SRA:  result_r = $signed(a) >>> b[4:0];
            FUNCT_SLT:  result_r = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            FUNCT_SLTU: result_r = (a < b) ? 32'd1 : 32'd0;
            default:    result_r = 32'b0; // reserved funct - control_unit.v's `illegal` output covers this
        endcase
    end
endmodule
