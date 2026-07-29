// Fixed-priority arbiter + one shared data_mem instance, giving the
// P-core and E-core a real communication channel (a small memory
// region both can read/write) instead of each only ever seeing its
// own private memory. P always wins a simultaneous request - a known,
// documented simplification (real designs would round-robin to avoid
// starving E permanently); not a problem for a 2-core proof where
// P's own poll loop only asks for the bus every few cycles, not
// every single cycle.
`timescale 1ns/1ps

module shared_bus #(
    parameter MEM_BYTES = 256
) (
    input  wire        clk,

    input  wire        p_req,
    input  wire [31:0]  p_addr,
    input  wire [31:0]  p_write_data,
    input  wire         p_mem_write,
    input  wire [1:0]   p_mem_size,
    input  wire         p_mem_unsigned,
    output wire         p_grant,
    output wire [31:0]  p_read_data,

    input  wire        e_req,
    input  wire [31:0]  e_addr,
    input  wire [31:0]  e_write_data,
    input  wire         e_mem_write,
    input  wire [1:0]   e_mem_size,
    input  wire         e_mem_unsigned,
    output wire         e_grant,
    output wire [31:0]  e_read_data
);
    assign p_grant = p_req;
    assign e_grant = e_req && !p_req;

    wire [31:0] sel_addr         = p_grant ? p_addr         : e_addr;
    wire [31:0] sel_write_data   = p_grant ? p_write_data   : e_write_data;
    wire        sel_mem_write    = p_grant ? p_mem_write    : (e_grant && e_mem_write);
    wire [1:0]  sel_mem_size     = p_grant ? p_mem_size     : e_mem_size;
    wire        sel_mem_unsigned = p_grant ? p_mem_unsigned : e_mem_unsigned;

    wire [31:0] shared_read_data;
    data_mem #(.MEM_BYTES(MEM_BYTES)) mem (
        .clk(clk), .addr(sel_addr), .write_data(sel_write_data),
        .mem_write(sel_mem_write), .mem_size(sel_mem_size),
        .mem_unsigned(sel_mem_unsigned), .read_data(shared_read_data)
    );

    // Whichever core didn't win this cycle simply ignores this value
    // (it's stalling and won't latch anything from the memory stage).
    assign p_read_data = shared_read_data;
    assign e_read_data = shared_read_data;
endmodule
