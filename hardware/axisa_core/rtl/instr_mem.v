// Instruction ROM. $readmemh-loaded from INIT_FILE (a parameter, not
// hardcoded - the same module serves every test program).
//
// SYNC_READ=0 (default): combinational read, unchanged from this
// module's original behavior - the single-cycle datapath gets the
// fetched instruction ready the same cycle PC changes, no fetch stage
// of its own. Structurally identical to the pre-SYNC_READ file (no
// clocked register at all in this branch) - `stall` is simply unused.
//
// SYNC_READ=1: registers the read (one real clock edge between `addr`
// changing and `instr` reflecting it). Exists because a real
// synth_ecp5/nextpnr-ecp5 run found the combinational-read form fails
// ECP5 block-RAM inference at this depth (1024 words) and falls back
// to ~32,000 wasted flip-flops instead of a real memory primitive -
// see [[project_axisa_synthesis_check]]. Used only by cpu_core.v,
// which supplies its own pc_r/squash_r registers to compensate for
// the added cycle - see cpu_core.v's own header comment for why a
// naive "just register the output" fix is NOT sufficient by itself
// for this ISA specifically (opcode 0 is a real, committing
// instruction here, unlike RV32I).
//
// `stall`: MUST be driven true on any cycle the calling core's own PC
// is frozen (a real multi-cycle stall - mem_stall/mmu_stall/etc, NOT
// the post-redirect squash bubble, where PC legitimately keeps
// advancing). Without this, a real bug (caught live via
// tb_trap_irq_stall.v: EPC landed on the WRONG instruction after a
// stalled STORE): `pc` always races one instruction ahead of the
// currently-decoding one (prefetching), so by the exact cycle a stall
// is first detected, this module's OWN internal register has already
// captured the NEXT (not-yet-relevant) address - and since this
// register has no awareness of the calling core's stall state, it
// would go on to LATCH that stale prefetch as `instr` one cycle later,
// silently overwriting the still-stalled instruction's own decode with
// the wrong one, even though `addr` itself stops changing at that
// exact point (freezing `addr` one cycle after the fact is one cycle
// too late to prevent this specific register from drifting).
`timescale 1ns/1ps

module instr_mem #(
    parameter MEM_WORDS = 1024,
    parameter INIT_FILE = "",
    parameter SYNC_READ = 0
) (
    input  wire        clk,
    input  wire [31:0] addr,   // byte address (word-aligned - addr[1:0] ignored)
    input  wire        stall,  // SYNC_READ=1 only - hold instr steady (see header comment)
    output wire [31:0] instr
);
    reg [31:0] mem [0:MEM_WORDS-1];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    generate
        if (SYNC_READ) begin: gen_sync_read
            reg [31:0] instr_r;
            always @(posedge clk) begin
                if (!stall) instr_r <= mem[addr[31:2]];
            end
            assign instr = instr_r;
        end else begin: gen_comb_read
            assign instr = mem[addr[31:2]];
        end
    endgenerate
endmodule
