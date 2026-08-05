// Instruction ROM. $readmemh-loaded from INIT_FILE (a parameter, not
// hardcoded - the same module serves every test program). Combinational
// read: the single-cycle datapath needs the fetched instruction ready
// the same cycle PC changes, there's no fetch stage of its own.
`timescale 1ns/1ps

module instr_mem #(
    parameter MEM_WORDS = 1024,
    parameter INIT_FILE = ""
) (
    input  wire [31:0] addr,   // byte address (word-aligned - addr[1:0] ignored)
    output wire [31:0] instr
);
    reg [31:0] mem [0:MEM_WORDS-1];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    assign instr = mem[addr[31:2]];
endmodule
