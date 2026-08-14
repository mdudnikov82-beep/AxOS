// Real place-and-route wrapper for cpu_core.v (the single-cycle base
// RV32I core, no FPU/pipeline) - mirrors AxISA's own
// hardware/axisa_core/fpga/cpu_core_fpga_top_pnr.v byte-for-byte in
// intent, built specifically to get an apples-to-apples nextpnr-ecp5
// comparison against AxISA's cpu_core.v (see
// [[project_axisa_synthesis_check]]/[[project_router_pipelining]] for
// the AxISA-side numbers this is being compared against). Loads a
// real program (sw/test1.hex) instead of leaving instr_mem blackboxed -
// place-and-route needs a fully concrete netlist, a blackboxed module
// has nothing for nextpnr to place.
`timescale 1ns/1ps

module cpu_core_fpga_top (
    input  wire        clk,
    input  wire        reset,
    output wire        halted,
    output wire [31:0] tohost_value,
    output wire        page_fault,

    output wire        bus_req,
    output wire [31:0] bus_addr,
    output wire [31:0] bus_write_data,
    output wire        bus_mem_write,
    output wire [1:0]  bus_mem_size,
    output wire        bus_mem_unsigned,
    input  wire        bus_grant,
    input  wire [31:0] bus_read_data
);
    cpu_core #(
        .INSTR_INIT_FILE("sw/test1.hex")
    ) core (
        .clk(clk), .reset(reset),
        .halted(halted), .tohost_value(tohost_value), .page_fault(page_fault),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(bus_grant), .bus_read_data(bus_read_data)
    );
endmodule
