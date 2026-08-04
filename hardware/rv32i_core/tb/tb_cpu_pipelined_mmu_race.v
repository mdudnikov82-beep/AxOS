// Adversarial race test for FDIV.S vs the MMU's mmu_stall signal on the
// pipelined P-core (cpu_core_pipelined.v) - the exact same hazard class
// fp_div_pipe_race_test.hex/tb_cpu_fp_div_pipe.v already proved for
// mem_stall (see that pair's own comments), now targeting fdiv_capture's
// !mmu_stall term instead of its !mem_stall term.
//
// Unlike mem_stall (an external bus_grant denial can be held indefinitely
// by the testbench), there is no external "deny" knob for an MMU
// page-table walk - a real walk always finishes in a handful of fixed
// cycles (mmu.v's S_L1/S_L0/S_FILL sequence), far shorter than FDIV.S's
// ~51-cycle latency, so it can never organically overlap fpu_div_done
// through instruction sequencing alone (by the time a walk could
// complete, the division isn't done yet; by the time the division is
// done, no walk from this program is still active). Instead, this
// testbench directly forces the DUT's own mmu_stall wire high for
// exactly the one cycle fpu_div_done first asserts - a legitimate
// white-box technique for exercising the timing window a design review
// identified as structurally reachable (any older instruction genuinely
// still occupying EX/MEM on FDIV's done cycle, whatever the reason)
// even though today's mmu.v can't organically produce a walk that long.
`timescale 1ns/1ps

`ifndef INSTR_HEX
`define INSTR_HEX "sw/fp_div_pipe_race_test.hex"
`endif

module tb_cpu_pipelined_mmu_race;
    reg clk, reset;
    wire halted, page_fault;
    wire [31:0] tohost_value;

    integer expect_tohost;
    integer max_cycles;
    integer cycle_count;
    reg forced;

    // MMU_ENABLE(0) deliberately - no real page table is built in this
    // testbench (the program does plain, unmapped private accesses),
    // and none is needed: `force` overrides mmu_stall's driver
    // regardless of whether it's the real walker FSM or the bypass
    // generate block's `assign mmu_stall = 1'b0;`, so this test isolates
    // fdiv_capture's timing interaction with the mmu_stall SIGNAL from
    // whether a real walk is in progress.
    cpu_core_pipelined #(
        .INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX), .DATA_MEM_BYTES(8192),
        .MMU_ENABLE(0)
    ) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value), .page_fault(page_fault),
        .bus_grant(1'b1), .bus_read_data(32'b0)
    );

    always #5 clk = ~clk;

    // Force mmu_stall high for exactly the one cycle fpu_div_done first
    // asserts, release the next cycle - see header comment. The #1
    // delay lets this edge's NBA updates (fp_div's state transition
    // into ST_DONE) settle before we sample done, same lesson as
    // tb_mmu.v's own documented delta-cycle race fix.
    always @(posedge clk) begin
        #1;
        if (!forced && dut.fpu_div_done) begin
            force dut.mmu_stall = 1'b1;
            forced = 1'b1;
        end else if (forced) begin
            release dut.mmu_stall;
            forced = 1'b0;
        end
    end

    initial begin
        $dumpfile("tb_cpu_pipelined_mmu_race.vcd");
        $dumpvars(0, tb_cpu_pipelined_mmu_race);

        if (!$value$plusargs("EXPECT_TOHOST=%d", expect_tohost)) expect_tohost = 1080033280; // 0x40600000 = 3.5
        // Tight on purpose, mirroring tb_cpu_fp_div_pipe.v's own bound:
        // the correct (buffered) capture finishes just past the natural
        // program length (~70 cycles incl. the shared-store setup); a
        // broken fdiv_capture drops the result and restarts the ~51-cycle
        // division from scratch, blowing well past this.
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 75;

        clk = 0; reset = 1; cycle_count = 0; forced = 1'b0;
        @(posedge clk); @(posedge clk);
        reset = 0;

        while (!halted && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!halted) begin
            $display("FAIL: core never halted within %0d cycles (FDIV result lost to the mmu_stall/fpu_div_done race, division restarted)", max_cycles);
        end else if (page_fault) begin
            $display("FAIL: unexpected page_fault");
        end else begin
            $display("Halted after %0d cycles. tohost=%0d (0x%h)", cycle_count, tohost_value, tohost_value);
            if (tohost_value === expect_tohost) begin
                $display("PASS: tohost matches expected value %0d (FDIV result survived the forced mmu_stall/fpu_div_done race)", expect_tohost);
            end else begin
                $display("FAIL: tohost=%0d, expected=%0d", tohost_value, expect_tohost);
            end
        end

        $finish;
    end
endmodule
