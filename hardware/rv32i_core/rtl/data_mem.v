// Byte-addressable data RAM, little-endian (mem[addr] is the least
// significant byte of a word/halfword - matches RISC-V's own
// endianness convention). Combinational read (same reasoning as
// instr_mem.v - single-cycle datapath, no separate memory stage);
// writes land on the clock edge with byte-lane masking so a narrow
// store never touches neighboring bytes.
//
// SYNC_READ (default 0, combinational - unchanged behavior) registers
// the read instead, same fix and reason as instr_mem.v's own
// SYNC_READ: a combinational read at this depth fails ECP5 block-RAM
// inference and falls back to wasteful per-bit flip-flops (confirmed
// via real synth_ecp5 - see [[project_axisa_synthesis_check]]). Unlike
// instr_mem.v, no `stall` port is needed - the address is a pure
// combinational function of the CURRENTLY FROZEN instruction, never
// races ahead - so a plain unconditional register is safe as long as
// cpu_core.v's LSU and mmu.v's walker each hold their address stable
// for one extra cycle before consuming the result (see cpu_core.v's
// dmem_load_stall and mmu.v's S_L1_ISSUE/S_L1_READ +
// S_L0_ISSUE/S_L0_READ splits). `mem_size` is ALSO registered
// (`mem_size_r`) in this mode - the byte/half/word selector must land
// on the same clock edge as the data it's selecting between, or the
// wrong sign/zero-extension applies one cycle out of phase.
`timescale 1ns/1ps

module data_mem #(
    parameter MEM_BYTES = 4096,
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
    reg [7:0] mem [0:MEM_BYTES-1];
    integer   i;

    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) mem[i] = 8'b0;
    end

    // Continuous assignment, NOT always @(*) - found live: Icarus
    // Verilog's implicit-sensitivity inference for a PROCEDURAL block
    // reading a memory array through a wide (32-bit) computed index hits
    // a severe elaboration performance cliff that scales steeply with
    // MEM_BYTES - every existing test stayed at/under 16384 bytes and
    // happened to compile in well under a second, but simply doubling to
    // 32768 (the first thing in this project to need more headroom) made
    // elaboration effectively never finish. An explicit sensitivity list
    // (addr/mem_size/mem_unsigned only) sidesteps the cliff but silently
    // breaks correctness instead: it stops reacting when a WRITE lands at
    // the currently-read address without addr itself changing, which a
    // write-then-immediately-read-same-address testbench pattern (see
    // tb_data_mem.v) legitimately relies on - caught live as two
    // regression failures the moment that "fix" was tried. Continuous
    // assignment has no such tradeoff: it has no explicit sensitivity
    // list to get wrong, correctly reacts to the memory array changing
    // same as always @(*) did, and empirically does NOT hit the same
    // elaboration cliff (confirmed at MEM_BYTES=32768).
    generate
        if (SYNC_READ) begin: gen_sync_read
            reg [31:0] byte_read_r, half_read_r, word_read_r;
            reg [1:0]  mem_size_r;
            always @(posedge clk) begin
                byte_read_r <= mem_unsigned ? {24'b0, mem[addr]} : {{24{mem[addr][7]}}, mem[addr]};
                half_read_r <= mem_unsigned ? {16'b0, mem[addr+1], mem[addr]}
                                             : {{16{mem[addr+1][7]}}, mem[addr+1], mem[addr]};
                word_read_r <= {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
                mem_size_r  <= mem_size;
            end
            assign read_data = (mem_size_r == 2'b00) ? byte_read_r :
                                (mem_size_r == 2'b01) ? half_read_r : word_read_r;
        end else begin: gen_comb_read
            wire [31:0] byte_read = mem_unsigned ? {24'b0, mem[addr]} : {{24{mem[addr][7]}}, mem[addr]};
            wire [31:0] half_read = mem_unsigned ? {16'b0, mem[addr+1], mem[addr]}
                                                  : {{16{mem[addr+1][7]}}, mem[addr+1], mem[addr]};
            wire [31:0] word_read = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
            assign read_data = (mem_size == 2'b00) ? byte_read :
                                (mem_size == 2'b01) ? half_read : word_read;
        end
    endgenerate

    always @(posedge clk) begin
        if (mem_write) begin
            case (mem_size)
                2'b00: begin
                    mem[addr] <= write_data[7:0];
                end
                2'b01: begin
                    mem[addr]   <= write_data[7:0];
                    mem[addr+1] <= write_data[15:8];
                end
                default: begin
                    mem[addr]   <= write_data[7:0];
                    mem[addr+1] <= write_data[15:8];
                    mem[addr+2] <= write_data[23:16];
                    mem[addr+3] <= write_data[31:24];
                end
            endcase
        end
    end
endmodule
