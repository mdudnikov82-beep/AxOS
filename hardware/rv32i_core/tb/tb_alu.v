// Standalone ALU testbench - hand-computed expected values, checked
// before the ALU is ever wired into the full core (same "verify each
// piece in isolation" discipline the rest of this project already
// follows in software).
`timescale 1ns/1ps

module tb_alu;
    reg  [31:0] a, b;
    reg  [3:0]  alu_op;
    wire [31:0] result;
    wire        zero;
    integer     errors;

    alu dut(.a(a), .b(b), .alu_op(alu_op), .result(result), .zero(zero));

    task check(input [31:0] expected, input [40*8-1:0] name);
        begin
            if (result !== expected) begin
                $display("FAIL %0s: a=%h b=%h op=%b got=%h expected=%h", name, a, b, alu_op, result, expected);
                errors = errors + 1;
            end else begin
                $display("OK   %0s", name);
            end
        end
    endtask

    initial begin
        errors = 0;

        a = 32'd10; b = 32'd3; alu_op = 4'b0000; #1; check(32'd13, "ADD 10+3");
        a = 32'd10; b = 32'd3; alu_op = 4'b0001; #1; check(32'd7,  "SUB 10-3");
        a = 32'h00000001; b = 32'd4; alu_op = 4'b0010; #1; check(32'h00000010, "SLL 1<<4");
        a = -32'sd5; b = 32'd3; alu_op = 4'b0011; #1; check(32'd1, "SLT -5<3 true");
        a = 32'd5;  b = 32'd3; alu_op = 4'b0011; #1; check(32'd0, "SLT 5<3 false");
        a = 32'hFFFFFFFB; b = 32'd3; alu_op = 4'b0100; #1; check(32'd0, "SLTU huge<3 false");
        a = 32'd2;  b = 32'd3; alu_op = 4'b0100; #1; check(32'd1, "SLTU 2<3 true");
        a = 32'hF0F0F0F0; b = 32'h0F0F0F0F; alu_op = 4'b0101; #1; check(32'hFFFFFFFF, "XOR");
        a = 32'h80000000; b = 32'd4; alu_op = 4'b0110; #1; check(32'h08000000, "SRL logical");
        a = 32'h80000000; b = 32'd4; alu_op = 4'b0111; #1; check(32'hF8000000, "SRA arithmetic");
        a = 32'hF0F0F0F0; b = 32'h0F0F0F0F; alu_op = 4'b1000; #1; check(32'hFFFFFFFF, "OR");
        a = 32'hFF00FF00; b = 32'h0F0F0F0F; alu_op = 4'b1001; #1; check(32'h0F000F00, "AND");
        a = 32'd5; b = 32'd5; alu_op = 4'b0001; #1; check(32'd0, "SUB equal -> zero flag");
        if (zero !== 1'b1) begin
            $display("FAIL zero flag not set when result==0");
            errors = errors + 1;
        end

        if (errors == 0) $display("ALL ALU TESTS PASSED");
        else $display("%0d ALU TESTS FAILED", errors);
        $finish;
    end
endmodule
