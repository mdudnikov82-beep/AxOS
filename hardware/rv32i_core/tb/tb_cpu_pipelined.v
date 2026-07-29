// Same structure/conventions as tb_cpu.v (the single-cycle
// testbench), instantiating cpu_core_pipelined instead - deliberately
// run against the SAME test programs so the pipelined core's result
// can be cross-checked against the already-verified single-cycle
// design, not just against hand-computed expected values.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/test1.hex"
`endif

module tb_cpu_pipelined;
    reg clk;
    reg reset;
    wire halted;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;
    integer trace_enabled;

    cpu_core_pipelined #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX), .DATA_MEM_BYTES(8192)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_cpu_pipelined.vcd");
        $dumpvars(0, tb_cpu_pipelined);

        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 42;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 300;
        trace_enabled = $test$plusargs("TRACE");

        clk = 0;
        reset = 1;
        cycle_count = 0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        // Optional per-cycle trace (off by default - run_sim.bat's own
        // pass/fail checks never enable it, only asked for on demand):
        // pc/instruction/hazard signals in one line per cycle, the
        // text equivalent of the waveform view, no GUI involved at all.
        if (trace_enabled) begin
            $display("cyc | if_id_pc if_id_instr | stall ex_tk fwd_a fwd_b | id_ex_rd mem_wb_rd wb_wr wb_data");
            $display("----+----------------------+-------------------------+---------------------------------");
        end

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (trace_enabled) begin
                $display("%3d | %h  %h |   %b     %b    %b    %b  |    %h        %h      %b   %h",
                         cycle_count, dut.if_id_pc, dut.if_id_instr,
                         dut.stall, dut.ex_taken, dut.forward_a, dut.forward_b,
                         dut.id_ex_rd, dut.mem_wb_rd, dut.wb_reg_write, dut.wb_rd_data);
            end
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles (infinite loop or ECALL never reached)", max_cycles);
        end else begin
            $display("Halted after %0d cycles. tohost=%0d (0x%h)", cycle_count, tohost_value, tohost_value);
            if (tohost_value === expect_tohost) begin
                $display("PASS: tohost matches expected value %0d", expect_tohost);
            end else begin
                $display("FAIL: tohost=%0d, expected=%0d", tohost_value, expect_tohost);
            end
        end

        $finish;
    end
endmodule
