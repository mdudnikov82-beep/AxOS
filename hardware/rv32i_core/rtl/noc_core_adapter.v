// Translates a CPU core's existing shared-bus master port (bus_req/
// bus_addr/bus_write_data/bus_mem_write/bus_mem_size/bus_mem_unsigned/
// bus_grant/bus_read_data - EXACTLY the port cpu_core.v/
// cpu_core_pipelined.v already expose, see shared_bus.v) into traffic
// on this node's two Local router ports (request network out, response
// network in) - zero changes needed to either core module.
//
// bus_grant timing is the one thing that MUST match shared_bus.v's
// existing contract exactly, or the core's own mem_stall/pipeline-
// freeze logic breaks silently: grant and read_data are read on the
// SAME cycle the pipeline unfreezes and commits, so grant must fire
// only once the ANSWER has actually arrived back from memory - NOT the
// instant the request is merely accepted into the network. This was a
// real bug in the first draft of this design, caught by a design
// review before any RTL was written (see [[project_noc_router]]):
// grant-at-injection-time would unfreeze the pipeline while
// bus_read_data was still garbage, and orphan the eventual real
// response with nothing left listening for it.
//
// No transaction tag is needed to match a response back to the right
// core, for two independent, structural reasons (also confirmed by
// that same review): (1) a core's own mem_stall freezes its pipeline
// on ANY shared access until bus_grant fires, so there is NEVER more
// than one outstanding request per core - not a convention this
// module has to enforce, a fact already guaranteed by cpu_core.v/
// cpu_core_pipelined.v's existing structure; (2) every node has a
// distinct (x,y), and XY routing can only ever deliver a response to
// the one router whose coordinates match - so routing BY ADDRESS
// already disambiguates every core from every other one.
`timescale 1ns/1ps

module noc_core_adapter #(
    parameter COORD_BITS = 2, // must match the router.v instances this feeds
    parameter MY_X = 0,
    parameter MY_Y = 0,
    parameter MEM_X = 1,
    parameter MEM_Y = 1,
    parameter REQ_FLIT_WIDTH  = 76,
    parameter RESP_FLIT_WIDTH = 36
) (
    input  wire clk,
    input  wire reset,

    // Core-facing port - identical shape to shared_bus.v's per-core port.
    input  wire        bus_req,
    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_write_data,
    input  wire        bus_mem_write,
    input  wire [1:0]  bus_mem_size,
    input  wire        bus_mem_unsigned,
    output wire        bus_grant,
    output wire [31:0] bus_read_data,

    // Request-network Local port (injecting INTO this node's req router).
    output wire                      req_out_valid,
    output wire [REQ_FLIT_WIDTH-1:0] req_out_flit,
    input  wire                      req_out_ready,

    // Response-network Local port (arriving FROM this node's resp router).
    input  wire                       resp_in_valid,
    input  wire [RESP_FLIT_WIDTH-1:0] resp_in_flit,
    output wire                       resp_in_ready
);
    // Request flit layout (top 2*COORD_BITS bits are dest_x/dest_y -
    // router.v's only requirement - everything else below is opaque to
    // it): {dest_x, dest_y, src_x, src_y, is_write, addr[31:0],
    // write_data[31:0], mem_size[1:0], mem_unsigned}.
    wire [REQ_FLIT_WIDTH-1:0] req_flit_build = {
        MEM_X[COORD_BITS-1:0], MEM_Y[COORD_BITS-1:0], MY_X[COORD_BITS-1:0], MY_Y[COORD_BITS-1:0],
        bus_mem_write, bus_addr, bus_write_data, bus_mem_size, bus_mem_unsigned
    };

    // Response flit layout: {dest_x, dest_y, read_data[31:0]}
    // (no src needed - the only thing that can ever address a response
    // to (MY_X,MY_Y) is the memory node answering THIS core's own
    // request, per the module-header reasoning above).
    wire [31:0] resp_read_data = resp_in_flit[31:0];

    // sent: have we successfully injected the current request into the
    // network yet? The core holds bus_req/bus_addr/etc perfectly stable
    // for as long as mem_stall (i.e. !bus_grant) lasts - see
    // cpu_core_pipelined.v - so this adapter needs no register of its
    // own for the request's DATA, only this 1-bit injection-progress flag.
    reg sent;

    assign req_out_valid = bus_req && !sent;
    assign req_out_flit  = req_flit_build;

    // Always ready for a response - at most one is EVER outstanding for
    // this node (see module header), so there's never a "which one do I
    // keep" ambiguity to buffer against.
    assign resp_in_ready = 1'b1;

    assign bus_grant     = sent && resp_in_valid;
    assign bus_read_data = resp_read_data;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sent <= 1'b0;
        end else if (!sent) begin
            if (bus_req && req_out_ready) sent <= 1'b1;
        end else begin
            if (resp_in_valid) sent <= 1'b0; // round trip complete
        end
    end
endmodule
