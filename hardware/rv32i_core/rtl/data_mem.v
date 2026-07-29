// Byte-addressable data RAM, little-endian (mem[addr] is the least
// significant byte of a word/halfword - matches RISC-V's own
// endianness convention). Combinational read (same reasoning as
// instr_mem.v - single-cycle datapath, no separate memory stage);
// writes land on the clock edge with byte-lane masking so a narrow
// store never touches neighboring bytes.
`timescale 1ns/1ps

module data_mem #(
    parameter MEM_BYTES = 4096
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire        mem_write,
    input  wire [1:0]  mem_size,      // 00=byte 01=half 10=word
    input  wire        mem_unsigned,  // zero- vs sign-extend on read
    output reg  [31:0] read_data
);
    reg [7:0] mem [0:MEM_BYTES-1];
    integer   i;

    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) mem[i] = 8'b0;
    end

    always @(*) begin
        case (mem_size)
            2'b00: read_data = mem_unsigned ? {24'b0, mem[addr]}
                                             : {{24{mem[addr][7]}}, mem[addr]};
            2'b01: read_data = mem_unsigned ? {16'b0, mem[addr+1], mem[addr]}
                                             : {{16{mem[addr+1][7]}}, mem[addr+1], mem[addr]};
            default: read_data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
        endcase
    end

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
