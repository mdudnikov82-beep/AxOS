// Full-core FSQRT.S integration test (see sw/asm_fp_sqrt_test.py for the
// exact program and expected result). Same structure as tb_cpu_fp_div.v,
// with a MAX_CYCLES sized for FSQRT.S's ~26-cycle latency (see
// fp_sqrt.v) rather than FDIV.S's ~50.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/fp_sqrt_test.hex"
`endif

module tb_cpu_fp_sqrt;
    reg clk;
    reg reset;
    wire halted;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;

    cpu_core #(.INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX), .DATA_MEM_BYTES(8192)) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .bus_grant(1'b1), .bus_read_data(32'b0)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_cpu_fp_sqrt.vcd");
        $dumpvars(0, tb_cpu_fp_sqrt);

        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 1068827891; // 0x3fb504f3 = sqrt(2.0)
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 60;

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
