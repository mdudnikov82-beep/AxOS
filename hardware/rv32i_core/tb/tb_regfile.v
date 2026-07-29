`timescale 1ns/1ps

module tb_regfile;
    reg         clk;
    reg  [4:0]  rs1_addr, rs2_addr, rd_addr;
    reg  [31:0] rd_data;
    reg         reg_write;
    wire [31:0] rs1_data, rs2_data;
    integer     errors;

    regfile dut(
        .clk(clk), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .reg_write(reg_write)
    );

    always #5 clk = ~clk;

    task check(input [31:0] got, input [31:0] expected, input [40*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL %0s: got=%h expected=%h", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("OK   %0s", name);
            end
        end
    endtask

    initial begin
        errors = 0;
        clk = 0;
        reg_write = 0;
        rs1_addr = 0; rs2_addr = 0; rd_addr = 0; rd_data = 0;

        // x0 always reads zero, even after a would-be write to it.
        rs1_addr = 5'd0;
        #1 check(rs1_data, 32'd0, "x0 reads zero initially");

        rd_addr = 5'd0; rd_data = 32'hDEADBEEF; reg_write = 1;
        @(posedge clk); #1;
        reg_write = 0;
        rs1_addr = 5'd0;
        #1 check(rs1_data, 32'd0, "x0 write is dropped");

        // Write x5 = 123, then read it back on both ports.
        rd_addr = 5'd5; rd_data = 32'd123; reg_write = 1;
        @(posedge clk); #1;
        reg_write = 0;
        rs1_addr = 5'd5; rs2_addr = 5'd5;
        #1 check(rs1_data, 32'd123, "x5 read after write (rs1)");
        #0 check(rs2_data, 32'd123, "x5 read after write (rs2)");

        // Write x10 and x20 at once via two sequential writes, confirm
        // both hold their own values and don't clobber each other.
        rd_addr = 5'd10; rd_data = 32'hAAAA0000; reg_write = 1;
        @(posedge clk); #1;
        rd_addr = 5'd20; rd_data = 32'h0000BBBB; reg_write = 1;
        @(posedge clk); #1;
        reg_write = 0;
        rs1_addr = 5'd10; rs2_addr = 5'd20;
        #1 check(rs1_data, 32'hAAAA0000, "x10 retains its value");
        #0 check(rs2_data, 32'h0000BBBB, "x20 retains its value");

        // reg_write=0 must not modify anything even if rd_addr/rd_data
        // are set to something else.
        rd_addr = 5'd10; rd_data = 32'hFFFFFFFF; reg_write = 0;
        @(posedge clk); #1;
        rs1_addr = 5'd10;
        #1 check(rs1_data, 32'hAAAA0000, "reg_write=0 does not write");

        if (errors == 0) $display("ALL REGFILE TESTS PASSED");
        else $display("%0d REGFILE TESTS FAILED", errors);
        $finish;
    end
endmodule
