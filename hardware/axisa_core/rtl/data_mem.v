// Data memory for AxISA's LOAD/STORE (see docs/ISA.md) - word-only,
// no partial-word (byte/halfword) access exists in v0.1, so this is
// modeled on instr_mem.v's WORD-addressed array, not rv32i_core's
// byte-addressable data_mem.v (which exists only to serve RV32I's
// LB/LH/LW - unneeded complexity here). Any non-word-aligned address
// silently rounds down (addr[1:0] dropped), same as instr_mem.v - no
// alignment-fault checking, matching this ISA's "no fault-checking in
// v0.1" scope.
//
// Combinational read via a continuous `assign` (not an `always @(*)`
// block indexing the array) - rv32i_core/rtl/data_mem.v documents a
// real Icarus Verilog elaboration-performance cliff hit by the
// `always @(*)` form with a computed wide index; instr_mem.v already
// sidesteps it the same way this module does, so the lesson carries
// forward rather than being rediscovered.
`timescale 1ns/1ps

module data_mem #(
    parameter MEM_WORDS = 1024
) (
    input  wire        clk,
    input  wire [31:0] addr,   // byte address (word-aligned - addr[1:0] ignored)
    input  wire [31:0] wdata,
    input  wire        we,
    output wire [31:0] rdata
);
    reg [31:0] mem [0:MEM_WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 32'b0;
    end

    assign rdata = mem[addr[31:2]];

    always @(posedge clk) begin
        if (we) mem[addr[31:2]] <= wdata;
    end
endmodule
