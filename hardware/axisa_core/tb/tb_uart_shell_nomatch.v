// AxISA mini-kernel test, unrecognized-command scenario against the
// SAME sw/mini_shell.axasm program - types "xy\r" (2 characters, so
// it passes the length check but fails the 'h'/'i' comparison),
// expects "?\r\n" and tohost=0. Proves the mismatch path (a real
// negative control on the match path tb_uart_shell.v already proved)
// without duplicating that file's own commentary - see it for the RX
// handshake contract this shares.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/mini_shell.hex"
`endif

module tb_uart_shell_nomatch;
    reg clk, reset;
    integer errors;

    reg [7:0] rx_bytes [0:2];
    initial begin
        rx_bytes[0] = "x";
        rx_bytes[1] = "y";
        rx_bytes[2] = 8'h0D; // CR
    end
    integer rx_idx;
    integer rx_len;

    reg  [7:0] uart_rx_data_in;
    reg        uart_rx_ready_in;
    wire       uart_rx_ack;

    wire halted;
    wire [31:0] tohost_value;
    wire        bus_req, bus_mem_write, bus_mem_unsigned, bus_grant;
    wire [31:0] bus_addr, bus_write_data, bus_read_data;
    wire [1:0]  bus_mem_size;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(1'b0), .bus_read_data(32'b0),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(uart_rx_data_in), .uart_rx_ready_in(uart_rx_ready_in), .uart_rx_ack(uart_rx_ack)
    );

    always #5 clk = ~clk;

    reg [7:0] captured [0:63];
    integer   captured_len;
    always @(posedge clk) begin
        if (uart_tx_valid) begin
            captured[captured_len] <= uart_tx_data;
            captured_len <= captured_len + 1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_idx <= 0;
        end else if (uart_rx_ack) begin
            if (rx_idx < rx_len) rx_idx <= rx_idx + 1;
        end
    end
    always @(*) begin
        if (rx_idx < rx_len) begin
            uart_rx_data_in  = rx_bytes[rx_idx];
            uart_rx_ready_in = 1'b1;
        end else begin
            uart_rx_data_in  = 8'b0;
            uart_rx_ready_in = 1'b0;
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
        rx_len = 3;
        captured_len = 0;
        max_cycles = 200;

        // Expected byte-exact TX stream: "> " (prompt) + "xy\r" (echo)
        // + "?\r\n" (unmatched response).
        expected_len = 0;
        expected[expected_len] = ">";  expected_len = expected_len + 1;
        expected[expected_len] = " ";  expected_len = expected_len + 1;
        expected[expected_len] = "x";  expected_len = expected_len + 1;
        expected[expected_len] = "y";  expected_len = expected_len + 1;
        expected[expected_len] = 8'h0D; expected_len = expected_len + 1;
        expected[expected_len] = "?";  expected_len = expected_len + 1;
        expected[expected_len] = 8'h0D; expected_len = expected_len + 1;
        expected[expected_len] = 8'h0A; expected_len = expected_len + 1;

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles", max_cycles);
            errors = errors + 1;
        end else begin
            $display("Halted after %0d cycles. tohost=%0d, captured %0d TX bytes.",
                      cycle_count, tohost_value, captured_len);
            $write("Captured console output: ");
            for (i = 0; i < captured_len; i = i + 1) $write("%c", captured[i]);
            $write("\n");

            if (tohost_value === 32'd0) $display("PASS: tohost=0 (command 'xy' correctly NOT recognized)");
            else begin
                $display("FAIL: tohost=%0d, expected 0", tohost_value);
                errors = errors + 1;
            end

            if (captured_len !== expected_len) begin
                $display("FAIL: captured %0d TX bytes, expected %0d", captured_len, expected_len);
                errors = errors + 1;
            end else begin
                for (i = 0; i < expected_len; i = i + 1) check_byte(i, expected[i]);
                if (errors == 0) $display("PASS: TX byte stream matches expected prompt+echo+response exactly");
            end
        end

        if (errors == 0) $display("ALL AXISA UART SHELL NOMATCH TESTS PASSED");
        else $display("%0d AXISA UART SHELL NOMATCH TEST(S) FAILED", errors);
        $finish;
    end
endmodule
