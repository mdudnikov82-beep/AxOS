// Tiny Tapeout wrapper test - drives/observes tt_um_axisa_core ONLY
// through its 24-pin tt_um interface (ui_in/uo_out/uio_in/uio_out/
// uio_oe/ena/clk/rst_n), never cpu_core's native ports directly -
// that's the whole point versus tb_uart_shell.v, which this borrows
// its RX-handshake-driver/TX-capture structure from.
//
// The wrapper's program (sw/mini_shell_loop.axasm) never HALTs, so
// there's no halted-based termination like the other UART shell
// testbenches use - this runs for a fixed, generous cycle budget and
// checks THREE back-to-back command round trips against one
// continuous RX byte stream:
//   1. "hi\r"  -> "> " + "hi\r" + "OK\r\n"   (match path)
//   2. "xy\r"  -> "> " + "xy\r" + "?\r\n"    (no-match path, AND
//                 proves the loop actually re-arms, not just "didn't
//                 hang")
//   3. "hi\r"  -> "> " + "hi\r" + "OK\r\n"   (match path again -
//                 proves the buffer-offset reset (N3) leaves no stale
//                 characters behind from round 2's shorter command)
// Also asserts uio_out[3] (halted) stays 0 the whole run, and uio_oe
// stays constant at 8'h0D throughout (the wrapper's fixed pin-
// direction contract).
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/mini_shell_loop.hex"
`endif

module tb_tt_um_axisa_core;
    reg clk, rst_n, ena;
    integer errors;

    // Continuous "keyboard" stream: "hi\r" + "xy\r" + "hi\r".
    reg [7:0] rx_bytes [0:8];
    initial begin
        rx_bytes[0] = "h"; rx_bytes[1] = "i"; rx_bytes[2] = 8'h0D;
        rx_bytes[3] = "x"; rx_bytes[4] = "y"; rx_bytes[5] = 8'h0D;
        rx_bytes[6] = "h"; rx_bytes[7] = "i"; rx_bytes[8] = 8'h0D;
    end
    integer rx_idx;
    integer rx_len;

    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    wire uart_tx_valid = uio_out[0];
    wire uart_rx_ack   = uio_out[2];
    wire halted_pin    = uio_out[3];

    tt_um_axisa_core dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #5 clk = ~clk;

    // ---- Captured TX byte stream ----
    reg [7:0] captured [0:63];
    integer   captured_len;
    always @(posedge clk) begin
        if (uart_tx_valid) begin
            captured[captured_len] <= uo_out;
            captured_len <= captured_len + 1;
        end
    end

    // ---- RX driver: advance to the next byte only after uart_rx_ack ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_idx <= 0;
        end else if (uart_rx_ack) begin
            if (rx_idx < rx_len) rx_idx <= rx_idx + 1;
        end
    end
    always @(*) begin
        ui_in       = (rx_idx < rx_len) ? rx_bytes[rx_idx] : 8'b0;
        uio_in       = 8'b0;
        uio_in[1]    = (rx_idx < rx_len) ? 1'b1 : 1'b0;
    end

    // ---- uio_oe must stay constant at 8'h0D for the whole run ----
    reg oe_error_seen;
    always @(posedge clk) begin
        if (uio_oe !== 8'h0D && !oe_error_seen) begin
            $display("FAIL: uio_oe=0x%h at time %0t, expected constant 0x0D", uio_oe, $time);
            errors = errors + 1;
            oe_error_seen = 1'b1;
        end
    end

    // ---- halted pin must stay 0 the whole run ----
    reg halted_error_seen;
    always @(posedge clk) begin
        if (halted_pin !== 1'b0 && !halted_error_seen) begin
            $display("FAIL: halted pin went high at time %0t - mini_shell_loop.axasm should never HALT", $time);
            errors = errors + 1;
            halted_error_seen = 1'b1;
        end
    end

    task check_byte(input integer idx, input [7:0] expected);
        begin
            if (captured[idx] !== expected) begin
                $display("FAIL: captured[%0d]=0x%h ('%c'), expected=0x%h ('%c')",
                          idx, captured[idx], captured[idx], expected, expected);
                errors = errors + 1;
            end
        end
    endtask

    integer i;
    integer max_cycles;
    integer cycle_count;
    reg [7:0] expected [0:63];
    integer expected_len;

    initial begin
        errors = 0;
        oe_error_seen = 0;
        halted_error_seen = 0;
        rx_len = 9;
        captured_len = 0;
        max_cycles = 600;

        // Round 1: "> " + "hi\r" + "OK\r\n"
        expected_len = 0;
        expected[expected_len]=">"; expected_len=expected_len+1;
        expected[expected_len]=" "; expected_len=expected_len+1;
        expected[expected_len]="h"; expected_len=expected_len+1;
        expected[expected_len]="i"; expected_len=expected_len+1;
        expected[expected_len]=8'h0D; expected_len=expected_len+1;
        expected[expected_len]="O"; expected_len=expected_len+1;
        expected[expected_len]="K"; expected_len=expected_len+1;
        expected[expected_len]=8'h0D; expected_len=expected_len+1;
        expected[expected_len]=8'h0A; expected_len=expected_len+1;
        // Round 2: "> " + "xy\r" + "?\r\n"
        expected[expected_len]=">"; expected_len=expected_len+1;
        expected[expected_len]=" "; expected_len=expected_len+1;
        expected[expected_len]="x"; expected_len=expected_len+1;
        expected[expected_len]="y"; expected_len=expected_len+1;
        expected[expected_len]=8'h0D; expected_len=expected_len+1;
        expected[expected_len]="?"; expected_len=expected_len+1;
        expected[expected_len]=8'h0D; expected_len=expected_len+1;
        expected[expected_len]=8'h0A; expected_len=expected_len+1;
        // Round 3: "> " + "hi\r" + "OK\r\n" (proves N3 reset, no stale chars)
        expected[expected_len]=">"; expected_len=expected_len+1;
        expected[expected_len]=" "; expected_len=expected_len+1;
        expected[expected_len]="h"; expected_len=expected_len+1;
        expected[expected_len]="i"; expected_len=expected_len+1;
        expected[expected_len]=8'h0D; expected_len=expected_len+1;
        expected[expected_len]="O"; expected_len=expected_len+1;
        expected[expected_len]="K"; expected_len=expected_len+1;
        expected[expected_len]=8'h0D; expected_len=expected_len+1;
        expected[expected_len]=8'h0A; expected_len=expected_len+1;

        clk = 0;
        ena = 1'b1;
        rst_n = 1'b0;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        rst_n = 1'b1;

        // Stop as soon as the 3 expected round trips are fully
        // captured, rather than a fixed budget - the core keeps
        // looping and starts printing a 4th prompt almost immediately
        // after round 3 (proof the loop genuinely continues forever),
        // which would otherwise be captured too and make an exact
        // captured_len==expected_len check flaky.
        while (captured_len < expected_len && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        $write("Captured console output: ");
        for (i = 0; i < captured_len; i = i + 1) $write("%c", captured[i]);
        $write("\n");
        $display("Captured %0d TX bytes after %0d cycles.", captured_len, cycle_count);

        if (captured_len !== expected_len) begin
            $display("FAIL: captured %0d TX bytes, expected %0d", captured_len, expected_len);
            errors = errors + 1;
        end else begin
            for (i = 0; i < expected_len; i = i + 1) check_byte(i, expected[i]);
            if (errors == 0) $display("PASS: 3 round-trip TX byte stream matches expected exactly (match/nomatch/match, loop re-arms, N3 resets cleanly)");
        end

        if (errors == 0) $display("ALL AXISA TT_UM WRAPPER TESTS PASSED");
        else $display("%0d AXISA TT_UM WRAPPER TEST(S) FAILED", errors);
        $finish;
    end
endmodule
