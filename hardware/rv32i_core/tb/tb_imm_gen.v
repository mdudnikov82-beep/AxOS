// Builds each test instruction by concatenating named fields (not
// hand-computed hex) so the encoding is self-documenting and can't
// silently drift from the RV32I spec through an arithmetic slip.
`timescale 1ns/1ps

module tb_imm_gen;
    reg  [31:0] instr;
    wire [31:0] imm;
    integer     errors;

    imm_gen dut(.instr(instr), .imm(imm));

    task check(input [31:0] expected, input [40*8-1:0] name);
        begin
            #1;
            if (imm !== expected) begin
                $display("FAIL %0s: instr=%h got=%h expected=%h", name, instr, imm, expected);
                errors = errors + 1;
            end else begin
                $display("OK   %0s", name);
            end
        end
    endtask

    initial begin
        errors = 0;

        // I-type: ADDI x1, x0, -1
        instr = {12'hFFF, 5'd0, 3'b000, 5'd1, 7'b0010011};
        check(32'hFFFFFFFF, "I-type imm=-1");

        // I-type: ADDI x1, x0, 5
        instr = {12'd5, 5'd0, 3'b000, 5'd1, 7'b0010011};
        check(32'd5, "I-type imm=5");

        // S-type: SW x2, 100(x1)  (imm[11:5]=0000011 imm[4:0]=00100)
        instr = {7'b0000011, 5'd2, 5'd1, 3'b010, 5'b00100, 7'b0100011};
        check(32'd100, "S-type imm=100");

        // S-type: SW x2, -4(x1)
        instr = {7'b1111111, 5'd2, 5'd1, 3'b010, 5'b11100, 7'b0100011};
        check(-32'sd4, "S-type imm=-4");

        // B-type: BEQ x1, x2, +8
        instr = {1'b0, 6'b000000, 5'd2, 5'd1, 3'b000, 4'b0100, 1'b0, 7'b1100011};
        check(32'd8, "B-type imm=8");

        // B-type: BEQ x1, x2, -8 (13-bit two's complement of -8 is
        // 1111111111000, i.e. imm[4:1]=1100, not 1000 - miscomputed
        // once already, caught by this very test failing).
        instr = {1'b1, 6'b111111, 5'd2, 5'd1, 3'b000, 4'b1100, 1'b1, 7'b1100011};
        check(-32'sd8, "B-type imm=-8");

        // U-type: LUI x1, 0x12345
        instr = {20'h12345, 5'd1, 7'b0110111};
        check(32'h12345000, "U-type LUI");

        // J-type: JAL x1, +16
        instr = {1'b0, 10'b0000001000, 1'b0, 8'b00000000, 5'd1, 7'b1101111};
        check(32'd16, "J-type imm=16");

        // J-type: JAL x1, -16
        instr = {1'b1, 10'b1111111000, 1'b1, 8'b11111111, 5'd1, 7'b1101111};
        check(-32'sd16, "J-type imm=-16");

        if (errors == 0) $display("ALL IMM_GEN TESTS PASSED");
        else $display("%0d IMM_GEN TESTS FAILED", errors);
        $finish;
    end
endmodule
