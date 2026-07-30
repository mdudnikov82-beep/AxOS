// N-way round-robin arbiter + one shared data_mem instance, giving up
// to NUM_CORES cores a real communication channel (a small memory
// region all of them can read/write) instead of each only ever seeing
// its own private memory. A LONE requester is always granted
// immediately (no reason to make an uncontended access wait); on an
// actual TIE among several requesters, the grant rotates via
// last_granted so no core can be permanently starved by the others.
//
// Ports use flattened vectors (addr_flat[i*32 +: 32] for core i)
// rather than Verilog unpacked-array ports, treated here as a
// portability/tooling risk not worth taking on this toolchain.
//
// Fairness bound: any requester that keeps holding req is granted
// within at most NUM_CORES-1 cycles of contention - but that bound
// depends on the requester actually HOLDING req until granted, which
// this module doesn't enforce itself. Every core wired to this bus
// already does that via its own mem_stall gating (is_shared_access &&
// !bus_grant retries the SAME request every cycle) - the guarantee
// lives there, not here.
`timescale 1ns/1ps

module shared_bus #(
    parameter NUM_CORES = 4,
    parameter MEM_BYTES = 256
) (
    input  wire clk,
    input  wire reset,

    input  wire [NUM_CORES-1:0]    req,
    input  wire [NUM_CORES*32-1:0] addr_flat,
    input  wire [NUM_CORES*32-1:0] write_data_flat,
    input  wire [NUM_CORES-1:0]    mem_write,
    input  wire [NUM_CORES*2-1:0]  mem_size_flat,
    input  wire [NUM_CORES-1:0]    mem_unsigned,
    output wire [NUM_CORES-1:0]    grant,
    // Broadcast to every requester, same value regardless of who's
    // granted - a non-granted core simply never consumes it (its own
    // mem_stall gating prevents that), same reasoning as the earlier
    // 2-way version, unaffected by how many OTHER cores exist.
    output wire [31:0]             read_data
);
    localparam IDX_BITS = $clog2(NUM_CORES);

    // Index of the core granted last (or the NUM_CORES-1 reset
    // fiction, so core 0 wins the very first tie after reset - the
    // direct N-way analog of the 2-way version's "last_granted<=1
    // makes P win first").
    reg [IDX_BITS-1:0] last_granted;

    // Rotating-priority grant: scan starting at last_granted+1
    // (wrapping mod NUM_CORES), grant the FIRST requester found in
    // that order. Confirmed by design review: this bounds any
    // continuously-requesting core's wait to at most NUM_CORES-1
    // cycles regardless of reset phase or which subset of other cores
    // is requesting.
    integer gi;
    reg [IDX_BITS-1:0] chosen;
    reg chosen_valid;
    always @(*) begin
        chosen_valid = 1'b0;
        chosen = {IDX_BITS{1'b0}};
        for (gi = 0; gi < NUM_CORES; gi = gi + 1) begin
            if (!chosen_valid && req[(last_granted + 1 + gi) % NUM_CORES]) begin
                chosen = (last_granted + 1 + gi) % NUM_CORES;
                chosen_valid = 1'b1;
            end
        end
    end

    genvar gk;
    generate
        for (gk = 0; gk < NUM_CORES; gk = gk + 1) begin: grant_gen
            assign grant[gk] = chosen_valid && (chosen == gk);
        end
    endgenerate

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            last_granted <= NUM_CORES - 1;
        end else if (chosen_valid) begin
            last_granted <= chosen;
        end
        // no grant this cycle: hold (no update)
    end

    // N-way priority-select mux feeding the single underlying memory -
    // only one grant[i] is ever set, so "last match wins" here is a
    // clean one-hot mux, not a real priority chain. The all-zero
    // defaults are the safety net for chosen_valid==0 (nobody granted).
    reg [31:0] sel_addr, sel_write_data;
    reg        sel_mem_write, sel_mem_unsigned;
    reg [1:0]  sel_mem_size;
    integer si;
    always @(*) begin
        sel_addr = 32'b0; sel_write_data = 32'b0; sel_mem_write = 1'b0;
        sel_mem_size = 2'b0; sel_mem_unsigned = 1'b0;
        for (si = 0; si < NUM_CORES; si = si + 1) begin
            if (grant[si]) begin
                sel_addr         = addr_flat[si*32 +: 32];
                sel_write_data   = write_data_flat[si*32 +: 32];
                sel_mem_write    = mem_write[si];
                sel_mem_size     = mem_size_flat[si*2 +: 2];
                sel_mem_unsigned = mem_unsigned[si];
            end
        end
    end

    data_mem #(.MEM_BYTES(MEM_BYTES)) mem (
        .clk(clk), .addr(sel_addr), .write_data(sel_write_data),
        .mem_write(sel_mem_write), .mem_size(sel_mem_size),
        .mem_unsigned(sel_mem_unsigned), .read_data(read_data)
    );
endmodule
