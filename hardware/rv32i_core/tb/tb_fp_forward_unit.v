`timescale 1ns/1ps

module tb_fp_forward_unit;
    reg  [4:0] id_ex_rs1, id_ex_rs2, ex_mem_rd, mem_wb_rd;
    reg        ex_mem_reg_write, mem_wb_reg_write;
    wire [1:0] forward_a, forward_b;
    integer    errors;

    fp_forward_unit dut(
        .id_ex_rs1(id_ex_rs1), .id_ex_rs2(id_ex_rs2),
        .ex_mem_rd(ex_mem_rd), .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd(mem_wb_rd), .mem_wb_reg_write(mem_wb_reg_write),
        .forward_a(forward_a), .forward_b(forward_b)
    );

    task check(input [1:0] got, input [1:0] expected, input [40*8-1:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL %0s: got=%b expected=%b", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("OK   %0s", name);
            end
        end
    endtask

    initial begin
        errors = 0;

        // No hazard at all.
        id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd2;
        ex_mem_rd = 5'd3; ex_mem_reg_write = 1;
        mem_wb_rd = 5'd4; mem_wb_reg_write = 1;
        #1;
        check(forward_a, 2'b00, "no hazard on rs1");
        check(forward_b, 2'b00, "no hazard on rs2");

        // EX/MEM matches rs1.
        id_ex_rs1 = 5'd3; id_ex_rs2 = 5'd2;
        #1;
        check(forward_a, 2'b10, "EX/MEM forwards to rs1");
        check(forward_b, 2'b00, "rs2 unaffected");

        // MEM/WB matches rs2 (EX/MEM doesn't match).
        id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd4;
        #1;
        check(forward_a, 2'b00, "rs1 unaffected");
        check(forward_b, 2'b01, "MEM/WB forwards to rs2");

        // Both EX/MEM and MEM/WB match rs1 - EX/MEM (more recent) wins.
        id_ex_rs1 = 5'd3; ex_mem_rd = 5'd3; mem_wb_rd = 5'd3; id_ex_rs2 = 5'd7;
        #1;
        check(forward_a, 2'b10, "EX/MEM priority over MEM/WB when both match");

        // reg_write=0 on the matching stage must not forward.
        ex_mem_reg_write = 0; mem_wb_reg_write = 0;
        #1;
        check(forward_a, 2'b00, "no forward when reg_write=0 on both");

        // f0 (register number 0) MUST forward, unlike the integer
        // forward_unit's x0 - this is the whole reason this is a
        // separate module: fp_regfile.v has no hardwired-zero rule.
        id_ex_rs1 = 5'd0; ex_mem_rd = 5'd0; ex_mem_reg_write = 1;
        #1;
        check(forward_a, 2'b10, "f0 DOES forward from EX/MEM (unlike integer x0)");

        ex_mem_reg_write = 0; mem_wb_rd = 5'd0; mem_wb_reg_write = 1;
        #1;
        check(forward_a, 2'b01, "f0 DOES forward from MEM/WB too");

        if (errors == 0) $display("ALL FP_FORWARD_UNIT TESTS PASSED");
        else $display("%0d FP_FORWARD_UNIT TESTS FAILED", errors);
        $finish;
    end
endmodule
