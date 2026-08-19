// Memory Management Unit: Sv32-inspired two-level page-table walker +
// small fully-associative TLB, giving each core (cpu_core.v/
// cpu_core_pipelined.v) real virtual-to-physical translation for its
// own private data_mem.v accesses - see [[project_mmu]] for the full
// design rationale (a design review before any RTL caught two real
// bugs: a walker/data_mem port-sharing hazard, and an interaction with
// cpu_core_pipelined.v's existing fpu_div_stall logic).
//
// SCOPE (deliberately narrow, matching this project's no-CSR/no-
// exception-infrastructure reality): translates DATA accesses to a
// core's own private data_mem ONLY. Instruction fetch stays physically
// addressed (no I-side MMU). The shared-bus/NoC region
// [SHARED_MEM_BASE, SHARED_MEM_BASE+SHARED_MEM_BYTES) is decoded on the
// RAW (virtual) address BEFORE this module is even consulted - exactly
// as it already was before the MMU existed - so an access routed to
// the shared bus never touches this module at all, and MMU-stall /
// shared-bus-arbitration-stall are mutually exclusive by construction,
// not by priority ordering.
//
// MMU_ENABLE=0 (the default) makes this module a pure wire-through
// (paddr=vaddr, stall=0, fault=0) - every existing test program with no
// page table ever set up keeps working with ZERO behavior change.
//
// PTE format (32 bits, Sv32-like positioning but simplified - no U/G/A/D
// bits, no superpages, PPN narrowed to 20 bits so PPN<<12 always fits a
// plain 32-bit physical address, matching this project's actual address
// width rather than Sv32's full 34-bit physical reach):
//   [31:12] = PPN (physical page number - also the physical page's own
//             32-bit base address once left-shifted by 12, i.e. simply
//             the PTE with its low 12 bits masked to zero)
//   [2]     = W (writable)
//   [1]     = R (readable)
//   [0]     = V (valid)
// Level-1 PTE's PPN field points at the physical page holding the
// level-0 table (always a pointer, never a leaf - superpages are not
// supported, a deliberate simplification). Level-0 PTE's PPN field
// points at the actual data page (always a leaf).
//
// Fault conditions (all funnel into the SAME page_fault path - there is
// no principled reason to distinguish "invalid PTE" from "permission
// violation" when both terminate the same way, absent real exception
// hardware): V=0 at either level, a write hitting a page without W, a
// read hitting a page without R (checked on every TLB HIT too, not just
// during the walk - a page's permissions can only ever get less
// permissive from a cached lookup's perspective, so re-checking is
// cheap and correct), or a translated physical page base landing at or
// beyond DATA_MEM_BYTES (data_mem.v itself does no bounds checking, so
// a wrong-but-nonzero PPN would otherwise silently read/write out of
// range instead of faulting).
//
// TLB: TLB_ENTRIES-way fully-associative (the same "N-way parallel
// compare + priority-select mux" idiom shared_bus.v/router.v already
// use for arbitration), round-robin replacement (no LRU, matching this
// project's established "rotate, don't rank" preference). A PTE's PPN
// must never alias the physical range the page tables themselves occupy
// (nothing stops a badly-built test page table from making the walker
// read/write its own live table, since the walker uses the same
// physical data_mem as everything else - a documented invariant for
// whoever builds a page table, not a hardware guarantee).
//
// TLB invalidation: `tlb_flush` (pulsed by SFENCE.VMA in both cores)
// clears every tlb_valid bit. Critical property, found by a design
// review BEFORE this was built: the flush must NEVER be able to block
// the walker FSM's own state transitions, or a flush held asserted for
// multiple cycles (which genuinely happens in the pipelined core - see
// cpu_core_pipelined.v's one-shot tlb_flush comment for why it's
// one-shot specifically to avoid this) could permanently prevent an
// unrelated in-flight walk from ever reaching S_IDLE, since mmu_stall
// (mmu_busy) would never clear - a real deadlock the review traced
// through in detail before any RTL existed. The fix: every `case(state)`
// branch below transitions purely on its own terms, and the flush's
// TLB-clearing loop is a SEPARATE, unconditional statement placed AFTER
// the case block in the same always block - relying on the standard,
// deterministic Verilog rule that multiple non-blocking assignments to
// the same variable in one time step resolve to whichever is scheduled
// LAST in program order. A same-cycle collision with S_FILL just means
// that walk's freshly-written entry is immediately wiped again -
// harmless (forces one extra walk on retry, nothing consumes a TLB fill
// beyond the cycle it's produced), never a correctness bug.
`timescale 1ns/1ps

module mmu #(
    parameter MMU_ENABLE    = 0,
    parameter TLB_ENTRIES   = 4, // must be a power of 2 (round-robin pointer wraps via plain overflow)
    parameter DATA_MEM_BYTES = 8192
) (
    input  wire        clk,
    input  wire        reset,

    input  wire [31:0] vaddr,
    input  wire        is_access, // a real load or store this cycle (shared-bus accesses excluded by the caller already)
    input  wire        is_write,
    input  wire [31:0] page_table_base,
    input  wire        tlb_flush, // SFENCE.VMA - see the TLB invalidation comment above



    output wire [31:0] paddr,      // valid combinationally whenever !mmu_stall
    output wire        mmu_stall,
    output wire        page_fault, // sticky - once set, stays set (core is meant to freeze)
    output wire [31:0] fault_vaddr,

    // This core's OWN data_mem port - the walker issues its PTE reads
    // through the SAME physical memory the core's LSU already uses, so
    // the caller MUST mux walk_addr into data_mem's addr input (and
    // force data_mem's mem_write to 0) whenever walk_active is high, or
    // a pending stalled store would corrupt whatever physical address
    // the walker happens to be reading that cycle - a real bug a design
    // review caught before this was ever built.
    output wire        walk_active,
    output wire [31:0] walk_addr,
    input  wire [31:0] walk_read_data
);
    generate
    if (MMU_ENABLE == 0) begin: bypass
        assign paddr        = vaddr;
        assign mmu_stall    = 1'b0;
        assign page_fault   = 1'b0;
        assign fault_vaddr  = 32'b0;
        assign walk_active  = 1'b0;
        assign walk_addr    = 32'b0;
    end else begin: real_mmu
        localparam S_IDLE     = 3'd0;
        // Split from single S_L1/S_L0 states (design review before this
        // split: see [[project_axisa_synthesis_check]] - data_mem.v's
        // own read is now registered (SYNC_READ=1) to fix ECP5
        // block-RAM inference, so walk_read_data is no longer valid the
        // same cycle walk_addr is first presented). Each _ISSUE state
        // presents its address and does nothing else; each _READ state
        // is the ENTIRE old S_L1/S_L0 case body, verbatim, now reading
        // the registered walk_read_data one cycle later.
        localparam S_L1_ISSUE = 3'd1;
        localparam S_L1_READ  = 3'd2;
        localparam S_L0_ISSUE = 3'd3;
        localparam S_L0_READ  = 3'd4;
        localparam S_FILL     = 3'd5;
        localparam S_FAULT    = 3'd6;

        localparam RR_BITS = $clog2(TLB_ENTRIES);

        reg [2:0]  state;
        reg [19:0] l1_ppn_r;
        reg [19:0] fill_ppn_r;
        reg        fill_r_r, fill_w_r;
        reg [31:0] fault_vaddr_r;
        reg [RR_BITS-1:0] rr_ptr;

        reg [TLB_ENTRIES-1:0] tlb_valid;
        reg [19:0] tlb_vpn [0:TLB_ENTRIES-1];
        reg [19:0] tlb_ppn [0:TLB_ENTRIES-1];
        reg        tlb_r   [0:TLB_ENTRIES-1];
        reg        tlb_w   [0:TLB_ENTRIES-1];

        wire [9:0]  vpn1 = vaddr[31:22];
        wire [9:0]  vpn0 = vaddr[21:12];
        wire [19:0] vpn  = vaddr[31:12];

        // ---- TLB lookup (combinational every cycle) ----
        wire [TLB_ENTRIES-1:0] hit_vec;
        genvar gi;
        for (gi = 0; gi < TLB_ENTRIES; gi = gi + 1) begin: tlb_cmp
            assign hit_vec[gi] = tlb_valid[gi] && (tlb_vpn[gi] == vpn);
        end

        reg [19:0] hit_ppn;
        reg        hit_r, hit_w, tlb_hit;
        integer k;
        always @(*) begin
            hit_ppn = 20'b0; hit_r = 1'b0; hit_w = 1'b0; tlb_hit = 1'b0;
            for (k = 0; k < TLB_ENTRIES; k = k + 1) begin
                if (hit_vec[k]) begin
                    hit_ppn = tlb_ppn[k];
                    hit_r   = tlb_r[k];
                    hit_w   = tlb_w[k];
                    tlb_hit = 1'b1;
                end
            end
        end

        // Permission re-checked on every hit, not just during the walk -
        // a page's cached permissions are exactly what was true when it
        // was filled (see module header: page tables are write-once, so
        // this can't go stale), but a LOAD and a STORE to the same
        // cached page still need their OWN, independent check each time.
        wire hit_perm_ok = is_write ? hit_w : hit_r;
        wire hit_ok      = tlb_hit && hit_perm_ok;

        assign paddr = {hit_ppn, vaddr[11:0]};

        wire mmu_busy = (state != S_IDLE);
        assign mmu_stall   = mmu_busy || (is_access && !hit_ok);
        assign page_fault  = (state == S_FAULT);
        assign fault_vaddr = fault_vaddr_r;

        wire [31:0] l1_addr = page_table_base + {20'b0, vpn1, 2'b00};
        wire [31:0] l0_addr = {l1_ppn_r, 12'b0} | {20'b0, vpn0, 2'b00};

        assign walk_active = (state == S_L1_ISSUE) || (state == S_L1_READ) ||
                              (state == S_L0_ISSUE) || (state == S_L0_READ);
        assign walk_addr   = (state == S_L1_ISSUE || state == S_L1_READ) ? l1_addr : l0_addr;

        wire [19:0] l0_ppn_field = walk_read_data[31:12];

        always @(posedge clk or posedge reset) begin
            if (reset) begin
                state    <= S_IDLE;
                rr_ptr   <= {RR_BITS{1'b0}};
                fault_vaddr_r <= 32'b0;
                for (k = 0; k < TLB_ENTRIES; k = k + 1) tlb_valid[k] <= 1'b0;
            end else begin
                case (state)
                    S_IDLE: begin
                        if (is_access) begin
                            if (tlb_hit) begin
                                if (!hit_perm_ok) begin
                                    fault_vaddr_r <= vaddr;
                                    state <= S_FAULT;
                                end
                                // else: hit_ok - translation already valid
                                // combinationally this same cycle, no
                                // state change needed.
                            end else begin
                                state <= S_L1_ISSUE;
                            end
                        end
                    end

                    S_L1_ISSUE: begin
                        // l1_addr already presented (combinational, see
                        // walk_addr above) - wait one cycle for
                        // data_mem's registered read to land.
                        state <= S_L1_READ;
                    end

                    S_L1_READ: begin
                        // Verbatim old S_L1 case body - walk_read_data
                        // is valid now, one cycle after S_L1_ISSUE.
                        if (!walk_read_data[0]) begin
                            fault_vaddr_r <= vaddr;
                            state <= S_FAULT;
                        end else begin
                            l1_ppn_r <= walk_read_data[31:12];
                            state    <= S_L0_ISSUE;
                        end
                    end

                    S_L0_ISSUE: begin
                        // l0_addr already presented (combinational,
                        // depends on l1_ppn_r which S_L1_READ just
                        // latched) - wait one cycle for data_mem's
                        // registered read to land.
                        state <= S_L0_READ;
                    end

                    S_L0_READ: begin
                        // Verbatim old S_L0 case body - walk_read_data
                        // is valid now, one cycle after S_L0_ISSUE.
                        if (!walk_read_data[0]) begin
                            fault_vaddr_r <= vaddr;
                            state <= S_FAULT;
                        end else if (is_write && !walk_read_data[2]) begin
                            fault_vaddr_r <= vaddr;
                            state <= S_FAULT;
                        end else if (!is_write && !walk_read_data[1]) begin
                            fault_vaddr_r <= vaddr;
                            state <= S_FAULT;
                        end else if ({l0_ppn_field, 12'b0} >= DATA_MEM_BYTES) begin
                            fault_vaddr_r <= vaddr;
                            state <= S_FAULT;
                        end else begin
                            fill_ppn_r <= l0_ppn_field;
                            fill_r_r   <= walk_read_data[1];
                            fill_w_r   <= walk_read_data[2];
                            state      <= S_FILL;
                        end
                    end

                    S_FILL: begin
                        // TLB write commits on THIS edge - mmu_stall only
                        // reads 0 again the cycle AFTER this one (state
                        // becomes S_IDLE only now), so there is no window
                        // where the core could observe the stall clearing
                        // before the fill has actually landed.
                        tlb_valid[rr_ptr] <= 1'b1;
                        tlb_vpn[rr_ptr]   <= vpn;
                        tlb_ppn[rr_ptr]   <= fill_ppn_r;
                        tlb_r[rr_ptr]     <= fill_r_r;
                        tlb_w[rr_ptr]     <= fill_w_r;
                        rr_ptr            <= rr_ptr + 1'b1;
                        state             <= S_IDLE;
                    end

                    S_FAULT: begin
                        // Sticky forever - no transition out. mmu_stall
                        // stays 1 (mmu_busy is true), page_fault stays 1,
                        // the core stays frozen. Distinct from `halted`
                        // deliberately (see module header / cpu_core.v's
                        // integration) so a testbench can tell "the
                        // program legitimately finished" apart from
                        // "it page-faulted and got stuck looking similar."
                    end

                    default: state <= S_FAULT;
                endcase

                // Deliberately OUTSIDE and AFTER the case statement above,
                // and NOT gated on `state` - see the TLB invalidation
                // header comment for why: this must never be able to
                // prevent the case statement's own transitions (that's
                // what avoids the deadlock a design review found), and a
                // same-cycle collision with S_FILL's write to
                // tlb_valid[rr_ptr] is resolved in this statement's favor
                // purely because it's scheduled after it, per Verilog's
                // last-non-blocking-write-wins rule for the same variable
                // in one time step - not because of any explicit priority
                // logic here.
                if (tlb_flush) begin
                    for (k = 0; k < TLB_ENTRIES; k = k + 1) tlb_valid[k] <= 1'b0;
                end
            end
        end
    end
    endgenerate
endmodule
