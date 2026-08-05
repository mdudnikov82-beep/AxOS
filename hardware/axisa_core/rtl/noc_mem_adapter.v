// Memory-node adapter: sits at the ONE dedicated grid position hosting
// the shared memory (see [[project_noc_router]] - center placement,
// not a corner, per design review), wrapping shared_mem_backing.v (a
// verbatim, renamed-only copy of rv32i_core's own byte-addressable
// data_mem.v - renamed here specifically to avoid colliding with this
// project's own, unrelated word-addressed data_mem.v used for AxISA's
// private per-core memory). This whole file (noc_mem_adapter.v) is
// itself ported byte-for-byte, unmodified, from rv32i_core - it only
// speaks the generic bus_req/addr/write_data/mem_write/mem_size/
// mem_unsigned protocol, with zero ISA-specific assumptions anywhere
// in it. Receives request flits on this node's req router's Local
// port, drives shared_mem_backing, and injects a response flit back
// into the resp router's Local port addressed to the request's own
// src coordinates.
//
// Single-outstanding-at-sink throttle (design review point 2): this
// adapter refuses ("not ready" on the request side) to accept a NEW
// request until the PREVIOUS one's response has actually been handed
// off into the response network. With no queue/buffer here, accepting
// a second request before the first's response drains would have
// nowhere to hold the pending result. Net effect: this node still
// processes exactly one transaction end-to-end at a time - the NoC
// decentralizes ROUTING/arbitration relative to the old shared_bus.v,
// it does not add memory bandwidth, and that's an accepted, deliberate
// tradeoff, not an oversight.
`timescale 1ns/1ps

module noc_mem_adapter #(
    parameter COORD_BITS = 3, // must match the router.v instances this feeds
    parameter MEM_BYTES       = 256,
    parameter REQ_FLIT_WIDTH  = 92, // 8*COORD_BITS + 68 (2 roles [dest,src] x 4 axes + fixed payload) at COORD_BITS=3
    parameter RESP_FLIT_WIDTH = 44  // 4*COORD_BITS + 32 (1 role [dest] x 4 axes + read_data) at COORD_BITS=3
) (
    input  wire clk,
    input  wire reset,

    // Request-network Local port (flits ARRIVE here from the network).
    input  wire                      req_in_valid,
    input  wire [REQ_FLIT_WIDTH-1:0] req_in_flit,
    output wire                      req_in_ready,

    // Response-network Local port (flits are INJECTED here into the network).
    output wire                       resp_out_valid,
    output wire [RESP_FLIT_WIDTH-1:0] resp_out_flit,
    input  wire                       resp_out_ready
);
    // Request flit layout - see noc_core_adapter.v's matching comment.
    // The fixed-size payload (is_write..mem_unsigned, 68 bits) always
    // sits at the bottom regardless of COORD_BITS or how many coordinate
    // fields sit above it; only src_w/src_x/src_y/src_z's position
    // depends on COORD_BITS (they sit directly above the payload, below
    // dest_x/dest_y/dest_z/dest_w - which this adapter never needs to
    // read, since routing already happened by the time a flit gets
    // here). Indexed by PAYLOAD_BITS + role*COORD_BITS (role 0=src_z,
    // 1=src_y, 2=src_x, 3=src_w, matching noc_core_adapter.v's {...,
    // src_w, src_x, src_y, src_z, payload} concatenation order, LSB-most
    // coordinate closest to the payload) rather than hand-recomputed
    // magic numbers - this is the third time this exact offset needed
    // re-deriving (2-coordinate, then 3-axis, now 4-axis), and the 4th
    // axis needed ZERO changes to the existing 3 role lines below,
    // confirmed by design review before this was written - only a new
    // role=3 line was added.
    localparam PAYLOAD_BITS = 68;
    wire        req_is_write     = req_in_flit[67];
    wire [31:0] req_addr         = req_in_flit[66:35];
    wire [31:0] req_write_data   = req_in_flit[34:3];
    wire [1:0]  req_mem_size     = req_in_flit[2:1];
    wire        req_mem_unsigned = req_in_flit[0];
    wire [COORD_BITS-1:0] req_src_z = req_in_flit[PAYLOAD_BITS + 0*COORD_BITS +: COORD_BITS];
    wire [COORD_BITS-1:0] req_src_y = req_in_flit[PAYLOAD_BITS + 1*COORD_BITS +: COORD_BITS];
    wire [COORD_BITS-1:0] req_src_x = req_in_flit[PAYLOAD_BITS + 2*COORD_BITS +: COORD_BITS];
    wire [COORD_BITS-1:0] req_src_w = req_in_flit[PAYLOAD_BITS + 3*COORD_BITS +: COORD_BITS];

    reg        busy; // holding a not-yet-injected response
    reg [31:0] pending_read_data;
    reg [COORD_BITS-1:0] pending_dest_x, pending_dest_y, pending_dest_z, pending_dest_w;

    assign req_in_ready = !busy;

    wire [31:0] dm_read_data;
    // mem_write only actually commits on the exact cycle a request is
    // freshly ACCEPTED (req_in_valid && !busy) - re-presenting the same
    // still-unaccepted flit on later cycles (if it were ever valid while
    // busy, which req_in_ready already prevents) must never re-fire it.
    shared_mem_backing #(.MEM_BYTES(MEM_BYTES)) mem (
        .clk(clk), .addr(req_addr), .write_data(req_write_data),
        .mem_write(req_in_valid && !busy && req_is_write),
        .mem_size(req_mem_size), .mem_unsigned(req_mem_unsigned),
        .read_data(dm_read_data)
    );

    // Response flit layout: {dest_x, dest_y, dest_z, dest_w, read_data[31:0]}.
    assign resp_out_valid = busy;
    assign resp_out_flit  = {pending_dest_x, pending_dest_y, pending_dest_z, pending_dest_w, pending_read_data};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 1'b0;
            pending_read_data <= 32'b0;
            pending_dest_x <= {COORD_BITS{1'b0}};
            pending_dest_y <= {COORD_BITS{1'b0}};
            pending_dest_z <= {COORD_BITS{1'b0}};
            pending_dest_w <= {COORD_BITS{1'b0}};
        end else if (!busy) begin
            if (req_in_valid) begin
                busy <= 1'b1;
                // shared_mem_backing's read is combinational off THIS cycle's addr -
                // valid the same cycle regardless of whether this is a
                // read or a write (the requesting core just ignores it
                // for writes, per noc_core_adapter.v's matching comment).
                pending_read_data <= dm_read_data;
                pending_dest_x    <= req_src_x;
                pending_dest_y    <= req_src_y;
                pending_dest_z    <= req_src_z;
                pending_dest_w    <= req_src_w;
            end
        end else begin
            if (resp_out_ready) busy <= 1'b0; // handed off - ready for the next request
        end
    end
endmodule
