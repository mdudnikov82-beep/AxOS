// AxISA v2.1 step 1 (see sw/mte_mmu_test.axasm): memory tagging under
// the MMU - the tag check must use the translated PHYSICAL granule.
`timescale 1ns/1ps
`ifndef INSTR_HEX
`define INSTR_HEX "sw/mte_mmu_test.hex"
`endif

module tb_mte_mmu;
    reg clk, reset;
    integer errors;
    integer max_cycles;
    integer cycle_count;

    wire halted;
    wire [31:0] tohost_value;
    wire        bus_req, bus_mem_write, bus_mem_unsigned, bus_grant;
    wire [31:0] bus_addr, bus_write_data, bus_read_data;
    wire [1:0]  bus_mem_size;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    cpu_core #(
        .INSTR_MEM_WORDS(1024), .INSTR_INIT_FILE(`INSTR_HEX),
        .MMU_ENABLE(1)
    ) dut (
        .clk(clk), .reset(reset), .halted(halted), .tohost_value(tohost_value),
        .irq_in(1'b0),
        .bus_req(bus_req), .bus_addr(bus_addr), .bus_write_data(bus_write_data),
        .bus_mem_write(bus_mem_write), .bus_mem_size(bus_mem_size), .bus_mem_unsigned(bus_mem_unsigned),
        .bus_grant(1'b0), .bus_read_data(32'b0),
        .uart_tx_valid(uart_tx_valid), .uart_tx_data(uart_tx_data),
        .uart_rx_data_in(8'b0), .uart_rx_ready_in(1'b0), .uart_rx_ack()
    );

    always #5 clk = ~clk;

    task check(input [31:0] got, input [31:0] expected, input [64*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL: %0s got=%0d expected=%0d", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", name, got);
            end
        end
    endtask

    initial begin
        errors = 0;
        max_cycles = 200; // real translation costs a few extra stall cycles per miss - more headroom than the non-MMU trap tests

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
            $display("Halted after %0d cycles. tohost=%0d", cycle_count, tohost_value);
            check(tohost_value, 32'd261, "tohost: 1 trap, cause 5 (TAG_FAULT)");
            check(dut.dmem.mem[32'h1100 >> 2], 32'hAB, "tagged user store landed at physical 0x1100");
            check(dut.dmem.mem[32'h1104 >> 2], 32'h0, "untagged user store to the same granule was blocked");
            check(dut.n_bank.regs[5], 32'hAB, "tagged user load read it back");
            check(dut.g_mte.tag_mem[32'h1100 >> 4], 4'd9, "physical granule 0x1100 has tag 9");
            check(dut.g_mte.tag_mem[32'h0100 >> 4], 4'd0, "virtual granule 0x100 was never tagged");
        end

        if (errors == 0) $display("ALL AXISA MTE-MMU TESTS PASSED");
        else $display("%0d AXISA MTE-MMU TEST(S) FAILED", errors);
        $finish;
    end
endmodule
