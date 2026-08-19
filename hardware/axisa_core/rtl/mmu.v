// Minimal virtual memory for AxISA - design review before this was
// written (see docs/ISA.md's "Virtual memory" section for the full
// rationale). Modeled on rv32i_core/rtl/mmu.v (this project's own,
// already-reviewed-and-tested Sv32-inspired MMU), but deliberately
// simplified for AxISA's actual scale and given the chance to do
// something rv32i_core's own MMU structurally could NOT: deliver a
// page fault as a REAL, RECOVERABLE trap (rv32i_core had no trap
// infrastructure when its MMU was built, so its own page_fault is
// sticky - freezes the core forever, no way back). AxISA now has
// RFT/SYSCALL/MVSR, so a page fault here is TRANSIENT - one combinational
// pulse, consumed by cpu_core.v's own sync_trap, with the walker
// itself returning to idle the same cycle, ready for whatever the
// kernel's fault handler (and the eventually-RFT'd-back program) does
// next.
//
// SCOPE: single-level, flat page table (NOT rv32i_core's 2-level
// design) - AxISA's private data_mem is currently only
// DATA_MEM_WORDS*4 bytes (8192 today = exactly 2 4KB pages), so a
// real 2-level Sv32-style walk would be solving a problem this address
// space doesn't have. PT_INDEX_BITS (default 4, 16 entries) sizes the
// flat table; any virtual address whose bits ABOVE the index field are
// nonzero faults immediately (never silently wraps/aliases).
//
// NO TLB - a genuine, deliberate simplification (also confirmed by
// design review): a single-level table is only a 1-cycle-extra walk
// away, so there is little a small associative cache would actually
// buy here that a "fill once, use it that cycle, forget it" single
// scratch entry doesn't already give for free (functionally a 1-entry
// TLB, not a real cache - every DIFFERENT following access simply
// re-walks). Only translates the core's own PRIVATE data_mem accesses,
// exactly like rv32i_core's own scope decision, extended with AxISA's
// own extra MMIO tier: the shared-bus window AND the UART range are
// both decoded on the raw (untranslated) address by cpu_core.v BEFORE
// this module is even consulted, so a translated access can never
// alias either one from this module's own perspective.
//
// Kernel mode (mode_r==KERNEL) ALWAYS bypasses translation entirely -
// not just "usually" - avoiding the real bootstrap chicken-and-egg
// problem (kernel code would need identity-mapped PTEs before it could
// ever build a page table at all). cpu_core.v computes ONE shared
// `is_access` gate (folding in the mode check) rather than checking
// `mode_r` separately in two places that could quietly diverge - the
// same "one shared gate, not several independently-drifting copies"
// discipline this project's own `gated_reg_write` comment already
// established.
//
// PTE format (32 bits) - IDENTICAL bit layout to rv32i_core's own,
// deliberately, for zero new design cost:
//   [31:12] = PPN (physical page number - PPN<<12 is the page's own
//             physical base address)
//   [2]     = W (writable)
//   [1]     = R (readable)
//   [0]     = V (valid)
`timescale 1ns/1ps

module mmu #(
    parameter MMU_ENABLE     = 0,
    parameter PT_INDEX_BITS  = 4, // 16 entries - see module header
    parameter DATA_MEM_WORDS = 2048
) (
    input  wire        clk,
    input  wire        reset,

    input  wire [31:0] vaddr,
    input  wire        is_access, // a real user-mode private-data_mem load/store this cycle (mode/shared/UART already excluded by the caller)
    input  wire        is_write,
    input  wire [31:0] ptb,       // page table base (physical byte address, kernel-writable via MVSR-style PTB instruction)
    input  wire        ptb_changed, // one-cycle pulse the cycle PTB is written - invalidates the single cached entry (see module header: PTB write is the only thing that can make a cached translation wrong, given v0.1 has no live in-place page-table editing)

    output wire [31:0] paddr,     // valid combinationally whenever !mmu_stall
    output wire        mmu_stall,
    output wire        mmu_fault, // ONE-CYCLE COMBINATIONAL pulse, NOT sticky - see module header for why this differs from rv32i_core's own design

    // This core's OWN private data_mem port - the walker issues its PTE
    // read through the SAME physical memory the LSU already uses, so
    // the caller must mux walk_addr into data_mem's addr input (and
    // force data_mem's we to 0) whenever walk_active is high - mirrors
    // rv32i_core/rtl/cpu_core.v's own dmem_addr/dmem_write gating
    // exactly (a real bug there once, before that project's own review
    // caught it pre-RTL).
    output wire        walk_active,
    output wire [31:0] walk_addr,
    input  wire [31:0] walk_read_data
);
    generate
    if (MMU_ENABLE == 0) begin: bypass
        assign paddr        = vaddr;
        assign mmu_stall    = 1'b0;
        assign mmu_fault    = 1'b0;
        assign walk_active  = 1'b0;
        assign walk_addr    = 32'b0;
    end else begin: real_mmu
        localparam S_IDLE       = 2'd0;
        // Split from a single S_WALK (design review before this split:
        // see [[project_axisa_synthesis_check]] - data_mem.v's own read
        // is now registered (SYNC_READ=1) to fix ECP5 block-RAM
        // inference, so walk_read_data is no longer valid the same
        // cycle walk_addr is first presented) - S_WALK_ISSUE presents
        // pt_addr and does nothing else; S_WALK_READ is the ENTIRE old
        // S_WALK case body, verbatim, now reading the registered
        // walk_read_data one cycle later.
        localparam S_WALK_ISSUE = 2'd1;
        localparam S_WALK_READ  = 2'd2;
        localparam S_FILL       = 2'd3;

        reg [1:0]  state;
        reg        have_valid;
        reg [31:0] have_vpn; // full upper 20 bits (vaddr[31:12]) - not just the index - so a hi-bits mismatch after a PTB change etc. can never look like a stale hit
        reg [19:0] have_ppn;
        reg        have_r, have_w;

        reg [19:0] fill_ppn_r;
        reg        fill_r_r, fill_w_r;

        wire [31:0] vpn = {vaddr[31:12]};
        wire [PT_INDEX_BITS-1:0] index = vaddr[12 +: PT_INDEX_BITS];
        wire hi_ok = (vaddr[31:12+PT_INDEX_BITS] == {(32-12-PT_INDEX_BITS){1'b0}});

        wire have_hit = have_valid && (have_vpn == vpn) &&
                        (is_write ? have_w : have_r);

        assign paddr = {have_ppn, vaddr[11:0]};

        wire [31:0] pt_addr = ptb + {{(30-PT_INDEX_BITS){1'b0}}, index, 2'b00};
        // Must span BOTH new states, not just S_WALK_READ - cpu_core.v's
        // STORE-write gate is `!mmu_walk_active && !mmu_stall`, and on
        // S_WALK_READ a faulting access has mmu_stall already dropped
        // to !mmu_fault=0 that same cycle (see mmu_fault below) - if
        // walk_active didn't also cover S_WALK_READ, a STORE could slip
        // through the write gate on the exact cycle a fault fires.
        assign walk_active = (state == S_WALK_ISSUE) || (state == S_WALK_READ);
        assign walk_addr   = pt_addr;

        wire pte_v = walk_read_data[0];
        wire pte_r = walk_read_data[1];
        wire pte_w = walk_read_data[2];
        wire [19:0] pte_ppn = walk_read_data[31:12];
        wire perm_ok  = is_write ? pte_w : pte_r;
        wire in_range = ({pte_ppn, 12'b0} < (DATA_MEM_WORDS * 4));

        // Combinational, true ONLY during the exact S_WALK_READ cycle
        // (walk_read_data is now valid, one cycle after S_WALK_ISSUE
        // presented pt_addr) a fault is detected - this is the one
        // deliberate departure from rv32i_core's own sticky S_FAULT:
        // mmu_stall must drop to 0 on THIS SAME cycle (see below) or
        // cpu_core.v's trap-entry block (gated on !mem_stall) would
        // never even see the fault, since mmu_busy alone would
        // otherwise hold mem_stall high for the whole walk regardless
        // of outcome.
        wire walk_fault = !hi_ok || !pte_v || !perm_ok || !in_range;
        assign mmu_fault = (state == S_WALK_READ) && walk_fault;

        // A real, found-live bug in an earlier version of this line:
        // written as plain `mmu_busy && !mmu_fault` (mmu_busy =
        // state!=S_IDLE), which forgot the very FIRST cycle of a fresh
        // miss entirely - while still in S_IDLE, "busy" reads false
        // regardless of whether this instruction needs a walk, so
        // mmu_stall read 0 for one full cycle before the FSM had even
        // started walking. cpu_core.v's pc advanced immediately on
        // that cycle (mem_stall=0), so BY THE TIME the walk actually
        // ran (next cycle), it was translating the WRONG (next)
        // instruction's address - caught immediately by tb_mmu.v (a
        // STORE landed at the untranslated raw address, and the
        // following LOAD then silently walked using stale/unrelated
        // state). Explicit per-state case instead, so each state's
        // condition is self-contained and cannot silently drop a case
        // like the OR-based version did:
        //   S_IDLE:       stall iff this cycle needs a walk that hasn't
        //                 started yet (a miss) - 0 on a hit, 0 if idle.
        //   S_WALK_ISSUE: always stall - pt_addr was just presented,
        //                 walk_read_data isn't valid yet (data_mem's
        //                 own SYNC_READ=1 registered capture lands at
        //                 the end of THIS cycle).
        //   S_WALK_READ:  stall unless the fault is firing THIS cycle
        //                 (must read 0 exactly then, or cpu_core.v's
        //                 own !mem_stall-gated trap-entry block would
        //                 never see it and the trap would silently
        //                 never fire).
        //   S_FILL:       always stall - the real access commits (or,
        //                 for a LOAD, its result is read) starting the
        //                 cycle AFTER this, once `have_ppn` is valid.
        assign mmu_stall = (state == S_IDLE)       ? (is_access && !have_hit) :
                            (state == S_WALK_ISSUE) ? 1'b1 :
                            (state == S_WALK_READ)  ? !mmu_fault :
                                                       1'b1; // S_FILL

        always @(posedge clk or posedge reset) begin
            if (reset) begin
                state      <= S_IDLE;
                have_valid <= 1'b0;
            end else begin
                case (state)
                    S_IDLE: begin
                        if (is_access && !have_hit) state <= S_WALK_ISSUE;
                    end

                    S_WALK_ISSUE: begin
                        // pt_addr is already presented (combinational,
                        // see walk_addr above) - just wait one cycle for
                        // data_mem's registered read to land.
                        state <= S_WALK_READ;
                    end

                    S_WALK_READ: begin
                        // Verbatim old S_WALK case body - walk_read_data
                        // is valid now, one cycle after S_WALK_ISSUE.
                        if (walk_fault) begin
                            state <= S_IDLE; // transient - see module header
                        end else begin
                            fill_ppn_r <= pte_ppn;
                            fill_r_r   <= pte_r;
                            fill_w_r   <= pte_w;
                            state      <= S_FILL;
                        end
                    end

                    S_FILL: begin
                        have_valid <= 1'b1;
                        have_vpn   <= vpn;
                        have_ppn   <= fill_ppn_r;
                        have_r     <= fill_r_r;
                        have_w     <= fill_w_r;
                        state      <= S_IDLE;
                    end

                    default: state <= S_IDLE;
                endcase

                // Deliberately outside/after the case, unconditional on
                // `state` - same reasoning as rv32i_core's own
                // tlb_flush ordering (see its module header): a PTB
                // write must never be able to block the walker FSM's
                // own transitions, and a same-cycle collision with
                // S_FILL is resolved in THIS statement's favor purely
                // by Verilog's last-non-blocking-write-wins rule -
                // harmless (forces one extra walk on the very next
                // access, nothing else observes the momentarily-filled
                // entry in between).
                if (ptb_changed) have_valid <= 1'b0;
            end
        end
    end
    endgenerate
endmodule
