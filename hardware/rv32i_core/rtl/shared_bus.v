// Round-robin arbiter + one shared data_mem instance, giving the
// P-core and E-core a real communication channel (a small memory
// region both can read/write) instead of each only ever seeing its
// own private memory. A LONE requester is always granted immediately
// (no reason to make an uncontended access wait); on an actual TIE,
// the grant alternates via last_granted so neither core can be
// permanently starved by the other - unlike a fixed-priority arbiter,
// where a core that always wins ties could, in principle, lock the
// other out forever.
`timescale 1ns/1ps

module shared_bus #(
    parameter MEM_BYTES = 256
) (
    input  wire        clk,
    input  wire        reset,

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
    // 0 = P was last granted, 1 = E was last granted.
    reg last_granted;

    assign p_grant = p_req && (!e_req || last_granted);
    assign e_grant = e_req && (!p_req || !last_granted);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Fiction "E was last granted" so P wins the FIRST real
            // tie after reset - an arbitrary but fixed, testable choice.
            last_granted <= 1'b1;
        end else begin
            if (p_grant)      last_granted <= 1'b0;
            else if (e_grant) last_granted <= 1'b1;
            // neither granted this cycle: hold (no update)
        end
    end

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
