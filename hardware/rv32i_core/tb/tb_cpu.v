// Full-core testbench: loads a hex program (INIT_FILE, passed via
// +INSTR_HEX=path on the vvp command line, defaulting to
// sw/test1.hex), runs the clock until the core halts (ECALL) or a
// cycle-count ceiling is hit (safety net against an infinite loop
// from a real bug rather than iverilog hanging forever), then reports
// the tohost value. EXPECT_TOHOST (also a +plusarg) is compared
// against the actual result for a pass/fail exit, matching this
// project's usual "assert exact values, don't just eyeball it" style.
`timescale 1ns/1ps

// Overridable at compile time: iverilog -DINSTR_HEX=\"sw/other.hex\" -
// module parameters can't be changed after elaboration, and Icarus's
// -p flag turned out not to reach a parameter nested this deep (tried
// -pdut.INSTR_INIT_FILE=... live, it silently kept the default), so a
// preprocessor macro is the reliable way to run this same testbench
// against more than one program.
`ifndef INSTR_HEX
`define INSTR_HEX "sw/test1.hex"
`endif

module tb_cpu;
    reg clk;
    reg reset;
    wire halted;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX), .DATA_MEM_BYTES(8192)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_cpu.vcd");
        $dumpvars(0, tb_cpu);

        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 42;
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
