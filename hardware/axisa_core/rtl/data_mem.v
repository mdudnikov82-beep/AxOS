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
//
// SYNC_READ (default 0, combinational - unchanged behavior) registers
// the read instead, same fix and same reason as instr_mem.v's own
// SYNC_READ: the combinational read fails ECP5 block-RAM inference at
// this depth and silently falls back to thousands of wasted flip-flops
// instead of real DP16KD block RAM (confirmed via real synth_ecp5 -
// see [[project_axisa_synthesis_check]]). Unlike instr_mem.v, no
// `stall` port is needed here - data_mem's address is a pure
// combinational function of the CURRENTLY FROZEN instruction (never
// races ahead the way pc does for fetch), so a plain unconditional
// register is safe as long as every consumer (cpu_core.v's LSU,
// mmu.v's walker) holds its address stable for one extra cycle before
// consuming the result - see cpu_core.v's dmem_load_stall and mmu.v's
// S_WALK_ISSUE/S_WALK_READ split. One real behavior change worth
// knowing: SYNC_READ=1 loses the old combinational version's
// incidental same-cycle write-then-read forwarding (a write and a
// registered read to the same address in the same cycle now returns
// the OLD value, standard BRAM "read-old-data" semantics) - every real
// consumer already mutually excludes a pending store from a
// walker/LSU read on this shared port, so this is safe.
`timescale 1ns/1ps

module data_mem #(
    parameter MEM_WORDS = 1024,
    parameter SYNC_READ = 0
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

    generate
        if (SYNC_READ) begin: gen_sync_read
            reg [31:0] rdata_r;
            always @(posedge clk) rdata_r <= mem[addr[31:2]];
            assign rdata = rdata_r;
        end else begin: gen_comb_read
            assign rdata = mem[addr[31:2]];
        end
    endgenerate

    always @(posedge clk) begin
        if (we) mem[addr[31:2]] <= wdata;
    end
endmodule
