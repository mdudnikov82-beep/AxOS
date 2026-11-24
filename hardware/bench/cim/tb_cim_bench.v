// Fair fight 2 (see ../gen_bench_cim.py): cycles of SUM / COUNT / ADD on
// 64 words, von Neumann code vs the CIM block, same AxISA core. Each job
// sits between two UART marks; a job's cycles = cycles between the marks
// minus the mark itself (one STORE, one cycle). Results are checked: both
// sides must agree, and the memory and the block must be equal after ADD.
`timescale 1ns/1ps

module tb_cim_bench;
    reg clk, reset;
    integer cycle_count, marks, last_mark, errors, i;
    integer cyc [0:7];

    wire halted;
    wire [31:0] tohost_value;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE("cim/cim_bench.hex")) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .irq_in(1'b0),
        .bus_req(), .bus_addr(), .bus_write_data(), .bus_mem_write(), .bus_mem_size(), .bus_mem_unsigned(),
        .bus_grant(1'b0), .bus_read_data(32'b0),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(8'b0), .uart_rx_ready_in(1'b0), .uart_rx_ack()
    );

    always #5 clk = ~clk;
    function [31:0] w; input [31:0] addr; w = dut.dmem.mem[addr >> 2]; endfunction

    always @(posedge clk) if (!reset) begin
        cycle_count = cycle_count + 1;
        if (uart_tx_valid) begin
            if (marks > 0) cyc[marks - 1] = cycle_count - last_mark - 1;
            last_mark = cycle_count;
            marks = marks + 1;
        end
    end

    task check(input [31:0] got, input [31:0] expected, input [48*8-1:0] name);
        if (got !== expected) begin
            $display("FAIL: %0s got=%0d expected=%0d", name, got, expected);
            errors = errors + 1;
        end
    endtask

    initial begin
        clk = 0; reset = 1; cycle_count = 0; marks = 0; last_mark = 0; errors = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;
        wait (halted || cycle_count > 5000);
        @(posedge clk);
        check(halted, 1, "halted");
        check(marks, 7, "7 timing marks");
        check(w(32'h300), 32'd2848, "SUM, von Neumann");
        check(w(32'h304), 32'd2848, "SUM, CIM");
        check(w(32'h308), 32'd17, "COUNT, von Neumann");
        check(w(32'h30C), 32'd17, "COUNT, CIM");
        for (i = 0; i < 64; i = i + 1) begin
            check(w(32'h400 + 4 * i), 3 * i + 50, "ADD, von Neumann");
            check(dut.cimb.w[i], 3 * i + 50, "ADD, CIM");
        end
        $display("CIM-BENCH SUM   von Neumann %0d cycles, CIM %0d cycles", cyc[0], cyc[1]);
        $display("CIM-BENCH COUNT von Neumann %0d cycles, CIM %0d cycles", cyc[2], cyc[3]);
        $display("CIM-BENCH ADD   von Neumann %0d cycles, CIM %0d cycles", cyc[4], cyc[5]);
        if (errors == 0) $display("CIM-BENCH PASSED");
        else $display("CIM-BENCH: %0d check(s) FAILED", errors);
        $finish;
    end
endmodule
