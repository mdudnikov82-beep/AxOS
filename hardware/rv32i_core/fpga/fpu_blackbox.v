// Synthesis-only stand-in for the 5 FPU submodules, used ONLY to
// isolate the integer-core-only area for a fair comparison against
// AxISA's cpu_core.v (which has no FPU at all) - see
// [[project_axisa_synthesis_check]]. NOT used for simulation.
`timescale 1ns/1ps

(* blackbox *)
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
endmodule

(* blackbox *)
module fp_addsub (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        op_sub,
    output wire [31:0] result
);
endmodule

(* blackbox *)
module fp_mul (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [31:0] result
);
endmodule

(* blackbox *)
module fp_div (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [31:0] result,
    output wire        busy,
    output wire        done
);
endmodule

(* blackbox *)
module fp_sqrt (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [31:0] a,
    output wire [31:0] result,
    output wire        busy,
    output wire        done
);
endmodule
