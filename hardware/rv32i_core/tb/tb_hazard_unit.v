`timescale 1ns/1ps

module tb_hazard_unit;
    reg        id_ex_mem_read;
    reg        id_ex_fp_reg_write;
    reg  [4:0] id_ex_rd, if_id_rs1, if_id_rs2;
    wire       stall;
    integer    errors;

    hazard_unit dut(
        .id_ex_mem_read(id_ex_mem_read), .id_ex_rd(id_ex_rd),
        .id_ex_fp_reg_write(id_ex_fp_reg_write),
        .if_id_rs1(if_id_rs1), .if_id_rs2(if_id_rs2), .stall(stall)
    );

    task check(input expected, input [40*8-1:0] name);
        begin
            #1;
            if (stall !== expected) begin
                $display("FAIL %0s: got=%b expected=%b", name, stall, expected);
                errors = errors + 1;
            end else begin
                $display("OK   %0s", name);
            end
        end
    endtask

    initial begin
        errors = 0;

        id_ex_fp_reg_write = 0;

        // Not a load at all - never stalls regardless of register overlap.
        id_ex_mem_read = 0; id_ex_rd = 5'd3; if_id_rs1 = 5'd3; if_id_rs2 = 5'd0;
        check(1'b0, "non-load never stalls");

        // Load, but no register overlap with the following instruction.
        id_ex_mem_read = 1; id_ex_rd = 5'd3; if_id_rs1 = 5'd7; if_id_rs2 = 5'd8;
        check(1'b0, "load with no dependent use");

        // Load-use hazard on rs1.
        id_ex_mem_read = 1; id_ex_rd = 5'd3; if_id_rs1 = 5'd3; if_id_rs2 = 5'd8;
        check(1'b1, "load-use hazard on rs1");

        // Load-use hazard on rs2.
        id_ex_mem_read = 1; id_ex_rd = 5'd3; if_id_rs1 = 5'd8; if_id_rs2 = 5'd3;
        check(1'b1, "load-use hazard on rs2");

        // x0 destination never stalls (writes to x0 are meaningless).
        id_ex_mem_read = 1; id_ex_rd = 5'd0; if_id_rs1 = 5'd0; if_id_rs2 = 5'd0;
        check(1'b0, "load writing x0 never stalls");

        // FLW writing f0 (register number 0) MUST still stall - f0 is
        // an ordinary, non-special register in RV32F, unlike x0. This
        // is the real bug found while porting the FPU to this pipeline:
        // without id_ex_fp_reg_write, this case would wrongly return 0.
        id_ex_mem_read = 1; id_ex_rd = 5'd0; id_ex_fp_reg_write = 1;
        if_id_rs1 = 5'd0; if_id_rs2 = 5'd8;
        check(1'b1, "FLW writing f0 still stalls (f0 is not special)");
        id_ex_fp_reg_write = 0;

        if (errors == 0) $display("ALL HAZARD_UNIT TESTS PASSED");
        else $display("%0d HAZARD_UNIT TESTS FAILED", errors);
        $finish;
    end
endmodule
