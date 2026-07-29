`timescale 1ns/1ps

module tb_control_unit;
    reg  [6:0] opcode;
    reg  [2:0] funct3;
    reg  [6:0] funct7;
    wire       reg_write, mem_read, mem_write, mem_to_reg, alu_src;
    wire       branch, jump, jalr, auipc, mem_unsigned, illegal;
    wire [3:0] alu_op;
    wire [1:0] mem_size;
    integer    errors;

    control_unit dut(
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .mem_to_reg(mem_to_reg), .alu_src(alu_src), .branch(branch),
        .jump(jump), .jalr(jalr), .auipc(auipc), .alu_op(alu_op),
        .mem_size(mem_size), .mem_unsigned(mem_unsigned), .illegal(illegal)
    );

    integer pass_count;

    task expect_bit(input got, input exp, input [40*8-1:0] name);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got=%b expected=%b", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task expect_vec(input [3:0] got, input [3:0] exp, input [40*8-1:0] name);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got=%b expected=%b", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;

        // ADD: opcode=0110011 funct3=000 funct7=0000000
        opcode = 7'b0110011; funct3 = 3'b000; funct7 = 7'b0000000; #1;
        expect_bit(reg_write, 1, "ADD reg_write"); expect_vec(alu_op, 4'b0000, "ADD alu_op");

        // SUB: opcode=0110011 funct3=000 funct7=0100000
        opcode = 7'b0110011; funct3 = 3'b000; funct7 = 7'b0100000; #1;
        expect_vec(alu_op, 4'b0001, "SUB alu_op");

        // ADDI: opcode=0010011 funct3=000
        opcode = 7'b0010011; funct3 = 3'b000; funct7 = 7'b0000000; #1;
        expect_bit(reg_write, 1, "ADDI reg_write"); expect_bit(alu_src, 1, "ADDI alu_src");
        expect_vec(alu_op, 4'b0000, "ADDI alu_op");

        // SRAI: opcode=0010011 funct3=101 funct7=0100000
        opcode = 7'b0010011; funct3 = 3'b101; funct7 = 7'b0100000; #1;
        expect_vec(alu_op, 4'b0111, "SRAI alu_op (SRA)");

        // SRLI: opcode=0010011 funct3=101 funct7=0000000
        opcode = 7'b0010011; funct3 = 3'b101; funct7 = 7'b0000000; #1;
        expect_vec(alu_op, 4'b0110, "SRLI alu_op (SRL)");

        // LW: opcode=0000011 funct3=010
        opcode = 7'b0000011; funct3 = 3'b010; funct7 = 7'b0; #1;
        expect_bit(reg_write, 1, "LW reg_write"); expect_bit(mem_read, 1, "LW mem_read");
        expect_bit(mem_to_reg, 1, "LW mem_to_reg"); if (mem_size !== 2'b10) begin $display("FAIL LW mem_size: got=%b", mem_size); errors=errors+1; end
        expect_bit(mem_unsigned, 0, "LW mem_unsigned");

        // LBU: opcode=0000011 funct3=100
        opcode = 7'b0000011; funct3 = 3'b100; funct7 = 7'b0; #1;
        if (mem_size !== 2'b00) begin $display("FAIL LBU mem_size: got=%b", mem_size); errors=errors+1; end
        expect_bit(mem_unsigned, 1, "LBU mem_unsigned");

        // SW: opcode=0100011 funct3=010
        opcode = 7'b0100011; funct3 = 3'b010; funct7 = 7'b0; #1;
        expect_bit(mem_write, 1, "SW mem_write"); expect_bit(reg_write, 0, "SW reg_write=0");
        if (mem_size !== 2'b10) begin $display("FAIL SW mem_size: got=%b", mem_size); errors=errors+1; end

        // BEQ: opcode=1100011
        opcode = 7'b1100011; funct3 = 3'b000; funct7 = 7'b0; #1;
        expect_bit(branch, 1, "BEQ branch"); expect_bit(reg_write, 0, "BEQ reg_write=0");

        // LUI: opcode=0110111
        opcode = 7'b0110111; funct3 = 3'b0; funct7 = 7'b0; #1;
        expect_bit(reg_write, 1, "LUI reg_write"); expect_bit(alu_src, 1, "LUI alu_src");

        // AUIPC: opcode=0010111
        opcode = 7'b0010111; funct3 = 3'b0; funct7 = 7'b0; #1;
        expect_bit(auipc, 1, "AUIPC auipc");

        // JAL: opcode=1101111
        opcode = 7'b1101111; funct3 = 3'b0; funct7 = 7'b0; #1;
        expect_bit(jump, 1, "JAL jump"); expect_bit(reg_write, 1, "JAL reg_write");

        // JALR: opcode=1100111
        opcode = 7'b1100111; funct3 = 3'b000; funct7 = 7'b0; #1;
        expect_bit(jalr, 1, "JALR jalr"); expect_bit(alu_src, 1, "JALR alu_src");

        // Unknown opcode -> illegal
        opcode = 7'b1111111; funct3 = 3'b0; funct7 = 7'b0; #1;
        expect_bit(illegal, 1, "unknown opcode -> illegal");

        if (errors == 0) $display("ALL CONTROL_UNIT TESTS PASSED");
        else $display("%0d CONTROL_UNIT TESTS FAILED", errors);
        $finish;
    end
endmodule
