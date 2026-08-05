// Generic single-program AxISA runner - just checks tohost against
// EXPECT_TOHOST, no per-program register peeks (unlike tb_cpu.v/
// tb_cpu2.v, which also assert specific R/G/B contents tied to THEIR
// OWN hand-built test programs). Meant for real assembly-source demo
// programs (see sw/axasm.py, sw/*.axasm) where the program itself,
// not a testbench peeking inside it, is the thing being exercised.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/test1.hex"
`endif

module tb_run;
    reg clk, reset;
    wire halted;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value)
    );

    always #5 clk = ~clk;

    initial begin
        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 0;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 200;

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
        end else begin
            $display("Halted after %0d cycles. tohost=%0d (0x%h)", cycle_count, tohost_value, tohost_value);
            if (tohost_value === expect_tohost)
                $display("PASS: tohost matches expected value %0d", expect_tohost);
            else
                $display("FAIL: tohost=%0d, expected=%0d", tohost_value, expect_tohost);
        end
        $finish;
    end
endmodule
