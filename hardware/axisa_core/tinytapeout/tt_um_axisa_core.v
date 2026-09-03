// Tiny Tapeout adapter for AxISA's cpu_core.v - shrinks cpu_core's own
// 157-pin native interface down to Tiny Tapeout's FIXED 24-pin tt_um_*
// signature (ui_in[7:0]/uo_out[7:0]/uio_in/out/oe[7:0]/ena/clk/rst_n).
// Structurally the same "thin instantiating wrapper" idea as
// asic/cpu_core_top.v (no added logic beyond pin adaptation + a fixed
// program), just for a much narrower pin budget.
//
// Permanent program: sw/mini_shell_loop.axasm - a real, working UART
// shell (prompt/echo/"hi" command/OK-or-? reply) that loops forever
// instead of halting, since there's no host to notice a HALT signal
// and restart real silicon. See that file's own header for why the
// loop is register-safe.
//
// Pin mapping (24 pins total, fully accounted for):
//   clk            -> cpu_core.clk               direct
//   rst_n (act-lo) -> cpu_core.reset (act-hi)     reset = ~rst_n, no
//                                                  synchronizer - matches
//                                                  this project's existing
//                                                  precedent (no reset-sync
//                                                  trees anywhere in rtl/)
//   ena            -> unused, tied off            per TT convention
//   ui_in[7:0]     -> uart_rx_data_in[7:0]        full-byte fit
//   uo_out[7:0]    -> uart_tx_data[7:0]           full-byte fit
//   uio[0] out     -> uart_tx_valid               uio_oe[0]=1
//   uio[1] in      -> uart_rx_ready_in            uio_oe[1]=0
//   uio[2] out     -> uart_rx_ack                 uio_oe[2]=1
//   uio[3] out     -> halted                      uio_oe[3]=1 (reads 0
//                                                  always - see
//                                                  mini_shell_loop.axasm's
//                                                  header, HALT is never
//                                                  reached by design)
//   uio[7:4]       -> reserved, unused            uio_oe[7:4]=0
//
// irq_in: tied 1'b0, no pin spent. Provably dead for this program -
// cpu_core.v's ie_r (interrupt-enable) can only be set via a
// privileged MVSR write, which mini_shell_loop.axasm never issues, so
// irq_taken is always false regardless of any external irq_in value.
//
// Shared-bus/NoC port (bus_req/bus_addr/bus_write_data/bus_mem_write/
// bus_mem_size/bus_mem_unsigned/bus_grant/bus_read_data): tied off
// internally (bus_grant=0, bus_read_data=0), not exposed to any pin.
// mini_shell_loop.axasm only ever touches addresses below
// SHARED_MEM_BASE (0x2000 by default), so is_shared_access is
// provably always false for this program.
//
// FOOTGUN if this wrapper is ever reused with a DIFFERENT
// INSTR_INIT_FILE: if that program issues a LOAD/STORE into
// [SHARED_MEM_BASE, SHARED_MEM_BASE+SHARED_MEM_BYTES), the access will
// stall forever, since mem_stall = is_shared_access && !bus_grant and
// bus_grant is hard-tied low here. Fine for mini_shell_loop.axasm,
// NOT fine for an arbitrary future program without revisiting this.
`timescale 1ns/1ps

module tt_um_axisa_core (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire        ena,
    input  wire        clk,
    input  wire        rst_n
);
    // ena and uio_in[7:2]/uio_in[0] are intentionally unread - see the
    // pin-mapping table above (ena ignored per TT convention, those
    // uio bits are reserved/unused spares).
    wire reset = ~rst_n;

    wire        halted;
    wire [31:0] tohost_value;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;
    wire        uart_rx_ack;

    cpu_core #(
        .INSTR_INIT_FILE("../sw/mini_shell_loop.hex")
    ) core (
        .clk(clk), .reset(reset),
        .halted(halted), .tohost_value(tohost_value),
        .irq_in(1'b0),
        .bus_req(), .bus_addr(), .bus_write_data(),
        .bus_mem_write(), .bus_mem_size(), .bus_mem_unsigned(),
        .bus_grant(1'b0), .bus_read_data(32'b0),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(ui_in), .uart_rx_ready_in(uio_in[1]),
        .uart_rx_ack(uart_rx_ack)
    );

    assign uo_out    = uart_tx_data;
    assign uio_out    = {4'b0, halted, uart_rx_ack, 1'b0, uart_tx_valid};
    assign uio_oe     = 8'b0000_1101;
endmodule
