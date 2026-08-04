// Memory-node adapter: sits at the ONE dedicated grid position hosting
// the shared memory (see [[project_noc_router]] - center placement,
// not a corner, per design review), wrapping the exact same data_mem.v
// shared_bus.v already used. Receives request flits on this node's req
// router's Local port, drives data_mem, and injects a response flit
// back into the resp router's Local port addressed to the request's
// own src coordinates.
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
    parameter MEM_BYTES       = 256,
    parameter REQ_FLIT_WIDTH  = 76,
    parameter RESP_FLIT_WIDTH = 36
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
    wire [1:0]  req_src_x        = req_in_flit[71:70];
    wire [1:0]  req_src_y        = req_in_flit[69:68];
    wire        req_is_write     = req_in_flit[67];
    wire [31:0] req_addr         = req_in_flit[66:35];
    wire [31:0] req_write_data   = req_in_flit[34:3];
    wire [1:0]  req_mem_size     = req_in_flit[2:1];
    wire        req_mem_unsigned = req_in_flit[0];

    reg        busy; // holding a not-yet-injected response
    reg [31:0] pending_read_data;
    reg [1:0]  pending_dest_x, pending_dest_y;

    assign req_in_ready = !busy;

    wire [31:0] dm_read_data;
    // mem_write only actually commits on the exact cycle a request is
    // freshly ACCEPTED (req_in_valid && !busy) - re-presenting the same
    // still-unaccepted flit on later cycles (if it were ever valid while
    // busy, which req_in_ready already prevents) must never re-fire it.
    data_mem #(.MEM_BYTES(MEM_BYTES)) mem (
        .clk(clk), .addr(req_addr), .write_data(req_write_data),
        .mem_write(req_in_valid && !busy && req_is_write),
        .mem_size(req_mem_size), .mem_unsigned(req_mem_unsigned),
        .read_data(dm_read_data)
    );

    // Response flit layout: [35:34]=dest_x [33:32]=dest_y [31:0]=read_data.
    assign resp_out_valid = busy;
    assign resp_out_flit  = {pending_dest_x, pending_dest_y, pending_read_data};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 1'b0;
            pending_read_data <= 32'b0;
            pending_dest_x <= 2'b0;
            pending_dest_y <= 2'b0;
        end else if (!busy) begin
            if (req_in_valid) begin
                busy <= 1'b1;
                // data_mem's read is combinational off THIS cycle's addr -
                // valid the same cycle regardless of whether this is a
                // read or a write (the requesting core just ignores it
                // for writes, per noc_core_adapter.v's matching comment).
                pending_read_data <= dm_read_data;
                pending_dest_x    <= req_src_x;
                pending_dest_y    <= req_src_y;
            end
        end else begin
            if (resp_out_ready) busy <= 1'b0; // handed off - ready for the next request
        end
    end
endmodule
