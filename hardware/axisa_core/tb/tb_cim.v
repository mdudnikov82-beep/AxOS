// AxISA v2.4 (see sw/cim_test.axasm and docs/ISA.md's "CIM"): all eight
// CIM operations on 64 words, ILLEGAL indices, and an external IRQ
// pulsed inside the first CIM.SUM (+IRQ_PHASE=0 first cycle, 1 middle,
// 2 last): it must be taken only after the SUM, at the next instruction.
`timescale 1ns/1ps
`ifndef INSTR_HEX
`define INSTR_HEX "sw/cim_test.hex"
`endif

module tb_cim;
    reg clk, reset, irq_in;
    integer errors, cycle_count, irq_phase, sum_seen, stall_cycles, early_writes;
    reg [31:0] sum_pc;

    wire halted;
    wire [31:0] tohost_value;
    wire        bus_req, bus_mem_write, bus_mem_unsigned;
    wire [31:0] bus_addr, bus_write_data;
    wire [1:0]  bus_mem_size;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .irq_in(irq_in),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(1'b0), .bus_read_data(32'b0),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(8'b0), .uart_rx_ready_in(1'b0), .uart_rx_ack()
    );

    always #5 clk = ~clk;

    function [31:0] w; input [31:0] addr; w = dut.dmem.mem[addr >> 2]; endfunction

    task check(input [31:0] got, input [31:0] expected, input [56*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL: %0s got=%0d (0x%h) expected=%0d (0x%h)", name, got, got, expected, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d (0x%h)", name, got, got);
            end
        end
    endtask

    // the first SUM: which of its 3 cycles is it in (cimb.st 0, 1, 2)?
    wire in_sum = dut.is_cim && dut.cim_funct == 3'd6 && !dut.squash_r;
    always @(negedge clk) if (!reset) begin
        if (dut.cim_stall) stall_cycles = stall_cycles + 1;
        // nd is written once, on the terminal cycle - not with the tree's
        // partial results while it stalls (that would only cost power)
        if (dut.cim_stall && dut.n_write_en) early_writes = early_writes + 1;
        if (in_sum && sum_seen == 0) sum_pc = dut.pc_r;
        irq_in = 1'b0;
        if (in_sum && sum_seen == 0 && dut.cimb.st == irq_phase) begin
            irq_in = 1'b1;           // one cycle, latched by irq_pending
            sum_seen = 1;
        end
    end

    initial begin
        errors = 0; sum_seen = 0; stall_cycles = 0; early_writes = 0;
        if (!$value$plusargs("IRQ_PHASE=%d", irq_phase)) irq_phase = 1;
        clk = 0; reset = 1; irq_in = 0; cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;
        while (!halted && cycle_count < 2000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted");
            errors = errors + 1;
        end else begin
            $display("Halted after %0d cycles (IRQ in SUM cycle %0d). tohost=%0d", cycle_count, irq_phase, tohost_value);
            check(tohost_value, 32'd770, "tohost: IRQ + 2 ILLEGAL");
            check(sum_seen, 1, "the IRQ was pulsed inside a SUM");
            check(w(32'h440), sum_pc + 4, "IRQ taken after the SUM (EPC = SUM + 4)");
            check(w(32'h400), -32'sd20, "GET w[10] = -20");
            check(w(32'h404), 32'd2848, "SUM = 2848 (despite the IRQ)");
            check(w(32'h408), 32'd17, "FINDLT 0: 17 negative words");
            check(w(32'h40C), -32'sd442, "SUMF of the negative words = -442");
            check(w(32'h410), 32'd0, "FIRST negative word: 0");
            check(w(32'h414), 32'd9248, "SUM after ADD 100 = 9248");
            check(w(32'h418), 32'd1, "FINDEQ 110: 1 word");
            check(w(32'h41C), 32'd20, "FIRST: word 20");
            check(w(32'h420), 32'd2, "FINDEQ 110 after PUT w[5]: 2");
            check(w(32'h424), 32'd5, "FIRST: word 5");
            check(w(32'h428), 32'd220, "SUMF = 220");
            check(w(32'h42C), 32'd0, "FINDEQ 1: none");
            check(w(32'h430), 32'hFFFF_FFFF, "FIRST with no flag: -1");
            check(w(32'h434), 32'd0, "SUMF with no flag: 0");
            check(w(32'h438), 32'd77, "ILLEGAL GET wrote nothing");
            check(w(32'h43C), 32'd239, "w[63] = 239 (ILLEGAL PUT did not wrap)");
            check(w(32'h444), 32'd50, "w[0] = 50");
            check(dut.cimb.w[5], 32'd110, "w[5] in the block");
            check(stall_cycles, 10, "5 sums x 2 stall cycles");
            check(early_writes, 0, "no N write while a SUM stalls");
        end

        if (errors == 0) $display("ALL AXISA CIM TESTS PASSED");
        else $display("%0d AXISA CIM TEST(S) FAILED", errors);
        $finish;
    end
endmodule
