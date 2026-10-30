// Instruction ROM. $readmemh-loaded from INIT_FILE (a parameter, not
// hardcoded - the same module serves every test program).
//
// SYNC_READ=0 (default): combinational read, unchanged from this
// module's original behavior - the single-cycle datapath gets the
// fetched instruction ready the same cycle PC changes, no fetch stage
// of its own. Structurally identical to the pre-SYNC_READ file (no
// clocked register at all in this branch) - used unmodified by
// cpu_core_pipelined.v (its own IF/ID register already solves this
// problem independently - do not change its instantiation to
// SYNC_READ=1, that would double-register the fetch). `stall` is
// simply unused in this branch.
//
// SYNC_READ=1: registers the read (one real clock edge between `addr`
// changing and `instr` reflecting it). Exists because a real
// synth_ecp5/nextpnr-ecp5 run found the combinational-read form fails
// ECP5 block-RAM inference at this depth (1024 words) and falls back
// to ~32,000 wasted flip-flops instead of a real memory primitive -
// see [[project_axisa_synthesis_check]]. Used only by cpu_core.v
// (single-cycle), which supplies its own pc_r/squash_r registers to
// compensate for the added cycle.
//
// `stall`: MUST be driven true on any cycle the calling core's own PC
// is frozen (mem_stall/mmu_stall/fpu_div_stall/fpu_sqrt_stall - NOT
// the post-redirect squash bubble, where PC legitimately keeps
// advancing). Without this, a real bug (caught live on the AxISA
// sibling of this file via its own tb_trap_irq_stall.v: EPC landed on
// the WRONG instruction after a stalled access): `pc` always races one
// instruction ahead of the currently-decoding one (prefetching), so by
// the exact cycle a stall is first detected, this module's OWN
// internal register has already captured the NEXT (not-yet-relevant)
// address - and since this register has no awareness of the calling
// core's stall state, it would go on to LATCH that stale prefetch as
// `instr` one cycle later, silently overwriting the still-stalled
// instruction's own decode with the wrong one, even though `addr`
// itself stops changing at that exact point (freezing `addr` one cycle
// after the fact is one cycle too late to prevent this specific
// register from drifting).
`timescale 1ns/1ps

module instr_mem #(
    parameter MEM_WORDS = 1024,
    parameter INIT_FILE = "",
    parameter SYNC_READ = 0
) (
    input  wire        clk,
    input  wire [31:0] addr,   // byte address (word-aligned - addr[1:0] ignored)
    input  wire        stall,  // SYNC_READ=1 only - hold instr steady (see header comment)
    output wire [31:0] instr,
    // Program load port (2026-10-30): writes one word while the core is
    // held in reset. Only the ASIC wrapper (asic/cpu_core_top.v) drives it;
    // elsewhere it is left open. A program baked in as a ROM would let
    // synthesis prove most of the core unreachable and delete it - that
    // happened to AxISA's first ASIC numbers.
    input  wire        load_we,
    input  wire [31:0] load_addr,
    input  wire [31:0] load_data
);
    reg [31:0] mem [0:MEM_WORDS-1];
    always @(posedge clk) if (load_we) mem[load_addr[31:2]] <= load_data;

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
