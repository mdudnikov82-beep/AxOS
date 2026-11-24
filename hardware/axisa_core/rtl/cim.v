// CIM - compute-in-memory block (AxISA v2.4, docs/ISA.md "CIM").
//
// A von Neumann core moves every word through one port: to add x to 64
// words it LOADs, adds and STOREs 64 times. Here the memory does it
// itself: each of the 64 words has its own adder and comparators, so
// CIM.ADD changes all 64 words in one cycle, CIM.FINDEQ/FINDLT compare
// all 64 at once (an associative memory: one match flag per word), and
// CIM.SUM/SUMF add them up through a 4-ary adder tree in 3 cycles.
// Only N registers talk to it (like memory - the confinement rule).
//
// funct (instr[26:24]):
//   0 PUT    w[ns] = nt                       (ns >= 64 -> ILLEGAL)
//   1 GET    nd = w[ns]                       (ns >= 64 -> ILLEGAL)
//   2 ADD    w[i] += nt for every i
//   3 FINDEQ flag[i] = (w[i] == nt); nd = number of flags set
//   4 FINDLT flag[i] = (w[i] <  nt), signed; nd = number of flags set
//   5 FIRST  nd = lowest i with flag[i], or 0xFFFFFFFF if none
//   6 SUM    nd = sum of all w[i] (mod 2^32), 3 cycles
//   7 SUMF   nd = sum of the flagged w[i], 3 cycles
//
// The words and flags are cleared by reset (not by `initial`, which
// synthesis drops - the MTE tag-memory lesson). State changes only on
// `commit` (the instruction really retires: not stalled, not trapped).
`timescale 1ns/1ps

module cim (
    input  wire        clk,
    input  wire        reset,
    input  wire        active,   // a CIM instruction is in the execute cycle
    input  wire [2:0]  funct,
    input  wire        commit,   // ... and it retires this cycle
    input  wire        run,      // the core is not halted (the SUM tree may advance)
    input  wire [31:0] idx,      // N[ns]: word index for PUT/GET
    input  wire [31:0] val,      // N[nt]: value for PUT/ADD/FINDEQ/FINDLT
    output wire [31:0] result,   // for GET/FINDEQ/FINDLT/FIRST/SUM/SUMF
    output wire        bad,      // PUT/GET index out of range
    output wire        stall     // SUM/SUMF still adding
);
    localparam WORDS = 64;
    localparam F_PUT = 3'd0, F_GET = 3'd1, F_ADD = 3'd2, F_FINDEQ = 3'd3,
               F_FINDLT = 3'd4, F_FIRST = 3'd5, F_SUM = 3'd6, F_SUMF = 3'd7;

    reg [31:0]      w [0:WORDS-1];
    reg [WORDS-1:0] flag;

    // ---- every word computes on itself, at once ----
    // One adder per word does both jobs: w + val for ADD, w - val for
    // FINDLT (w < val, signed, is the sign of the difference corrected for
    // overflow) - half the adders of a separate adder and comparator.
    wire sub = (funct != F_ADD);
    wire [31:0] opnd = sub ? ~val : val;
    wire [WORDS-1:0] eq, lt;
    wire [31:0] nxt [0:WORDS-1];   // w + val (ADD's new value)
    genvar gi;
    generate
        for (gi = 0; gi < WORDS; gi = gi + 1) begin: g_cmp
            wire [31:0] r = w[gi] + opnd + {31'd0, sub};
            assign nxt[gi] = r;
            assign eq[gi] = (w[gi] == val);
            // overflow of w - val: the operands' signs differ and the result's differs from w's
            assign lt[gi] = r[31] ^ ((w[gi][31] ^ val[31]) & (r[31] ^ w[gi][31]));
        end
    endgenerate

    wire [WORDS-1:0] hits = (funct == F_FINDEQ) ? eq : lt;
    reg  [6:0] hit_count;
    integer k;
    always @(*) begin
        hit_count = 7'd0;
        for (k = 0; k < WORDS; k = k + 1) hit_count = hit_count + {6'd0, hits[k]};
    end

    // lowest flagged word
    reg [31:0] first;
    integer kf;
    always @(*) begin
        first = 32'hFFFF_FFFF;
        for (kf = WORDS - 1; kf >= 0; kf = kf - 1) if (flag[kf]) first = kf;
    end

    // ---- SUM / SUMF: 64 -> 16 -> 4 -> 1, a register after each 4:1 level ----
    localparam S_IDLE = 2'd0, S_L2 = 2'd1, S_L3 = 2'd2;
    reg [1:0]  st;
    reg [31:0] p1 [0:15];
    reg [31:0] p2 [0:3];
    wire is_sum = active && (funct == F_SUM || funct == F_SUMF);
    wire sum_go = is_sum && (st == S_IDLE) && run;

    wire [31:0] m [0:WORDS-1];     // the words the sum takes
    generate
        for (gi = 0; gi < WORDS; gi = gi + 1) begin: g_mask
            assign m[gi] = (funct == F_SUM || flag[gi]) ? w[gi] : 32'd0;
        end
    endgenerate
    wire [31:0] total = (p2[0] + p2[1]) + (p2[2] + p2[3]);

    // in the terminal cycle (S_L3) the result is already in p2: no stall
    assign stall = (st == S_IDLE) ? sum_go : (st != S_L3);

    integer j;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            st <= S_IDLE;
            for (j = 0; j < 16; j = j + 1) p1[j] <= 32'd0;
            for (j = 0; j < 4; j = j + 1) p2[j] <= 32'd0;
        end else if (run) begin
            case (st)
                S_IDLE: if (sum_go) begin
                    for (j = 0; j < 16; j = j + 1)
                        p1[j] <= (m[4*j] + m[4*j+1]) + (m[4*j+2] + m[4*j+3]);
                    st <= S_L2;
                end
                S_L2: begin
                    for (j = 0; j < 4; j = j + 1)
                        p2[j] <= (p1[4*j] + p1[4*j+1]) + (p1[4*j+2] + p1[4*j+3]);
                    st <= S_L3;
                end
                default: st <= S_IDLE;      // S_L3: result taken this cycle
            endcase
        end
    end

    // ---- the words themselves ----
    wire [5:0] wi = idx[5:0];
    assign bad = active && (funct == F_PUT || funct == F_GET) && (idx >= WORDS);

    integer jw;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (jw = 0; jw < WORDS; jw = jw + 1) w[jw] <= 32'd0;
            flag <= {WORDS{1'b0}};
        end else if (commit) begin
            case (funct)
                F_PUT:    w[wi] <= val;
                F_ADD:    for (jw = 0; jw < WORDS; jw = jw + 1) w[jw] <= nxt[jw];
                F_FINDEQ, F_FINDLT: flag <= hits;
                default: ;
            endcase
        end
    end

    assign result = (funct == F_GET)                        ? w[wi] :
                    (funct == F_FINDEQ || funct == F_FINDLT) ? {25'd0, hit_count} :
                    (funct == F_FIRST)                      ? first :
                                                              total;
endmodule
