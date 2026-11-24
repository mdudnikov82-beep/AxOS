// rtl/cim.v alone against a plain behavioral model: random operations
// on random (and edge-case) values - the shared adder/comparator, the
// signed overflow cases of FINDLT, the flags, FIRST and the SUM tree.
`timescale 1ns/1ps

module tb_cim_fuzz;
    reg clk, reset, active, commit;
    reg [2:0] funct;
    reg [31:0] idx, val;
    wire [31:0] result;
    wire bad, stall;

    cim dut (.clk(clk), .reset(reset), .active(active), .funct(funct), .commit(commit),
             .run(1'b1), .idx(idx), .val(val), .result(result), .bad(bad), .stall(stall));

    always #5 clk = ~clk;

    reg [31:0] mw [0:63];
    reg [63:0] mflag;
    reg [31:0] expect_r, acc;
    integer n, i, errors, ops, cnt;

    function [31:0] pick;
        input integer r;
        case (r % 8)
            0: pick = 32'h8000_0000;
            1: pick = 32'h7FFF_FFFF;
            2: pick = 32'hFFFF_FFFF;
            3: pick = 32'd0;
            4: pick = mw[$urandom % 64];          // makes FINDEQ hit
            default: pick = $urandom;
        endcase
    endfunction

    initial begin
        clk = 0; reset = 1; active = 0; commit = 0; funct = 0; idx = 0; val = 0;
        errors = 0; ops = 0;
        for (i = 0; i < 64; i = i + 1) mw[i] = 0;
        mflag = 0;
        @(posedge clk); @(negedge clk); reset = 0;
        for (n = 0; n < 20000; n = n + 1) begin
            funct = (n < 200) ? 3'd0 : $urandom % 8;   // fill first
            idx = ($urandom % 16 == 0) ? 64 + $urandom % 100 : $urandom % 64;
            val = pick($urandom);
            active = 1;
            // the model's answer, before the clock edge
            case (funct)
                1: expect_r = mw[idx[5:0]];
                3, 4: begin
                    cnt = 0;
                    for (i = 0; i < 64; i = i + 1)
                        if (funct == 3 ? (mw[i] == val) : ($signed(mw[i]) < $signed(val))) cnt = cnt + 1;
                    expect_r = cnt;
                end
                5: begin
                    expect_r = 32'hFFFF_FFFF;
                    for (i = 63; i >= 0; i = i - 1) if (mflag[i]) expect_r = i;
                end
                6, 7: begin
                    acc = 0;
                    for (i = 0; i < 64; i = i + 1) if (funct == 6 || mflag[i]) acc = acc + mw[i];
                    expect_r = acc;
                end
                default: expect_r = 0;
            endcase
            #1;
            if (bad !== ((funct == 0 || funct == 1) && idx >= 64)) begin
                $display("FAIL n=%0d bad=%b funct=%0d idx=%0d", n, bad, funct, idx); errors = errors + 1;
            end
            commit = !bad;
            // SUM/SUMF: wait out the stall cycles (the CPU would be frozen)
            while (stall) begin
                commit = 0;
                @(negedge clk);
                #1;
            end
            if (!bad && funct != 0 && funct != 2 && result !== expect_r) begin
                $display("FAIL n=%0d funct=%0d val=%h got %h expected %h", n, funct, val, result, expect_r);
                errors = errors + 1;
            end
            commit = !bad;
            @(negedge clk);
            // the model's state change
            if (!bad) case (funct)
                0: mw[idx[5:0]] = val;
                2: for (i = 0; i < 64; i = i + 1) mw[i] = mw[i] + val;
                3: for (i = 0; i < 64; i = i + 1) mflag[i] = (mw[i] == val);
                4: for (i = 0; i < 64; i = i + 1) mflag[i] = ($signed(mw[i]) < $signed(val));
                default: ;
            endcase
            ops = ops + 1;
            active = 0; commit = 0;
            for (i = 0; i < 64; i = i + 1)
                if (dut.w[i] !== mw[i]) begin
                    if (errors < 10) $display("FAIL n=%0d word %0d = %h, model %h", n, i, dut.w[i], mw[i]);
                    errors = errors + 1;
                end
            if (dut.flag !== mflag) begin $display("FAIL n=%0d flags", n); errors = errors + 1; end
            if (errors > 20) n = 1 << 30;
        end
        if (errors == 0) $display("ALL AXISA CIM FUZZ TESTS PASSED (%0d operations)", ops);
        else $display("%0d AXISA CIM FUZZ MISMATCHES", errors);
        $finish;
    end
endmodule
