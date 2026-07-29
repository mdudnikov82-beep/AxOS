`timescale 1ns/1ps

module tb_data_mem;
    reg         clk;
    reg  [31:0] addr, write_data;
    reg         mem_write;
    reg  [1:0]  mem_size;
    reg         mem_unsigned;
    wire [31:0] read_data;
    integer     errors;

    data_mem dut(.clk(clk), .addr(addr), .write_data(write_data), .mem_write(mem_write),
                 .mem_size(mem_size), .mem_unsigned(mem_unsigned), .read_data(read_data));

    always #5 clk = ~clk;

    task check(input [31:0] expected, input [40*8-1:0] name);
        begin
            #1;
            if (read_data !== expected) begin
                $display("FAIL %0s: got=%h expected=%h", name, read_data, expected);
                errors = errors + 1;
            end else begin
                $display("OK   %0s", name);
            end
        end
    endtask

    initial begin
        errors = 0;
        clk = 0;
        mem_write = 0; addr = 0; write_data = 0; mem_size = 2'b10; mem_unsigned = 0;

        // Store a word at addr=0x10, read it back.
        addr = 32'h10; write_data = 32'h11223344; mem_size = 2'b10; mem_write = 1;
        @(posedge clk); #1; mem_write = 0;
        check(32'h11223344, "word store/load");

        // Store a byte at addr=0x20 with the top bit set - sign vs zero extend.
        addr = 32'h20; write_data = 32'h000000FE; mem_size = 2'b00; mem_write = 1;
        @(posedge clk); #1; mem_write = 0;
        mem_unsigned = 0;
        check(32'hFFFFFFFE, "byte load sign-extended (LB)");
        mem_unsigned = 1;
        check(32'h000000FE, "byte load zero-extended (LBU)");

        // Store a halfword with top bit set.
        addr = 32'h30; write_data = 32'h0000FF00; mem_size = 2'b01; mem_write = 1;
        @(posedge clk); #1; mem_write = 0;
        mem_unsigned = 0;
        check(32'hFFFFFF00, "half load sign-extended (LH)");
        mem_unsigned = 1;
        check(32'h0000FF00, "half load zero-extended (LHU)");

        // Byte store at addr=0x40 must not disturb neighboring bytes -
        // pre-fill a word, then overwrite only byte 1.
        addr = 32'h40; write_data = 32'hAABBCCDD; mem_size = 2'b10; mem_write = 1;
        @(posedge clk); #1; mem_write = 0;
        addr = 32'h41; write_data = 32'h000000EE; mem_size = 2'b00; mem_write = 1;
        @(posedge clk); #1; mem_write = 0;
        addr = 32'h40; mem_size = 2'b10; mem_unsigned = 1;
        check(32'hAABBEEDD, "byte store doesn't clobber neighbors");

        if (errors == 0) $display("ALL DATA_MEM TESTS PASSED");
        else $display("%0d DATA_MEM TESTS FAILED", errors);
        $finish;
    end
endmodule
