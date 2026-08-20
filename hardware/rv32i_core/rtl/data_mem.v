// Byte-addressable data RAM, little-endian (byte 0 of a word/halfword is
// the least significant - matches RISC-V's own endianness convention).
//
// SYNC_READ (default 0, combinational - unchanged behavior) registers
// the read instead, same fix and reason as instr_mem.v's own SYNC_READ:
// a combinational read at this depth fails ECP5 block-RAM inference and
// falls back to wasteful per-bit flip-flops (confirmed via real
// synth_ecp5 - see [[project_axisa_synthesis_check]]). Unlike instr_mem.v,
// no `stall` port is needed - the address is a pure combinational
// function of the CURRENTLY FROZEN instruction, never races ahead - so a
// plain unconditional register is safe as long as cpu_core.v's LSU and
// mmu.v's walker each hold their address stable for one extra cycle
// before consuming the result (see cpu_core.v's dmem_load_stall and
// mmu.v's S_L1_ISSUE/S_L1_READ + S_L0_ISSUE/S_L0_READ splits).
//
// WORD-LANE ORGANIZATION (2026-08-20, [[project_axisa_synthesis_check]]):
// the array used to be one flat `mem[0:MEM_BYTES-1]`, with a store
// writing up to 4 INDEPENDENT byte addresses (mem[addr]..mem[addr+3]) in
// one cycle - real synth_ecp5 confirmed this pattern (not the read
// timing, already fixed separately) is what actually blocks ECP5 DP16KD
// block-RAM inference: no single BRAM write port can represent 4
// independent addresses per cycle. Fixed by splitting into 4 parallel
// byte-lane arrays (mem0..mem3, one per byte position within a 4-byte
// word), always written/read at the SAME shared `word_idx` with 4
// independent per-lane write-enables - the standard byte-enable-BRAM
// idiom real hardware (and Yosys's memory_bram pass) expects.
//
// Deliberate consequence, a real user-approved tradeoff: a halfword/word
// access that isn't naturally aligned to its own size no longer reads/
// writes past the end of its containing 4-byte word - byte_off is
// rounded DOWN to the nearest valid lane (or pair of lanes) within the
// SAME word instead of touching the next one. This never crashes and is
// fully deterministic, just not the "real" misaligned value - matching
// what the RISC-V spec already allows (misaligned support is optional)
// and what every actual compiler-emitted LW/SW/LH/SH already satisfies
// by construction (naturally aligned). No test in this project's suite
// exercises a genuinely misaligned access (confirmed by grep before this
// change) - a single-byte op is NEVER affected (a lone byte has no
// "next word" to spill into, bit-exact identical to the old array for
// every address).
`timescale 1ns/1ps

module data_mem #(
    parameter MEM_BYTES = 4096,   // must be a multiple of 4 (word-lane organized)
    parameter SYNC_READ = 0
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire        mem_write,
    input  wire [1:0]  mem_size,      // 00=byte 01=half 10=word
    input  wire        mem_unsigned,  // zero- vs sign-extend on read
    output wire [31:0] read_data
);
    localparam WORDS = MEM_BYTES / 4;

    reg [7:0] mem0 [0:WORDS-1];  // byte lane 0 (bits [7:0] of each word)
    reg [7:0] mem1 [0:WORDS-1];  // byte lane 1 (bits [15:8])
    reg [7:0] mem2 [0:WORDS-1];  // byte lane 2 (bits [23:16])
    reg [7:0] mem3 [0:WORDS-1];  // byte lane 3 (bits [31:24])
    integer   i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            mem0[i] = 8'b0;
            mem1[i] = 8'b0;
            mem2[i] = 8'b0;
            mem3[i] = 8'b0;
        end
    end

    wire [29:0] word_idx = addr[31:2];
    wire [1:0]  byte_off = addr[1:0];
    wire        lo_lane  = byte_off[1];  // half-word pair select: 0->lanes{0,1}, 1->lanes{2,3}

    wire byte_op = (mem_size == 2'b00);
    wire half_op = (mem_size == 2'b01);
    wire word_op = mem_size[1];          // 2'b10 or 2'b11 - both "word", matches the old `default:` case

    // Per-lane write enable - structurally IDENTICAL shape across all 4
    // lanes (only the literal lane index differs), deliberately: an
    // asymmetric per-lane write pattern is a known ECP5 byte-enable-BRAM
    // inference breaker. word_op always hits all 4 lanes (ignoring
    // byte_off - a real word-aligned SW always has byte_off==0 anyway);
    // half_op hits exactly the 2 lanes of one pair, selected by lo_lane
    // (byte_off==1 rounds down into the SAME pair as byte_off==0,
    // byte_off==3 rounds down into the same pair as byte_off==2 - never
    // the next word); byte_op hits exactly 1 lane, bit-exact identical
    // to the old flat array for every byte_off value.
    wire we0 = mem_write && (word_op || (half_op && !lo_lane) || (byte_op && byte_off == 2'd0));
    wire we1 = mem_write && (word_op || (half_op && !lo_lane) || (byte_op && byte_off == 2'd1));
    wire we2 = mem_write && (word_op || (half_op &&  lo_lane) || (byte_op && byte_off == 2'd2));
    wire we3 = mem_write && (word_op || (half_op &&  lo_lane) || (byte_op && byte_off == 2'd3));

    // Per-lane write data - lane 0 and the "low" member of an active half
    // pair (lanes 0/2) always source write_data[7:0] (a byte op's value
    // always lives there regardless of which physical lane it targets;
    // a half op's low byte always lives there too); lane 1/3 as the
    // "high" member of a pair sources write_data[15:8]; word_op overrides
    // every lane to its own fixed byte position in write_data.
    wire [7:0] wd0 = write_data[7:0];
    wire [7:0] wd1 = word_op ? write_data[15:8]  : (byte_op ? write_data[7:0] : write_data[15:8]);
    wire [7:0] wd2 = word_op ? write_data[23:16] : write_data[7:0];
    wire [7:0] wd3 = word_op ? write_data[31:24] : (byte_op ? write_data[7:0] : write_data[15:8]);

    always @(posedge clk) begin
        if (we0) mem0[word_idx] <= wd0;
        if (we1) mem1[word_idx] <= wd1;
        if (we2) mem2[word_idx] <= wd2;
        if (we3) mem3[word_idx] <= wd3;
    end

    // Continuous assignment, NOT always @(*) - found live (before this
    // word-lane split): Icarus Verilog's implicit-sensitivity inference
    // for a PROCEDURAL block reading a memory array through a computed
    // index hits a severe elaboration performance cliff, and a
    // hand-restricted sensitivity list silently breaks the
    // write-then-immediately-read-same-address pattern tb_data_mem.v
    // relies on - see git history for the full original investigation.
    // Continuous assignment has no such tradeoff and is kept for both
    // generate branches below, same as before this split.
    generate
        if (SYNC_READ) begin: gen_sync_read
            reg [7:0] lane0_r, lane1_r, lane2_r, lane3_r;
            reg [1:0] mem_size_r, byte_off_r;
            always @(posedge clk) begin
                lane0_r    <= mem0[word_idx];
                lane1_r    <= mem1[word_idx];
                lane2_r    <= mem2[word_idx];
                lane3_r    <= mem3[word_idx];
                mem_size_r <= mem_size;
                byte_off_r <= byte_off;
            end
            wire        lo_lane_r  = byte_off_r[1];
            wire [7:0]  byte_sel_r = (byte_off_r == 2'd0) ? lane0_r :
                                      (byte_off_r == 2'd1) ? lane1_r :
                                      (byte_off_r == 2'd2) ? lane2_r : lane3_r;
            wire [7:0]  half_lo_r  = lo_lane_r ? lane2_r : lane0_r;
            wire [7:0]  half_hi_r  = lo_lane_r ? lane3_r : lane1_r;
            wire [31:0] byte_read  = mem_unsigned ? {24'b0, byte_sel_r} : {{24{byte_sel_r[7]}}, byte_sel_r};
            wire [31:0] half_read  = mem_unsigned ? {16'b0, half_hi_r, half_lo_r}
                                                   : {{16{half_hi_r[7]}}, half_hi_r, half_lo_r};
            wire [31:0] word_read  = {lane3_r, lane2_r, lane1_r, lane0_r};
            assign read_data = (mem_size_r == 2'b00) ? byte_read :
                                (mem_size_r == 2'b01) ? half_read : word_read;
        end else begin: gen_comb_read
            wire [7:0]  lane0 = mem0[word_idx];
            wire [7:0]  lane1 = mem1[word_idx];
            wire [7:0]  lane2 = mem2[word_idx];
            wire [7:0]  lane3 = mem3[word_idx];
            wire [7:0]  byte_sel = (byte_off == 2'd0) ? lane0 :
                                    (byte_off == 2'd1) ? lane1 :
                                    (byte_off == 2'd2) ? lane2 : lane3;
            wire [7:0]  half_lo = lo_lane ? lane2 : lane0;
            wire [7:0]  half_hi = lo_lane ? lane3 : lane1;
            wire [31:0] byte_read = mem_unsigned ? {24'b0, byte_sel} : {{24{byte_sel[7]}}, byte_sel};
            wire [31:0] half_read = mem_unsigned ? {16'b0, half_hi, half_lo}
                                                  : {{16{half_hi[7]}}, half_hi, half_lo};
            wire [31:0] word_read = {lane3, lane2, lane1, lane0};
            assign read_data = (mem_size == 2'b00) ? byte_read :
                                (mem_size == 2'b01) ? half_read : word_read;
        end
    endgenerate
endmodule
